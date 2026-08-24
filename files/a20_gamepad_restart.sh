#!/system/bin/sh
# A20 手柄修复 - 开机后组合拳
# 原因：霸王宝盒开机自启时缓存的设备列表不含虚拟手柄（player1），导致按键被拒。
# 修复：重建虚拟设备（重启守护进程）+ 重启霸王宝盒进程（重新枚举设备）。
# 由 init oneshot service (a20_gamepad_restart.rc) 在 boot_completed 后拉起。
export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

sleep 15

# 1. 重建虚拟设备（重启守护进程，init 会重新拉起）
stop a20_gamepad 2>/dev/null
sleep 2
start a20_gamepad 2>/dev/null
sleep 8

# 2. 重启霸王宝盒进程（重新枚举，识别 player1 虚拟手柄）
killall com.tigerleap.gamebox 2>/dev/null
am start -n com.tigerleap.gamebox/com.tigerleap.gamebox.activity.GameHomeActivity 2>/dev/null
