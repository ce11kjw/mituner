#!/system/bin/sh
# 进程监听脚本（无畏契约启动/退出自动清理）
# 作者: 呆呆 | QQ:891354018 | 群:774886621
# 用法:
#   sh monitor.sh start    启动监听（后台常驻）
#   sh monitor.sh stop     停止监听
#   sh monitor.sh status   查询监听状态

MOD_DIR="/data/adb/modules/webui_info"
SETTINGS_FILE="$MOD_DIR/settings.conf"
LOG_FILE="/data/local/tmp/webui_monitor.log"
PID_FILE="/data/local/tmp/webui_monitor.pid"
TARGET_PKG="com.tencent.tmgp.codev"
ACTION="$1"

read_setting() {
    local key="$1"
    [ -f "$SETTINGS_FILE" ] && grep -E "^${key}=" "$SETTINGS_FILE" | head -1 | cut -d'=' -f2-
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ============ 监听主循环（前台执行）============
run_monitor() {
    log "===== 监听脚本启动 PID=$$ ====="
    LAST_CLEAN_TS=0

    trigger_clean() {
        local reason="$1"
        local now=$(date +%s)
        local diff=$((now - LAST_CLEAN_TS))
        if [ $diff -lt 3 ]; then
            log "防抖跳过 ($reason)"
            return
        fi
        LAST_CLEAN_TS=$now
        local mode=$(read_setting clean_mode)
        [ -z "$mode" ] && mode="deep"
        log "触发清理 ($reason, 模式: $mode)"
        sh "$MOD_DIR/scripts/cleaner.sh" "$mode" >> "$LOG_FILE" 2>&1
    }

    while true; do
        logcat -b main -T 1 ActivityManager:I '*:S' 2>/dev/null | while IFS= read -r line; do

            # 进程启动检测
            if echo "$line" | grep -qE "Start proc.*$TARGET_PKG|START.*cmp=$TARGET_PKG"; then
                AUTO_START=$(read_setting auto_clean_on_codev_start)
                if [ "$AUTO_START" = "1" ]; then
                    trigger_clean "进程启动"
                fi
            fi

            # 进程结束检测
            if echo "$line" | grep -qE "Killing.*$TARGET_PKG|Process $TARGET_PKG.*has died"; then
                AUTO_STOP=$(read_setting auto_clean_on_codev_stop)
                if [ "$AUTO_STOP" = "1" ]; then
                    sleep 2
                    if ! pgrep -f "$TARGET_PKG" >/dev/null 2>&1; then
                        trigger_clean "进程退出"
                    fi
                fi
            fi
        done

        log "logcat 退出，5 秒后重连"
        sleep 5
    done
}

# ============ 主入口 ============
case "$ACTION" in
    start)
        # 防止重复启动
        if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
                log "已在运行 PID=$OLD_PID，跳过"
                exit 0
            fi
        fi
        # fork 到后台
        ( run_monitor ) &
        BG_PID=$!
        echo "$BG_PID" > "$PID_FILE"
        log "监听后台运行 PID=$BG_PID"
        ;;

    stop)
        if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
                kill "$OLD_PID" 2>/dev/null
                # 只杀掉本脚本派生的 logcat（按父进程匹配，不误伤其他工具）
                for p in $(pgrep -f "logcat -b main -T 1 ActivityManager" 2>/dev/null); do
                    [ "$p" != "$$" ] && [ "$p" != "$OLD_PID" ] && kill "$p" 2>/dev/null
                done
                log "监听已停止 PID=$OLD_PID"
                rm -f "$PID_FILE"
                echo '{"ok":true,"msg":"监听已停止"}'
            else
                rm -f "$PID_FILE"
                echo '{"ok":false,"error":"未在运行"}'
            fi
        else
            echo '{"ok":false,"error":"未在运行"}'
        fi
        ;;

    restart)
        sh "$0" stop >/dev/null 2>&1
        sleep 1
        sh "$0" start
        echo '{"ok":true,"msg":"监听已重启"}'
        ;;

    status)
        if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
                printf '{"running":true,"pid":"%s"}\n' "$OLD_PID"
                exit 0
            fi
        fi
        echo '{"running":false}'
        ;;

    *)
        # 没参数时直接前台运行（兼容旧调用方式）
        run_monitor
        ;;
esac
