#!/system/bin/sh
# MiTuner - 运行态守护：三态智能切换（日常 / 游戏 / 息屏）
#
# 设计原则：
#   1. 绝不降低 CPU 频率上限（那是 CTS 等调度模块的职责，改会打架）
#   2. 只做「减少浪费」：内存回收、IO 预读、调度响应
#   3. 按场景差异化：游戏放开、息屏省电、日常平衡
#   4. 热更新：games.conf 改动 3 秒内自动重载，无需重启

MODDIR=${0%/*}
LOG=/data/local/tmp/mituner.log
BK=/data/adb/mituner
CFG=$BK/settings.conf
GAMEFILE=$BK/games.conf
PIDFILE=/data/local/tmp/mituner.pid

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }
w() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; return 0; }

mkdir -p "$BK"

# 防重复启动
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$$" ] && [ -d "/proc/$old" ]; then
    log "已有实例 pid=$old，本实例退出"
    exit 0
  fi
fi
echo $$ > "$PIDFILE"

# ---------- 默认配置 ----------
AUTO_GAME=1
AUTO_GPU_TH=60
IDLE_MIN_C0=220000
IDLE_MIN_C1=400000
IDLE_MIN_C2=1200000
IDLE_RA=128
NORMAL_RA=256
GAME_RA=512
[ -f "$CFG" ] && . "$CFG"

STATE=""
FB=$BK/fb_flag
GL=$BK/games.list
FORCE=$BK/force

# ---------- 白名单清洗 ----------
build_game_list() {
  # ★ 只取每行第一段（丢弃备注），避免 "包名<TAB>备注" 被粘连
  [ -f "$GAMEFILE" ] || { : > "$GL"; return 0; }
  awk '{
    if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next
    pkg = $1
    gsub(/\t/, "", pkg)
    if (pkg != "") print pkg
  }' "$GAMEFILE" > "$GL" 2>/dev/null
}

build_game_list
GAME_COUNT=$(wc -l < "$GL" 2>/dev/null | tr -d ' ')
log "游戏白名单加载: ${GAME_COUNT:-0} 个"

# ---------- 工具 ----------
get_fg() {
  timeout 4 dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 | sed 's/.*u0 \([^\/]*\).*/\1/'
}

get_screen() {
  dumpsys power 2>/dev/null | grep -oE "mWakefulness=(Awake|Asleep|Dozing)" | head -1 | sed 's/.*=//'
}

is_game() {
  pkg="$1"
  [ -z "$pkg" ] && return 1
  [ -s "$GL" ] || return 1
  grep -qFx "$pkg" "$GL"
}

gpu_load() {
  cat /sys/module/ged/parameters/gpu_loading 2>/dev/null | head -1
}

is_heavy_auto() {
  g=$(gpu_load)
  [ -z "$g" ] && return 1
  [ "$g" -lt "$AUTO_GPU_TH" ] 2>/dev/null && return 1
  fg=$(cat "$FB" 2>/dev/null)
  case "$fg" in
    *launcher*|*miui.home*|*systemui*|*inputmethod*|*settings*|*.lark*|*tencent.mm*|*NotificationShade*|"")
      return 1 ;;
  esac
  return 0
}

# ---------- 三态策略 ----------
apply_normal() {
  w /proc/sys/vm/swappiness 60
  w /proc/sys/vm/vfs_cache_pressure 80
  w /proc/sys/vm/dirty_ratio 15
  w /proc/sys/vm/dirty_background_ratio 5
  w /proc/sys/vm/page-cluster 0
  for q in /sys/block/*/queue; do
    case "$q" in *loop*|*ram*|*zram*) continue;; esac
    echo $NORMAL_RA > "$q/read_ahead_kb" 2>/dev/null
    echo 1 > "$q/rq_affinity" 2>/dev/null
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo 500 > "$p/schedutil/rate_limit_us" 2>/dev/null
  done
  w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 220000
  w /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq 400000
  w /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq 1200000
}

apply_game() {
  w /proc/sys/vm/swappiness 40
  w /proc/sys/vm/vfs_cache_pressure 60
  w /proc/sys/vm/dirty_ratio 10
  w /proc/sys/vm/dirty_background_ratio 3
  for q in /sys/block/*/queue; do
    case "$q" in *loop*|*ram*|*zram*) continue;; esac
    echo $GAME_RA > "$q/read_ahead_kb" 2>/dev/null
    echo 1 > "$q/rq_affinity" 2>/dev/null
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo 200 > "$p/schedutil/rate_limit_us" 2>/dev/null
  done
  w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 220000
  w /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq 400000
  w /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq 1200000
  w /dev/stune/top-app/schedtune.boost 10
  w /dev/stune/top-app/schedtune.prefer_idle 1
}

