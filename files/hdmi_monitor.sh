#!/system/bin/sh
export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

# ==========================================
# 1. 基础功能模块
# ==========================================
mute_local_speaker() {
    tinymix 31 None; tinymix 32 None; tinymix 33 None; tinymix 34 None
}

unmute_local_speaker() {
    tinymix 31 LOLP_SEL_DACL; tinymix 32 LOLN_SEL_DACL_INV
    tinymix 33 LORP_SEL_DACR; tinymix 34 LORN_SEL_DACR_INV
}

auto_turn_off_local_screen() {
    # 使用简单的文件锁代替 PID，更稳定
    [ -f /data/local/tmp/hdmi_lock ] && return
    (
        touch /data/local/tmp/hdmi_lock
        sleep 10
        if [ "$(cat /sys/class/amhdmitx/amhdmitx0/hpd_state 2>/dev/null)" == "1" ]; then
            for bl in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness; do
                [ -f "$bl" ] && echo 0 > "$bl"
            done
        fi
        rm /data/local/tmp/hdmi_lock 2>/dev/null
    ) &
}

restore_local_screen() {
    rm /data/local/tmp/hdmi_lock 2>/dev/null
    SYS_BRIGHT=$(settings get system screen_brightness 2>/dev/null)
    [ -z "$SYS_BRIGHT" ] && SYS_BRIGHT=128 
    for bl in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness; do
        [ -f "$bl" ] && echo "$SYS_BRIGHT" > "$bl"
    done
}

# ==========================================
# 2. 开机同步等待
# ==========================================
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 5

# ==========================================
# 3. 核心运行循环
# ==========================================
LAST_STATE=-1 

while true; do
    if [ -f /sys/class/amhdmitx/amhdmitx0/hpd_state ]; then
        CURRENT_STATE=$(cat /sys/class/amhdmitx/amhdmitx0/hpd_state)
    else
        CURRENT_STATE=0
    fi

    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        if [ "$CURRENT_STATE" == "1" ]; then
            # --- [关键改进：热插拔防抖] ---
            # 先给原生系统 2 秒钟去处理它的 HDMI 逻辑
            sleep 2
            
            # 强制重置一次渲染尺寸，确保夺回控制权
            wm size reset
            sleep 0.5
            wm size 1280x720
            wm density 213
            mute_local_speaker 
            
            # 4K 重载逻辑
            input keyevent 223
            sleep 3
            input keyevent 224
            
            auto_turn_off_local_screen
        else
            # --- [恢复模式] ---
            wm size reset
            sleep 0.5
            wm size 640x480
            wm density 160
            unmute_local_speaker
            restore_local_screen
        fi
        LAST_STATE=$CURRENT_STATE
    fi

    # 持续监控：只要亮着就熄屏
    if [ "$CURRENT_STATE" == "1" ]; then
        IS_BRIGHT=0
        for bl in /sys/class/backlight/*/brightness /sys/class/leds/lcd-backlight/brightness; do
            if [ -f "$bl" ]; then
                [ $(cat "$bl") -gt 0 ] && IS_BRIGHT=1
                break
            fi
        done
        [ "$IS_BRIGHT" == "1" ] && auto_turn_off_local_screen
    fi
    
    sleep 3
done
