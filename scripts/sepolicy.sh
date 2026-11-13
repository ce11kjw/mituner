#!/system/bin/sh
# SELinux 策略硬化 —— 清除 app 域对 root 框架类型的大范围放行
# 背景：Duck Detector 等反作弊通过 selinux_check_access 查询
#       untrusted_app -> ksu_file:file read，若返回 Allowed 判定为 root 残留
#
# ⚠️ 关键修正（v1.3.5）：
#   旧版只匹配 `allow appdomain <type>`，但 APatch/KernelSU 实际把规则写在
#   **具体域**（untrusted_app_all / untrusted_app_visible_halserver_violators 等）
#   上，导致旧版永远读到 0 条、误报"已干净"。
#   现版同时匹配 appdomain 与所有 untrusted_app* 域。
#
# 用法:
#   sepolicy.sh scan     检查污染情况(JSON，只读)
#   sepolicy.sh fix      修复（热加载，立即生效）
#   sepolicy.sh restore  从备份还原（需重启或再次 --live）

D="$(cd "$(dirname "$0")" && pwd)"
BD="/data/adb/fusion"
BAK="$BD/backup/policy_orig.bin"
LOG="/data/local/tmp/fusion_sepolicy.log"
logdir=$(dirname "$LOG"); [ -d "$logdir" ] || mkdir -p "$logdir" 2>/dev/null
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null; }
json_s(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

MP=""
for p in /data/adb/ap/bin/magiskpolicy /data/adb/magisk/magiskpolicy /system/bin/magiskpolicy; do
  [ -x "$p" ] && MP="$p" && break
done
[ -z "$MP" ] && MP=$(command -v magiskpolicy 2>/dev/null)

# 需要清理的类型（root 框架专用，普通 app 绝不该访问）
TARGET_TYPES="ksu_file magisk_file"

# 受影响的域：appdomain 宏 + 所有 untrusted_app 系列具体域
# 用正则一次匹配，避免逐个枚举漏网
DOMAIN_RE='^(appdomain|untrusted_app[A-Za-z0-9_]*)'

# 统计某类型被 app 域放行的规则数
count_rules() {
  "$MP" --load /sys/fs/selinux/policy --print-rules 2>/dev/null \
    | grep -E "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) $1 " | wc -l
}

# 列出某类型涉及的所有域（去重）
list_domains() {
  "$MP" --load /sys/fs/selinux/policy --print-rules 2>/dev/null \
    | grep -E "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) $1 " | awk '{print $2}' | sort -u
}

do_scan() {
  [ -z "$MP" ] && { echo '{"ok":false,"error":"未找到 magiskpolicy"}'; return 1; }
  mkdir -p "$BD" 2>/dev/null
  TMP="$BD/.policy_dump.$$"
  "$MP" --load /sys/fs/selinux/policy --print-rules 2>/dev/null > "$TMP"

  # 宽匹配：任何域对 ksu_file/magisk_file 的放行（用于诊断）
  k=$(grep -cE "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) ksu_file " "$TMP" 2>/dev/null)
  m=$(grep -cE "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) magisk_file " "$TMP" 2>/dev/null)
  l=$(grep -cE "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) lsposed_file " "$TMP" 2>/dev/null)
  x=$(grep -cE "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) xposed_data " "$TMP" 2>/dev/null)
  # 专项：file class 的读写（最致命的提权面）
  kf=$(grep -cE "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) ksu_file file " "$TMP" 2>/dev/null)
  # 涉及哪些域
  doms=$(grep -E "^allow untrusted_app[A-Za-z0-9_]* ksu_file " "$TMP" 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' '|')
  rm -f "$TMP"

  printf '{"ok":true,"policy_tool":"%s","ksu_file":%d,"magisk_file":%d,"lsposed_file":%d,"xposed_data":%d,"ksu_file_class":%d,"domains":"%s","dirty":%s}\n' \
    "$(json_s "$MP")" "${k:-0}" "${m:-0}" "${l:-0}" "${x:-0}" "${kf:-0}" "$(json_s "$doms")" \
    "$([ "${k:-0}" -gt 0 ] || [ "${m:-0}" -gt 0 ] && echo true || echo false)"
}

do_fix() {
  [ -z "$MP" ] && { echo '{"ok":false,"error":"未找到 magiskpolicy"}'; return 1; }
  mkdir -p "$BD/backup" 2>/dev/null
  [ -f "$BAK" ] || "$MP" --load /sys/fs/selinux/policy --save "$BAK" 2>/dev/null

  TMP="$BD/.policy_dump.$$"
  "$MP" --load /sys/fs/selinux/policy --print-rules 2>/dev/null > "$TMP"
  if [ ! -s "$TMP" ]; then rm -f "$TMP"; echo '{"ok":false,"error":"导出策略失败"}'; return 1; fi

  # 生成逐 (域, 类型, class) 的 deny 语句
  DENY="$BD/.deny_rules.$$"
  : > "$DENY"
  n=0
  for t in $TARGET_TYPES; do
    for d in $(grep -E "^allow (appdomain|untrusted_app[A-Za-z0-9_]*) $t " "$TMP" 2>/dev/null | awk '{print $2}' | sort -u); do
      for c in $(grep -E "^allow $d $t " "$TMP" 2>/dev/null | awk '{print $4}' | sort -u); do
        echo "deny $d $t $c *" >> "$DENY"
        n=$((n+1))
      done
    done
  done
  rm -f "$TMP"

  if [ "$n" -eq 0 ]; then
    rm -f "$DENY"
    printf '{"ok":true,"applied":0,"note":"无需清理（已干净）"}\n'
    return 0
  fi

  # 分批应用，避免单行过长
  OUT=$("$MP" --live --apply "$DENY" 2>&1)
  rc=$?
  rm -f "$DENY"

  # 验证
  after_k=$(count_rules ksu_file)
  after_m=$(count_rules magisk_file)

  log "fix: deny=$n rc=$rc ksu=$after_k magisk=$after_m"
  if [ $rc -eq 0 ] && [ "${after_k:-1}" -eq 0 ] && [ "${after_m:-1}" -eq 0 ]; then
    printf '{"ok":true,"applied":%d,"ksu_file":0,"magisk_file":0,"note":"已立即生效，重启后需重跑"}\n' "$n"
  else
    printf '{"ok":false,"applied":%d,"ksu_file":%s,"magisk_file":%s,"error":"%s"}\n' \
      "$n" "${after_k:-?}" "${after_m:-?}" "$(json_s "$OUT")"
  fi
}

do_restore() {
  [ -z "$MP" ] && { echo '{"ok":false,"error":"未找到 magiskpolicy"}'; return 1; }
  [ -f "$BAK" ] || { echo '{"ok":false,"error":"无备份可恢复"}'; return 1; }
  "$MP" --live --load "$BAK" 2>/dev/null
  k=$(count_rules ksu_file); m=$(count_rules magisk_file)
  log "restore: ksu=$k magisk=$m"
  printf '{"ok":true,"ksu_file":%s,"magisk_file":%s,"msg":"已恢复原始策略"}\n' "${k:-?}" "${m:-?}"
}

case "$1" in
  scan)    do_scan ;;
  fix)     do_fix ;;
  restore) do_restore ;;
  *) echo '{"ok":false,"error":"usage: sepolicy.sh scan|fix|restore"}' ;;
esac
