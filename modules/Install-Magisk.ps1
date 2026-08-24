# Install-Magisk.ps1 - Magisk boot 分区刷写模块

param([switch]$NoReboot)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

$toolkitRoot = Split-Path $modulesDir
$bootImage = Join-Path $toolkitRoot "files\magisk_boot.img"

Write-Title "Magisk boot 分区刷写"

if (-not (Find-Adb)) { exit 1 }
if (-not (Test-Path $bootImage)) {
    Write-Err ("找不到 magisk_boot.img: " + $bootImage)
    Write-Info "请将 Magisk patched 的 boot 镜像放入 files 目录"
    exit 1
}
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# 检查当前状态
Write-Info "检查当前 Magisk 状态..."
$magisk = Get-MagiskVersion
if ($magisk) {
    Write-OK ("当前 Magisk: " + $magisk)
}
else {
    Write-Warn "当前未检测到 Magisk 运行"
}

$cmdline = Get-DeviceCmdline
if ($cmdline -match "skip_initramfs") {
    Write-Warn "cmdline 包含 skip_initramfs (env 可能需要修复)"
}

# 备份当前 boot
Write-Info "备份当前 boot 分区..."
Invoke-AdbShell "dd if=/dev/block/boot of=/data/local/tmp/boot_backup.bin bs=1048576 count=16 2>&1" | Out-Null

$backupDir = Join-Path $toolkitRoot "backup"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupDir ("boot_" + $timestamp + ".img")
Invoke-Adb @("pull", "/data/local/tmp/boot_backup.bin", $backupFile) 2>&1 | Out-Null
if (Test-Path $backupFile) {
    Write-OK ("备份已保存: " + $backupFile)
}

# 推送并刷写
Write-Info "推送 patched boot 镜像..."
Invoke-Adb @("push", $bootImage, "/data/local/tmp/boot_new.img") 2>&1 | Out-Null

Write-Info "写入 boot 分区..."
Invoke-AdbShell "dd if=/data/local/tmp/boot_new.img of=/dev/block/boot bs=1048576 count=16 2>&1" | Out-Null

# 验证
Write-Info "验证写入..."
$localMd5 = (Get-FileHash -Algorithm MD5 $bootImage).Hash.ToLower()
$devMd5Raw = Invoke-AdbShell "cat /dev/block/boot | md5sum"
$devMd5Parts = $devMd5Raw.StdOut -split "\s+"
$devMd5 = $devMd5Parts[0].ToLower()

if ($localMd5 -eq $devMd5) {
    Write-OK ("MD5 一致: " + $localMd5)
}
else {
    Write-Err ("MD5 不一致! 本地=" + $localMd5 + " 设备=" + $devMd5)
    Write-Warn ("如需回滚，备份文件在: " + $backupFile)
    exit 1
}

# 清理
Invoke-AdbShell "rm -f /data/local/tmp/boot_new.img /data/local/tmp/boot_backup.bin" | Out-Null

Write-Host ""
Write-OK "boot 分区刷写完成"
Write-Info ("备份保存在: " + $backupFile)

if (-not $NoReboot) {
    Write-Host ""
    Write-Info "提示: boot 刷完后通常还需要修复 env 分区"
    Write-Info "建议从主菜单选择 [1. 一键修复 Magisk] 完成完整修复"
}
