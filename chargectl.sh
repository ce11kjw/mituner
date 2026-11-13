#!/system/bin/sh
# MiTuner - 充电控制
# 用法：chargectl.sh get | limit <mA> | stop | resume | cap <百分比> | reset | applycap
#
# 节点说明（本机实测）：
#   battery/input_suspend                          1=停充 0=正常           ✓可写
#   battery/constant_charge_current                充电电流(uA)            ✓可写
#   mtk-master-charger/constant_charge_current_max 充电电流上限(uA)        ✓可写（但驱动可能不立即生效）
#   mtk-master-charger/input_current_limit         输入电流上限(uA)        ✓可写
#
# ⚠️ 实测发现：改 constant_charge_current_max 后读回仍是原值，
#    因为充电 IC 会周期性回写。所以限流要用 battery/constant_charge_current 才生效。

BK=/data/adb/mituner
CH_BAK=$BK/charge_orig.conf
BAT=/sys/class/power_supply/battery
CHG=/sys/class/power_supply/mtk-master-charger

backup() {
  [ -f "$CH_BAK" ] && return
  {
    echo "C_SUSPEND=$(cat $BAT/input_suspend 2>/dev/null)"
    echo "C_CC=$(cat $BAT/constant_charge_current 2>/dev/null)"
    echo "C_CCMAX=$(cat $CHG/constant_charge_current_max 2>/dev/null)"
    echo "C_ICL=$(cat $CHG/input_current_limit 2>/dev/null)"
  } > "$CH_BAK"
}

# 读充电 IC 温度
get_ic_temp() {
  for z in /sys/class/thermal/thermal_zone*/; do
    if [ "$(cat $z/type 2>/dev/null)" = "charger1_therm" ]; then
      cat $z/temp 2>/dev/null
      return
    fi
  done
  echo 0
}

cmd="$1"

