#!/system/bin/sh
# 隔离式 Linux chroot 启动器 —— 挂载完全隔离，反作弊看不到
# 原理：unshare(CLONE_NEWNS) + MS_PRIVATE 递归，阻止挂载事件传播到 Android 全局
#       （toybox mount 不支持传播类型，故自带 make-private 小工具）
# 用法:
#   chroot.sh status                 检查环境与当前隔离状态(JSON)
#   chroot.sh run <rootfs> [cmd...]  在隔离命名空间中进入 chroot
#   chroot.sh check                  验证挂载是否泄漏(JSON)
D="$(cd "$(dirname "$0")" && pwd)"
MODDIR="$(cd "$D/.." && pwd)"
MKP="$MODDIR/bin/make-private"
LOG="/data/local/tmp/fusion_chroot.log"
logdir=$(dirname "$LOG"); [ -d "$logdir" ] || mkdir -p "$logdir" 2>/dev/null
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null; }
json_s(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

has_ns(){ grep -qE "^CONFIG_MNT_NS=y|^CONFIG_NAMESPACES=y" /proc/config.gz 2>/dev/null; }

# 生成一次完整的"隔离 chroot 启动脚本"，供 unshare 内部执行
build_inner() {
  RIS="$1"; shift
  cat <<INNER
#!/system/bin/sh
# 1) 关键：把 root 设为 private，阻止挂载向外传播
"$MKP" / || { echo '{"ok":false,"error":"make-private failed"}'; exit 1; }
# 2) 挂载虚拟文件系统（只在当前 namespace 可见）
for pair in "/dev:\$R/dev" "/proc:\$R/proc" "/sys:\$R/sys" "/dev/pts:\$R/dev/pts"; do
  src=\${pair%%:*}; dst=\${pair#*:}
  [ -d "\$dst" ] && mount --bind "\$src" "\$dst" 2>/dev/null
done
# /dev/shm
[ -d "\$R/dev/shm" ] && mount -t tmpfs -o size=256M tmpfs "\$R/dev/shm" 2>/dev/null
# /sdcard
[ -d "\$R/sdcard" ] && mount --bind /sdcard "\$R/sdcard" 2>/dev/null
# 3) 进入 chroot
exec chroot "\$R" "\$@"
INNER
}

case "$1" in
  status)
    [ -x "$MKP" ] && mkp_ok=true || mkp_ok=false
    mnt_ns=$(zcat /proc/config.gz 2>/dev/null | grep -c '^CONFIG_NAMESPACES=y')
    pid_ns=$(zcat /proc/config.gz 2>/dev/null | grep -c '^CONFIG_PID_NS=y')
    user_ns=$(zcat /proc/config.gz 2>/dev/null | grep -c '^CONFIG_USER_NS=y')
    printf '{"ok":true,"make_private":%s,"ns_support":{"mnt":%s,"pid":%s,"user":%s},"unshare":"%s","chroot":"%s"}\n' \
      "$mkp_ok" "${mnt_ns:-0}" "${pid_ns:-0}" "${user_ns:-0}" \
      "$(json_s "$(command -v unshare)")" "$(json_s "$(command -v chroot)")"
    ;;
  check)
    n=$(su 2000 -c 'grep -c "/data/local\|/data/adb" /proc/self/mountinfo' 2>/dev/null || echo 0)
    printf '{"ok":true,"leaked_mounts":%s,"verdict":"%s"}\n' "${n:-0}" \
      "$([ "${n:-0}" -eq 0 ] && echo clean || echo leaked)"
    ;;
  run)
    RIS="$2"; shift 2
    [ -z "$RIS" ] && { echo '{"error":"usage: chroot.sh run <rootfs> [cmd]"}' >&2; exit 1; }
    [ -d "$RIS" ] || { echo "{\"error\":\"rootfs not found: $RIS\"}" >&2; exit 1; }
    [ -x "$MKP" ] || { echo '{"error":"make-private missing"}' >&2; exit 1; }
    INNER=$(mktemp "${TMPDIR:-/data/local/tmp}/.chroot.XXXXXX")
    build_inner "$RIS" > "$INNER"
    chmod 700 "$INNER"
    log "run rootfs=$RIS cmd=$*"
    # 关键：unshare -m 在新挂载命名空间中执行
    exec unshare -m env R="$RIS" sh "$INNER" "$@"
    ;;
  *)
    echo '{"ok":false,"error":"usage: chroot.sh status|check|run <rootfs> [cmd...]"}'
    ;;
esac
exit 0
