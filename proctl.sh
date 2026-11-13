#!/system/bin/sh
# MiTuner - 进程管理
# 用法：proctl.sh top [N] | kill <pid> | killpkg <包名> | detail <pid>
#
# ⚠️ 高风险：加了系统进程黑名单 + uid 校验

BK=/data/adb/mituner

# 绝对不杀
PROTECTED="system_server surfaceflinger zygote zygote64 init kthreadd
com.android.systemui com.android.phone com.android.settings
com.miui.home com.android.launcher3 com.miui.securitycenter
android netd rild vold logd servicemanager com.android.nfc
com.android.bluetooth com.android.se com.android.permissioncontroller
com.android.providers.settings com.android.shell media"

is_protected() {
  local p="$1"
  for x in $PROTECTED; do
    [ "$p" = "$x" ] && return 0
  done
  return 1
}

cmd="$1"

case "$cmd" in

  top)
    N=${2:-15}
    case "$N" in *[!0-9]*) N=15;; esac
    ps -A -o PID,RSS,NAME 2>/dev/null | tail -n +2 | sort -k2 -rn | head -$N | \
      awk '{printf "%s|%.0f|%s\n", $1, $2/1024, $3}'
    ;;

  detail)
    P="$2"
    [ -z "$P" ] && { echo "ERR 缺pid"; exit 1; }
    [ -d "/proc/$P" ] || { echo "ERR 进程不存在"; exit 1; }
    echo "PID=$P"
    echo "NAME=$(tr '\0' ' ' < /proc/$P/cmdline 2>/dev/null | cut -c1-80)"
    grep -E "^(VmRSS|VmSize|Threads)" /proc/$P/status 2>/dev/null | sed 's/:/=/' | tr '\n' '|'
    echo ""
    echo "PPID=$(awk '{print $4}' /proc/$P/stat 2>/dev/null)"
    echo "STATE=$(awk '{print $3}' /proc/$P/stat 2>/dev/null)"
    echo "UID=$(awk '/^Uid:/{print $2}' /proc/$P/status 2>/dev/null)"
    ;;

  kill)
    P="$2"
    [ -z "$P" ] && { echo "ERR 缺pid"; exit 1; }
    case "$P" in *[!0-9]*) echo "ERR pid 必须数字"; exit 1;; esac
    [ -d "/proc/$P" ] || { echo "ERR 进程不存在"; exit 1; }

    # 进程名
    NAME=$(cat /proc/$P/comm 2>/dev/null)
    [ -z "$NAME" ] && NAME=$(tr '\0' ' ' < /proc/$P/cmdline 2>/dev/null | cut -d' ' -f1)

    if is_protected "$NAME"; then
      echo "ERR 受保护进程，拒绝：$NAME"
      exit 1
    fi

    # uid 校验：0=root, 1000=system, 1001=radio 全部拒绝
    UID=$(awk '/^Uid:/{print $2}' /proc/$P/status 2>/dev/null)
    case "$UID" in
      0|1000|1001)
        echo "ERR 系统进程（uid=$UID），拒绝：$NAME"
        exit 1
        ;;
    esac

    kill -15 "$P" 2>/dev/null
    sleep 1
    [ -d "/proc/$P" ] && { kill -9 "$P" 2>/dev/null; sleep 1; }

    if [ -d "/proc/$P" ]; then
      echo "ERR 仍存活（可能需要更强权限）"
    else
      echo "OK KILLED=$P NAME=$NAME"
    fi
    ;;

  killpkg)
    PG="$2"
    [ -z "$PG" ] && { echo "ERR 缺包名"; exit 1; }
    if is_protected "$PG"; then
      echo "ERR 受保护：$PG"
      exit 1
    fi
    # force-stop 比 kill 安全（系统会正常回收）
    am force-stop "$PG" 2>/dev/null
    sleep 1
    LEFT=$(ps -A -o NAME 2>/dev/null | grep -cFx "$PG")
    echo "OK FORCE_STOP=$PG LEFT=$LEFT"
    ;;

  *)
    echo "用法: proctl.sh {top [N]|detail <pid>|kill <pid>|killpkg <包名>}"
    exit 1
    ;;
esac
