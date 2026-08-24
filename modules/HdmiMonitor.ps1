# HdmiMonitor.ps1 - HDMI 自动分辨率切换脚本 安装/卸载模块
# 部署位置：/vendor（独立 ext4 直写持久；不受 Magisk system overlay 影响）
# 兼容：安装/卸载时自动清理旧版 /system 部署，避免 init 重复注册同名 service

param(
    [ValidateSet("install", "uninstall")]
    [string]$Action = "install"
)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

$toolkitRoot = Split-Path $modulesDir
$filesDir = Join-Path $toolkitRoot "files"
$shFile = Join-Path $filesDir "hdmi_monitor.sh"
$rcFile = Join-Path $filesDir "hdmi_monitor.rc"

# 设备端目标路径（/vendor 直写持久）
$VendorSh = "/vendor/bin/hdmi_monitor.sh"
$VendorRc = "/vendor/etc/init/hdmi_monitor.rc"
# 旧版 /system 部署路径（v1 兼容清理）
$LegacySh = "/system/bin/hdmi_monitor.sh"
$LegacyRc = "/system/etc/init/hdmi_monitor.rc"

if ($Action -eq "install") {
    Write-Title "HDMI 自动分辨率切换脚本 - 安装"
}
else {
    Write-Title "HDMI 自动分辨率切换脚本 - 卸载"
}

# 公共检查
if (-not (Find-Adb)) { exit 1 }
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# remount /vendor 可写
function Do-RemountVendor {
    Invoke-AdbShell "mount -o remount,rw /vendor 2>/dev/null" | Out-Null
    Start-Sleep -Milliseconds 500
}
function Do-RemountVendorRo {
    Invoke-AdbShell "mount -o remount,ro /vendor 2>/dev/null" | Out-Null
}

# 清理旧版 /system 部署（避免 init 重复注册同名 service）
# 注意：删 /system 文件必须先 remount /system 可写（仅 remount /vendor 不够）
function Remove-LegacySystemFiles {
    Write-Info "清理旧版 /system 部署（兼容迁移）..."
    $legacy = Invoke-AdbShell "ls $LegacySh $LegacyRc 2>/dev/null"
    if ($legacy.StdOut -match "hdmi_monitor") {
        Invoke-Adb @("remount") 2>&1 | Out-Null
        Invoke-AdbShell "mount -o rw,remount / 2>/dev/null" | Out-Null
        Invoke-AdbShell "rm -f $LegacySh $LegacyRc $LegacySh.bak $LegacyRc.bak" | Out-Null
        $chk = Invoke-AdbShell "ls $LegacySh $LegacyRc 2>/dev/null"
        if ($chk.StdOut -match "hdmi_monitor") { Write-Warn "旧版 /system 文件清理失败（可能被 Magisk overlay 保护，请手动处理）" }
        else { Write-OK "旧版 /system 文件已清理" }
    }
    else {
        Write-Info "未发现旧版 /system 部署"
    }
}

