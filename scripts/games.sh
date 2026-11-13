#!/system/bin/sh
# 游戏缓存清理引擎 —— 数据驱动（games.db）
# 用法:
#   games.sh list                列出游戏+安装状态(JSON)
#   games.sh clean <id> [light]  清理指定游戏(JSON)
#   games.sh cleanall [light]    清理全部已安装游戏
D="$(cd "$(dirname "$0")" && pwd)"
DB="$D/games.db"
LOG="/data/local/tmp/fusion_games.log"
# 深度清理时保留的防重下凭证
KEEP='Manifest_UFSFiles_Android.txt|NotAllowedUnattendedBugReports|Version\.cfg|ClearFlag_|BagSkinCache_|PlayerData\.cfg|PCache\.meta|Manifest\.ini'
logdir=$(dirname "$LOG"); [ -d "$logdir" ] || mkdir -p "$logdir" 2>/dev/null
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG" 2>/dev/null; }
installed(){ pm list packages 2>/dev/null | grep -q "package:$1$"; }

clean_one(){
  gid="$1"; mode="${2:-deep}"
  line=$(awk -F"|" -v g="$gid" '$1==g' "$DB")
  [ -z "$line" ] && { echo "{\"ok\":false,\"error\":\"unknown game\"}"; return 1; }
  name=$(echo "$line" | cut -d'|' -f2)
  pkg=$(echo "$line" | cut -d'|' -f3)
  subs=$(echo "$line" | cut -d'|' -f4- | tr '|' '\n')
  installed "$pkg" || { echo "{\"ok\":false,\"game\":\"$name\",\"error\":\"未安装\"}"; return 1; }
  before=$(du -sk /data/user/*/"$pkg" 2>/dev/null | awk '{s+=$1}END{print s+0}')
  # 内部数据 /data/user/*/<pkg>/<sub>
  for u in /data/user/*/; do
    u="${u%/}"
    printf '%s\n' "$subs" | while IFS= read -r s; do
      [ -z "$s" ] && continue
      case "$s" in *UE4Game*|*Saved*) [ "$mode" = "light" ] && continue;; esac
      [ -e "$u/$pkg/$s" ] && rm -rf "$u/$pkg/$s" 2>/dev/null
    done
  done
  # 外部数据 /storage/emulated/*/Android/{data,media,obb}/<pkg>
  for st in /storage/emulated/*/; do
    for base in Android/data Android/media Android/obb; do
      ext="$st$base/$pkg"; [ -d "$ext" ] || continue
      if [ "$mode" = "light" ]; then
        rm -rf "$ext/cache" "$ext/code_cache" 2>/dev/null
      else
        if [ -d "$ext/files" ]; then
          find "$ext/files" -mindepth 1 -maxdepth 1 2>/dev/null | while read -r f; do
            if ! printf '%s' "$(basename "$f")" | grep -qE "$KEEP"; then rm -rf "$f" 2>/dev/null; fi
          done
        fi
        rm -rf "$ext/cache" "$ext/code_cache" 2>/dev/null
      fi
    done
  done
  after=$(du -sk /data/user/*/"$pkg" 2>/dev/null | awk '{s+=$1}END{print s+0}')
  delta=$(( ${before:-0} - ${after:-0} )); [ $delta -lt 0 ] && delta=0
  log "clean $name mode=$mode freed=${delta}KB"
  printf '{"ok":true,"game":"%s","pkg":"%s","mode":"%s","freed_kb":%d,"time":"%s"}\n' "$name" "$pkg" "$mode" "$delta" "$(date '+%F %T')"
}

case "$1" in
  list)
    # 优化：pm 只调一次 + awk 一次生成（原 48 个子进程 ~1594ms -> ~150ms）
    PMTMP="/data/local/tmp/.games_pm.$$"
    pm list packages 2>/dev/null > "$PMTMP"
    awk -f "$D/games-list.awk" "$PMTMP" "$DB"
    rm -f "$PMTMP"
    ;;
  clean) clean_one "$2" "$3" ;;
  cleanall)
    awk -F"|" '{print $1}' "$DB" | while read -r id; do [ -n "$id" ] && clean_one "$id" "${2:-deep}"; done
    ;;
  *) echo '{"ok":false,"error":"usage: games.sh list|clean <id>|cleanall"}' ;;
esac
exit 0
