#!/system/bin/sh
# JSON 字符串转义：反斜杠、双引号、控制字符
json_s() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g'
}
ANDROID=$(getprop ro.build.version.release)
SDK=$(getprop ro.build.version.sdk)
KERNEL=$(uname -r)
DEVICE=$(getprop ro.product.model)
BRAND=$(getprop ro.product.brand)
MANUFACTURER=$(getprop ro.product.manufacturer)
BUILD_ID=$(getprop ro.build.id)
BUILD_DATE=$(getprop ro.build.date)
CPU_ABI=$(getprop ro.product.cpu.abi)
BOARD=$(getprop ro.product.board)
HARDWARE=$(getprop ro.hardware)
SECURITY=$(getprop ro.build.version.security_patch)
FINGERPRINT=$(getprop ro.build.fingerprint)
BOOTLOADER=$(getprop ro.bootloader)
SELINUX=$(getenforce 2>/dev/null || echo "Unknown")
KSU_VER=$(getprop ro.kernelsu.version 2>/dev/null)
[ -z "$KSU_VER" ] && KSU_VER=$(magisk -v 2>/dev/null || echo "Unknown")
SCREEN=$(wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1)
DENSITY=$(wm density 2>/dev/null | grep -oE '[0-9]+' | head -1)
BATTERY=$(dumpsys battery 2>/dev/null | awk '/level:/{gsub(/[^0-9]/,"",$2); print $2; exit}'); BATTERY=${BATTERY:-0}
UPTIME=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null); UPTIME=${UPTIME:-0}
RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null); RAM_KB=${RAM_KB:-0}
RAM_MB=$(( RAM_KB / 1024 ))
TIMEZONE=$(getprop persist.sys.timezone)
LANG=$(getprop persist.sys.locale)

printf '{"android":"%s","sdk":"%s","kernel":"%s","device":"%s","brand":"%s","manufacturer":"%s","build_id":"%s","build_date":"%s","cpu_abi":"%s","board":"%s","hardware":"%s","security_patch":"%s","fingerprint":"%s","bootloader":"%s","selinux":"%s","magisk":"%s","screen":"%s","density":"%s","battery":"%s","uptime":%s,"ram_mb":%s,"timezone":"%s","lang":"%s"}' \
    "$(json_s "$ANDROID")" "$(json_s "$SDK")" "$(json_s "$KERNEL")" "$(json_s "$DEVICE")" \
    "$(json_s "$BRAND")" "$(json_s "$MANUFACTURER")" "$(json_s "$BUILD_ID")" "$(json_s "$BUILD_DATE")" \
    "$(json_s "$CPU_ABI")" "$(json_s "$BOARD")" "$(json_s "$HARDWARE")" "$(json_s "$SECURITY")" \
    "$(json_s "$FINGERPRINT")" "$(json_s "$BOOTLOADER")" "$(json_s "$SELINUX")" "$(json_s "$KSU_VER")" \
    "$(json_s "$SCREEN")" "$(json_s "$DENSITY")" "${BATTERY:-0}" "${UPTIME:-0}" "${RAM_MB:-0}" \
    "$(json_s "$TIMEZONE")" "$(json_s "$LANG")"
