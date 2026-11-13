#!/system/bin/sh
# MiTuner 热更新守护
# 监听 /data/adb/modules_update/mituner/，发现新版本就自动同步到正式目录并重启服务
# 用户装完新版本不用重启手机

LOG=/data/local/tmp/mituner.log
MODDIR=/data/adb/modules/mituner
UPD=/data/adb/modules_update/mituner
PIDFILE=/data/local/tmp/mituner-hotupdate.pid
SPID=/data/local/tmp/mituner.pid

log() { echo "[$(date '+%m-%d %H:%M:%S')] [hot] $*" >> "$LOG"; }

# 防重复
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$old" ] && [ "$old" != "$$" ] && [ -d "/proc/$old" ]; then
    log "已有实例 pid=$old，退出"
    exit 0
  fi
fi
echo $$ > "$PIDFILE"

log "=== 热更新守护启动 (pid=$$) ==="

restart_service() {
  if [ -f "$SPID" ]; then
    old=$(cat "$SPID" 2>/dev/null)
    [ -n "$old" ] && [ -d "/proc/$old" ] && kill -9 "$old" 2>/dev/null
  fi
  rm -f "$SPID"
  sleep 1
  BB=/data/adb/ap/bin/busybox
  [ -x "$BB" ] || BB=busybox
  $BB setsid sh "$MODDIR/service.sh" >/dev/null 2>&1 &
  log "service.sh 已重启"
}

do_sync() {
  log "检测到新版本，开始同步"

  # 1. 备份（回滚用）
  if [ -d "$MODDIR" ]; then
    rm -rf /data/adb/mituner.backup 2>/dev/null
    cp -a "$MODDIR" /data/adb/mituner.backup 2>/dev/null
  fi

  # ★ 2. 全量同步（不写死文件名，新增文件也能带过来）
  mkdir -p "$MODDIR"
  # 用 cp -a 逐项复制（避免 rm -rf 导致服务运行中的脚本消失）
  for item in "$UPD"/*; do
    [ -e "$item" ] || continue
    base=$(basename "$item")
    case "$base" in
      update) continue ;;   # 跳过 update 标记
      *.bak)  continue ;;
    esac
    if [ -d "$item" ]; then
      mkdir -p "$MODDIR/$base"
      cp -rf "$item"/* "$MODDIR/$base/" 2>/dev/null
    else
      cp -f "$item" "$MODDIR/$base" 2>/dev/null
    fi
  done

  # 3. 权限
  chmod 755 "$MODDIR"/*.sh 2>/dev/null
  chmod 644 "$MODDIR"/*.md "$MODDIR"/*.json "$MODDIR"/module.prop "$MODDIR"/games.conf 2>/dev/null
  [ -d "$MODDIR/webroot" ] && chmod 644 "$MODDIR/webroot"/* 2>/dev/null

  # 4. 清标记
  rm -f "$MODDIR/update"
  rm -rf "$UPD"

  # 5. 首次部署默认 games.conf（不覆盖用户已有的）
  if [ -f "$MODDIR/games.conf" ] && [ ! -f /data/adb/mituner/games.conf ]; then
    mkdir -p /data/adb/mituner
    cp -f "$MODDIR/games.conf" /data/adb/mituner/games.conf 2>/dev/null
    log "已部署默认 games.conf"
  fi

  # 6. 立即应用优化 + 重启服务
  [ -f "$MODDIR/apply.sh" ] && sh "$MODDIR/apply.sh" >/dev/null 2>&1

  # 开机完成才重启服务（首次安装时服务还没起过）
  if [ "$(getprop sys.boot_completed)" = "1" ]; then
    restart_service
  fi

  log "同步完成"
}

# 启动时如果已经有待更新的，先处理
[ -d "$UPD" ] && [ -f "$UPD/module.prop" ] && do_sync

# 轮询（8 秒一次）
while true; do
  sleep 8
  if [ -d "$UPD" ] && [ -f "$UPD/module.prop" ]; then
    # 等 3 秒确保文件写完（管理器可能是分批写入）
    sleep 3
    [ -d "$UPD" ] && do_sync
  fi
done
