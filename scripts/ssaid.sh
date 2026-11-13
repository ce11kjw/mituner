#!/system/bin/sh
# SSAID + 图标提取脚本（流式输出，避免大变量）
# 作者: 呆呆 | QQ:891354018 | 群:774886621

SSAID_FILE="/data/system/users/0/settings_ssaid.xml"
ICON_CACHE_DIR="/data/adb/modules/webui_info/webroot/icons/cache"
ACTION="$1"
PKG="$2"

TARGET_APPS="com.tencent.ngr|王者荣耀世界|res/drawable-xhdpi-v4/icon.png|res/mipmap-xxxhdpi-v4/ic_launcher.png|res/mipmap-xxhdpi-v4/ic_launcher.png
com.tencent.tmgp.pubgmhd|和平精英|res/drawable-xxhdpi-v4/icon.png|res/drawable-xhdpi-v4/icon.png|res/drawable-hdpi-v4/icon.png
com.tencent.tmgp.sgame|王者荣耀|res/mipmap-xxxhdpi-v4/app_icon_round.png|res/mipmap-xxxhdpi-v4/app_icon.png|res/drawable-xxxhdpi-v4/icon.png
com.tencent.tmgp.codev|无畏契约手游|res/drawable-xxxhdpi-v4/icon.png|res/mipmap-xxxhdpi-v4/ic_launcher.png|res/drawable-xxhdpi-v4/icon.png
com.tencent.tmgp.cf|穿越火线枪战王者|res/drawable-xxxhdpi-v4/app_icon.png|assets/AppIcon/UnCompress_CF_Appicon_192.png|res/drawable-xxhdpi-v4/app_icon.png
com.tencent.tmgp.cod|使命召唤手游|res/mipmap-xxxhdpi-v4/ic_launcher.png|res/drawable-xxxhdpi-v4/icon.png|res/mipmap-xxhdpi-v4/ic_launcher.png"

gen_random_id() {
    if [ -r /dev/urandom ]; then
        cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16 2>/dev/null
    else
        echo "$(date +%s)$$RANDOM" | md5sum | head -c 16
    fi
}

SSAID_STREAM_CACHE="/data/local/tmp/ssaid_stream_$$.txt"

prepare_ssaid_stream() {
    [ -f "$SSAID_STREAM_CACHE" ] && return
    strings "$SSAID_FILE" 2>/dev/null > "$SSAID_STREAM_CACHE"
}

cleanup() {
    rm -f "$SSAID_STREAM_CACHE" 2>/dev/null
}
trap cleanup EXIT

get_ssaid() {
    local pkg="$1"
    local id

    prepare_ssaid_stream

    id=$(grep -A 1 "$pkg" "$SSAID_STREAM_CACHE" 2>/dev/null | grep -oE '[0-9a-fA-F]{16}' | head -n 1)
    if [ -n "$id" ]; then
        echo "$id"
        return
    fi

    id=$(grep "$pkg" "$SSAID_STREAM_CACHE" 2>/dev/null | grep -oE '[0-9a-fA-F]{16}' | head -n 1)
    echo "$id"
}

is_installed() {
    pm path "$1" >/dev/null 2>&1
}

get_apk_path() {
    pm path "$1" 2>/dev/null | head -1 | sed 's/^package://'
}

is_valid_image() {
    local file="$1"
    [ ! -s "$file" ] && return 1
    local magic
    magic=$(od -An -tx1 -N4 "$file" 2>/dev/null | tr -d ' \n')
    case "$magic" in
        89504e47*) return 0 ;;
        52494646*) return 0 ;;
        *) return 1 ;;
    esac
}

# 提取图标到缓存文件，返回缓存路径（成功）或空（失败）
ensure_icon_cache() {
    local pkg="$1"
    local path1="$2"
    local path2="$3"
    local path3="$4"

    mkdir -p "$ICON_CACHE_DIR" 2>/dev/null

    local cache_file="$ICON_CACHE_DIR/${pkg}.png"

    # 已有有效缓存
    if is_valid_image "$cache_file"; then
        echo "$cache_file"
        return
    fi

    local apk_path
    apk_path=$(get_apk_path "$pkg")
    [ -z "$apk_path" ] && return
    [ ! -f "$apk_path" ] && return

    for try_path in "$path1" "$path2" "$path3"; do
        [ -z "$try_path" ] && continue
        unzip -p "$apk_path" "$try_path" > "$cache_file" 2>/dev/null
        if is_valid_image "$cache_file"; then
            chmod 644 "$cache_file" 2>/dev/null
            echo "$cache_file"
            return
        fi
    done

    rm -f "$cache_file" 2>/dev/null
}

