#!/system/bin/sh
# 缓存清理脚本 - 无畏契约
# 作者: 呆呆 | QQ:891354018 | 群:774886621
# 用法:
#   sh cleaner.sh                    深度清理（默认，输出 JSON）
#   sh cleaner.sh deep               深度清理（输出 JSON）
#   sh cleaner.sh light              轻度清理（输出 JSON）
#   sh cleaner.sh inotify            仅优化 inotify 参数（静默）

MOD_DIR="/data/adb/modules/webui_info"
SETTINGS_FILE="$MOD_DIR/settings.conf"
LOG_FILE="/data/local/tmp/webui_cleaner.log"
ARG1="$1"

write_setting() {
    local key="$1"
    local val="$2"
    [ ! -f "$SETTINGS_FILE" ] && touch "$SETTINGS_FILE"
    if grep -q "^${key}=" "$SETTINGS_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$SETTINGS_FILE"
    else
        echo "${key}=${val}" >> "$SETTINGS_FILE"
    fi
}

PKG="com.tencent.tmgp.codev"
EXT_DIR="/storage/emulated/0/Android/data/$PKG"
INT_DIR="/data/user/0/$PKG"

optimize_inotify() {
    echo 16384 > /proc/sys/fs/inotify/max_queued_events 2>/dev/null
    echo 128 > /proc/sys/fs/inotify/max_user_instances 2>/dev/null
    echo 8192 > /proc/sys/fs/inotify/max_user_watches 2>/dev/null
}

clean_light() {
    rm -rf /data/user/*/"$PKG/files/ano_tmp" 2>/dev/null
    rm -rf "$INT_DIR/cache" "$INT_DIR/code_cache" 2>/dev/null
    return 0
}

clean_deep() {
    optimize_inotify
    rm -rf /data/user/*/"$PKG/files/ano_tmp" 2>/dev/null

    if [ ! -d "$EXT_DIR" ] && [ ! -d "$INT_DIR" ]; then
        return 1
    fi

    [ -d "$EXT_DIR" ] && find "$EXT_DIR" -mindepth 1 -maxdepth 1 ! -name files -exec rm -r {} + 2>/dev/null

    [ -d "$EXT_DIR/files" ] && find "$EXT_DIR/files/" -mindepth 1 -maxdepth 1 \
        ! \( -name EstvShadowPlugin_shadow-app -o -name VulkanProgramBinaryCache -o -name UE4Game \) \
        -exec rm -r {} + 2>/dev/null

    if [ -d "$EXT_DIR/files/UE4Game/CodeV" ]; then
        find "$EXT_DIR/files/UE4Game/CodeV/" -maxdepth 1 -type f 2>/dev/null | while read f; do
            fn=$(basename "$f")
            case "$fn" in
                Manifest_UFSFiles_Android.txt|NotAllowedUnattendedBugReports|Version.cfg|ClearFlag_*|BagSkinCache_*.json|PlayerData.cfg|PCache.meta|Manifest.ini)
                    continue ;;
                *)
                    rm -f "$f" ;;
            esac
        done
    fi

    SAVED="$EXT_DIR/files/UE4Game/CodeV/CodeV/Saved"
    if [ -d "$SAVED" ]; then
        rm -rf "$SAVED/Gamelet/logs" "$SAVED/Gamelet/cookies" 2>/dev/null
        find "$SAVED/" -mindepth 1 -maxdepth 1 \
            ! \( -name ClearFlag_* -o -name ImageDownload -o -name Gamelet -o -name ShaderCache -o -name Paks -o -name MMKV -o -name Version.cfg -o -name PlayerData.cfg -o -name PCache.meta \) \
            -exec rm -r {} + 2>/dev/null
    fi

    rm -rf "$INT_DIR/cache" "$INT_DIR/code_cache" 2>/dev/null

    [ -d "$INT_DIR/files" ] && find "$INT_DIR/files/" -mindepth 1 -maxdepth 1 \
        ! \( -name ves -o -name live -o -name EstvShadowDir -o -name estv-valm-RELEASE \) \
        -exec rm -r {} + 2>/dev/null

    [ -d "$INT_DIR" ] && find "$INT_DIR/" -mindepth 1 -maxdepth 1 \
        ! \( -name app_tbs_64 -o -name files \) -exec rm -r {} + 2>/dev/null

    return 0
}

run_and_report() {
    local mode="$1"
    local label
    optimize_inotify
    # 统一委托给 games.sh（唯一清理实现），避免与新面板重复
    local out ret codev_ok
    out=$(sh "$(dirname "$0")/games.sh" clean codev "$mode" 2>/dev/null)
    ret=$?
    codev_ok=$(printf '%s' "$out" | grep -c '"ok":true')
    if [ "$mode" = "light" ]; then label="轻度清理"; else label="深度清理"; fi
    if [ "$codev_ok" -ge 1 ]; then
        NOW="$(date '+%Y-%m-%d %H:%M:%S')"
        write_setting "last_clean_time" "$NOW"
        echo "[$NOW] $label 完成" >> "$LOG_FILE"
        printf '{"ok":true,"msg":"%s完成","mode":"%s","time":"%s"}\n' "$label" "$mode" "$NOW"
    else
        echo "[$(date)] $label 失败：游戏未安装" >> "$LOG_FILE"
        echo '{"ok":false,"error":"无畏契约未安装"}'
    fi
}

case "$ARG1" in
    inotify)
        optimize_inotify
        ;;
    light)
        run_and_report "light"
        ;;
    deep|"")
        run_and_report "deep"
        ;;
    *)
        echo '{"ok":false,"error":"unknown mode"}'
        exit 1
        ;;
esac

exit 0
