#!/system/bin/sh
# MiTuner - IO 调度器
# 用法：ioctl2.sh get | set <none|mq-deadline|kyber|bfq> | auto
#
# 本机 sda 支持：none / mq-deadline / kyber / bfq
#   none         = 无调度，UFS 直通（默认，性能最好）
#   kyber        = 低延迟，适合交互
#   bfq          = 按进程公平，后台下载不卡前台
#   mq-deadline = 保证延迟上限

BK=/data/adb/mituner
DEV=/sys/block/sda
SCH=$DEV/queue/scheduler

get_cur() {
  cat $SCH 2>/dev/null | grep -oE '\[[a-z-]+\]' | tr -d '[]'
}

cmd="$1"

case "$cmd" in

  get)
    echo "CURRENT=$(get_cur)"
    echo "AVAIL=$(cat $SCH 2>/dev/null | tr '[]' ' ' | xargs)"
    echo "NR_REQUESTS=$(cat $DEV/queue/nr_requests 2>/dev/null)"
    echo "READ_AHEAD=$(cat $DEV/queue/read_ahead_kb 2>/dev/null)"
    echo "NOMERGES=$(cat $DEV/queue/nomerges 2>/dev/null)"
    ;;

  set)
    S="$2"
    [ -z "$S" ] && { echo "ERR 缺调度器"; exit 1; }
    case "$S" in
      none|mq-deadline|kyber|bfq) ;;
      *) echo "ERR 不支持 $S（可选 none/mq-deadline/kyber/bfq）"; exit 1 ;;
    esac
    # 校验在可用列表里
    AVAIL=$(cat $SCH 2>/dev/null | tr -d '[]')
    case " $AVAIL " in
      *" $S "*) ;;
      *) echo "ERR 系统不支持 $S"; exit 1 ;;
    esac
    echo "$S" > $SCH 2>/dev/null
    sleep 1
    NOW=$(get_cur)
    if [ "$NOW" = "$S" ]; then
      echo "OK SET=$S"
    else
      echo "ERR 切换失败（当前 $NOW）"
    fi
    ;;

  auto)
    # 按当前状态自动选：游戏用 none，日常 kyber，息屏 bfq
    M=$(cat /data/adb/mituner/state 2>/dev/null)
    case "$M" in
      GAME)   T=none ;;
      IDLE)   T=bfq ;;
      *)      T=none ;;
    esac
    echo "$T" > $SCH 2>/dev/null
    echo "OK AUTO MODE=$M SET=$T"
    ;;

  *)
    echo "用法: ioctl2.sh {get|set <none|mq-deadline|kyber|bfq>|auto}"
    exit 1
    ;;
esac