# 流式输出单个应用的 JSON。直接 printf 到 stdout，不存到变量
emit_app_json() {
    local pkg_line="$1"
    local label="$2"
    local icon1="$3"
    local icon2="$4"
    local icon3="$5"

    [ -z "$pkg_line" ] && return 1
    [ -z "$label" ] && return 1
    is_installed "$pkg_line" || return 1

    local ssaid_val ver icon_file
    ssaid_val=$(get_ssaid "$pkg_line")
    [ -z "$ssaid_val" ] && ssaid_val="未分配"

    ver=$(dumpsys package "$pkg_line" 2>/dev/null \
        | grep versionName | head -1 \
        | awk -F= '{print $2}' | tr -d ' \r')

    icon_file=$(ensure_icon_cache "$pkg_line" "$icon1" "$icon2" "$icon3")

    label=$(echo "$label" | sed 's/\\/\\\\/g;s/"/\\"/g')
    ver=$(echo "$ver" | sed 's/"/\\"/g')

    # 流式输出，避免在 shell 中存储巨大字符串
    printf '{"pkg":"%s","label":"%s","ssaid":"%s","ver":"%s","icon":"' \
        "$pkg_line" "$label" "$ssaid_val" "$ver"

    if [ -n "$icon_file" ] && [ -s "$icon_file" ]; then
        printf 'data:image/png;base64,'
        # base64 直接管道到 tr 去换行，再到 stdout
        if base64 -w 0 "$icon_file" 2>/dev/null; then
            :
        else
            base64 "$icon_file" 2>/dev/null | tr -d '\n'
        fi
    fi

    printf '"}'
    return 0
}

case "$ACTION" in
    list)
        printf '{"apps":['
        FIRST=1

        # 用 IFS 切分 TARGET_APPS 多行
        OLD_IFS="$IFS"
        IFS='
'
        for LINE in $TARGET_APPS; do
            IFS='|'
            set -- $LINE
            IFS="$OLD_IFS"

            # 先在子 shell 中检查是否会有输出
            if is_installed "$1" 2>/dev/null; then
                if [ "$FIRST" = "1" ]; then
                    FIRST=0
                else
                    printf ','
                fi
                emit_app_json "$1" "$2" "$3" "$4" "$5"
            fi
        done
        IFS="$OLD_IFS"

        printf ']}'
        ;;

    get)
        [ -z "$PKG" ] && { echo '{"ok":false,"error":"missing pkg"}'; exit 1; }
        SSAID_VAL=$(get_ssaid "$PKG")
        printf '{"ok":true,"pkg":"%s","ssaid":"%s"}\n' "$PKG" "${SSAID_VAL:-未分配}"
        ;;

    reset)
        [ -z "$PKG" ] && { echo '{"ok":false,"error":"missing pkg"}'; exit 1; }
        # 包名白名单校验：只允许字母数字点下划线，防 sed 表达式注入
        case "$PKG" in
            *[!A-Za-z0-9._]*) echo '{"ok":false,"error":"invalid package name"}'; exit 1 ;;
        esac
        [ ! -f "$SSAID_FILE" ] && { echo '{"ok":false,"error":"ssaid file not found"}'; exit 1; }

        OLD_ID=$(get_ssaid "$PKG")
        NEW_ID=$(gen_random_id)
        # OLD_ID 必须是 16 位 hex，否则 sed 会把空串当模式 → 全文件插字符
        if [ -n "$OLD_ID" ]; then
            case "$OLD_ID" in
                *[!0-9a-fA-F]*) OLD_ID="" ;;
            esac
            [ ${#OLD_ID} -ne 16 ] && OLD_ID=""
        fi

        if [ -z "$OLD_ID" ]; then
            MAX_ID=$(strings "$SSAID_FILE" 2>/dev/null | grep -oE '_id="[0-9]+"' | grep -oE '[0-9]+' | sort -n | tail -1)
            NEXT_ID=$(( ${MAX_ID:-0} + 1 ))
            sed -i "s|</settings>|<setting id=\"$NEXT_ID\" name=\"$PKG\" value=\"$NEW_ID\" package=\"android\" defaultValue=\"$NEW_ID\" defaultSysSet=\"true\" />\n</settings>|" "$SSAID_FILE"
            RESULT="inserted"
        else
            # 先备份，再精确替换（只替换该 pkg 那一行的 value，不全局替换）
            cp -f "$SSAID_FILE" "${SSAID_FILE}.fusion.bak" 2>/dev/null
            sed -i "/name=\"$PKG\"/s/$OLD_ID/$NEW_ID/g" "$SSAID_FILE"
            RESULT="updated"
        fi

        # 重置缓存让下次重新读
        rm -f "$SSAID_STREAM_CACHE"
        CHECK=$(get_ssaid "$PKG")
        if [ "$CHECK" = "$NEW_ID" ]; then
            printf '{"ok":true,"pkg":"%s","old":"%s","new":"%s","action":"%s"}\n' \
                "$PKG" "${OLD_ID:-none}" "$NEW_ID" "$RESULT"
        else
            printf '{"ok":false,"pkg":"%s","error":"verify failed","old":"%s","new":"%s","check":"%s"}\n' \
                "$PKG" "${OLD_ID:-none}" "$NEW_ID" "${CHECK:-none}"
        fi
        ;;

    clear_cache)
        # 只清缓存子目录，模块自带的 webroot/icons/*.png 不受影响
        rm -rf "$ICON_CACHE_DIR" 2>/dev/null
        echo '{"ok":true,"msg":"icon cache cleared"}'
        ;;

    *)
        echo '{"ok":false,"error":"unknown action"}'
        ;;
esac
