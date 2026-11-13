#!/system/bin/sh
# MiTuner - 运行态守护：三态智能切换
#
# 检测策略（混合模式，2026-11-14 用户确认）：
#   前台是游戏           → 立即 GAME
#   游戏切到后台但屏幕亮  → 保持 GAME 最多 30 秒
#   超时 / 屏幕灭         → 退出

MODDIR=${0%/*}
LOG=/data/local/tmp/mituner.log
DEBUG_LOG=/data/local/tmp/mituner-debug.log
BK=/data/adb/mituner
CFG=$BK/settings.conf
GAMEFILE=$BK/games.conf
PIDFILE=/data/local/tmp/mituner.pid

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }
dbg() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"; }
w() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; return 0; }

mkdir -p "$BK"

# ★ 强化防重复：扫描 /proc 找所有同名实例，只保留最早的一个
# ★ 强化防重复：扫描 /proc 找所有同名实例，只保留最早的一个
lock_self() {
  local me=$$
  local first=""
  for d in /proc/[0-9]*; do
    local pid=${d#/proc/}
    [ -d "$d" ] || continue
    local c=$(tr "\0" " " < $d/cmdline 2>/dev/null)
    case "$c" in
      *"sh /data/adb/modules/mituner/service.sh"*)
        [ -z "$first" ] && first=$pid
        ;;
    esac
  done
  if [ -n "$first" ] && [ "$first" != "$me" ]; then
    log "已有更早实例 pid=$first，本实例($me)退出"
    exit 0
  fi
  echo "$me" > "$PIDFILE"
  dbg "lock_self: pidfile 写入 $me"
}
lock_self
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$$" ] && [ -d "/proc/$old" ]; then
    log "已有实例 pid=$old，退出"
    exit 0
  fi
echo $$ > "$PIDFILE"

# ---------- 配置 ----------
AUTO_GAME=0
AUTO_GPU_TH=60
GAME_EXIT_SEC=30
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
GAME_UNTIL=$BK/game_until

# ---------- 白名单清洗（只取第一段） ----------
build_game_list() {
  [ -f "$GAMEFILE" ] || { : > "$GL"; return 0; }
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { pkg=$1; gsub(/\t/,"",pkg); if (pkg != "") print pkg }
  ' "$GAMEFILE" > "$GL" 2>/dev/null
}

build_game_list
GAME_COUNT=$(wc -l < "$GL" 2>/dev/null | tr -d ' ')
log "白名单: ${GAME_COUNT:-0} 个 (退出延迟 ${GAME_EXIT_SEC}s)"

# ---------- 工具 ----------
# ★ 严格提取包名：格式必须是 xxx.yyy，否则返回空
get_fg() {
  local raw=$(timeout 4 dumpsys window 2>/dev/null | grep mCurrentFocus | head -1)
  [ -z "$raw" ] && return
  local pkg=$(echo "$raw" | sed -n 's/.*u[0-9][0-9]* \([^ \/]*\)\/.*/\1/p')
  # 严格校验：至少含一个点，只用包名字符
  case "$pkg" in
    *.*)
      echo "$pkg" | grep -qE '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$' && echo "$pkg"
      ;;
  esac
}

get_screen() {
  local s=$(dumpsys power 2>/dev/null | grep -oE "mWakefulness=(Awake|Asleep|Dozing)" | head -1 | sed 's/.*=//')
  echo "$s"
}

is_game() {
  local pkg="$1"
  [ -z "$pkg" ] && return 1
  [ -s "$GL" ] || return 1
  grep -qFx "$pkg" "$GL" 2>/dev/null
}

gpu_load() { cat /sys/module/ged/parameters/gpu_loading 2>/dev/null | head -1; }
now() { date +%s; }

is_heavy_auto() {
  local g=$(gpu_load)
  [ -z "$g" ] && return 1
  [ "$g" -lt "$AUTO_GPU_TH" ] 2>/dev/null && return 1
  local fg=$(cat "$FB" 2>/dev/null)
  case "$fg" in
    ""|*launcher*|*miui.home*|*systemui*|*inputmethod*|*settings*|*.lark*|*tencent.mm*|*searchbox*|*intentresolver*)
      return 1 ;;
  esac
  return 0
}

