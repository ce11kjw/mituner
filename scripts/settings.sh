#!/system/bin/sh
# 模块设置管理脚本
# 作者: 呆呆 | QQ:891354018 | 群:774886621
# 用法:
#   sh settings.sh get              获取所有设置（JSON）
#   sh settings.sh set <key> <val>  设置单项
#
# 配置项:
#   auto_clean_on_boot          开机自动清理 (0/1)
#   auto_clean_on_codev_start   游戏启动时自动清理 (0/1)
#   auto_clean_on_codev_stop    游戏退出时自动清理 (0/1)
#   clean_mode                  清理模式 (light/deep)

MOD_DIR="/data/adb/modules/webui_info"
SETTINGS_FILE="$MOD_DIR/settings.conf"
ACTION="$1"
KEY="$2"
VAL="$3"

# 只允许 a-z0-9_ 的 key，杜绝正则元字符
is_valid_key() {
    case "$1" in
        ""|*[!a-z0-9_]*) return 1 ;;
        *) return 0 ;;
    esac
}
# 值只允许安全字符（字母数字、下划线、冒号、空格、点、斜杠、中文）
is_valid_val() {
    case "$1" in
        *[!A-Za-z0-9_:./\ -]*) return 1 ;;
        *) return 0 ;;
    esac
}

read_setting() {
    local key="$1"
    [ -f "$SETTINGS_FILE" ] || return
    awk -F'=' -v k="$key" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$SETTINGS_FILE" 2>/dev/null
}

write_setting() {
    local key="$1"
    local val="$2"
    is_valid_key "$key" || return 1
    is_valid_val "$val" || return 1
    [ -f "$SETTINGS_FILE" ] || touch "$SETTINGS_FILE"
    # 用 awk 重写整个文件，避免 sed 替换串注入（& | \ 等）
    local TMP="${SETTINGS_FILE}.tmp.$$"
    awk -F'=' -v k="$key" -v v="$val" '
        BEGIN{done=0}
        {
            if ($1==k) { print k"="v; done=1 }
            else print
        }
        END{ if(!done) print k"="v }
    ' "$SETTINGS_FILE" > "$TMP" 2>/dev/null && mv -f "$TMP" "$SETTINGS_FILE"
    return 0
}

case "$ACTION" in
    get)
        AUTO_BOOT=$(read_setting auto_clean_on_boot)
        AUTO_START=$(read_setting auto_clean_on_codev_start)
        AUTO_STOP=$(read_setting auto_clean_on_codev_stop)
        MODE=$(read_setting clean_mode)
        LAST_CLEAN=$(read_setting last_clean_time)
        CUR_SPOOF=$(read_setting current_spoof)
        CUR_LABEL=$(read_setting current_spoof_label)
        ORIG_MODEL=$(read_setting orig_model)
        HIDE_ENV=$(read_setting auto_hide_env)
        SE_FIX=$(read_setting auto_sepolicy_fix)

        # 默认值
        [ -z "$AUTO_BOOT" ] && AUTO_BOOT="1"
        [ -z "$AUTO_START" ] && AUTO_START="0"
        [ -z "$AUTO_STOP" ] && AUTO_STOP="0"
        [ -z "$MODE" ] && MODE="deep"
        [ -z "$HIDE_ENV" ] && HIDE_ENV="0"
        [ -z "$SE_FIX" ] && SE_FIX="0"

        printf '{"auto_clean_on_boot":"%s","auto_clean_on_codev_start":"%s","auto_clean_on_codev_stop":"%s","clean_mode":"%s","last_clean":"%s","current_spoof":"%s","current_spoof_label":"%s","orig_model":"%s","auto_hide_env":"%s","auto_sepolicy_fix":"%s"}\n' \
            "$AUTO_BOOT" "$AUTO_START" "$AUTO_STOP" "$MODE" \
            "${LAST_CLEAN:-从未}" "${CUR_SPOOF:-none}" "${CUR_LABEL:-原机型}" "${ORIG_MODEL:-未知}" "$HIDE_ENV" "$SE_FIX"
        ;;

    set)
        if [ -z "$KEY" ] || [ -z "$VAL" ]; then
            echo '{"ok":false,"error":"missing key or value"}'
            exit 1
        fi
        # clean_mode 只允许 light/deep
        if [ "$KEY" = "clean_mode" ]; then
            case "$VAL" in light|deep) ;; *) echo '{"ok":false,"error":"clean_mode must be light or deep"}'; exit 1 ;; esac
        fi
        case "$KEY" in
            auto_clean_on_boot|auto_clean_on_codev_start|auto_clean_on_codev_stop|clean_mode|auto_hide_env|auto_sepolicy_fix)
                if ! write_setting "$KEY" "$VAL"; then
                    echo '{"ok":false,"error":"invalid key or value"}'
                    exit 1
                fi

                # 副作用：切换 start/stop 开关时自动启停监听
                case "$KEY" in
                    auto_clean_on_codev_start|auto_clean_on_codev_stop)
                        START_EN=$(read_setting auto_clean_on_codev_start)
                        STOP_EN=$(read_setting auto_clean_on_codev_stop)
                        if [ "$START_EN" = "1" ] || [ "$STOP_EN" = "1" ]; then
                            sh "$MOD_DIR/scripts/monitor.sh" start >/dev/null 2>&1
                        else
                            sh "$MOD_DIR/scripts/monitor.sh" stop >/dev/null 2>&1
                        fi
                        ;;
                esac

                printf '{"ok":true,"key":"%s","val":"%s"}\n' "$KEY" "$VAL"
                ;;
            *)
                echo '{"ok":false,"error":"unknown key"}'
                exit 1
                ;;
        esac
        ;;

    *)
        echo '{"ok":false,"error":"unknown action - use: get | set"}'
        exit 1
        ;;
esac
