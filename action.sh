#!/system/bin/sh
# MiTuner - 模块按钮动作：显示当前状态
MODDIR=${0%/*}
BK=/data/adb/mituner

get_fg() { timeout 4 dumpsys window 2>/dev/null | grep mCurrentFocus | head -1 | sed 's/.*u0 \([^\/]*\).*/\1/'; }
w() { [ -e "$1" ] && echo "$2" > "$1" 2>/dev/null; return 0; }

S=$(cat $BK/state 2>/dev/null)
case "$S" in
  GAME|GAME_AUTO) NAME="游戏模式（放开性能）" ;;
  IDLE)           NAME="息屏模式（省电优先）" ;;
  *)              NAME="日常模式（平衡）" ;;
esac

echo "════════ MiTuner 状态 ════════"
echo "模块版本 : $(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)"
echo "当前档位 : $NAME"
echo "前台应用 : $(get_fg)"
echo "屏幕状态 : $(dumpsys power 2>/dev/null | grep -oE 'mWakefulness=[A-Za-z]+' | head -1 | cut -d= -f2)"
echo "GPU 负载 : $(cat /sys/module/ged/parameters/gpu_loading 2>/dev/null | head -1)%"
echo
echo "── 守护进程 ──"
if pgrep -f "mituner/service.sh" >/dev/null 2>&1; then
  echo "状态     : ✓ 运行中 (pid $(pgrep -f 'mituner/service.sh' | head -1))"
else
  echo "状态     : ✗ 未运行"
fi
echo
echo "── 当前参数 ──"
echo "swappiness      : $(cat /proc/sys/vm/swappiness 2>/dev/null)  (原厂 100)"
echo "vfs_cache_press : $(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)  (原厂 100)"
echo "read_ahead_kb   : $(cat /sys/block/dm-47/queue/read_ahead_kb 2>/dev/null) KB  (原厂 1024)"
echo "schedutil.rate  : $(cat /sys/devices/system/cpu/cpufreq/policy7/schedutil/rate_limit_us 2>/dev/null) us  (原厂 1000)"
echo "CPU 下限        : c0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null) c1=$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq 2>/dev/null) c2=$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_min_freq 2>/dev/null)"
echo
echo "── CPU 频率上限（本模块不干预）──"
for i in 0 4 7; do
  echo "  cpu$i : $(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq 2>/dev/null) / $(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq 2>/dev/null)"
done
echo
echo "── 最近日志 ──"
tail -10 /data/local/tmp/mituner.log 2>/dev/null
