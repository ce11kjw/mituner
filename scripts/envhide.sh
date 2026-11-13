#!/system/bin/sh
# 环境伪装：隐藏 BL / root 痕迹 / tmp 元数据 + 设备安全检测
# 用法: envhide.sh hide-bl | hide-tmp | check | status
# ⚠️ 能力边界：只处理「属性层 + tmp 元数据层」。
#    Zygisk 注入、magic mount 映射、SELinux policy、TEE 证书链
#    需内核级方案（ZygiskNext/Shamiko/SUSFS/PathMask），脚本无能为力。

D="$(cd "$(dirname "$0")" && pwd)"
LOG="/data/local/tmp/fusion_envhide.log"

RP=""
for p in /data/adb/magisk/resetprop /data/adb/ap/bin/resetprop /data/adb/apatch/resetprop /sbin/resetprop /system/bin/resetprop /system_ext/bin/resetprop /product/bin/resetprop; do
  [ -x "$p" ] && RP="$p" && break
done
[ -z "$RP" ] && command -v resetprop >/dev/null 2>&1 && RP="resetprop"

setprop_ro(){ "$RP" -n "$1" "$2" 2>/dev/null; }
json_s(){ printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g'; }
logdir=$(dirname "$LOG"); [ -d "$logdir" ] || mkdir -p "$logdir" 2>/dev/null
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null; }

PROPS="
ro.boot.verifiedbootstate|green
ro.boot.verifiedbootstate_lock|green
ro.boot.vbmeta.device_state|locked
ro.boot.flash.locked|1
ro.boot.veritymode|enforcing
ro.boot.enable_dm_verity|1
ro.boot.secureboot|1
ro.boot.bootlock|locked
ro.oem_unlock_supported|0
sys.oem_unlock_allowed|0
ro.boot.warranty_bit|0
ro.warranty_bit|0
ro.vendor.boot.warranty_bit|0
ro.vendor.warranty_bit|0
vendor.boot.vbmeta.device_state|locked
ro.secureboot.lockstate|locked
ro.debuggable|0
ro.secure|1
ro.build.type|user
ro.build.tags|release-keys
ro.fmp_config|1
ro.boot.realme_lockstate|locked
ro.boot.hwc|CN
ro.boot.hwcountry|CN
"

hide_bl(){
  if [ -z "$RP" ]; then
    printf '{"ok":false,"error":"未找到 resetprop，无法修改只读属性"}\n'; return 1
  fi
  n=0
  while IFS='|' read -r k v; do
    [ -z "$k" ] && continue
    setprop_ro "$k" "$v"
    n=$((n+1))
  done <<EOF
$PROPS
EOF
  log "hide-bl applied=$n"
  printf '{"ok":true,"applied":%d,"note":"属性层伪装已应用；重启后由 service.sh 自动重跑"}\n' "$n"
}

hide_tmp(){
  [ -d /data/local/tmp ] || { printf '{"ok":false,"error":"/data/local/tmp 不存在"}\n'; return 1; }
  detail=""
  cur_owner=$(stat -c '%U:%G' /data/local/tmp 2>/dev/null)
  [ "$cur_owner" != "shell:shell" ] && chown shell:shell /data/local/tmp 2>/dev/null && detail="${detail}owner:${cur_owner}->shell:shell;"
  cur_mode=$(stat -c '%a' /data/local/tmp 2>/dev/null)
  [ "$cur_mode" != "771" ] && chmod 771 /data/local/tmp 2>/dev/null && detail="${detail}mode:${cur_mode}->771;"
  inode=$(stat -c '%i' /data/local/tmp 2>/dev/null)
  high=false; [ "${inode:-0}" -gt 10000 ] 2>/dev/null && high=true
  log "hide-tmp owner=$cur_owner mode=$cur_mode inode=$inode"
  printf '{"ok":true,"owner":"%s","mode":"%s","inode":"%s","changed":"%s","inode_high":%s}\n' \
    "$(json_s "$cur_owner")" "$(json_s "$cur_mode")" "$(json_s "$inode")" "$(json_s "$detail")" "$high"
}

check_env(){
  bl=$(getprop ro.boot.verifiedbootstate); lk=$(getprop ro.boot.flash.locked)
  vb=$(getprop ro.boot.vbmeta.device_state); se=$(getenforce 2>/dev/null)
  dg=$(getprop ro.debuggable); sc=$(getprop ro.secure); bt=$(getprop ro.build.tags)
  root=0
  for su in /system/bin/su /system/xbin/su /data/adb/magisk /data/adb/ap /data/adb/ksu; do
    [ -e "$su" ] && { root=1; break; }
  done
  # v1.4.1: 只认真实文件（-s 判非空），0 字节 chmod 000 占位不算残留
  frida=0; for f in /data/local/tmp/frida-server /data/local/tmp/frida-server16 /data/local/tmp/re.frida.server /data/local/tmp/frida /data/local/tmp/hluda_server; do [ -s "$f" ] && frida=1; done
  xposed=0; [ -e /system/framework/XposedBridge.jar ] && xposed=1
  emu=0; [ "$(getprop ro.kernel.qemu)" = "1" ] && emu=1
  to=$(stat -c '%U:%G' /data/local/tmp 2>/dev/null); tm=$(stat -c '%a' /data/local/tmp 2>/dev/null)
  ti=$(stat -c '%i' /data/local/tmp 2>/dev/null)
  risky=0
  for p in com.byxiaorun.detector com.Longze.detector.pro2 com.OrangeEnvironment.Detector; do
    pm list packages 2>/dev/null | grep -q "$p" && risky=$((risky+1))
  done
  printf '{"ok":true,"bootloader":"%s","flash_locked":"%s","vbmeta_state":"%s","selinux":"%s",' \
    "$(json_s "$bl")" "$(json_s "$lk")" "$(json_s "$vb")" "$(json_s "$se")"
  printf '"debuggable":"%s","secure":"%s","build_tags":"%s",' "$(json_s "$dg")" "$(json_s "$sc")" "$(json_s "$bt")"
  printf '"root":%s,"frida":%s,"xposed":%s,"emulator":%s,"risky_apps":%d,' "$root" "$frida" "$xposed" "$emu" "$risky"
  printf '"tmp_owner":"%s","tmp_mode":"%s","tmp_inode":"%s"}\n' \
    "$(json_s "$to")" "$(json_s "$tm")" "$(json_s "$ti")"
}

status(){
  pc=$(printf '%s\n' "$PROPS" | grep -c '|')
  printf '{"ok":true,"resetprop":"%s","props":%d,"bl_state":"%s","tmp_owner":"%s","tmp_mode":"%s"}\n' \
    "$(json_s "$RP")" "$pc" "$(json_s "$(getprop ro.boot.verifiedbootstate)")" \
    "$(json_s "$(stat -c '%U:%G' /data/local/tmp 2>/dev/null)")" \
    "$(json_s "$(stat -c '%a' /data/local/tmp 2>/dev/null)")"
}

case "$1" in
  hide-bl)  hide_bl ;;
  hide-tmp) hide_tmp ;;
  check)    check_env ;;
  status)   status ;;
  *) echo '{"ok":false,"error":"usage: envhide.sh hide-bl|hide-tmp|check|status"}' ;;
esac
exit 0
