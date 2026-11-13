#!/system/bin/sh
# MiTuner - 网络调优
# 用法：netctl.sh get | cc <cubic|reno> | bufsize <MB> | reset

BK=/data/adb/mituner
NET_BAK=$BK/net_orig.conf

backup() {
  [ -f "$NET_BAK" ] && return
  {
    echo "N_CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
    echo "N_RMEM=$(cat /proc/sys/net/core/rmem_max 2>/dev/null)"
    echo "N_WMEM=$(cat /proc/sys/net/core/wmem_max 2>/dev/null)"
  } > "$NET_BAK"
}

cmd="$1"

case "$cmd" in

  get)
    echo "CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
    echo "AVAIL_CC=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)"
    echo "RMEM_MAX=$(cat /proc/sys/net/core/rmem_max 2>/dev/null)"
    echo "WMEM_MAX=$(cat /proc/sys/net/core/wmem_max 2>/dev/null)"
    echo "TCP_FASTOPEN=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null)"
    echo "TCP_TW_REUSE=$(cat /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null)"
    echo "WINDOW_SCALING=$(cat /proc/sys/net/ipv4/tcp_window_scaling 2>/dev/null)"
    echo "SACK=$(cat /proc/sys/net/ipv4/tcp_sack 2>/dev/null)"
    ;;

  cc)
    C="$2"
    [ -z "$C" ] && { echo "ERR 缺算法"; exit 1; }
    AVAIL=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)
    case " $AVAIL " in
      *" $C "*) ;;
      *) echo "ERR 不支持 $C（可用：$AVAIL）"; exit 1 ;;
    esac
    backup
    echo "$C" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
    echo "OK CC=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)"
    ;;

  bufsize)
    M="$2"
    [ -z "$M" ] && { echo "ERR 缺大小(MB)"; exit 1; }
    case "$M" in *[!0-9]*) echo "ERR 必须数字"; exit 1;; esac
    [ "$M" -lt 1 ] && { echo "ERR 最小 1MB"; exit 1; }
    [ "$M" -gt 64 ] && { echo "ERR 最大 64MB"; exit 1; }
    backup
    V=$(( M * 1024 * 1024 ))
    echo "$V" > /proc/sys/net/core/rmem_max 2>/dev/null
    echo "$V" > /proc/sys/net/core/wmem_max 2>/dev/null
    echo "OK RMEM=$(cat /proc/sys/net/core/rmem_max) WMEM=$(cat /proc/sys/net/core/wmem_max)"
    ;;

  tune)
    # 一键应用推荐设置
    backup
    echo 3 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse 2>/dev/null
    echo 16777216 > /proc/sys/net/core/rmem_max 2>/dev/null
    echo 16777216 > /proc/sys/net/core/wmem_max 2>/dev/null
    echo "OK TUNED"
    ;;

  reset)
    if [ -f "$NET_BAK" ]; then
      . "$NET_BAK"
      [ -n "$N_CC" ] && echo "$N_CC" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
      [ -n "$N_RMEM" ] && echo "$N_RMEM" > /proc/sys/net/core/rmem_max 2>/dev/null
      [ -n "$N_WMEM" ] && echo "$N_WMEM" > /proc/sys/net/core/wmem_max 2>/dev/null
      echo "OK RESET"
    else
      echo "ERR 无备份"
    fi
    ;;

  *)
    echo "用法: netctl.sh {get|cc <cubic|reno>|bufsize <MB>|tune|reset}"
    exit 1
    ;;
esac
