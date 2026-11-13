#!/system/bin/sh
# MiTuner - 卸载时还原原始参数

LOG=/data/local/tmp/mituner.log
echo "[$(date '+%m-%d %H:%M:%S')] === uninstall ===" >> "$LOG"

w() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; return 0; }

BK=/data/adb/mituner
if [ -f "$BK/orig.conf" ]; then
  . "$BK/orig.conf"
  w /proc/sys/vm/swappiness          "${O_SWAPPINESS:-100}"
  w /proc/sys/vm/vfs_cache_pressure  "${O_VFS:-100}"
  w /proc/sys/vm/dirty_ratio         "${O_DIRTY:-20}"
  w /proc/sys/vm/dirty_background_ratio "${O_DIRTYBG:-10}"
  w /proc/sys/vm/page-cluster        "${O_PAGECLUSTER:-3}"
  w /proc/sys/vm/watermark_scale_factor "${O_WATERMARK:-60}"
  for d in dm-47 dm-48 dm-49 sda sdc; do
    w /sys/block/$d/queue/read_ahead_kb "${O_RA:-1024}"
    w /sys/block/$d/queue/rq_affinity   "${O_RQAFF:-0}"
  done
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    w $p/schedutil/rate_limit_us "${O_RL:-1000}"
  done
  w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 220000
  w /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq 400000
  w /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq 1200000
  echo "已还原原始参数" >> "$LOG"
fi

# 停守护
for p in $(pgrep -f "mituner/service.sh" 2>/dev/null); do
  kill -9 "$p" 2>/dev/null
done

rm -rf "$BK"
echo "卸载完成" >> "$LOG"
