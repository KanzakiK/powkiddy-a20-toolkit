# Restore-FactorySu.ps1 - 恢复原厂 /system/xbin/su

param([switch]$NoReboot)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

$toolkitRoot = Split-Path $modulesDir
$suFile = Join-Path $toolkitRoot "files\factory_su.bin"

Write-Title "恢复原厂 /system/xbin/su"

if (-not (Find-Adb)) { exit 1 }
if (-not (Test-Path $suFile)) {
    Write-Err ("找不到 factory_su.bin: " + $suFile)
    exit 1
}
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# 检查当前状态
Write-Info "检查 /system/xbin/su 当前状态..."
$check = Invoke-AdbShell "ls -la /system/xbin/su 2>&1"
if ($check.StdOut -match "No such file") {
    Write-Info "/system/xbin/su 不存在，准备恢复"
}
else {
    Write-Warn "/system/xbin/su 已存在:"
    Write-Log ("  " + $check.StdOut.Trim())
    $curMd5Raw = Invoke-AdbShell "md5sum /system/xbin/su"
    $curMd5 = ($curMd5Raw.StdOut -split "\s+")[0]
    $srcMd5 = (Get-FileHash -Algorithm MD5 $suFile).Hash.ToLower()
    if ($curMd5 -eq $srcMd5) {
        Write-OK "MD5 一致，原厂 su 已在设备上，无需操作"
        exit 0
    }
    Write-Warn ("当前 MD5: " + $curMd5)
    Write-Warn ("原厂 MD5: " + $srcMd5)
    Write-Info "将用原厂 su 覆盖当前文件"
}

# remount
Write-Info "重新挂载 /system..."
Invoke-Adb @("remount") 2>&1 | Out-Null
Start-Sleep -Seconds 1
Invoke-AdbShell "mount -o rw,remount /" 2>&1 | Out-Null
Write-OK "挂载完成"

# 检测含 system/ 的 Magisk 模块（它们会 overlay 挡住 /system 写入，
# 导致 su 恢复"看似成功、重启后不保留"——su 有路径语义无法迁移，只能事前拦截）
Write-Info "检查 Magisk system 模块..."
$sysMods = Invoke-AdbShell "ls -d /data/adb/modules/*/system 2>/dev/null"
if ($sysMods.StdOut -match "system") {
    $modCount = @($sysMods.StdOut.Trim() -split "`n" | Where-Object { $_ -ne "" }).Count
    Write-Warn "检测到 $modCount 个含 system/ 的 Magisk 模块！"
    Write-Warn "它们会 overlay 挂载到 /system，su 写入可能被覆盖（重启后不保留）"
    Write-Warn "建议：先移除这些模块，或在无 Magisk system 模块的环境下执行"
    $confirm = Read-Host "  仍要继续? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Info "已取消"
        exit 1
    }
}
else {
    Write-OK "无 Magisk system 模块干扰，/system 写入可靠"
}

# 推送并写入
Write-Info "推送原厂 su..."
Invoke-Adb @("push", $suFile, "/data/local/tmp/factory_su.bin") 2>&1 | Out-Null

# 备份现有 su（remount 后、覆盖前）
Write-Info "备份现有 /system/xbin/su..."
Invoke-AdbShell "cp /system/xbin/su /system/xbin/su.bak 2>/dev/null" | Out-Null
$suBak = Invoke-AdbShell "ls /system/xbin/su.bak 2>/dev/null"
if ($suBak.StdOut -match "su\.bak") { Write-OK "已备份为 /system/xbin/su.bak" }
else { Write-Info "无现有 su 可备份" }

Write-Info "写入 /system/xbin/su..."
Invoke-AdbShell "cp /data/local/tmp/factory_su.bin /system/xbin/su" | Out-Null
Invoke-AdbShell "chmod 6755 /system/xbin/su" | Out-Null
Invoke-AdbShell "chown root:shell /system/xbin/su" | Out-Null

# 验证
Write-Info "验证..."
$verify = Invoke-AdbShell "ls -la /system/xbin/su"
Write-Log ("  " + $verify.StdOut.Trim())

$devMd5Raw = Invoke-AdbShell "cat /system/xbin/su | md5sum"
$devMd5 = ($devMd5Raw.StdOut -split "\s+")[0].ToLower()
$srcMd5 = (Get-FileHash -Algorithm MD5 $suFile).Hash.ToLower()

if ($devMd5 -eq $srcMd5) {
    Write-OK ("MD5 一致: " + $srcMd5)
}
else {
    Write-Err ("MD5 不一致! 期望=" + $srcMd5 + " 实际=" + $devMd5)
    exit 1
}

# 清理
Invoke-AdbShell "rm -f /data/local/tmp/factory_su.bin" | Out-Null

Write-Host ""
Write-OK "原厂 su 已恢复"
Write-Warn "注意: 如果 Magisk 正在运行，它可能会提示有多余的 su 文件"
Write-Info "这是正常的，不影响 Magisk 功能"
