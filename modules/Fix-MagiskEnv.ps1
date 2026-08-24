# Fix-MagiskEnv.ps1 - Magisk env 分区修复模块

param([switch]$NoReboot)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

Write-Title "Magisk env 分区修复"

if (-not (Find-Adb)) { exit 1 }
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# 读取 env 分区
Write-Info "读取 env 分区 (8MB)..."
$tmpDevice = "/data/local/tmp/env_fix_tmp.bin"
$tmpLocal = Join-Path $env:TEMP "env_fix_tmp.bin"

Invoke-AdbShell ("dd if=/dev/block/env of=" + $tmpDevice + " bs=1048576 count=8 2>/dev/null") | Out-Null
Invoke-AdbShell ("chmod 644 " + $tmpDevice) | Out-Null
Invoke-Adb @("pull", $tmpDevice, $tmpLocal) 2>&1 | Out-Null

if (-not (Test-Path $tmpLocal)) {
    Write-Err "拉取 env 分区失败"
    exit 1
}

$data = [System.IO.File]::ReadAllBytes($tmpLocal)
Write-OK ("env 分区已读取 (" + $data.Length + " 字节)")

# CRC 校验
$CRC_SIZE = 65532
$storedCrc = [BitConverter]::ToUInt32($data, 0)
$crcData = New-Object byte[] $CRC_SIZE
[Array]::Copy($data, 4, $crcData, 0, $CRC_SIZE)
$calcCrc = Get-CRC32 -Data $crcData

Write-Info ("存储 CRC: " + $storedCrc.ToString("x8") + ", 计算 CRC: " + $calcCrc.ToString("x8"))
if ($storedCrc -eq $calcCrc) {
    Write-OK "CRC 校验通过"
}
else {
    Write-Warn "CRC 不匹配 (env 可能已被 U-Boot 修改)"
}

# 查找 skip/want_initramfs
$skipBytes = [System.Text.Encoding]::ASCII.GetBytes("skip_initramfs")
$wantBytes = [System.Text.Encoding]::ASCII.GetBytes("want_initramfs")
$skipPos = Find-BytePattern -Haystack $data -Needle $skipBytes -Start 4
$wantPos = Find-BytePattern -Haystack $data -Needle $wantBytes -Start 4

if ($wantPos -ge 0 -and $skipPos -lt 0 -and $storedCrc -eq $calcCrc) {
    Write-OK "env 已经是 want_initramfs，CRC 有效，无需修复"
    Remove-Item $tmpLocal -ErrorAction SilentlyContinue
    exit 0
}
elseif ($wantPos -ge 0 -and $skipPos -lt 0) {
    Write-Warn "want_initramfs 已存在但 CRC 无效，需要重算 CRC"
}
elseif ($skipPos -ge 0) {
    Write-Warn ("发现 skip_initramfs (偏移 " + $skipPos + ")，需要修复")
}
else {
    Write-Err "env 中未找到 skip_initramfs 或 want_initramfs"
    exit 1
}

# 替换
if ($skipPos -ge 0) {
    for ($i = 0; $i -lt $wantBytes.Length; $i++) {
        $data[$skipPos + $i] = $wantBytes[$i]
    }
    Write-OK ("skip_initramfs -> want_initramfs (偏移 " + $skipPos + ")")
}

# 重算 CRC
$crcData = New-Object byte[] $CRC_SIZE
[Array]::Copy($data, 4, $crcData, 0, $CRC_SIZE)
$newCrc = Get-CRC32 -Data $crcData
$crcBytes = [BitConverter]::GetBytes($newCrc)
[Array]::Copy($crcBytes, 0, $data, 0, 4)
Write-OK ("新 CRC: " + $newCrc.ToString("x8"))

# 写回设备
$outLocal = Join-Path $env:TEMP "env_fixed_out.bin"
[System.IO.File]::WriteAllBytes($outLocal, $data)

Write-Info "推送修复后的 env..."
Invoke-Adb @("push", $outLocal, $tmpDevice) 2>&1 | Out-Null

Write-Info "写入 env 分区..."
Invoke-AdbShell ("dd if=" + $tmpDevice + " of=/dev/block/env bs=1048576 count=8 2>&1") | Out-Null

# 验证 MD5
Write-Info "验证写入完整性..."
$localMd5 = (Get-FileHash -Algorithm MD5 $outLocal).Hash.ToLower()
$devMd5Raw = Invoke-AdbShell "cat /dev/block/env | md5sum"
$devMd5Parts = $devMd5Raw.StdOut -split "\s+"
$devMd5 = $devMd5Parts[0].ToLower()

if ($localMd5 -eq $devMd5) {
    Write-OK ("MD5 一致: " + $localMd5)
}
else {
    Write-Err ("MD5 不一致! 本地=" + $localMd5 + " 设备=" + $devMd5)
    exit 1
}

# 清理
Invoke-AdbShell ("rm -f " + $tmpDevice) | Out-Null
Remove-Item $tmpLocal -ErrorAction SilentlyContinue
Remove-Item $outLocal -ErrorAction SilentlyContinue

Write-Host ""
Write-OK "env 分区修复完成"
Write-Host ""

if (-not $NoReboot) {
    Write-Info "正在重启设备..."
    Invoke-Adb @("reboot") 2>&1 | Out-Null
    Write-Info "等待设备重启..."
    Invoke-Adb @("wait-for-device") 2>&1 | Out-Null
    Start-Sleep -Seconds 25

    $cmdline = Get-DeviceCmdline
    if ($cmdline -match "want_initramfs") {
        Write-OK "cmdline 包含 want_initramfs"
    }
    elseif ($cmdline -match "skip_initramfs") {
        Write-Err "cmdline 仍然是 skip_initramfs，U-Boot 可能回滚了"
        exit 1
    }
    else {
        Write-Warn "cmdline 中未找到 initramfs 参数"
    }

    $magisk = Get-MagiskVersion
    if ($magisk) {
        Write-OK ("Magisk 运行中: " + $magisk)
    }
    else {
        Write-Warn "未检测到 Magisk 守护进程"
    }
}
else {
    Write-Info "已跳过重启 (-NoReboot)"
}

Write-Host ""
Write-OK "全部完成"
