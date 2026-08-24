param([string]$key)
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$texts = @{
    "title"       = "Powkiddy A20 搞机工具箱"

    "main_1"      = "1. Magisk 管理"
    "main_2"      = "2. HDMI 脚本"
    "main_3"      = "3. 恢复原厂"
    "main_4"      = "4. 手柄修复"
    "main_0"      = "0. 退出"

    "magisk_t"    = "Magisk 管理"
    "magisk_1"    = "1. 一键修复 Magisk          (boot + env, 升级后推荐)"
    "magisk_2"    = "2. 刷写 Magisk boot 分区    (仅 boot)"
    "magisk_3"    = "3. 修复 env 分区            (仅 env)"
    "back"        = "0. 返回主菜单"

    "hdmi_t"      = "HDMI 脚本"
    "hdmi_1"      = "1. 安装 HDMI 脚本"
    "hdmi_2"      = "2. 卸载 HDMI 脚本"

    "factory_t"   = "恢复原厂"
    "factory_1"   = "1. 恢复原厂 boot"
    "factory_2"   = "2. 恢复原厂 su"
    "factory_3"   = "3. 完全恢复原厂            (boot + su + env)"

    "gamepad_t"   = "标准手柄修复"
    "gamepad_1"   = "1. 安装手柄修复          (按键重映射 + 摇杆行程)"
    "gamepad_2"   = "2. 卸载手柄修复"

    "prompt"      = "请输入数字选择操作"
    "invalid"     = "[!!] 无效选择，请重新输入。"
    "bye"         = "再见！"
}

if ($texts.ContainsKey($key)) {
    Write-Host $texts[$key]
}