# ---------- 三态 ----------
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

# ---------- 判定（带调试） ----------
decide() {
  if [ -f "$FORCE" ]; then
    local f=$(cat "$FORCE" 2>/dev/null)
    rm -f "$FORCE"
    case "$f" in
      GAME)   dbg "force -> GAME"; echo GAME;   return ;;
      NORMAL) dbg "force -> NORMAL"; echo NORMAL; return ;;
      IDLE)   dbg "force -> IDLE"; echo IDLE;   return ;;
    esac
  fi

  local scr=$(get_screen)
  if [ "$scr" != "Awake" ]; then
    dbg "scr=[$scr] -> IDLE"
    echo "IDLE"
    return
  fi

  local fg=$(get_fg)
  [ -n "$fg" ] && echo "$fg" > "$FB"

  if is_game "$fg"; then
    now > "$GAME_UNTIL" 2>/dev/null
    dbg "fg=[$fg] 命中白名单 -> GAME（重置 until）"
    echo GAME
    return
  fi

  if [ "$AUTO_GAME" = "1" ] && is_heavy_auto; then
    now > "$GAME_UNTIL" 2>/dev/null
    dbg "fg=[$fg] GPU自动识别 -> GAME"
    echo GAME
    return
  fi

  if [ -f "$GAME_UNTIL" ]; then
    local since=$(cat "$GAME_UNTIL" 2>/dev/null)
    if [ -n "$since" ]; then
      local el=$(( $(now) - since ))
      if [ "$el" -ge 0 ] && [ "$el" -lt "$GAME_EXIT_SEC" ]; then
        dbg "fg=[$fg] 保持期 ${el}s/${GAME_EXIT_SEC}s -> GAME_HOLD"
        echo "GAME_HOLD"
        return
      fi
      dbg "fg=[$fg] 保持期已过 ${el}s -> 清除 until，NORMAL"
      rm -f "$GAME_UNTIL"
    fi
  fi

  dbg "fg=[$fg] -> NORMAL"
  echo "NORMAL"
}

switch_state() {
  local raw="$1"
  local new="$raw"
  [ "$raw" = "GAME_HOLD" ] && new="GAME"

  case "$new" in
    IDLE)  apply_idle ;;
    GAME)  apply_game ;;
    *)     apply_normal ;;
  esac

  echo "$new" > "$BK/state"
  echo "$raw" > "$BK/state_raw" 2>/dev/null

  if [ "$raw" = "GAME_HOLD" ] && [ -f "$GAME_UNTIL" ]; then
    local left=$(( GAME_EXIT_SEC - ($(now) - $(cat "$GAME_UNTIL" 2>/dev/null)) ))
    log "保持 GAME（剩余约 ${left}s）"
  else
    log "切换 -> $new"
  fi
}

# ---------- 主循环 ----------
log "=== service.sh 启动 (pid=$$) ==="
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 180 ]; do
  sleep 2; i=$((i+1))
done
log "开机完成"

STATE=$(decide)
switch_state "$STATE"

GHASH=""
while true; do
  if [ "$STATE" = "IDLE" ]; then sleep 5; else sleep 3; fi

  # 白名单热重载
  if [ -f "$GAMEFILE" ]; then
    NEWH=$(wc -c < "$GAMEFILE" 2>/dev/null | tr -d ' ')
    if [ "$NEWH" != "$GHASH" ]; then
      GHASH="$NEWH"
      build_game_list
      GAME_COUNT=$(wc -l < "$GL" 2>/dev/null | tr -d ' ')
      log "白名单重载: ${GAME_COUNT:-0} 个"
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

  # 自动识别的 GAME 需二次确认
  if [ "$NEW" = "GAME" ] && [ "$STATE" != "GAME" ]; then
    local fg=$(cat "$FB" 2>/dev/null)
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
