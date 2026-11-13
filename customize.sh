#!/system/bin/sh
# MiTuner - 安装脚本（支持热更新，装完自动同步并重启服务）
SKIPUNZIP=0

ui_print " "
ui_print "════════════════════════════════"
ui_print "  MiTuner 系统调优"
ui_print "════════════════════════════════"
ui_print " "
ui_print "- 设备 : $(getprop ro.product.odm.marketname)"
ui_print "- 型号 : $(getprop ro.product.model) ($(getprop ro.product.device))"
ui_print "- SoC  : $(getprop ro.board.platform)"
ui_print "- 系统 : Android $(getprop ro.build.version.release)"
ui_print "- 内存 : $(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo) MB"
ui_print " "

SOC=$(getprop ro.board.platform)
case "$SOC" in
  mt*) ui_print "- MTK 平台 : ✓ ($SOC)" ;;
  *)   ui_print "! 非 MTK ($SOC)，通用优化仍有效" ;;
esac

mkdir -p /data/adb/mituner

# 备份原始值
if [ ! -f /data/adb/mituner/orig.conf ]; then
  {
    echo "O_SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null)"
    echo "O_VFS=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"
    echo "O_DIRTY=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null)"
    echo "O_DIRTYBG=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null)"
    echo "O_PAGECLUSTER=$(cat /proc/sys/vm/page-cluster 2>/dev/null)"
    echo "O_WATERMARK=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null)"
    echo "O_RA=$(cat /sys/block/dm-47/queue/read_ahead_kb 2>/dev/null)"
    echo "O_RQAFF=$(cat /sys/block/dm-47/queue/rq_affinity 2>/dev/null)"
    echo "O_RL=$(cat /sys/devices/system/cpu/cpufreq/policy7/schedutil/rate_limit_us 2>/dev/null)"
  } > /data/adb/mituner/orig.conf
  ui_print "- 已备份原始参数"
fi

# ★ 游戏白名单：只有不存在时才装（保护用户自定义）
if [ -f "$MODPATH/games.conf" ]; then
  if [ ! -f /data/adb/mituner/games.conf ]; then
    cp -f "$MODPATH/games.conf" /data/adb/mituner/games.conf
    ui_print "- 已安装游戏白名单"
  else
    ui_print "- 保留已有游戏白名单（不覆盖你的自定义）"
  fi
  N=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' /data/adb/mituner/games.conf 2>/dev/null | wc -l)
  ui_print "  当前收录 $N 款"
fi

# 默认参数
if [ ! -f /data/adb/mituner/settings.conf ]; then
  cat > /data/adb/mituner/settings.conf <<'EOC'
# MiTuner 配置
AUTO_GAME=1
AUTO_GPU_TH=60
IDLE_MIN_C0=220000
IDLE_MIN_C1=400000
IDLE_MIN_C2=1200000
NORMAL_RA=256
GAME_RA=512
IDLE_RA=128
EOC
fi

set_perm_recursive $MODPATH 0 0 0755 0644
for f in service.sh post-fs-data.sh action.sh apply.sh hotupdate.sh; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
set_perm "$MODPATH/games.conf" 0 0 0644
set_perm_recursive $MODPATH/webroot 0 0 0755 0644

# ★★ 热更新：立即同步 modules_update -> modules 并重启服务
ui_print " "
ui_print "- 正在热应用（无需重启手机）…"

REAL=/data/adb/modules/mituner
if [ -d "$MODPATH" ] && [ "$MODPATH" != "$REAL" ]; then
  mkdir -p "$REAL"
  for f in module.prop post-fs-data.sh service.sh action.sh customize.sh uninstall.sh apply.sh hotupdate.sh games.conf README.md CHANGELOG.md update.json; do
    [ -f "$MODPATH/$f" ] && cp -f "$MODPATH/$f" "$REAL/$f" 2>/dev/null
  done
  if [ -d "$MODPATH/webroot" ]; then
    mkdir -p "$REAL/webroot"
    cp -f "$MODPATH/webroot/"* "$REAL/webroot/" 2>/dev/null
  fi
  chmod 755 "$REAL"/*.sh 2>/dev/null
  chmod 644 "$REAL"/*.md "$REAL"/*.json "$REAL/module.prop" "$REAL/games.conf" 2>/dev/null
  chmod 644 "$REAL"/webroot/* 2>/dev/null
  rm -f "$REAL/update"

  # 重启守护
  for pf in /data/local/tmp/mituner.pid /data/local/tmp/mituner-hotupdate.pid; do
    if [ -f "$pf" ]; then
      old=$(cat "$pf" 2>/dev/null)
      [ -n "$old" ] && kill -9 "$old" 2>/dev/null
      rm -f "$pf"
    fi
  done

  # 立即应用优化
  [ -f "$REAL/apply.sh" ] && sh "$REAL/apply.sh" >/dev/null 2>&1

  # 拉起服务
  if [ "$(getprop sys.boot_completed)" = "1" ]; then
    /data/adb/ap/bin/busybox setsid sh "$REAL/hotupdate.sh" >/dev/null 2>&1 &
    sleep 1
    /data/adb/ap/bin/busybox setsid sh "$REAL/service.sh" >/dev/null 2>&1 &
    sleep 2
    ui_print "  ✓ 已生效，无需重启"
  else
    ui_print "  ✓ 已完成同步（首次安装仍需重启）"
  fi
fi

ui_print " "
ui_print "────────────────────────────────"
ui_print " 安装完成"
ui_print "────────────────────────────────"
ui_print " "
ui_print "WebUI: 在管理器里点开本模块即可"
ui_print "  · 游戏白名单可在 WebUI 里增删"
ui_print "  · 改完立即生效，无需重启"
ui_print " "
ui_print "配置文件: /data/adb/mituner/"
ui_print "日志: /data/local/tmp/mituner.log"
ui_print " "
