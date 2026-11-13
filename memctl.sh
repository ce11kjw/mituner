#!/system/bin/sh
# MiTuner - 内存管理
# 用法：memctl.sh info | top [N] | dropcache | pressure | reset

BK=/data/adb/mituner
MEM_BAK=$BK/mem_orig.conf

backup() {
  [ -f "$MEM_BAK" ] && return
  echo "M_MINFREE=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null)" > "$MEM_BAK"
}

cmd="$1"

case "$cmd" in

  info)
    awk '
      /^MemTotal:/{mt=$2}
      /^MemFree:/{mf=$2}
      /^MemAvailable:/{ma=$2}
      /^Cached:/{ca=$2}
      /^Buffers:/{bu=$2}
      /^SwapTotal:/{st=$2}
      /^SwapFree:/{sf=$2}
      /^SwapCached:/{sc=$2}
      /^Active:/{ac=$2}
      /^Inactive:/{ic=$2}
      END{
        printf "TOTAL=%.0f\n", mt/1024
        printf "FREE=%.0f\n", mf/1024
        printf "AVAIL=%.0f\n", ma/1024
        printf "CACHED=%.0f\n", ca/1024
        printf "BUFFERS=%.0f\n", bu/1024
        printf "SWAP_TOTAL=%.0f\n", st/1024
        printf "SWAP_FREE=%.0f\n", sf/1024
        printf "SWAP_USED=%.0f\n", (st-sf)/1024
        printf "SWAP_CACHED=%.0f\n", sc/1024
        printf "ACTIVE=%.0f\n", ac/1024
        printf "INACTIVE=%.0f\n", ic/1024
        if (mt>0) printf "USED_PCT=%.0f\n", ((mt-ma)*100)/mt
        if (st>0) printf "SWAP_PCT=%.0f\n", ((st-sf)*100)/st
      }
    ' /proc/meminfo

    # zram（用 awk 避免整数除法精度问题）
    DS=$(cat /sys/block/zram0/disksize 2>/dev/null)
    if [ -n "$DS" ]; then
      echo "$DS" | awk '{printf "ZRAM_SIZE=%.0f\n", $1/1048576}'
    else
      echo "ZRAM_SIZE=0"
    fi
    ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oE '\[[a-z0-9-]+\]' | tr -d '[]')
    echo "ZRAM_ALGO=${ALGO:-unknown}"
    MU=$(cat /sys/block/zram0/mem_used_total 2>/dev/null)
    if [ -n "$MU" ]; then
      echo "$MU" | awk '{printf "ZRAM_USED=%.0f\n", $1/1048576}'
    else
      echo "ZRAM_USED=0"
    fi
    # 压缩比
    OD=$(cat /sys/block/zram0/orig_data_size 2>/dev/null)
    CD=$(cat /sys/block/zram0/compr_data_size 2>/dev/null)
    if [ -n "$OD" ] && [ -n "$CD" ] && [ "$CD" -gt 0 ] 2>/dev/null; then
      echo "$OD $CD" | awk '{printf "ZRAM_RATIO=%.1f\n", $1/$2}'
    else
      echo "ZRAM_RATIO=0"
    fi
    # 内存压力 PSI
    PSI=$(cat /proc/pressure/memory 2>/dev/null | head -1 | grep -oE 'avg10=[0-9.]+' | cut -d= -f2)
    echo "PRESSURE=${PSI:-0}"
    ;;

  top)
    N=${2:-10}
    case "$N" in *[!0-9]*) N=10;; esac
    ps -A -o PID,RSS,NAME 2>/dev/null | tail -n +2 | sort -k2 -rn | head -$N | \
      awk '{printf "%s|%.0f|%s\n", $1, $2/1024, $3}'
    ;;

  dropcache)
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    RC=$?
    sleep 1
    if [ "$RC" = "0" ]; then
      NOW=$(awk '/^MemAvailable:/{printf "%.0f", $2/1024}' /proc/meminfo)
      CACHE=$(awk '/^Cached:/{printf "%.0f", $2/1024}' /proc/meminfo)
      echo "OK AVAIL=$NOW CACHED=$CACHE"
    else
      echo "ERR 无权限"
    fi
    ;;

  pressure)
    cat /proc/pressure/memory 2>/dev/null
    ;;

  reset)
    if [ -f "$MEM_BAK" ]; then
      . "$MEM_BAK"
      [ -n "$M_MINFREE" ] && echo "$M_MINFREE" > /proc/sys/vm/min_free_kbytes 2>/dev/null
      echo "OK RESET"
    else
      echo "ERR 无备份"
    fi
    ;;

  *)
    echo "用法: memctl.sh {info|top [N]|dropcache|pressure|reset}"
    exit 1
    ;;
esac
