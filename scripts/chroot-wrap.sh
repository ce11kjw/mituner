#!/system/bin/sh
# 通用 chroot 隔离包装器 —— 不改被包装程序的任何源码
#
# 原理：Android 的 / 是 shared 传播类型。任何在当前 namespace 里的 mount
#       都会传播到 Android 全局，被反作弊（读 /proc/self/mountinfo）看到。
#       本包装器先把 / 设为 private（阻断传播），再 exec 原程序 ——
#       原程序的所有 mount 就都关在私有命名空间内，外部完全不可见。
#
# 用法:
#   chroot-wrap.sh run <原程序路径> [参数...]     用隔离方式执行
#   chroot-wrap.sh install <目标路径> [备份名]     给某个程序套上垫片
#   chroot-wrap.sh uninstall <目标路径>           移除垫片
#   chroot-wrap.sh list                           列出已安装垫片
D="$(cd "$(dirname "$0")" && pwd)"
MODDIR="$(cd "$D/.." && pwd)"
MKP="$MODDIR/bin/make-private"
REG="/data/adb/fusion/wrapped.list"
mkdir -p /data/adb/fusion

case "$1" in
  run)
    shift
    TARGET="$1"; shift
    [ -x "$TARGET" ] || { echo "chroot-wrap: not executable: $TARGET" >&2; exit 127; }
    [ -x "$MKP" ] || { echo "chroot-wrap: make-private missing" >&2; exit 127; }
    # 关键：unshare -m 建私有挂载命名空间 → make-private 阻断传播 → exec 原程序
    exec unshare -m sh -c '
      "$0" / || exit 1
      exec "$@"
    ' "$MKP" "$TARGET" "$@"
    ;;
  install)
    TARGET="$2"; BAKSUF="${3:-.fusion-orig}"
    [ -f "$TARGET" ] || { echo "{\"ok\":false,\"error\":\"not found: $TARGET\"}"; exit 1; }
    BAK="${TARGET}${BAKSUF}"
    if [ -f "$BAK" ]; then
      echo "{\"ok\":false,\"error\":\"already wrapped (backup exists)\",\"backup\":\"$BAK\"}"
      exit 1
    fi
    # 1) 原文件改名备份
    mv -f "$TARGET" "$BAK" || { echo '{"ok":false,"error":"backup failed"}'; exit 1; }
    # 2) 写垫片（指向备份）
    cat > "$TARGET" <<WRAP
#!/system/bin/sh
# [InkVault chroot-wrap] 隔离垫片 —— 原程序: $BAK
exec "$D/chroot-wrap.sh" run "$BAK" "\$@"
WRAP
    chmod 0755 "$TARGET" || { mv -f "$BAK" "$TARGET"; echo '{"ok":false,"error":"chmod failed"}'; exit 1; }
    # 3) 记录
    grep -qxF "$TARGET|$BAK" "$REG" 2>/dev/null || echo "$TARGET|$BAK" >> "$REG"
    # 4) 恢复 SELinux 上下文（systemless 挂载点可能是 system_file）
    ctx=$(ls -Z "$BAK" 2>/dev/null | awk '{print $1}')
    case "$ctx" in
      u:object_r:*) chcon "$ctx" "$TARGET" 2>/dev/null || true ;;
    esac
    echo "{\"ok\":true,\"target\":\"$TARGET\",\"backup\":\"$BAK\",\"context\":\"${ctx:-unknown}\"}"
    ;;
  uninstall)
    TARGET="$2"
    [ -n "$TARGET" ] || { echo '{"ok":false,"error":"missing target"}'; exit 1; }
    BAK=$(grep "^${TARGET}|" "$REG" 2>/dev/null | head -1 | cut -d'|' -f2)
    if [ -z "$BAK" ] || [ ! -f "$BAK" ]; then
      echo "{\"ok\":false,\"error\":\"not wrapped or backup missing\"}"
      exit 1
    fi
    rm -f "$TARGET"
    mv -f "$BAK" "$TARGET"
    grep -v "^${TARGET}|" "$REG" > "${REG}.tmp" 2>/dev/null && mv -f "${REG}.tmp" "$REG"
    echo "{\"ok\":true,\"restored\":\"$TARGET\"}"
    ;;
  list)
    if [ -f "$REG" ]; then
      printf '{"ok":true,"wrapped":['
      first=1
      while IFS='|' read -r t b; do
        [ -z "$t" ] && continue
        [ $first -eq 1 ] || printf ','
        first=0
        printf '{"target":"%s","backup":"%s","backup_exists":%s}' "$t" "$b" \
          "$([ -f "$b" ] && echo true || echo false)"
      done < "$REG"
      printf ']}\n'
    else
      echo '{"ok":true,"wrapped":[]}'
    fi
    ;;
  *)
    echo '{"ok":false,"error":"usage: chroot-wrap.sh run <prog> [args] | install <path> [suffix] | uninstall <path> | list"}'
    ;;
esac
exit 0