if ($Action -eq "install") {
    # ===== 安装 =====
    if (-not (Test-Path $shFile) -or -not (Test-Path $rcFile)) {
        Write-Err "缺少文件: hdmi_monitor.sh 或 hdmi_monitor.rc"
        exit 1
    }

    # 检查平台
    Write-Info "检查平台兼容性..."
    $platformCheck = Invoke-AdbShell "cat /proc/mounts"
    if ($platformCheck.StdOut -match "amlogic") {
        Write-OK "检测到 Amlogic 平台"
    }
    else {
        Write-Warn "未检测到 Amlogic 平台，可能不兼容"
    }

    Do-RemountVendor

    # 备份已有文件（必须在 remount 之后！源不存在则跳过）
    Write-Info "备份已有文件..."
    foreach ($f in @($VendorSh, $VendorRc)) {
        $leaf = Split-Path $f -Leaf
        $src = Invoke-AdbShell "ls $f 2>/dev/null"
        if ($src.StdOut -match [regex]::Escape($leaf)) {
            Invoke-AdbShell "cp $f ${f}.bak" | Out-Null
            $v = Invoke-AdbShell "ls ${f}.bak 2>/dev/null"
            if ($v.StdOut -match "$leaf\.bak") { Write-OK "$leaf 已备份" }
            else { Write-Warn "$leaf 备份失败（/vendor 可能仍不可写）" }
        }
        else {
            Write-Info "$leaf 不存在，跳过备份"
        }
    }

    # 清理旧版 /system 部署
    Remove-LegacySystemFiles

    # 推送 sh
    Write-Info "安装 hdmi_monitor.sh..."
    Invoke-Adb @("push", $shFile, "/data/local/tmp/hdmi_monitor.sh") 2>&1 | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/hdmi_monitor.sh $VendorSh" | Out-Null
    Invoke-AdbShell "chmod 755 $VendorSh" | Out-Null
    Write-OK "hdmi_monitor.sh 已安装"

    # 推送 rc
    Write-Info "安装 hdmi_monitor.rc..."
    Invoke-Adb @("push", $rcFile, "/data/local/tmp/hdmi_monitor.rc") 2>&1 | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/hdmi_monitor.rc $VendorRc" | Out-Null
    Invoke-AdbShell "chmod 644 $VendorRc" | Out-Null
    Write-OK "hdmi_monitor.rc 已安装"

    Do-RemountVendorRo

    # 清理临时
    Invoke-AdbShell "rm -f /data/local/tmp/hdmi_monitor.sh /data/local/tmp/hdmi_monitor.rc" 2>&1 | Out-Null

    # 验证
    Write-Info "验证安装..."
    $v1 = Invoke-AdbShell "ls $VendorSh"
    $v2 = Invoke-AdbShell "ls $VendorRc"
    if ($v1.StdOut -match "hdmi_monitor.sh") { Write-OK "hdmi_monitor.sh 验证通过" }
    else { Write-Err "hdmi_monitor.sh 验证失败" }
    if ($v2.StdOut -match "hdmi_monitor.rc") { Write-OK "hdmi_monitor.rc 验证通过" }
    else { Write-Err "hdmi_monitor.rc 验证失败" }

    Write-Host ""
    Write-OK "安装完成（/vendor），脚本将在下次开机后自动运行"
    $reboot = Read-Host "是否立即重启设备? (y/n)"
    if ($reboot -match "^[yY]") {
        Write-Info "设备重启中..."
        Invoke-Adb @("reboot") | Out-Null
        Write-OK "重启完成"
    }
}
else {
    # ===== 卸载 =====
    Write-Info "停止 hdmi_monitor 服务..."
    Invoke-AdbShell "stop hdmi_monitor 2>/dev/null" | Out-Null
    Write-OK "服务已停止"

    Do-RemountVendor

    # 删除文件（含旧版 /system 残留）
    Write-Info "删除文件..."
    Invoke-AdbShell "rm -f $VendorSh $VendorRc $VendorSh.bak $VendorRc.bak" | Out-Null
    Invoke-AdbShell "rm -f $LegacySh $LegacyRc $LegacySh.bak $LegacyRc.bak" | Out-Null
    Write-OK "文件已删除"

    Do-RemountVendorRo

    # 恢复分辨率
    Write-Info "恢复默认分辨率..."
    Invoke-AdbShell "wm size reset" 2>&1 | Out-Null
    Invoke-AdbShell "wm density reset" 2>&1 | Out-Null
    Write-OK "分辨率已恢复"

    # 验证
    Write-Info "验证卸载..."
    $v1 = Invoke-AdbShell "ls $VendorSh 2>&1"
    $v2 = Invoke-AdbShell "ls $VendorRc 2>&1"
    if ($v1.StdOut -match "No such") { Write-OK "hdmi_monitor.sh 已移除" }
    else { Write-Warn "hdmi_monitor.sh 仍存在" }
    if ($v2.StdOut -match "No such") { Write-OK "hdmi_monitor.rc 已移除" }
    else { Write-Warn "hdmi_monitor.rc 仍存在" }

    Write-Host ""
    Write-OK "卸载完成，重启后生效"
    $reboot = Read-Host "是否立即重启设备? (y/n)"
    if ($reboot -match "^[yY]") {
        Write-Info "设备重启中..."
        Invoke-Adb @("reboot") | Out-Null
        Write-OK "重启完成"
    }
}
