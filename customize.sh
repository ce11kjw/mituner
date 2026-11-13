#!/system/bin/sh
# MiTuner - 安装脚本
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

# 配置目录
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

# 部署游戏白名单（覆盖更新时保留用户的改动）
if [ -f "$MODPATH/games.conf" ]; then
  if [ -f /data/adb/mituner/games.conf ]; then
    # 已有文件：备份旧的，装新的
    cp -f /data/adb/mituner/games.conf /data/adb/mituner/games.conf.bak
    cp -f "$MODPATH/games.conf" /data/adb/mituner/games.conf
    ui_print "- 已更新游戏白名单（旧版备份为 games.conf.bak）"
  else
    cp -f "$MODPATH/games.conf" /data/adb/mituner/games.conf
    ui_print "- 已安装游戏白名单"
  fi
  N=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' /data/adb/mituner/games.conf 2>/dev/null | wc -l)
  ui_print "  收录 $N 个大型/3A 游戏"
fi

# 默认配置
if [ ! -f /data/adb/mituner/settings.conf ]; then
  cat > /data/adb/mituner/settings.conf <<'EOC'
# MiTuner 配置（改完重启生效）

# 白名单没命中时的自动识别：1=开 0=关
AUTO_GAME=1
# 自动识别的 GPU 负载阈值（百分比）
AUTO_GPU_TH=60

# 息屏时 CPU 下限（微秒）
IDLE_MIN_C0=220000
IDLE_MIN_C1=400000
IDLE_MIN_C2=1200000

# IO 预读大小（KB）
NORMAL_RA=256
GAME_RA=512
IDLE_RA=128
EOC
  ui_print "- 已生成默认配置 settings.conf"
fi

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/post-fs-data.sh 0 0 0755
set_perm $MODPATH/action.sh 0 0 0755
set_perm_recursive $MODPATH/webroot 0 0 0755 0644

ui_print " "
ui_print "────────────────────────────────"
ui_print " 安装完成"
ui_print "────────────────────────────────"
ui_print " "
ui_print "重启后自动生效。"
ui_print " "
ui_print "配置目录: /data/adb/mituner/"
ui_print "  games.conf    - 游戏白名单（可自己加）"
ui_print "  settings.conf - 调度参数"
ui_print " "
ui_print "日志: /data/local/tmp/mituner.log"
ui_print " "
ui_print "注意：本模块不修改 CPU 频率上限，"
ui_print "      性能上限由系统原有调度模块决定。"
ui_print " "
