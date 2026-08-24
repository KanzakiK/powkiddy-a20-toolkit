# GamepadFix.ps1 - 标准手柄修复（按键重映射 + 摇杆行程修复） 安装/卸载模块
# 说明：
#   1) 按键重映射：kl 写入 /vendor/usr/keylayout/（设备固定读取此路径）
#   2) 摇杆修复：uinput 守护进程读物理轴(±155)归一化合成标准虚拟手柄，
#      经 init 服务(a20_gamepad.rc)开机自启，并 grab 物理设备先于 Moonlight 抢占
#   落点统一为 /vendor（独立 ext4 直写持久；/system 在此机是临时 overlay 会丢）

param(
    [ValidateSet("install", "uninstall")]
    [string]$Action = "install"
)

$modulesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $modulesDir "Common.psm1") -Force

$toolkitRoot = Split-Path $modulesDir
$filesDir = Join-Path $toolkitRoot "files"
$klFile = Join-Path $filesDir "Vendor_0001_Product_0001.kl"
$origFile = Join-Path $filesDir "Vendor_0001_Product_0001.kl.orig"
$daemonFile = Join-Path $filesDir "a20_gamepad_daemon"
$shFile = Join-Path $filesDir "a20_gamepad.sh"
$rcFile = Join-Path $filesDir "a20_gamepad.rc"
$restartShFile = Join-Path $filesDir "a20_gamepad_restart.sh"
$restartRcFile = Join-Path $filesDir "a20_gamepad_restart.rc"

# 设备端目标路径（/vendor 直写持久）
$VendorKl      = "/vendor/usr/keylayout/Vendor_0001_Product_0001.kl"
$VendorDaemon  = "/vendor/bin/a20_gamepad_daemon"
$VendorSh      = "/vendor/bin/a20_gamepad.sh"
$VendorRc      = "/vendor/etc/init/a20_gamepad.rc"
$VendorRestartSh = "/vendor/bin/a20_gamepad_restart.sh"
$VendorRestartRc = "/vendor/etc/init/a20_gamepad_restart.rc"

if ($Action -eq "install") {
    Write-Title "标准手柄修复 - 安装"
}
else {
    Write-Title "标准手柄修复 - 卸载"
}

# 公共检查
if (-not (Find-Adb)) { exit 1 }
if (-not (Test-DeviceConnection)) { exit 1 }
if (-not (Enable-RootAdb)) { exit 1 }

# remount /vendor 可写（注意：此机 /system 不可持久写入，一律用 /vendor）
function Do-RemountVendor {
    Invoke-AdbShell "mount -o remount,rw /vendor 2>/dev/null" | Out-Null
    Start-Sleep -Milliseconds 500
}
function Do-RemountVendorRo {
    Invoke-AdbShell "mount -o remount,ro /vendor 2>/dev/null" | Out-Null
}

