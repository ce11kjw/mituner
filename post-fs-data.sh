#!/system/bin/sh
# MiTuner - 开机早期应用基础优化（在系统的调度模块之前跑完更好）
MODDIR=${0%/*}
LOG=/data/local/tmp/mituner.log

log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "=== post-fs-data 开始 ==="

# 写值辅助（静默失败，节点不存在就跳过）
w() {
  [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null
  return 0
}

# ---- 1. 内存回收策略（核心：减少卡顿 + 省电）----
# swappiness 100 -> 60：不再把活跃内存拼命挤进 zram
#   zram 压缩/解压要占 CPU，被换出的 App 切回来要解压 => 就是"点开卡1-2秒"
w /proc/sys/vm/swappiness 60

# vfs_cache_pressure 100 -> 80：更愿意保留目录项/inode 缓存
#   App 启动要大量 stat/open，缓存命中率高 => 冷启动更快
w /proc/sys/vm/vfs_cache_pressure 80

# 脏页回写更积极，避免大块写盘造成长时间卡顿
w /proc/sys/vm/dirty_ratio 15
w /proc/sys/vm/dirty_background_ratio 5

# page-cluster 0：zram 上做连续预读没意义，还浪费 CPU
w /proc/sys/vm/page-cluster 0

# 内存水位略提高，减少 kswapd 抖动
w /proc/sys/vm/watermark_scale_factor 100

log "VM 优化完成"

# ---- 2. IO（加快启动）----
for d in /sys/block/dm-47 /sys/block/dm-48 /sys/block/dm-49 /sys/block/sda /sys/block/sdc; do
  [ -d "$d/queue" ] || continue
  # 预读 1024K -> 256K：随机读为主时更省内存带宽，冷启动收益更明显
  w "$d/queue/read_ahead_kb" 256
  # rq_affinity 1：完成中断回到提交 CPU，提升缓存命中
  w "$d/queue/rq_affinity" 1
done
log "IO 优化完成"

# ---- 3. 调度响应 ----
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$p/schedutil" ] || continue
  # rate_limit 1000us -> 500us：升降频响应更快，减少"点了没反应"
  w "$p/schedutil/rate_limit_us" 500
done
log "调度优化完成"

# ---- 4. 网络（省电 + 建连更快）----
w /proc/sys/net/ipv4/tcp_fastopen 3
log "网络优化完成"

# ---- 5. 备份原始值（卸载时可还原）----
BK=/data/adb/mituner
mkdir -p "$BK"
if [ ! -f "$BK/orig.conf" ]; then
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
fi

log "=== post-fs-data 完成 ==="
