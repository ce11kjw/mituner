#!/system/bin/sh
# MiTuner - 刷新率控制（MIUI 专用）
# 用法：rrctl.sh get | set <60|90|120|144> | auto | reset
#
# ⚠️ 关键发现（本机实测）：
#   MIUI 控制刷新率用的是 secure/miui_refresh_rate，不是 system/peak_refresh_rate
#   实测设 secure/miui_refresh_rate=60 → SurfaceFlinger vsyncRate=60.00 生效

BK=/data/adb/mituner
RR_BAK=$BK/rr_orig.conf

backup() {
  [ -f "$RR_BAK" ] && return
  {
    echo "R_MIUI=$(settings get secure miui_refresh_rate 2>/dev/null)"
    echo "R_USER=$(settings get secure user_refresh_rate 2>/dev/null)"
    echo "R_PEAK=$(settings get system peak_refresh_rate 2>/dev/null)"
  } > "$RR_BAK"
}

get_sf_rate() {
  dumpsys SurfaceFlinger 2>/dev/null | grep -oE 'activeMode=\{[^}]*vsyncRate=[0-9.]+' | \
    head -1 | grep -oE '[0-9]+\.' | head -1 | cut -d. -f1
}

cmd="$1"

case "$cmd" in

  get)
    echo "MIUI=$(settings get secure miui_refresh_rate 2>/dev/null)"
    echo "USER=$(settings get secure user_refresh_rate 2>/dev/null)"
    echo "PEAK=$(settings get system peak_refresh_rate 2>/dev/null)"
    echo "SMART=$(settings get system is_smart_fps 2>/dev/null)"
    echo "ACTUAL=$(get_sf_rate)"
    # 支持的档位
    echo "SUPPORT=60,90,120,144"
    ;;

  set)
    R="$2"
    [ -z "$R" ] && { echo "ERR 缺刷新率"; exit 1; }
    case "$R" in
      60|90|120|144) ;;
      *) echo "ERR 只支持 60/90/120/144"; exit 1 ;;
    esac
    backup
    settings put secure miui_refresh_rate "$R" 2>/dev/null
    settings put secure user_refresh_rate "$R" 2>/dev/null
    settings put system peak_refresh_rate "$R" 2>/dev/null
    sleep 2
    A=$(get_sf_rate)
    echo "OK SET=$R ACTUAL=$A"
    ;;

  auto)
    # 恢复系统自动（智能切换）
    settings put system is_smart_fps 1 2>/dev/null
    settings put secure miui_refresh_rate 144 2>/dev/null
    settings put secure user_refresh_rate 144 2>/dev/null
    settings put system peak_refresh_rate 144 2>/dev/null
    sleep 2
    echo "OK AUTO ACTUAL=$(get_sf_rate)"
    ;;

  reset)
    settings put system is_smart_fps 0 2>/dev/null
    if [ -f "$RR_BAK" ]; then
      . "$RR_BAK"
      [ -n "$R_MIUI" ] && settings put secure miui_refresh_rate "$R_MIUI" 2>/dev/null
      [ -n "$R_USER" ] && settings put secure user_refresh_rate "$R_USER" 2>/dev/null
      [ -n "$R_PEAK" ] && settings put system peak_refresh_rate "$R_PEAK" 2>/dev/null
      echo "OK RESET ACTUAL=$(get_sf_rate)"
    else
      settings put secure miui_refresh_rate 144 2>/dev/null
      settings put secure user_refresh_rate 144 2>/dev/null
      settings put system peak_refresh_rate 144 2>/dev/null
      echo "OK RESET(默认144) ACTUAL=$(get_sf_rate)"
    fi
    ;;

  *)
    echo "用法: rrctl.sh {get|set <60|90|120|144>|auto|reset}"
    exit 1
    ;;
esac
