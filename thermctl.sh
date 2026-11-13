#!/system/bin/sh
# MiTuner - 温控阈值（⚠️ 高风险，默认禁用）
# 用法：thermctl.sh get | boost <0|1> | balance <0|1|2> | atc <0|1>
#
# 节点：/sys/class/thermal/thermal_message/{boost,balance_mode,atc_enable}
# ⚠️ 警告：改这些可能影响系统温控行为，导致过热或降频异常
#    默认全部保持原值，仅在用户明确要求时操作

BK=/data/adb/mituner
TH_BAK=$BK/thermal_orig.conf
TM=/sys/class/thermal/thermal_message

backup() {
  [ -f "$TH_BAK" ] && return
  {
    echo "T_BOOST=$(cat $TM/boost 2>/dev/null)"
    echo "T_BALANCE=$(cat $TM/balance_mode 2>/dev/null)"
    echo "T_ATC=$(cat $TM/atc_enable 2>/dev/null)"
  } > "$TH_BAK"
}

cmd="$1"

case "$cmd" in

  get)
    echo "BOOST=$(cat $TM/boost 2>/dev/null)"
    echo "BALANCE=$(cat $TM/balance_mode 2>/dev/null)"
    echo "ATC=$(cat $TM/atc_enable 2>/dev/null)"
    echo "SCONFIG=$(cat $TM/sconfig 2>/dev/null)"
    echo "BOARD_TEMP=$(cat $TM/board_sensor_temp 2>/dev/null)"
    echo "CHARGER_TEMP=$(cat $TM/charger_temp 2>/dev/null)"
    echo "CPU_LIMITS=$(cat $TM/cpu_limits 2>/dev/null)"
    echo "--- 当前温度 ---"
    for t in soc_max cpu-big1 quiet_therm charger1_therm; do
      for z in /sys/class/thermal/thermal_zone*/; do
        if [ "$(cat $z/type 2>/dev/null)" = "$t" ]; then
          echo "T_$(echo $t | tr 'a-z-' 'A-Z_')=$(( $(cat $z/temp 2>/dev/null) / 1000 ))"
          break
        fi
      done
    done
    ;;

  boost)
    V="$2"
    case "$V" in 0|1) ;; *) echo "ERR 只支持 0/1"; exit 1;; esac
    backup
    echo "$V" > $TM/boost 2>/dev/null
    echo "OK BOOST=$(cat $TM/boost 2>/dev/null)"
    ;;

  balance)
    V="$2"
    case "$V" in 0|1|2) ;; *) echo "ERR 只支持 0/1/2"; exit 1;; esac
    backup
    echo "$V" > $TM/balance_mode 2>/dev/null
    echo "OK BALANCE=$(cat $TM/balance_mode 2>/dev/null)"
    ;;

  atc)
    V="$2"
    case "$V" in 0|1|-1) ;; *) echo "ERR 只支持 0/1/-1"; exit 1;; esac
    backup
    echo "$V" > $TM/atc_enable 2>/dev/null
    echo "OK ATC=$(cat $TM/atc_enable 2>/dev/null)"
    ;;

  reset)
    if [ -f "$TH_BAK" ]; then
      . "$TH_BAK"
      [ -n "$T_BOOST" ] && echo "$T_BOOST" > $TM/boost 2>/dev/null
      [ -n "$T_BALANCE" ] && echo "$T_BALANCE" > $TM/balance_mode 2>/dev/null
      [ -n "$T_ATC" ] && echo "$T_ATC" > $TM/atc_enable 2>/dev/null
      echo "OK RESET BOOST=$(cat $TM/boost) BALANCE=$(cat $TM/balance_mode) ATC=$(cat $TM/atc_enable)"
    else
      echo "ERR 无备份"
    fi
    ;;

  *)
    echo "用法: thermctl.sh {get|boost <0|1>|balance <0|1|2>|atc <0|1|-1>|reset}"
    exit 1
    ;;
esac