if ($Action -eq "install") {
    # ===== 安装 =====
    foreach ($f in @($klFile, $daemonFile, $shFile, $rcFile, $restartShFile, $restartRcFile)) {
        if (-not (Test-Path $f)) {
            Write-Err "缺少文件: $f"
            exit 1
        }
    }

    # 备份现有 kl
    # 推送临时文件
    Write-Info "推送文件到设备..."
    Invoke-Adb @("push", $klFile, "/data/local/tmp/Vendor_0001_Product_0001.kl") 2>&1 | Out-Null
    Invoke-Adb @("push", $daemonFile, "/data/local/tmp/a20_gamepad_daemon") 2>&1 | Out-Null
    Invoke-Adb @("push", $shFile, "/data/local/tmp/a20_gamepad.sh") 2>&1 | Out-Null
    Invoke-Adb @("push", $rcFile, "/data/local/tmp/a20_gamepad.rc") 2>&1 | Out-Null
    Invoke-Adb @("push", $restartShFile, "/data/local/tmp/a20_gamepad_restart.sh") 2>&1 | Out-Null
    Invoke-Adb @("push", $restartRcFile, "/data/local/tmp/a20_gamepad_restart.rc") 2>&1 | Out-Null

    Do-RemountVendor

    # 备份原厂 kl（必须在 remount 之后！否则 /vendor 只读会静默失败）
    # 语义：仅当 ①无备份 且 ②当前 kl 是原厂（不含 BUTTON_）时才备份，
    #       避免把手柄版 kl 当"原厂备份"，导致卸载时恢复了个寂寞
    Write-Info "检查按键映射备份..."
    $hasBak = Invoke-AdbShell "ls ${VendorKl}.bak 2>/dev/null"
    $curKl  = Invoke-AdbShell "grep -c BUTTON_ $VendorKl 2>/dev/null"
    $isGamepadKl = ($curKl.StdOut.Trim() -match "^[1-9]")
    if ($hasBak.StdOut -match "Vendor_0001_Product_0001.kl.bak") {
        Write-OK "已存在原厂备份，跳过"
    }
    elseif (-not $isGamepadKl) {
        Invoke-AdbShell "cp $VendorKl ${VendorKl}.bak" | Out-Null
        $v = Invoke-AdbShell "ls -la ${VendorKl}.bak 2>/dev/null"
        if ($v.StdOut -match "Vendor_0001_Product_0001.kl.bak") {
            Write-OK "原厂 kl 已备份（来自设备）"
        }
        else {
            Write-Err "备份失败！请检查 /vendor 是否可写"
        }
    }
    elseif (Test-Path $origFile) {
        # 设备已是手柄版，但工具箱内置了原厂 kl → 用它建备份，保证卸载可还原
        Invoke-Adb @("push", $origFile, "/data/local/tmp/Vendor_0001_Product_0001.kl.orig") 2>&1 | Out-Null
        Invoke-AdbShell "cp /data/local/tmp/Vendor_0001_Product_0001.kl.orig ${VendorKl}.bak" | Out-Null
        $v = Invoke-AdbShell "ls -la ${VendorKl}.bak 2>/dev/null"
        if ($v.StdOut -match "Vendor_0001_Product_0001.kl.bak") {
            Write-OK "原厂 kl 已备份（来自工具箱内置）"
        }
        else {
            Write-Err "备份失败！"
        }
        Invoke-AdbShell "rm -f /data/local/tmp/Vendor_0001_Product_0001.kl.orig" | Out-Null
    }
    else {
        Write-Warn "当前 kl 已是手柄版且无原厂备份可用，卸载时将保留现状"
    }

    # 安装按键 kl
    Write-Info "安装按键映射 (kl)..."
    Invoke-AdbShell "mkdir -p /vendor/usr/keylayout" | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/Vendor_0001_Product_0001.kl $VendorKl" | Out-Null
    Invoke-AdbShell "chcon u:object_r:vendor_configs_file:s0 $VendorKl 2>/dev/null" | Out-Null

    # 安装摇杆守护进程 + init 服务
    Write-Info "安装摇杆守护进程 + init 自启服务..."
    Invoke-AdbShell "mkdir -p /vendor/bin /vendor/etc/init" | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/a20_gamepad_daemon $VendorDaemon" | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/a20_gamepad.sh $VendorSh" | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/a20_gamepad.rc $VendorRc" | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/a20_gamepad_restart.sh $VendorRestartSh" | Out-Null
    Invoke-AdbShell "cp /data/local/tmp/a20_gamepad_restart.rc $VendorRestartRc" | Out-Null
    Invoke-AdbShell "chmod 755 $VendorDaemon $VendorSh $VendorRestartSh" | Out-Null
    Invoke-AdbShell "chmod 644 $VendorRc $VendorRestartRc" | Out-Null

    Do-RemountVendorRo

    # 清理临时
    Invoke-AdbShell "rm -f /data/local/tmp/Vendor_0001_Product_0001.kl /data/local/tmp/a20_gamepad_daemon /data/local/tmp/a20_gamepad.sh /data/local/tmp/a20_gamepad.rc /data/local/tmp/a20_gamepad_restart.sh /data/local/tmp/a20_gamepad_restart.rc" | Out-Null

    # 验证
    Write-Info "验证安装..."
    $files = @($VendorKl, $VendorDaemon, $VendorSh, $VendorRc, $VendorRestartSh, $VendorRestartRc)
    foreach ($p in $files) {
        $v = Invoke-AdbShell "ls -la $p 2>/dev/null"
        if ($v.StdOut -match [regex]::Escape((Split-Path $p -Leaf))) {
            Write-OK "$(Split-Path $p -Leaf) 验证通过"
        }
        else {
            Write-Err "$(Split-Path $p -Leaf) 验证失败"
        }
    }

    Write-Host ""
    Write-OK "安装完成，重启后生效（按键映射 + 摇杆修复）"
    $reboot = Read-Host "是否立即重启设备? (y/n)"
    if ($reboot -match "^[yY]") {
        Write-Info "设备重启中..."
        Invoke-Adb @("reboot") | Out-Null
        Write-OK "重启完成，开机后守护进程自动运行"
    }
}
else {
    # ===== 卸载 =====
    Write-Info "停止 a20_gamepad 服务..."
    Invoke-AdbShell "stop a20_gamepad 2>/dev/null" | Out-Null
    Invoke-AdbShell "stop a20_gamepad_restart 2>/dev/null" | Out-Null

    Do-RemountVendor

    Write-Info "删除守护进程与 init 服务..."
    Invoke-AdbShell "rm -f $VendorDaemon $VendorSh $VendorRc $VendorRestartSh $VendorRestartRc" | Out-Null

    Write-Info "恢复按键映射备份..."
    $bak = Invoke-AdbShell "ls ${VendorKl}.bak 2>/dev/null"
    if ($bak.StdOut -match "Vendor_0001_Product_0001.kl.bak") {
        Invoke-AdbShell "cp ${VendorKl}.bak $VendorKl" | Out-Null
        Invoke-AdbShell "rm -f ${VendorKl}.bak" | Out-Null
        Write-OK "按键映射已恢复为备份"
    }
    elseif (Test-Path $origFile) {
        # 设备上无备份，但工具箱内置原厂 kl → 直接还原
        Invoke-Adb @("push", $origFile, "/data/local/tmp/Vendor_0001_Product_0001.kl.orig") 2>&1 | Out-Null
        Invoke-AdbShell "cp /data/local/tmp/Vendor_0001_Product_0001.kl.orig $VendorKl" | Out-Null
        Invoke-AdbShell "rm -f /data/local/tmp/Vendor_0001_Product_0001.kl.orig" | Out-Null
        Invoke-AdbShell "chcon u:object_r:vendor_configs_file:s0 $VendorKl 2>/dev/null" | Out-Null
        Write-OK "按键映射已恢复为原厂（来自工具箱内置）"
    }
    else {
        Write-Warn "未找到按键映射备份，保留当前 kl（如需还原请手动处理）"
    }

    Do-RemountVendorRo

    # 验证
    Write-Info "验证卸载..."
    foreach ($p in @($VendorDaemon, $VendorSh, $VendorRc, $VendorRestartSh, $VendorRestartRc)) {
        $v = Invoke-AdbShell "ls $p 2>&1"
        if ($v.StdOut -match "No such") { Write-OK "$(Split-Path $p -Leaf) 已移除" }
        else { Write-Warn "$(Split-Path $p -Leaf) 仍存在" }
    }

    Write-Host ""
    Write-OK "卸载完成，重启后生效"
    $reboot = Read-Host "是否立即重启设备? (y/n)"
    if ($reboot -match "^[yY]") {
        Write-Info "设备重启中..."
        Invoke-Adb @("reboot") | Out-Null
        Write-OK "重启完成"
    }
}
