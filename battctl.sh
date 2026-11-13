#!/system/bin/sh
# MiTuner - 电池健康
# 用法：battctl.sh info | history [N]

BK=/data/adb/mituner
BH=$BK/batt_history.csv
BAT=/sys/class/power_supply/battery
BMS=/sys/class/power_supply/bms

cmd="$1"

case "$cmd" in

  info)
    CYC=$(cat $BAT/cycle_count 2>/dev/null)
    FULL=$(cat $BAT/charge_full 2>/dev/null)
    DES=$(cat $BAT/charge_full_design 2>/dev/null)
    SOH=$(cat $BMS/soh 2>/dev/null)
    RES=$(cat $BMS/resistance 2>/dev/null)
    CAP=$(cat $BAT/capacity 2>/dev/null)
    ST=$(cat $BAT/status 2>/dev/null)
    TMP=$(cat $BAT/temp 2>/dev/null)
    VOL=$(cat $BAT/voltage_now 2>/dev/null)
    CUR=$(cat $BAT/current_now 2>/dev/null)

    echo "CYCLE=${CYC:-0}"
    echo "FULL_MAH=$(( ${FULL:-0} / 1000 ))"
    echo "DESIGN_MAH=$(( ${DES:-0} / 1000 ))"
    echo "SOH=${SOH:-0}"
    echo "RESISTANCE=$(( ${RES:-0} / 1000 ))"
    echo "CAPACITY=${CAP:-0}"
    echo "STATUS=${ST:-unknown}"
    echo "TEMP=$(( ${TMP:-0} / 10 ))"
    echo "VOLTAGE=$(( ${VOL:-0} / 1000 ))"
    echo "CURRENT=$(( ${CUR:-0} / 1000 ))"

    # 健康度计算（用实际/设计容量）
    if [ -n "$FULL" ] && [ -n "$DES" ] && [ "$DES" -gt 0 ] 2>/dev/null; then
      echo "HEALTH_PCT=$(( FULL * 100 / DES ))"
    else
      echo "HEALTH_PCT=${SOH:-0}"
    fi

    # 估算剩余寿命（循环 800 次到 80% 为参考）
    if [ -n "$CYC" ] && [ "$CYC" -ge 0 ] 2>/dev/null; then
      LEFT=$(( 800 - CYC ))
      [ "$LEFT" -lt 0 ] && LEFT=0
      echo "LIFE_LEFT=$LEFT"
    fi

    # 记录历史（每次调用追加，同一天只记一条）
    TODAY=$(date +%Y-%m-%d)
    if [ -f "$BH" ]; then
      LAST=$(tail -1 "$BH" 2>/dev/null | cut -d, -f1)
    else
      echo "date,cycle,full_mah,soh,health_pct" > "$BH"
      LAST=""
    fi
    if [ "$LAST" != "$TODAY" ]; then
      HP=$(( ${FULL:-0} * 100 / ${DES:-1} ))
      echo "$TODAY,${CYC:-0},$(( ${FULL:-0} / 1000 )),${SOH:-0},$HP" >> "$BH"
    fi
    ;;

  history)
    N=${2:-30}
    if [ -f "$BH" ]; then
      tail -$N "$BH"
    else
      echo "暂无历史数据（每次打开电池页会自动记录一天一条）"
    fi
    ;;

  *)
    echo "用法: battctl.sh {info|history [N]}"
    exit 1
    ;;
esac
