#!/system/bin/sh
# 系统垃圾清理 + 作弊驱动残留清理（融合自 Fish [82][84]）
# 用法: sysclean.sh junk | driver
D="$(cd "$(dirname "$0")" && pwd)"
LOG="/data/local/tmp/fusion_sysclean.log"
logdir=$(dirname "$LOG"); [ -d "$logdir" ] || mkdir -p "$logdir" 2>/dev/null
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null; }

junk_clean(){
  for d in /data/cache /cache /data/anr /data/tombstones /data/system/dropbox; do
    [ -d "$d" ] && rm -rf "$d"/* 2>/dev/null
  done
  # /data/local/tmp：只删明确的临时垃圾，绝不碰其他模块的文件
  for pat in '*.tmp' '*.temp' '*.log.old' '*.pid'; do
    find /data/local/tmp -maxdepth 1 -name "$pat" -delete 2>/dev/null
  done
  for dl in /storage/emulated/*/Download; do
    [ -d "$dl" ] || continue
    rm -rf "$dl/.tmp" 2>/dev/null
    find "$dl" -maxdepth 1 -name '*.tmp' -delete 2>/dev/null
    find "$dl" -maxdepth 1 -name '*.temp' -delete 2>/dev/null
  done
  log "junk clean done"
  printf '{"ok":true,"task":"junk","time":"%s"}\n' "$(date '+%F %T')"
}

driver_clean(){
  n=0
  for p in /data/nh /data/nh2 /data/nh3 /data/nh4 /data/nh5 /data/nh.ko /data/jz /data/jz.sh /data/system/liboxmem.so /data/system/liborangeinit.so /data/system/xydriver.ko; do
    [ -e "$p" ] && { rm -rf "$p" 2>/dev/null; n=$((n+1)); }
  done
  for p in /data/BingPUBG/guns.cfg /data/BingHPJY/pz.cfg /dev/Bing /data/单发枪配置.txt /data/local/tmp/单发枪配置.txt /data/A内核.ini /data/物资.txt /data/HPX /data/HPY /data/system/HPX /data/system/HPY "/storage/emulated/0/落叶配置" "/storage/emulated/0/BY物资"; do
    [ -e "$p" ] && { rm -rf "$p" 2>/dev/null; n=$((n+1)); }
  done
  log "driver clean removed=$n"
  printf '{"ok":true,"task":"driver","removed":%d,"time":"%s"}\n' "$n" "$(date '+%F %T')"
}

case "$1" in
  junk) junk_clean ;;
  driver) driver_clean ;;
  *) echo '{"ok":false,"error":"usage: sysclean.sh junk|driver"}' ;;
esac
exit 0
