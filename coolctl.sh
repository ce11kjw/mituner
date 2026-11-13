#!/system/bin/sh
# MiTuner - 散热器模式
# 用法：coolctl.sh status | on | off | auto
#
# 逻辑：
#   开启后 → 允许更高的温度阈值，不主动降频/限流
#   （具体表现：游戏档的 rate_limit 更激进、GPU 上限放开、充电限流放宽）
#
# 自动检测建议：
#   温度 < 42°C 且正在充电 → 可能插了散热器（或环境凉），提示可开启
#   （手机无法直接检测散热器，只能给建议）

BK=/data/adb/mituner
COOL_FLAG=$BK/heatsink

cmd="$1"

case "$cmd" in

  status)
    if [ -f "$COOL_FLAG" ]; then
      echo "ON=1"
      echo "SINCE=$(cat $COOL_FLAG 2>/dev/null)"
    else
      echo "ON=0"
    fi
    # 温度信息
    for t in cpu-big1 soc_max quiet_therm charger1_therm; do
      for z in /sys/class/thermal/thermal_zone*/; do
        if [ "$(cat $z/type 2>/dev/null)" = "$t" ]; then
          v=$(cat $z/temp 2>/dev/null)
          echo "T_$(echo $t | tr 'a-z-' 'A-Z_')=$v"
          break
        fi
      done
    done
    # 充电状态
    echo "CHARGING=$([ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = "1" ] && echo 1 || echo 0)"
    echo "CAPACITY=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
    ;;

  on)
    date +%s > "$COOL_FLAG"
    # 应用更激进的参数
    # 1. GPU 放开
    [ -x "/data/adb/modules/mituner/gpuctl.sh" ] && \
      sh /data/adb/modules/mituner/gpuctl.sh profile game >/dev/null 2>&1
    # 2. 调度更激进
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      echo 150 > "$p/schedutil/rate_limit_us" 2>/dev/null
    done
    # 3. 内存更宽松
    echo 30 > /proc/sys/vm/swappiness 2>/dev/null
    echo 50 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
    echo "OK ON"
    ;;

  off)
    rm -f "$COOL_FLAG"
    # 恢复正常
    [ -x "/data/adb/modules/mituner/gpuctl.sh" ] && \
      sh /data/adb/modules/mituner/gpuctl.sh profile normal >/dev/null 2>&1
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
      echo 500 > "$p/schedutil/rate_limit_us" 2>/dev/null
    done
    echo 60 > /proc/sys/vm/swappiness 2>/dev/null
    echo 80 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
    echo "OK OFF"
    ;;

  auto)
    # 给建议，不自动开关（用户选「手动为主 + 自动检测建议」）
    CHG=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
    CAP=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
    T=0
    for z in /sys/class/thermal/thermal_zone*/; do
      if [ "$(cat $z/type 2>/dev/null)" = "soc_max" ]; then
        T=$(cat $z/temp 2>/dev/null)
        break
      fi
    done
    T=$((T / 1000))
    IS_ON=$([ -f "$COOL_FLAG" ] && echo 1 || echo 0)

    echo "TEMP=$T"
    echo "CHARGING=$CHG"
    echo "CAPACITY=$CAP"
    echo "IS_ON=$IS_ON"

    # 建议逻辑
    if [ "$IS_ON" = "1" ]; then
      if [ "$T" -gt 45 ]; then
        echo "SUGGEST=off"
        echo "REASON=已开启但温度仍达 ${T}°C，建议关闭（可能没接散热器）"
      else
        echo "SUGGEST=keep"
        echo "REASON=散热器模式运行中，温度 ${T}°C 良好"
      fi
    else
      if [ "$T" -lt 42 ] && [ "$CHG" = "1" ]; then
        echo "SUGGEST=on"
        echo "REASON=充电中且温度仅 ${T}°C，可能已接散热器，可尝试开启"
      elif [ "$T" -lt 38 ]; then
        echo "SUGGEST=on"
        echo "REASON=温度很低（${T}°C），环境凉爽，可开启更激进调度"
      else
        echo "SUGGEST=none"
        echo "REASON=温度 ${T}°C 正常，无需散热器模式"
      fi
    fi
    ;;

  *)
    echo "用法: coolctl.sh {status|on|off|auto}"
    exit 1
    ;;
esac
