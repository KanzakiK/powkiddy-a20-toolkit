#!/system/bin/sh
export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

# A20 统一虚拟手柄守护进程启动脚本
# 由 init 服务 (a20_gamepad.rc, class late_start) 拉起，崩溃由 init 自动重启
# 注意：不能等待 sys.boot_completed！守护进程必须在 InputReader 枚举手柄
# 之前创建虚拟设备，才能抢占 ControllerNumber 1（player1），否则霸王宝盒
# 会因"A20 Gamepad 不是 player1"而忽略按键。
# 设备节点未就绪由守护进程内部重试处理。
exec /vendor/bin/a20_gamepad_daemon