apply_idle() {
  w /proc/sys/vm/swappiness 80
  w /proc/sys/vm/vfs_cache_pressure 120
  for q in /sys/block/*/queue; do
    case "$q" in *loop*|*ram*|*zram*) continue;; esac
    echo $IDLE_RA > "$q/read_ahead_kb" 2>/dev/null
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo 2000 > "$p/schedutil/rate_limit_us" 2>/dev/null
  done
  w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq $IDLE_MIN_C0
  w /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq $IDLE_MIN_C1
  w /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq $IDLE_MIN_C2
}

# ---------- 判定 ----------
decide() {
  # WebUI 手动强制（一次性，读完即删）
  if [ -f "$FORCE" ]; then
    local f=$(cat "$FORCE" 2>/dev/null)
    rm -f "$FORCE"
    case "$f" in
      GAME|NORMAL) echo "$f"; return ;;
    esac
  fi

  scr=$(get_screen)
  [ "$scr" != "Awake" ] && { echo "IDLE"; return; }

  fg=$(get_fg)
  [ -n "$fg" ] && echo "$fg" > "$FB"

  is_game "$fg" && { echo "GAME"; return; }

  if [ "$AUTO_GAME" = "1" ] && is_heavy_auto; then
    echo "GAME"
    return
  fi

  echo "NORMAL"
}

switch_state() {
  new="$1"
  case "$new" in
    IDLE)  apply_idle ;;
    GAME)  apply_game ;;
    *)     apply_normal ;;
  esac
  echo "$new" > "$BK/state"
  log "切换 -> $new (前台=$(cat $FB 2>/dev/null))"
}

# ---------- 主循环 ----------
log "=== service.sh 启动 (pid=$$) ==="

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 180 ]; do
  sleep 2; i=$((i+1))
done
log "开机完成，开始调度"

STATE=$(decide)
switch_state "$STATE"

GHASH=""
while true; do
  if [ "$STATE" = "IDLE" ]; then
    sleep 5      # 息屏也保持 5 秒，确保唤醒秒响应
  else
    sleep 3      # 亮屏 3 秒，游戏切换更灵敏 + games.conf 更快生效
  fi

  # ★ 热更新：games.conf 变了立即重建列表
  if [ -f "$GAMEFILE" ]; then
    NEWH=$(wc -c < "$GAMEFILE" 2>/dev/null | tr -d ' ')
    if [ "$NEWH" != "$GHASH" ]; then
      GHASH="$NEWH"
      build_game_list
      GAME_COUNT=$(wc -l < "$GL" 2>/dev/null | tr -d ' ')
      log "白名单重载: ${GAME_COUNT:-0} 个"
      # 立即重新判定（可能影响当前档位）
      NEW=$(decide)
      if [ "$NEW" != "$STATE" ]; then
        STATE="$NEW"
        switch_state "$STATE"
        continue
      fi
    fi
  fi

  NEW=$(decide)

  if [ "$STATE" = "IDLE" ] && [ "$NEW" != "IDLE" ]; then
    STATE="$NEW"
    switch_state "$STATE"
    continue
  fi

  if [ "$NEW" = "GAME" ] && [ "$STATE" != "GAME" ]; then
    fg=$(cat "$FB" 2>/dev/null)
    if ! is_game "$fg"; then
      sleep 2
      [ "$(decide)" = "GAME" ] || continue
    fi
  fi

  if [ "$NEW" != "$STATE" ]; then
    STATE="$NEW"
    switch_state "$STATE"
  fi
done
