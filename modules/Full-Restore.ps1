# Full-Restore.ps1 - 完全恢复原厂 (boot + su + env)

param([switch]$NoReboot)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

Write-Title "完全恢复原厂 (boot + su + env)"
Write-Warn "此操作将:"
Write-Log "  - 恢复原厂 boot (移除 Magisk)"
Write-Log "  - 恢复原厂 /system/xbin/su"
Write-Log "  - 修复 env 分区 (want_initramfs -> skip_initramfs)"
Write-Host ""
Write-Warn "执行后 Magisk 将完全失效!"
Write-Host ""

# 简单确认
$confirm = Read-Host "  确认执行? (y/N)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Info "已取消"
    exit 0
}

if (-not (Find-Adb)) { exit 1 }
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# 第一步: 恢复原厂 boot
Write-Host ""
Write-Log "===== 第一步: 恢复原厂 boot =====" -ForegroundColor Yellow
Write-Host ""

$restoreBoot = Join-Path $modulesDir "Restore-FactoryBoot.ps1"
& $restoreBoot -NoReboot
if ($LASTEXITCODE -ne 0) {
    Write-Err "boot 恢复失败"
    exit 1
}

# 第二步: 恢复原厂 su
Write-Host ""
Write-Log "===== 第二步: 恢复原厂 su =====" -ForegroundColor Yellow
Write-Host ""

$restoreSu = Join-Path $modulesDir "Restore-FactorySu.ps1"
& $restoreSu -NoReboot
if ($LASTEXITCODE -ne 0) {
    Write-Err "su 恢复失败"
    exit 1
}

# 第三步: 恢复 env (want -> skip)
Write-Host ""
Write-Log "===== 第三步: 恢复 env 分区 =====" -ForegroundColor Yellow
Write-Host ""

Write-Info "读取 env 分区..."
$tmpDevice = "/data/local/tmp/env_restore_tmp.bin"
$tmpLocal = Join-Path $env:TEMP "env_restore_tmp.bin"

Invoke-AdbShell ("dd if=/dev/block/env of=" + $tmpDevice + " bs=1048576 count=8 2>/dev/null") | Out-Null
Invoke-AdbShell ("chmod 644 " + $tmpDevice) | Out-Null
Invoke-Adb @("pull", $tmpDevice, $tmpLocal) 2>&1 | Out-Null

$data = [System.IO.File]::ReadAllBytes($tmpLocal)

$wantBytes = [System.Text.Encoding]::ASCII.GetBytes("want_initramfs")
$skipBytes = [System.Text.Encoding]::ASCII.GetBytes("skip_initramfs")
$wantPos = Find-BytePattern -Haystack $data -Needle $wantBytes -Start 4
$skipPos = Find-BytePattern -Haystack $data -Needle $skipBytes -Start 4

if ($skipPos -ge 0 -and $wantPos -lt 0) {
    Write-OK "env 已经是 skip_initramfs，无需修改"
}
elseif ($wantPos -ge 0) {
    for ($i = 0; $i -lt $skipBytes.Length; $i++) {
        $data[$wantPos + $i] = $skipBytes[$i]
    }
    Write-OK ("want_initramfs -> skip_initramfs (offset " + $wantPos + ")")

    # 重算 CRC
    $CRC_SIZE = 65532
    $crcData = New-Object byte[] $CRC_SIZE
    [Array]::Copy($data, 4, $crcData, 0, $CRC_SIZE)
    $newCrc = Get-CRC32 -Data $crcData
    $crcBytes = [BitConverter]::GetBytes($newCrc)
    [Array]::Copy($crcBytes, 0, $data, 0, 4)
    Write-OK ("新 CRC: " + $newCrc.ToString("x8"))

    $outLocal = Join-Path $env:TEMP "env_restore_out.bin"
    [System.IO.File]::WriteAllBytes($outLocal, $data)

    Invoke-Adb @("push", $outLocal, $tmpDevice) 2>&1 | Out-Null
    Invoke-AdbShell ("dd if=" + $tmpDevice + " of=/dev/block/env bs=1048576 count=8 2>&1") | Out-Null

    $localMd5 = (Get-FileHash -Algorithm MD5 $outLocal).Hash.ToLower()
    $devMd5Raw = Invoke-AdbShell "cat /dev/block/env | md5sum"
    $devMd5 = ($devMd5Raw.StdOut -split "\s+")[0].ToLower()

    if ($localMd5 -eq $devMd5) {
        Write-OK ("env 写入验证通过: " + $localMd5)
    }
    else {
        Write-Err "env MD5 不一致"
        exit 1
    }

    Remove-Item $outLocal -ErrorAction SilentlyContinue
}
else {
    Write-Warn "env 中未找到 initramfs 参数"
}

Invoke-AdbShell ("rm -f " + $tmpDevice) | Out-Null
Remove-Item $tmpLocal -ErrorAction SilentlyContinue

# 完成
Write-Host ""
Write-Host ""
Write-OK "完全恢复原厂完成!"

if (-not $NoReboot) {
    Write-Info "正在重启设备..."
    Invoke-Adb @("reboot") 2>&1 | Out-Null
    Write-Info "等待设备重启..."
    Invoke-Adb @("wait-for-device") 2>&1 | Out-Null
    Start-Sleep -Seconds 25

    $cmdline = Get-DeviceCmdline
    if ($cmdline -match "skip_initramfs") {
        Write-OK "cmdline: skip_initramfs (原厂行为)"
    }

    $magisk = Get-MagiskVersion
    if ($magisk) {
        Write-Warn ("Magisk 仍在运行: " + $magisk + " (重启后应消失)")
    }
    else {
        Write-OK "Magisk 未运行 (符合预期)"
    }

    $suCheck = Invoke-AdbShell "ls -la /system/xbin/su 2>&1"
    if ($suCheck.StdOut -match "root.*shell") {
        Write-OK "原厂 su 已恢复"
    }

    Write-Host ""
    Write-OK "全部完成，设备已恢复原厂状态"
}
else {
    Write-Info "已跳过重启 (-NoReboot)"
}
