# Restore-FactoryBoot.ps1 - 恢复原厂 boot 分区

param([switch]$NoReboot)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

$toolkitRoot = Split-Path $modulesDir
$bootImage = Join-Path $toolkitRoot "files\factory_boot.img"

Write-Title "恢复原厂 boot"

if (-not (Find-Adb)) { exit 1 }
if (-not (Test-Path $bootImage)) {
    Write-Err ("找不到 factory_boot.img: " + $bootImage)
    exit 1
}
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# 检查当前 boot
Write-Info "检查当前 boot 分区..."
$curMd5Raw = Invoke-AdbShell "cat /dev/block/boot | md5sum"
$curMd5 = ($curMd5Raw.StdOut -split "\s+")[0].ToLower()
$srcMd5 = (Get-FileHash -Algorithm MD5 $bootImage).Hash.ToLower()
Write-Log ("  当前 boot MD5: " + $curMd5)
Write-Log ("  原厂 boot MD5: " + $srcMd5)

if ($curMd5 -eq $srcMd5) {
    Write-OK "boot 分区已经是原厂镜像，无需操作"
    exit 0
}

# 备份当前 boot
Write-Info "备份当前 boot..."
Invoke-AdbShell "dd if=/dev/block/boot of=/data/local/tmp/boot_before_restore.bin bs=1048576 count=16 2>&1" | Out-Null
$backupDir = Join-Path $toolkitRoot "backup"
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupFile = Join-Path $backupDir ("boot_before_restore_" + $timestamp + ".img")
Invoke-Adb @("pull", "/data/local/tmp/boot_before_restore.bin", $backupFile) 2>&1 | Out-Null
if (Test-Path $backupFile) {
    Write-OK ("备份已保存: " + $backupFile)
}
Invoke-AdbShell "rm -f /data/local/tmp/boot_before_restore.bin" | Out-Null

# 推送并刷写
Write-Info "推送原厂 boot..."
Invoke-Adb @("push", $bootImage, "/data/local/tmp/factory_boot.bin") 2>&1 | Out-Null

Write-Info "写入 boot 分区..."
Invoke-AdbShell "dd if=/data/local/tmp/factory_boot.bin of=/dev/block/boot bs=1048576 count=16 2>&1" | Out-Null

# 验证
Write-Info "验证写入..."
$devMd5Raw = Invoke-AdbShell "cat /dev/block/boot | md5sum"
$devMd5 = ($devMd5Raw.StdOut -split "\s+")[0].ToLower()

if ($devMd5 -eq $srcMd5) {
    Write-OK ("MD5 一致: " + $srcMd5)
}
else {
    Write-Err ("MD5 不一致! 期望=" + $srcMd5 + " 实际=" + $devMd5)
    Write-Warn ("如需回滚，备份文件在: " + $backupFile)
    exit 1
}

Invoke-AdbShell "rm -f /data/local/tmp/factory_boot.bin" | Out-Null

Write-Host ""
Write-OK "原厂 boot 已恢复"
Write-Warn "注意: 原厂 boot 不含 Magisk，重启后 Magisk 将失效"
Write-Info ("备份保存在: " + $backupFile)
