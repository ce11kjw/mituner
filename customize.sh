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

# 平台检查（本模块针对 MTK + MIUI 优化，但通用项也能用）
SOC=$(getprop ro.board.platform)
case "$SOC" in
  mt*)
    ui_print "- MTK 平台 : ✓ ($SOC)"
    ;;
  *)
    ui_print "! 非 MTK 平台 ($SOC)"
    ui_print "! 通用优化项仍有效，但 MTK 专属路径会跳过"
    ;;
esac

# 备份原始值
mkdir -p /data/adb/mituner
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

# 默认配置（用户可编辑）
if [ ! -f /data/adb/mituner/settings.conf ]; then
  cat > /data/adb/mituner/settings.conf <<'EOC'
# MiTuner 配置（改完重启生效，或在 WebUI 点刷新）
#
# 游戏白名单：用 | 分隔，支持完整包名
# GAME_LIST="com.example.game1|com.example.game2"
#
# 自动识别（白名单没命中时）：1=开 0=关
AUTO_GAME=1
# 自动识别的 GPU 负载阈值（百分比）
AUTO_GPU_TH=60
#
# 息屏时 CPU 下限（微秒）
IDLE_MIN_C0=220000
IDLE_MIN_C1=400000
IDLE_MIN_C2=1200000
#
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
ui_print "工作方式："
ui_print "  · 开机早期应用基础优化"
ui_print "  · 每 5 秒检测前台应用，自动切换三种档位"
ui_print "  · 游戏时放开 / 日常平衡 / 息屏省电"
ui_print " "
ui_print "配置: /data/adb/mituner/settings.conf"
ui_print "日志: /data/local/tmp/mituner.log"
ui_print " "
ui_print "注意：本模块不修改 CPU 频率上限，"
ui_print "      性能上限由系统原有调度模块决定。"
ui_print " "
