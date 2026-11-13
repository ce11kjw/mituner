#!/system/bin/sh
# 设备伪装 + 检测对抗 统一入口
# 用法: device.sh status|reset-mac|reset-sn|hide-env|check
# 策略：安装/开机【绝不生成】任何随机值；只有用户显式点按钮才生成
# 设备标识本体由 ALING_MAC / ALING_Serialno 提供（外部模块，不重复实现）

MOD_DIR="/data/adb/modules/webui_info"
ALING_MAC="/data/adb/modules/ALING_MAC"
ALING_SN="/data/adb/modules/ALING_Serialno"
ALING_SE="/data/adb/modules/SELinux-LING"

json_s(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g'; }

mod_state(){ # id -> enabled|disabled|removing|missing
  [ -d "/data/adb/modules/$1" ] || { printf 'missing'; return; }
  [ -f "/data/adb/modules/$1/disable" ] && { printf 'disabled'; return; }
  [ -f "/data/adb/modules/$1/remove" ] && { printf 'removing'; return; }
  printf 'enabled'
}

# ---- 只读：状态 ----
do_status(){
  # 优化：getprop 全量写文件 + 一次提取（原 9 次串行 getprop ~155ms -> ~62ms）
  PT="/data/local/tmp/.iv_props.$$"
  getprop > "$PT" 2>/dev/null
  getp(){ awk -v k="$1" -F"[][]" '$2==k{print $4; exit}' "$PT" 2>/dev/null; }
  sn=$(getp 'ro.serialno')
  fp=$(getp 'ro.build.fingerprint')
  model=$(getp 'ro.product.model')
  brand=$(getp 'ro.product.brand')
  mk=$(getp 'ro.product.marketname')
  dev=$(getp 'ro.product.device')
  bl=$(getp 'ro.boot.verifiedbootstate')
  lk=$(getp 'ro.boot.flash.locked')
  vb=$(getp 'ro.boot.vbmeta.device_state')
  rm -f "$PT"
  se=$(getenforce 2>/dev/null)
  mac=$(cat /sys/class/net/wlan0/address 2>/dev/null)
  [ -z "$mac" ] && mac=$(cat /sys/class/net/eth0/address 2>/dev/null)
  fmac=$(head -1 "$ALING_MAC/MAC/TG频道@Whitelist520" 2>/dev/null)
  fsn=$(head -1 "$ALING_SN/Serialno/TG频道@Whitelist520" 2>/dev/null)
  aid=$(settings get secure android_id 2>/dev/null)
  printf '{"ok":true,"serial":"%s","mac":"%s","fingerprint":"%s","android_id":"%s",' \
    "$(json_s "$sn")" "$(json_s "$mac")" "$(json_s "$fp")" "$(json_s "$aid")"
  printf '"model":"%s","brand":"%s","marketname":"%s","device":"%s",' \
    "$(json_s "$model")" "$(json_s "$brand")" "$(json_s "$mk")" "$(json_s "$dev")"
  printf '"selinux":"%s","bootloader":"%s","flash_locked":"%s","vbmeta":"%s",' \
    "$(json_s "$se")" "$(json_s "$bl")" "$(json_s "$lk")" "$(json_s "$vb")"
  printf '"aling_mac":"%s","aling_sn":"%s","aling_selinux":"%s",' \
    "$(mod_state ALING_MAC)" "$(mod_state ALING_Serialno)" "$(mod_state SELinux-LING)"
  printf '"file_mac":"%s","file_sn":"%s","mac_match":%s,"sn_match":%s}\n' \
    "$(json_s "$fmac")" "$(json_s "$fsn")" \
    "$([ "$fmac" = "$mac" ] && echo true || echo false)" \
    "$([ "$fsn" = "$sn" ] && echo true || echo false)"
}

# ---- 用户操作：换 MAC（唯一会生成 MAC 的地方）----
do_reset_mac(){
  st=$(mod_state ALING_MAC)
  [ "$st" != "enabled" ] && { printf '{"ok":false,"error":"ALING_MAC 未安装或未启用(%s)"}\n' "$st"; return 1; }
  F="$ALING_MAC/MAC/TG频道@Whitelist520"
  B="$ALING_MAC/MAC/MAC.sh"
  [ -x "$B" ] || chmod 777 "$B" 2>/dev/null
  old=$(head -1 "$F" 2>/dev/null)
  # 合法单播 MAC：首字节取偶数且 >=0x02（清多播/本地管理位，避开 00/01 前缀）
  NM=$(printf '%02X:%02X:%02X:%02X:%02X:%02X' \
    $(( (RANDOM % 127) * 2 + 2 )) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
  # 保持 ALING 原有 3 行格式，不破坏其水印注释
  printf '%s\n#你为什么要来看这里？\n#如果你是小偷，偷东西死全家🤗\n' "$NM" > "$F" 2>/dev/null
  chmod 644 "$F" 2>/dev/null
  "$B" >/dev/null 2>&1
  # MAC.sh 内部要 stop/start wifi，实测 20-30s，轮询等待真正生效
  i=0; cur=""
  while [ $i -lt 40 ]; do
    sleep 1
    cur=$(cat /sys/class/net/wlan0/address 2>/dev/null)
    [ "$cur" = "$NM" ] && break
    i=$((i+1))
  done
  applied=false
  [ "$cur" = "$NM" ] && applied=true
  printf '{"ok":true,"old":"%s","generated":"%s","wlan0":"%s","applied":%s,"waited":%ss}\n' \
    "$(json_s "$old")" "$(json_s "$NM")" "$(json_s "$cur")" "$applied" "$i"
}

# ---- 用户操作：换 Serialno（唯一会生成 SN 的地方）----
do_reset_sn(){
  st=$(mod_state ALING_Serialno)
  [ "$st" != "enabled" ] && { printf '{"ok":false,"error":"ALING_Serialno 未安装或未启用(%s)"}\n' "$st"; return 1; }
  F="$ALING_SN/Serialno/TG频道@Whitelist520"
  B="$ALING_SN/Serialno/Serialno.sh"
  [ -x "$B" ] || chmod 777 "$B" 2>/dev/null
  old=$(getprop ro.serialno)
  NS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 15)
  printf '%s\n#你为什么要来看这里？\n#如果你是小偷，偷东西死全家🤗\n' "$NS" > "$F" 2>/dev/null
  chmod 644 "$F" 2>/dev/null
  "$B" >/dev/null 2>&1
  i=0; cur=""
  while [ $i -lt 15 ]; do
    sleep 1
    cur=$(getprop ro.serialno)
    [ "$cur" = "$NS" ] && break
    i=$((i+1))
  done
  applied=false
  [ "$cur" = "$NS" ] && applied=true
  printf '{"ok":true,"old":"%s","generated":"%s","now":"%s","applied":%s,"waited":%ss}\n' \
    "$(json_s "$old")" "$(json_s "$NS")" "$(json_s "$cur")" "$applied" "$i"
}

# ---- 用户操作：tmp 元数据整理（不生成设备标识）----
# ---- 只读+补齐：把 Serialno 全属性同步（不生成新值，只复用 ALING 文件里的值）----
# 背景：ALING_Serialno 只改 ro.serialno 和 ro.boot.chipecid，
#       漏了 ro.boot.serialno / ro.vendor.oem.serialno（仍是出厂真值），会被检测工具抓到。
do_sn_full(){
  F="$ALING_SN/Serialno/TG频道@Whitelist520"
  [ -f "$F" ] || { printf '{"ok":false,"error":"ALING_Serialno 未安装"}\n'; return 1; }
  V=$(head -1 "$F" 2>/dev/null)
  [ -z "$V" ] && { printf '{"ok":false,"error":"目标值为空"}\n'; return 1; }
  RP=""
  for p in /data/adb/ap/bin/resetprop /data/adb/magisk/resetprop /system/bin/resetprop; do
    [ -x "$p" ] && { RP="$p"; break; }
  done
  command -v resetprop >/dev/null 2>&1 && [ -z "$RP" ] && RP=resetprop
  [ -z "$RP" ] && { printf '{"ok":false,"error":"未找到 resetprop"}\n'; return 1; }
  before=$(getprop ro.boot.serialno)
  n=0
  for k in ro.serialno ro.boot.chipecid ro.boot.serialno ro.vendor.oem.serialno; do
    "$RP" "$k" "$V" 2>/dev/null && n=$((n+1))
  done
  printf '{"ok":true,"value":"%s","applied":%d,"before_boot_serialno":"%s","now_boot_serialno":"%s"}\n' \
    "$(json_s "$V")" "$n" "$(json_s "$before")" "$(json_s "$(getprop ro.boot.serialno)")"
}

do_hide_env(){
  # BL 属性伪装已移除（与 TEE attestation 矛盾，反而暴露）
  printf '\n'
  sh "$MOD_DIR/scripts/envhide.sh" hide-tmp 2>/dev/null
}

# ---- 只读：检测对抗总览 ----
do_check(){
  se=$(getenforce 2>/dev/null)
  bl=$(getprop ro.boot.verifiedbootstate)
  lk=$(getprop ro.boot.flash.locked)
  root=0
  for s in /data/adb/ap /data/adb/ksu /data/adb/magisk; do [ -e "$s" ] && { root=1; break; }; done
  # v1.4.1 修 su 假阳性：原实现用 root shell 判 -x /system/bin/su，root 永远能看到
  #   （APatch 的 /data/adb/ap/su_path 就指着它）=> 恒报 visible。改以普通 app 视角实测。
  suv="unknown"
  _su_uid=10500
  if [ -x /system/bin/su ] || [ -x /system/xbin/su ]; then
    if su $_su_uid sh -c "ls /system/bin/su" >/dev/null 2>&1 || su $_su_uid sh -c "ls /system/xbin/su" >/dev/null 2>&1; then suv="visible"; else suv="hidden"; fi
  else
    suv="hidden"
  fi
  # v1.4.1 修 frida 假阳性：只认真实文件（-s 非空），0 字节 chmod 000 占位不算残留
  fr=0; for f in /data/local/tmp/frida-server /data/local/tmp/frida-server16 /data/local/tmp/re.frida.server /data/local/tmp/frida /data/local/tmp/hluda_server; do [ -s "$f" ] && fr=1; done
  to=$(stat -c '%U:%G' /data/local/tmp 2>/dev/null)
  tm=$(stat -c '%a' /data/local/tmp 2>/dev/null)
  ti=$(stat -c '%i' /data/local/tmp 2>/dev/null)
  leaks=$(grep -cE 'magisk|KSU|APatch|overlay.*adb/modules' /proc/self/mountinfo 2>/dev/null)
  mp=""
  for p in /data/adb/ap/bin/magiskpolicy /data/adb/magisk/magiskpolicy /system/bin/magiskpolicy; do
    [ -x "$p" ] && { mp="$p"; break; }
  done
  # 优化：30 秒缓存 + 正确的目标域（untrusted_app* 而非 appdomain）
  kfile=-1
  KCACHE="/data/local/tmp/.iv_sepolicy_cache"
  if [ -f "$KCACHE" ]; then
    kage=$(( $(date +%s) - $(stat -c %Y "$KCACHE" 2>/dev/null || echo 0) ))
    [ "$kage" -lt 30 ] && kfile=$(cat "$KCACHE" 2>/dev/null)
  fi
  if [ "$kfile" = "-1" ] && [ -n "$mp" ]; then
    kfile=$("$mp" --load /sys/fs/selinux/policy --print-rules 2>/dev/null | grep -cE '^allow (appdomain|untrusted_app[A-Za-z0-9_]*) ksu_file ')
    printf '%s' "$kfile" > "$KCACHE" 2>/dev/null
  fi
  printf '{"ok":true,"selinux":"%s","bootloader":"%s","flash_locked":"%s","root":"%s","su":"%s","frida":%s,' \
    "$(json_s "$se")" "$(json_s "$bl")" "$(json_s "$lk")" "$([ $root -eq 1 ] && echo true || echo false)" \
    "$(json_s "$suv")" "$fr"
  printf '"tmp_owner":"%s","tmp_mode":"%s","tmp_inode":"%s","mount_leaks":%s,"ksu_file_allow":%s,' \
    "$(json_s "$to")" "$(json_s "$tm")" "$(json_s "$ti")" "${leaks:-0}" "$kfile"
  printf '"mods":['
  MTMP="/data/local/tmp/.iv_mods.$$"
  : > "$MTMP"
  for m in ALING_MAC ALING_Serialno SELinux-LING Shamiko_Service YH_YC zygisk_lsposed zygisksu hma_oss_zygisk playintegrityfix tricky_store ts_enhancer_extreme SoterFix auditpatch lib_tombstone; do
    f="/data/adb/modules/$m/module.prop"
    [ -f "$f" ] || continue
    st="enabled"
    [ -f "/data/adb/modules/$m/disable" ] && st="disabled"
    [ -f "/data/adb/modules/$m/remove" ] && st="removing"
    printf '%s\t%s\t%s\n' "$m" "$f" "$st" >> "$MTMP"
  done
  awk -F'\t' '
    BEGIN { first = 1 }
    {
      id=$1; f=$2; st=$3; nm="";
      while ((getline line < f) > 0) {
        if (line ~ /^name=/) { sub(/^name=/,"",line); nm=line; break }
      }
      close(f)
      if (nm=="") next
      gsub(/"/, "", nm)
      if (!first) printf ","
      first = 0
      printf "{\"id\":\"%s\",\"name\":\"%s\",\"state\":\"%s\"}", id, nm, st
    }
  ' "$MTMP"
  rm -f "$MTMP"
  printf ']}\n'
}

case "$1" in
  status)    do_status ;;
  reset-mac) do_reset_mac ;;
  reset-sn)  do_reset_sn ;;
  hide-env)  do_hide_env ;;
  sn-full)   do_sn_full ;;
  check)     do_check ;;
  *) echo "{\"ok\":false,\"error\":\"usage: device.sh status|reset-mac|reset-sn|hide-env|sn-full|check\"}" ;;
esac
exit 0
