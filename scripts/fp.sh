#!/system/bin/sh
# 设备指纹伪装 / 恢复（融合 Fish 的希腊字母混淆法）
# 用法:
#   fp.sh status                查看当前指纹与备份状态(JSON)
#   fp.sh spoof [n]             随机把 n 个拉丁字母换成希腊同形字(默认 n=4)
#   fp.sh spoof-full <值>       直接设置完整 fingerprint
#   fp.sh restore               恢复出厂原始指纹
#   fp.sh ids                   查看/重置 设备标识(serialno/meid 等)
#   fp.sh random-ids            随机化 serialno / meid
D="$(cd "$(dirname "$0")" && pwd)"
BAK="/data/adb/fusion/fp_backup.prop"
mkdir -p /data/adb/fusion

RP=""
for p in /data/adb/magisk/resetprop /data/adb/ap/bin/resetprop /data/adb/apatch/resetprop /sbin/resetprop /system/bin/resetprop /system_ext/bin/resetprop /product/bin/resetprop; do
  [ -x "$p" ] && RP="$p" && break
done
[ -z "$RP" ] && command -v resetprop >/dev/null 2>&1 && RP="resetprop"

setprop_ro(){ # key value
  if [ -n "$RP" ]; then "$RP" "$1" "$2" 2>/dev/null; else setprop "$1" "$2" 2>/dev/null; fi
}

# 拉丁→希腊同形字映射
to_greek(){
  case "$1" in
    a) printf 'α';; b) printf 'β';; c) printf 'κ';; d) printf 'δ';; e) printf 'ε';;
    f) printf 'φ';; g) printf 'γ';; h) printf 'η';; i) printf 'ι';; j) printf 'ι';;
    k) printf 'κ';; l) printf 'λ';; m) printf 'μ';; n) printf 'ν';; o) printf 'ο';;
    p) printf 'π';; q) printf 'κ';; r) printf 'ρ';; s) printf 'σ';; t) printf 'τ';;
    u) printf 'υ';; v) printf 'υ';; w) printf 'ω';; x) printf 'χ';; y) printf 'υ';; z) printf 'ζ';;
    *) printf '%s' "$1";;
  esac
}

json_s(){ printf '%s' "$1" | sed 's/\\/\\\\/g;s/"/\\"/g'; }

# 备份文件读写（统一 key=value 格式）
bak_set(){ # key value
  touch "$BAK"
  if grep -q "^$1=" "$BAK" 2>/dev/null; then
    sed -i "s|^$1=.*|$1=$2|" "$BAK"
  else
    printf '%s=%s\n' "$1" "$2" >> "$BAK"
  fi
}
bak_get(){ grep "^$1=" "$BAK" 2>/dev/null | head -1 | cut -d'=' -f2-; }
bak_has(){ grep -q "^$1=" "$BAK" 2>/dev/null; }

case "$1" in
  status)
    cur=$(getprop ro.build.fingerprint)
    if bak_has fp; then hasbak=true; else hasbak=false; fi
    printf '{"ok":true,"fingerprint":"%s","has_backup":%s,"resetprop":"%s","serial":"%s"}\n' \
      "$(json_s "$cur")" "$hasbak" "$(json_s "$RP")" "$(json_s "$(getprop ro.serialno)")"
    ;;
  spoof)
    n="${2:-4}"
    cur=$(getprop ro.build.fingerprint)
    bak_has fp || bak_set fp "$cur"
    # 用 sed 逐个替换 n 个拉丁字母为希腊同形字（避免多字节问题）
    out="$cur"; cnt=0
    for pair in a:α b:β c:κ d:δ e:ε f:φ g:γ h:η i:ι j:ι k:κ l:λ m:μ n:ν o:ο p:π q:κ r:ρ s:σ t:τ u:υ v:υ w:ω x:χ y:υ z:ζ; do
      [ $cnt -ge "$n" ] && break
      lat=${pair%%:*}; grk=${pair#*:}
      if printf '%s' "$out" | grep -q "$lat"; then
        out=$(printf '%s' "$out" | sed "s/$lat/$grk/")
        cnt=$((cnt+1))
      fi
    done
    setprop_ro ro.build.fingerprint "$out"
    sleep 1
    now=$(getprop ro.build.fingerprint)
    printf '{"ok":true,"old":"%s","new":"%s","applied":%s}\n' \
      "$(json_s "$cur")" "$(json_s "$now")" "$([ "$now" = "$out" ] && echo true || echo false)"
    ;;
  spoof-full)
    bak_has fp || bak_set fp "$(getprop ro.build.fingerprint)"
    setprop_ro ro.build.fingerprint "$2"
    printf '{"ok":true,"new":"%s"}\n' "$(json_s "$2")"
    ;;
  restore)
    if bak_has fp; then
      orig=$(bak_get fp)
      setprop_ro ro.build.fingerprint "$orig"
      # 恢复 serialno/meid（若有备份）
      bak_has serialno && setprop_ro ro.serialno "$(bak_get serialno)"
      bak_has meid && setprop_ro ro.ril.oem.meid "$(bak_get meid)"
      printf '{"ok":true,"restored":"%s"}\n' "$(json_s "$orig")"
    else
      printf '{"ok":false,"error":"无备份可恢复"}\n'
    fi
    ;;
  ids)
    printf '{"serial":"%s","meid":"%s","android_id":"%s"}\n' \
      "$(json_s "$(getprop ro.serialno)")" \
      "$(json_s "$(getprop ro.ril.oem.meid)")" \
      "$(json_s "$(settings get secure android_id 2>/dev/null)")"
    ;;
  random-ids)
    new_serial=$(date +%s%N | md5sum | cut -c1-10)
    new_meid="9900$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
    bak_has serialno || bak_set serialno "$(getprop ro.serialno)"
    bak_has meid || bak_set meid "$(getprop ro.ril.oem.meid)"
    setprop_ro ro.serialno "$new_serial"
    setprop_ro ro.ril.oem.meid "$new_meid"
    printf '{"ok":true,"serial":"%s","meid":"%s"}\n' "$new_serial" "$new_meid"
    ;;
  *)
    echo '{"ok":false,"error":"usage: fp.sh status|spoof [n]|spoof-full <v>|restore|ids|random-ids"}'
    ;;
esac
exit 0
