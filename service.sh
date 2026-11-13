#!/system/bin/sh
# MiTuner - 运行态守护：三态智能切换（日常 / 游戏 / 息屏）
#
# 设计原则：
#   1. 绝不降低 CPU 频率上限（那是 CTS 等调度模块的职责，改会打架）
#   2. 只做「减少浪费」：内存回收、IO 预读、调度响应
#   3. 按场景差异化：游戏放开、息屏省电、日常平衡
#
# 三态：
#   GAME   前台是游戏（白名单 或 GPU高负载自动识别）
#   IDLE   屏幕熄灭 -> 降低 CPU 下限、收紧回收
#   NORMAL 其他 -> 平衡

MODDIR=${0%/*}
LOG=/data/local/tmp/mituner.log
BK=/data/adb/mituner
CFG=$BK/settings.conf

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }
w() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; return 0; }

mkdir -p "$BK"

# ---------- 默认配置 ----------
GAME_LIST="com.tencent.tmgp.sgame|com.tencent.tmgp.pubgmhd|com.tencent.tmgp.pubgm|com.miHoYo.Yuanshen|com.miHoYo.ys.mi|com.netease.mrzh|com.netease.g78na.gb|com.tencent.ig|com.pubg.newstate|com.tencent.lolm|com.tencent.jkchess|com.tencent.tmgp.cod|com.activision.callofduty.shooter|com.ea.gp.apexlegendsmobilefps|com.dts.freefireth|com.mobile.legends|com.riotgames.league.wildrift|com.mojang.minecraftpe|com.tencent.tmgp.dnf|com.netease.harrypotter|com.tencent.tmgp.speedmobile|com.tencent.qqgame|com.hypergryph.arknights|com.miHoYo.bh3|com.miHoYo.hkrpg|com.papegames.nn4|com.bluepoch.m.reverse1999"
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
  echo "$pkg" | grep -qE "^($GAME_LIST)$" && return 0
  return 1
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
  for d in dm-47 dm-48 dm-49 sda sdc; do
    w /sys/block/$d/queue/read_ahead_kb $NORMAL_RA
    w /sys/block/$d/queue/rq_affinity 1
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    w $p/schedutil/rate_limit_us 500
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
  for d in dm-47 dm-48 dm-49 sda sdc; do
    w /sys/block/$d/queue/read_ahead_kb $GAME_RA
    w /sys/block/$d/queue/rq_affinity 1
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    w $p/schedutil/rate_limit_us 200
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
  for d in dm-47 dm-48 dm-49 sda sdc; do
    w /sys/block/$d/queue/read_ahead_kb $IDLE_RA
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    w $p/schedutil/rate_limit_us 2000
  done
  w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq $IDLE_MIN_C0
  w /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq $IDLE_MIN_C1
  w /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq $IDLE_MIN_C2
}

# ---------- 判定 ----------
decide() {
  scr=$(get_screen)
  # 屏幕非亮 -> IDLE（最高优先级，省电）
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
log "=== service.sh 启动 ==="

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 180 ]; do
  sleep 2; i=$((i+1))
done
log "开机完成，开始调度"

STATE=$(decide)
switch_state "$STATE"

# ⭐ 关键修复：息屏时不必高频轮询，但唤醒必须秒响应
#    做法：息屏时用 10 秒轮询（省电），但每轮都检查屏幕状态
#    一旦屏幕变亮，立刻切回并恢复正常轮询
while true; do
  if [ "$STATE" = "IDLE" ]; then
    sleep 10
  else
    sleep 5
  fi

  NEW=$(decide)

  # 从 IDLE 醒来时立刻生效，不做二次确认（避免延迟）
  if [ "$STATE" = "IDLE" ] && [ "$NEW" != "IDLE" ]; then
    STATE="$NEW"
    switch_state "$STATE"
    continue
  fi

  # 自动识别进游戏需连续 2 次命中，防误判
  if [ "$NEW" = "GAME" ] && [ "$STATE" != "GAME" ]; then
    fg=$(cat "$FB" 2>/dev/null)
    if ! is_game "$fg"; then
      sleep 3
      [ "$(decide)" = "GAME" ] || continue
    fi
  fi

  if [ "$NEW" != "$STATE" ]; then
    STATE="$NEW"
    switch_state "$STATE"
  fi
done
