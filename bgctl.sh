#!/system/bin/sh
# MiTuner - 后台限制模块（cgroup cpu.shares）
# 用法：bgctl.sh status | on | off | whitelist add/del/list
#
# 原理：调整 /dev/cpuctl/{background,foreground,top-app}/cpu.shares
#       cpu.shares 是「相对权重」，不是硬限制
#       默认：background=1024 / foreground=4096 / top-app=5120
#       限制：background=128（大幅降低后台抢 CPU 能力）
#
# ⚠️ 这是温和手段：不会杀进程，只是让后台抢不到 CPU
#    副作用极小，但效果也不如 kill -STOP

BK=/data/adb/mituner
BG_BAK=$BK/bg_orig.conf
WL=$BK/bg_whitelist

mkdir -p "$BK"

backup() {
  [ -f "$BG_BAK" ] && return
  {
    echo "B_BG=$(cat /dev/cpuctl/background/cpu.shares 2>/dev/null)"
    echo "B_FG=$(cat /dev/cpuctl/foreground/cpu.shares 2>/dev/null)"
    echo "B_TA=$(cat /dev/cpuctl/top-app/cpu.shares 2>/dev/null)"
  } > "$BG_BAK"
}

cmd="$1"

case "$cmd" in

  status)
    echo "BG_SHARES=$(cat /dev/cpuctl/background/cpu.shares 2>/dev/null)"
    echo "FG_SHARES=$(cat /dev/cpuctl/foreground/cpu.shares 2>/dev/null)"
    echo "TA_SHARES=$(cat /dev/cpuctl/top-app/cpu.shares 2>/dev/null)"
    # 后台进程数
    echo "BG_PROCS=$(wc -l < /dev/cpuctl/background/cgroup.procs 2>/dev/null || echo 0)"
    echo "FG_PROCS=$(wc -l < /dev/cpuctl/foreground/cgroup.procs 2>/dev/null || echo 0)"
    echo "TA_PROCS=$(wc -l < /dev/cpuctl/top-app/cgroup.procs 2>/dev/null || echo 0)"
    # 当前是否启用了限制（background 低于原厂）
    B=$(cat /dev/cpuctl/background/cpu.shares 2>/dev/null)
    if [ -n "$B" ] && [ "$B" -lt 512 ]; then echo "LIMITED=1"; else echo "LIMITED=0"; fi
    # 白名单数量
    echo "WL_COUNT=$(wc -l < "$WL" 2>/dev/null || echo 0)"
    ;;

  on)
    backup
    # 后台权重降到 1/8
    echo 128 > /dev/cpuctl/background/cpu.shares 2>/dev/null
    # 前台和 top-app 提高，让前台更流畅
    echo 7168 > /dev/cpuctl/foreground/cpu.shares 2>/dev/null
    echo 10240 > /dev/cpuctl/top-app/cpu.shares 2>/dev/null
    echo "OK BG=$(cat /dev/cpuctl/background/cpu.shares 2>/dev/null) FG=$(cat /dev/cpuctl/foreground/cpu.shares 2>/dev/null) TA=$(cat /dev/cpuctl/top-app/cpu.shares 2>/dev/null)"
    ;;

  off)
    if [ -f "$BG_BAK" ]; then
      . "$BG_BAK"
      [ -n "$B_BG" ] && echo "$B_BG" > /dev/cpuctl/background/cpu.shares 2>/dev/null
      [ -n "$B_FG" ] && echo "$B_FG" > /dev/cpuctl/foreground/cpu.shares 2>/dev/null
      [ -n "$B_TA" ] && echo "$B_TA" > /dev/cpuctl/top-app/cpu.shares 2>/dev/null
      echo "OK BG=$(cat /dev/cpuctl/background/cpu.shares 2>/dev/null) FG=$(cat /dev/cpuctl/foreground/cpu.shares 2>/dev/null) TA=$(cat /dev/cpuctl/top-app/cpu.shares 2>/dev/null)"
    else
      # 无备份时用默认值
      echo 1024 > /dev/cpuctl/background/cpu.shares 2>/dev/null
      echo 4096 > /dev/cpuctl/foreground/cpu.shares 2>/dev/null
      echo 5120 > /dev/cpuctl/top-app/cpu.shares 2>/dev/null
      echo "OK (恢复默认)"
    fi
    ;;

  whitelist)
    SUB="$2"
    case "$SUB" in
      add)
        P="$3"
        [ -z "$P" ] && { echo "ERR 缺包名"; exit 1; }
        touch "$WL"
        grep -qFx "$P" "$WL" 2>/dev/null || echo "$P" >> "$WL"
        echo "OK"
        ;;
      del)
        P="$3"
        [ -z "$P" ] && { echo "ERR 缺包名"; exit 1; }
        grep -vxF "$P" "$WL" > "$WL.tmp" 2>/dev/null && mv "$WL.tmp" "$WL"
        echo "OK"
        ;;
      list)
        cat "$WL" 2>/dev/null
        ;;
      *)
        echo "用法: bgctl.sh whitelist {add|del|list} [包名]"
        exit 1
        ;;
    esac
    ;;

  *)
    echo "用法: bgctl.sh {status|on|off|whitelist ...}"
    exit 1
    ;;
esac
