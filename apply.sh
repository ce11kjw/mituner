#!/system/bin/sh
# MiTuner - 基础优化应用脚本（幂等，可随时重复执行）
#
# 与 post-fs-data.sh 的区别：
#   post-fs-data.sh 只在开机早期跑一次（只做最基础的部分）
#   apply.sh 可被 service.sh / WebUI「重新应用」按钮随时调用
# 所有写操作都是幂等的，重复执行无副作用。

BK=/data/adb/mituner
LOG=/data/local/tmp/mituner.log
mkdir -p "$BK"

log() { echo "[$(date '+%m-%d %H:%M:%S')] [apply] $*" >> "$LOG"; }
w() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; return 0; }

# ---------- 备份原始值（只生成一次） ----------
backup_orig() {
  [ -f "$BK/orig.conf" ] && return
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
  } > "$BK/orig.conf"
  log "已备份原始值"
}

apply_base() {
  log "应用基础优化"

  # 内存回收
  w /proc/sys/vm/swappiness 60
  w /proc/sys/vm/vfs_cache_pressure 80
  w /proc/sys/vm/dirty_ratio 15
  w /proc/sys/vm/dirty_background_ratio 5
  w /proc/sys/vm/page-cluster 0
  w /proc/sys/vm/watermark_scale_factor 100

  # IO（动态扫描所有块设备，不写死）
  for q in /sys/block/*/queue; do
    [ -d "$q" ] || continue
    # 跳过 loop/ram/zram
    case "$q" in *loop*|*ram*|*zram*) continue;; esac
    echo 256 > "$q/read_ahead_kb" 2>/dev/null
    echo 1 > "$q/rq_affinity" 2>/dev/null
  done

  # 调度响应
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p/schedutil" ] || continue
    echo 500 > "$p/schedutil/rate_limit_us" 2>/dev/null
  done

  # 网络
  w /proc/sys/net/ipv4/tcp_fastopen 3

  log "基础优化完成"
}

backup_orig
apply_base

# 输出当前值（供 WebUI 展示 / 调试）
echo "swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)"
echo "vfs=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"
echo "ra=$(cat /sys/block/dm-47/queue/read_ahead_kb 2>/dev/null)"
echo "rl=$(cat /sys/devices/system/cpu/cpufreq/policy7/schedutil/rate_limit_us 2>/dev/null)"