case "$cmd" in

  get)
    CAP=$(cat $BAT/capacity 2>/dev/null)
    ST=$(cat $BAT/status 2>/dev/null)
    CUR=$(cat $BAT/current_now 2>/dev/null)
    VOL=$(cat $BAT/voltage_now 2>/dev/null)
    TMP=$(cat $BAT/temp 2>/dev/null)
    SUS=$(cat $BAT/input_suspend 2>/dev/null)
    CCM=$(cat $BAT/constant_charge_current 2>/dev/null)
    ICL=$(cat $CHG/input_current_limit 2>/dev/null)
    ONL=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
    ICT=$(get_ic_temp)
    CAP_T=$(cat $BK/charge_cap 2>/dev/null)

    echo "CAPACITY=$CAP"
    echo "STATUS=$ST"
    echo "CURRENT=$CUR"
    echo "VOLTAGE=$VOL"
    echo "TEMP=$TMP"
    echo "SUSPEND=$SUS"
    echo "CC=$CCM"
    echo "ICL=$ICL"
    echo "ONLINE=$ONL"
    echo "IC_TEMP=$ICT"
    echo "CAP_TARGET=${CAP_T:-0}"
    # 功率 (mW) = µV * µA / 1e9
    if [ -n "$VOL" ] && [ -n "$CUR" ]; then
      echo "POWER_MW=$(( VOL / 1000 * CUR / 1000000 ))"
    else
      echo "POWER_MW=0"
    fi
    # 是否正在充电
    if [ "$ONL" = "1" ] && [ "$SUS" = "0" ] && [ "$CUR" -gt 0 ] 2>/dev/null; then
      echo "CHARGING=1"
    else
      echo "CHARGING=0"
    fi
    ;;

  limit)
    MA="$2"
    [ -z "$MA" ] && { echo "ERR 缺电流值"; exit 1; }
    case "$MA" in *[!0-9]*) echo "ERR 必须数字"; exit 1;; esac
    [ "$MA" -lt 100 ] && { echo "ERR 最小 100mA"; exit 1; }
    [ "$MA" -gt 6000 ] && { echo "ERR 最大 6000mA"; exit 1; }
    backup
    UA=$(( MA * 1000 ))
    # 先写上限，再写实际电流（后者才真正生效）
    echo "$UA" > "$CHG/constant_charge_current_max" 2>/dev/null
    echo "$UA" > "$CHG/input_current_limit" 2>/dev/null
    echo "$UA" > "$BAT/constant_charge_current" 2>/dev/null
    echo "$MA" > "$BK/charge_limit_ma" 2>/dev/null
    R=$(cat $BAT/constant_charge_current 2>/dev/null)
    echo "OK LIMIT=${MA}mA READBACK=$R"
    ;;

  stop)
    backup
    echo 1 > "$BAT/input_suspend" 2>/dev/null
    echo "OK SUSPEND=$(cat $BAT/input_suspend 2>/dev/null)"
    ;;

  resume)
    echo 0 > "$BAT/input_suspend" 2>/dev/null
    echo "OK SUSPEND=$(cat $BAT/input_suspend 2>/dev/null)"
    ;;

  cap)
    P="$2"
    if [ -z "$P" ]; then
      rm -f "$BK/charge_cap"
      echo "OK CAP=off"
      exit 0
    fi
    case "$P" in *[!0-9]*) echo "ERR 必须数字"; exit 1;; esac
    [ "$P" -lt 50 ] && { echo "ERR 至少 50%"; exit 1; }
    [ "$P" -gt 100 ] && { echo "ERR 最大 100%"; exit 1; }
    echo "$P" > "$BK/charge_cap"
    echo "OK CAP=$P"
    ;;

  applycap)
    # 由 service.sh 每轮调用：达到上限就停充，低于上限-3% 恢复
    [ -f "$BK/charge_cap" ] || { echo "NOCAP"; exit 0; }
    TARGET=$(cat "$BK/charge_cap" 2>/dev/null)
    [ -z "$TARGET" ] && { echo "NOCAP"; exit 0; }
    CAP=$(cat $BAT/capacity 2>/dev/null)
    SUS=$(cat $BAT/input_suspend 2>/dev/null)
    [ -z "$CAP" ] && { echo "ERR 读不到电量"; exit 1; }

    RESUME_AT=$(( TARGET - 3 ))
    if [ "$CAP" -ge "$TARGET" ]; then
      [ "$SUS" != "1" ] && { echo 1 > "$BAT/input_suspend" 2>/dev/null; echo "STOPPED cap=$CAP target=$TARGET"; } || echo "ALREADY cap=$CAP"
    elif [ "$CAP" -le "$RESUME_AT" ]; then
      [ "$SUS" != "0" ] && { echo 0 > "$BAT/input_suspend" 2>/dev/null; echo "RESUMED cap=$CAP target=$TARGET"; } || echo "OK cap=$CAP"
    else
      echo "HOLD cap=$CAP target=$TARGET"
    fi
    ;;

  reset)
    if [ -f "$CH_BAK" ]; then
      . "$CH_BAK"
      [ -n "$C_SUSPEND" ] && echo "$C_SUSPEND" > "$BAT/input_suspend" 2>/dev/null
      [ -n "$C_CC" ] && echo "$C_CC" > "$BAT/constant_charge_current" 2>/dev/null
      [ -n "$C_CCMAX" ] && echo "$C_CCMAX" > "$CHG/constant_charge_current_max" 2>/dev/null
      [ -n "$C_ICL" ] && echo "$C_ICL" > "$CHG/input_current_limit" 2>/dev/null
      rm -f "$BK/charge_cap" "$BK/charge_limit_ma"
      echo "OK RESET"
    else
      echo "ERR 无备份"
    fi
    ;;

  *)
    echo "用法: chargectl.sh {get|limit <mA>|stop|resume|cap <百分比>|applycap|reset}"
    exit 1
    ;;
esac
