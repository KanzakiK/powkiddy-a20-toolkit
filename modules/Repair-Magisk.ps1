# Repair-Magisk.ps1 - 一键修复 Magisk (boot + env)

param([switch]$NoReboot)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

Write-Title "一键修复 Magisk (boot + env)"

if (-not (Find-Adb)) { exit 1 }
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# 第一步: 修 env
Write-Host ""
Write-Log "===== 第一步: 修复 env 分区 =====" -ForegroundColor Yellow
Write-Host ""

$fixEnvScript = Join-Path $modulesDir "Fix-MagiskEnv.ps1"
# 用子进程方式调用，$LASTEXITCODE 才能正确反映脚本退出码（PS5.1 中 & 调用不更新它）
$psPath = (Get-Process -Id $PID).Path
& $psPath -NoProfile -ExecutionPolicy Bypass -File $fixEnvScript -NoReboot
if ($LASTEXITCODE -ne 0) {
    Write-Err "env 修复失败"
    exit 1
}

# 第二步: 刷 boot
Write-Host ""
Write-Log "===== 第二步: 刷写 boot 分区 =====" -ForegroundColor Yellow
Write-Host ""

$installMagiskScript = Join-Path $modulesDir "Install-Magisk.ps1"
& $psPath -NoProfile -ExecutionPolicy Bypass -File $installMagiskScript -NoReboot
if ($LASTEXITCODE -ne 0) {
    Write-Err "boot 刷写失败"
    exit 1
}

# 第三步: 重启验证
Write-Host ""
Write-Log "===== 第三步: 重启验证 =====" -ForegroundColor Yellow
Write-Host ""

if ($NoReboot) {
    Write-Info "已跳过重启 (-NoReboot)"
    Write-Info "请手动重启设备后检查 Magisk 状态"
    exit 0
}

Write-Info "正在重启设备..."
Invoke-Adb @("reboot") 2>&1 | Out-Null
Write-Info "等待设备重启 (约 30 秒)..."
Invoke-Adb @("wait-for-device") 2>&1 | Out-Null
Start-Sleep -Seconds 30

# 验证 cmdline
$cmdline = Get-DeviceCmdline
if ($cmdline -match "want_initramfs") {
    Write-OK "cmdline: want_initramfs"
}
elseif ($cmdline -match "skip_initramfs") {
    Write-Err "cmdline 仍是 skip_initramfs"
    exit 1
}
else {
    Write-Warn "cmdline 中未找到 initramfs 参数"
}

# 验证 Magisk
$magisk = Get-MagiskVersion
if ($magisk) {
    Write-OK ("Magisk 运行中: " + $magisk)
}
else {
    Write-Warn "未检测到 Magisk 守护进程，可能需要多等一会"
}

# 验证 /system/xbin/su
$suCheck = Invoke-AdbShell "ls -la /system/xbin/su 2>&1"
if ($suCheck.StdOut -match "No such file") {
    Write-OK "/system/xbin/su 已清除"
}
elseif ($suCheck.StdOut -match "su") {
    Write-Warn "/system/xbin/su 仍然存在，Magisk 可能提示修复"
}

Write-Host ""
Write-OK "一键修复完成，请打开 Magisk App 确认状态"
