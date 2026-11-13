#!/system/bin/sh
# MiTuner - 开机自启管理
# 用法：bootctl.sh list | disable <包名> | enable <包名> | disabled
#
# ⚠️ 高风险：禁用系统组件可能导致功能异常
#    只允许操作第三方应用（uid >= 10000）
#    系统应用一律拒绝

BK=/data/adb/mituner
BOOT_BAK=$BK/boot_disabled.txt

# 受保护包（不允许禁用）
PROTECTED="android com.android.systemui com.android.phone com.android.settings
com.android.providers.settings com.android.shell com.android.bluetooth
com.android.nfc com.miui.home com.miui.securitycenter com.android.permissioncontroller"

is_protected() {
  for x in $PROTECTED; do [ "$1" = "$x" ] && return 0; done
  return 1
}

# 判断是否第三方应用（用 pm dump 查 uid）
is_third_party() {
  local p=$1
  local uid=$(dumpsys package "$p" 2>/dev/null | grep -m1 -oE 'userId=[0-9]+' | cut -d= -f2)
  [ -z "$uid" ] && return 1
  [ "$uid" -ge 10000 ] 2>/dev/null && return 0
  return 1
}

cmd="$1"

case "$cmd" in

  list)
    # 列有 BOOT_COMPLETED 接收器的第三方应用
    # 用 pm dump 逐个查太慢，改用 aapt/包信息批量
    for p in $(pm list packages -3 2>/dev/null | sed 's/package://'); do
      # 快速判断：查 dumpsys package 里是否有 BOOT_COMPLETED
      if dumpsys package "$p" 2>/dev/null | grep -q "android.intent.action.BOOT_COMPLETED"; then
        local dis=$(pm list packages -d 2>/dev/null | grep -cFx "package:$p")
        echo "$p|$dis"
      fi
    done
    ;;

  disabled)
    # 列出被 MiTuner 禁用的
    cat "$BOOT_BAK" 2>/dev/null
    ;;

  disable)
    P="$2"
    [ -z "$P" ] && { echo "ERR 缺包名"; exit 1; }
    if is_protected "$P"; then echo "ERR 受保护包，拒绝：$P"; exit 1; fi
    if ! is_third_party "$P"; then echo "ERR 非第三方应用（或查不到 uid），拒绝：$P"; exit 1; fi

    # 记录到备份
    touch "$BOOT_BAK"
    grep -qFx "$P" "$BOOT_BAK" 2>/dev/null || echo "$P" >> "$BOOT_BAK"

    # 禁用（用 pm disable-user，比 pm disable 温和，用户可恢复）
    OUT=$(pm disable-user --user 0 "$P" 2>&1)
    case "$OUT" in
      *"new state: disabled"*) echo "OK DISABLED=$P" ;;
      *Error*|*Exception*) echo "ERR $OUT" ;;
      *) echo "WARN $OUT" ;;
    esac
    ;;

  enable)
    P="$2"
    [ -z "$P" ] && { echo "ERR 缺包名"; exit 1; }
    OUT=$(pm enable --user 0 "$P" 2>&1)
    case "$OUT" in
      *"new state: enabled"*) 
        grep -vxF "$P" "$BOOT_BAK" > "$BOOT_BAK.t" 2>/dev/null && mv "$BOOT_BAK.t" "$BOOT_BAK"
        echo "OK ENABLED=$P"
        ;;
      *) echo "WARN $OUT" ;;
    esac
    ;;

  restore)
    # 恢复所有被禁用的
    n=0
    if [ -f "$BOOT_BAK" ]; then
      while read -r p; do
        [ -z "$p" ] && continue
        pm enable --user 0 "$p" >/dev/null 2>&1 && n=$((n+1))
      done < "$BOOT_BAK"
      : > "$BOOT_BAK"
    fi
    echo "OK RESTORED=$n"
    ;;

  *)
    echo "用法: bootctl.sh {list|disabled|disable <包名>|enable <包名>|restore}"
    exit 1
    ;;
esac
