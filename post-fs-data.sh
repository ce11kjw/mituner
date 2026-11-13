#!/system/bin/sh
# MiTuner - 开机早期（在系统服务之前）
MODDIR=${0%/*}
LOG=/data/local/tmp/mituner.log
BK=/data/adb/mituner

log() { echo "[$(date '+%m-%d %H:%M:%S')] [pfd] $*" >> "$LOG"; }

log "=== post-fs-data 开始 ==="

mkdir -p "$BK"

# 1. 部署默认配置（首次安装时）
if [ ! -f "$BK/games.conf" ] && [ -f "$MODDIR/games.conf" ]; then
  cp -f "$MODDIR/games.conf" "$BK/games.conf" 2>/dev/null
  log "已部署默认 games.conf"
fi

# 2. 同步模块内 games.conf 到配置目录（仅当配置不存在）
#    ⚠️ 不能覆盖用户已有的，否则 WebUI 里的增删会被抹掉

# 3. 应用基础优化（幂等）
if [ -f "$MODDIR/apply.sh" ]; then
  sh "$MODDIR/apply.sh" >/dev/null 2>&1
  log "基础优化已应用"
fi

# 4. 启动热更新守护（监听 modules_update，实现免重启更新）
if [ -f "$MODDIR/hotupdate.sh" ]; then
  /data/adb/ap/bin/busybox setsid sh "$MODDIR/hotupdate.sh" >/dev/null 2>&1 &
  log "热更新守护已启动"
fi

log "=== post-fs-data 完成 ==="
