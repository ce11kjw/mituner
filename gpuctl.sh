#!/system/bin/sh
# MiTuner - GPU 调优
# 用法：gpuctl.sh get | set <max|min|gov> <值> | profile <game|normal|save> | reset

BK=/data/adb/mituner
GPU_BAK=$BK/gpu_orig.conf
D=$(ls -d /sys/class/devfreq/*mali* 2>/dev/null | head -1)

[ -z "$D" ] && { echo "ERR 找不到 GPU devfreq 节点"; exit 1; }

backup() {
  [ -f "$GPU_BAK" ] && return
  {
    echo "G_MAX=$(cat $D/max_freq 2>/dev/null)"
    echo "G_MIN=$(cat $D/min_freq 2>/dev/null)"
    echo "G_GOV=$(cat $D/governor 2>/dev/null)"
  } > "$GPU_BAK"
}

# 校验频率是否在可用列表
valid_freq() {
  case " $(cat $D/available_frequencies 2>/dev/null) " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# 找最接近的合法频率（用于 profile 预设）
nearest_freq() {
  local target=$1 best=0 diff=999999999 f
  for f in $(cat $D/available_frequencies 2>/dev/null); do
    case "$f" in *[!0-9]*) continue;; esac
    local d=$(( f > target ? f - target : target - f ))
    if [ "$d" -lt "$diff" ]; then diff=$d; best=$f; fi
  done
  echo "$best"
}

cmd="$1"

case "$cmd" in

  get)
    echo "NODE=$D"
    echo "CUR=$(cat $D/cur_freq 2>/dev/null)"
    echo "MIN=$(cat $D/min_freq 2>/dev/null)"
    echo "MAX=$(cat $D/max_freq 2>/dev/null)"
    echo "GOV=$(cat $D/governor 2>/dev/null)"
    echo "AVAIL_GOV=$(cat $D/available_governors 2>/dev/null)"
    echo "FREQS=$(cat $D/available_frequencies 2>/dev/null)"
    echo "LOAD=$(cat /sys/module/ged/parameters/gpu_loading 2>/dev/null)"
    echo "REAL_KHZ=$(cat /sys/kernel/ged/hal/current_freqency 2>/dev/null | awk '{print $2}')"
    ;;

  set)
    K="$2"; V="$3"
    backup
    case "$K" in
      max)
        valid_freq "$V" || { echo "ERR 非法频率 $V"; exit 1; }
        CURMIN=$(cat $D/min_freq 2>/dev/null)
        [ "$V" -lt "$CURMIN" ] && echo "$V" > "$D/min_freq" 2>/dev/null
        echo "$V" > "$D/max_freq" 2>/dev/null
        echo "OK MAX=$(cat $D/max_freq 2>/dev/null)"
        ;;
      min)
        valid_freq "$V" || { echo "ERR 非法频率 $V"; exit 1; }
        CURMAX=$(cat $D/max_freq 2>/dev/null)
        [ "$V" -gt "$CURMAX" ] && echo "$V" > "$D/max_freq" 2>/dev/null
        echo "$V" > "$D/min_freq" 2>/dev/null
        echo "OK MIN=$(cat $D/min_freq 2>/dev/null)"
        ;;
      gov)
        case " $(cat $D/available_governors 2>/dev/null) " in
          *" $V "*) ;;
          *) echo "ERR 非法 governor $V"; exit 1 ;;
        esac
        echo "$V" > "$D/governor" 2>/dev/null
        echo "OK GOV=$(cat $D/governor 2>/dev/null)"
        ;;
      *)
        echo "ERR 未知键 $K（max/min/gov）"; exit 1
        ;;
    esac
    ;;

  profile)
    backup
    P="$2"
    case "$P" in
      game)
        echo performance > "$D/governor" 2>/dev/null
        F=$(nearest_freq 825000000)
        echo "$F" > "$D/max_freq" 2>/dev/null
        ;;
      normal)
        echo simple_ondemand > "$D/governor" 2>/dev/null
        F=$(nearest_freq 825000000)
        echo "$F" > "$D/max_freq" 2>/dev/null
        ;;
      save)
        echo simple_ondemand > "$D/governor" 2>/dev/null
        F=$(nearest_freq 460000000)
        echo "$F" > "$D/max_freq" 2>/dev/null
        ;;
      *)
        echo "ERR 未知方案 $P（game/normal/save）"; exit 1
        ;;
    esac
    echo "OK PROFILE=$P GOV=$(cat $D/governor 2>/dev/null) MAX=$(cat $D/max_freq 2>/dev/null)"
    ;;

  reset)
    if [ -f "$GPU_BAK" ]; then
      . "$GPU_BAK"
      [ -n "$G_MIN" ] && echo "$G_MIN" > "$D/min_freq" 2>/dev/null
      [ -n "$G_MAX" ] && echo "$G_MAX" > "$D/max_freq" 2>/dev/null
      [ -n "$G_GOV" ] && echo "$G_GOV" > "$D/governor" 2>/dev/null
      echo "OK RESET GOV=$(cat $D/governor 2>/dev/null) MAX=$(cat $D/max_freq 2>/dev/null)"
    else
      echo "ERR 无备份"
    fi
    ;;

  *)
    echo "用法: gpuctl.sh {get|set <max|min|gov> <值>|profile <game|normal|save>|reset}"
    exit 1
    ;;
esac
