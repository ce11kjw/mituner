#!/system/bin/sh
# MiTuner - 游戏白名单管理（供 WebUI 调用）
#
# 用法：
#   gamectl.sh list              列出（中文名<TAB>包名）
#   gamectl.sh add <包名> [名字]  添加
#   gamectl.sh del <包名>         删除
#   gamectl.sh check <包名>       检查（1=存在 0=不存在）
#   gamectl.sh count             数量
#   gamectl.sh restore           恢复内置名单
#   gamectl.sh reload            强制重载

BK=/data/adb/mituner
GC=$BK/games.conf
GL=$BK/games.list
MOD=/data/adb/modules/mituner

mkdir -p "$BK"

# ---------- 校验包名 ----------
valid_pkg() {
  case "$1" in *.*) ;; *) return 1 ;; esac
  echo "$1" | grep -qE '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$'
}

# ---------- ★ 核心：重建纯包名列表 ----------
# 关键点：必须只取每行第一段（丢弃备注），否则 "包名<TAB>备注"
#         会被 sed 粘成 "包名备注"，导致 grep -Fx 永远匹配不上
rebuild() {
  [ -f "$GC" ] || return 0
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      pkg = $1
      gsub(/\t/, "", pkg)
      if (pkg != "") print pkg
    }
  ' "$GC" > "$GL" 2>/dev/null
}

notify() {
  rebuild
  date +%s > "$BK/reload_req" 2>/dev/null
}

# ---------- 命令 ----------
cmd="$1"
shift 2>/dev/null

case "$cmd" in

  list)
    [ -f "$GC" ] || exit 0
    awk 'BEGIN{
      split("com.tencent.tmgp.sgame:王者荣耀|com.tencent.tmgp.sgamece:王者荣耀体验服|com.tencent.lolm:英雄联盟手游|com.levelinfinite.sgameGlobal.midaspay:王者荣耀国际版|com.garena.game.kgtw:传说对决|com.tencent.jkchess:金铲铲之战|com.tencent.tmgp.pubgmhd:和平精英|com.tencent.ig:PUBG Mobile|com.rekoo.pubgm:PUBG台服|com.pubg.imobile:PUBG韩服|com.pubg.krmobile:PUBG韩国版|com.pubg.newstate:PUBG NewState|com.tencent.tmgp.cod:使命召唤手游|com.activision.callofduty.warzone:COD Warzone|com.activision.callofduty.shooter:COD射手版|com.tencent.tmgp.dfm:三角洲行动|com.tencent.mf.uam:暗区突围|com.proximabeta.mf.uamo:暗区突围海外|com.tencent.tmgp.cf:穿越火线|com.tencent.tmgp.gnyx:高能英雄|com.proximabeta.nikke:NIKKE|com.epicgames.fortnite:Fortnite|com.dts.freefireth:FreeFire|com.mobile.legends:MobileLegends|com.riotgames.league.wildrift:LOL手游国际|com.tencent.tmgp.dnf:DNF手游|com.tencent.KiHan:火影忍者|com.tencent.naruto:火影国际|com.tencent.tmgp.speedmobile:QQ飞车|com.garena.game.fctw:QQ飞车台服|com.tencent.nfsonline:极品飞车集结|com.tencent.letsgo:元梦之星|com.tencent.tmgp.eyou.eygy:光遇腾讯版|com.tencent.tmgp.wdsj666:我的世界腾讯|com.tencent.tmgp.mhxy.sqsy:梦幻西游三维|com.tencent.tmgp.qqx5:QQ炫舞|com.tencent.game.rhythmmaster:节奏大师|com.tencent.nba2kx:美职篮全明星|com.tencent.tmgp.supercell.clashofclans:部落冲突|com.tencent.tmgp.supercell.brawlstars:荒野乱斗|com.miHoYo.Yuanshen:原神|com.miHoYo.GenshinImpact:原神国际|com.miHoYo.ys.bilibili:原神B服|com.miHoYo.ys.mi:原神米服|com.miHoYo.hkrpg:星穹铁道|com.miHoYo.hkrpg.bilibili:星铁B服|com.HoYoverse.hkrpgoversea:星铁国际|com.miHoYo.Nap:绝区零|com.mihoyo.nap.bilibili:绝区零B服|com.HoYoverse.Nap:绝区零国际|com.miHoYo.bh3:崩坏3|com.miHoYo.bh3.mi:崩坏3米服|com.miHoYo.bh3.bilibili:崩坏3B服|com.miHoYo.enterprise.NGHSoD:崩坏3国际|com.netease.l22:永劫无间|com.netease.l22.mi:永劫无间米服|com.netease.nshm:逆水寒|com.netease.nshm.mi:逆水寒米服|com.netease.nshmhmt:逆水寒国际|com.netease.yyslscn:燕云十六声|com.netease.yyslshmt:燕云台服|com.netease.mrzh:明日之后|com.netease.mrzh.mi:明日之后米服|com.netease.dwrg:第五人格|com.netease.dwrg.mi:第五人格米服|com.netease.hyxd.mi:荒野行动|com.netease.hyxd.nearme.gamecenter:荒野行动渠道|com.netease.hyxd.aligames:荒野行动阿里|com.netease.party:蛋仔派对|com.netease.party.nearme.gamecenter:蛋仔派对渠道|com.netease.sky:光遇|com.netease.sky.mi:光遇米服|com.netease.sky.bilibili:光遇B服|com.tgc.sky.android:光遇国际|com.netease.my:梦幻西游|com.netease.moba:决战平安京|com.netease.race:巅峰极速|com.netease.aceracer:王牌竞速|com.netease.qrsj:七日世界|com.netease.harrypotter:哈利波特|com.netease.allstar:全明星街球|com.kurogame.mingchao:鸣潮|com.kurogame.wutheringwaves.global:鸣潮国际|com.kurogame.haru.hero:战双帕弥什|com.kurogame.haru.mi:战双米服|com.kurogame.haru.aligames:战双阿里|com.hypergryph.arknights:明日方舟|com.hypergryph.arknights.bilibili:明日方舟B服|com.YoStarEN.Arknights:明日方舟国际|com.papegames.nn4:恋与深空|com.papegames.infinitynikki:无限暖暖|com.bluepoch.m.reverse1999:重返未来1999|com.bilibili.azurlane:碧蓝航线|com.pwrd.hotta.laohu:幻塔|com.hottagames.hotta.mi:幻塔米服|com.hottagames.hotta.bilibili:幻塔B服|com.dw.h5yvzr.yt:幻塔渠道|com.hermes.h1game:航海王热血航线|com.hermes.h1game.m4399:航海王4399|com.mojang.minecraftpe:我的世界|com.netease.x19:我的世界网易|com.ea.gp.apexlegendsmobilefps:Apex手游|com.neowizgames.game.browndust2:棕色尘埃2|com.hero.sm.android:创造与魔法|com.hero.sm.bz:创造与魔法bz|com.pi.czrxdfirst:超自然行动组|com.yoka.sgs.x:三国杀一将成名|cn.jj.chess:JJ象棋|cn.jj.chess.mi:JJ象棋米服", p, "|");
      for(i in p){ split(p[i], kv, ":"); m[kv[1]] = kv[2] }
    }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      pkg = $1
      gsub(/\t/, "", pkg)
      if (pkg == "") next
      # 备注：优先 # 之后，其次第一段之后的内容
      remark = ""
      if (index($0, "#") > 0) {
        remark = substr($0, index($0,"#")+1)
      } else {
        tmp = $0
        sub(/^[[:space:]]*[^[:space:]]+/, "", tmp)
        remark = tmp
      }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", remark)
      gsub(/\t/, "", remark)
      if (remark == "" && (pkg in m)) remark = m[pkg]
      printf "%s\t%s\n", remark, pkg
    }' "$GC" 2>/dev/null
    ;;

  add)
    PKG="$1"; NAME="$2"
    if [ -z "$PKG" ]; then echo "ERR 缺少包名"; exit 1; fi
    if ! valid_pkg "$PKG"; then echo "ERR 包名格式不对（应形如 com.example.game）"; exit 1; fi
    rebuild
    if [ -f "$GL" ] && grep -qFx "$PKG" "$GL" 2>/dev/null; then
      echo "EXISTS"; exit 0
    fi
    if [ -n "$NAME" ]; then
      NAME=$(echo "$NAME" | tr -d '\t\n\r' | cut -c1-40)
      printf '%s\t%s\n' "$PKG" "$NAME" >> "$GC"
    else
      echo "$PKG" >> "$GC"
    fi
    notify
    echo "OK"
    ;;

  del)
    PKG="$1"
    if [ -z "$PKG" ]; then echo "ERR 缺少包名"; exit 1; fi
    rebuild
    if ! grep -qFx "$PKG" "$GL" 2>/dev/null; then
      echo "NOTFOUND"; exit 1
    fi
    TMP="$GC.tmp.$$"
    awk -v t="$PKG" '{
      line=$0
      if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) { print; next }
      p = $1
      gsub(/\t/, "", p)
      if (p == t) next
      print
    }' "$GC" > "$TMP" 2>/dev/null && mv -f "$TMP" "$GC"
    notify
    echo "OK"
    ;;

  check)
    PKG="$1"
    [ -z "$PKG" ] && { echo "0"; exit 1; }
    rebuild
    if [ -f "$GL" ] && grep -qFx "$PKG" "$GL" 2>/dev/null; then
      echo "1"; exit 0
    fi
    echo "0"; exit 1
    ;;

  count)
    rebuild
    wc -l < "$GL" 2>/dev/null | tr -d ' '
    ;;

  restore)
    if [ -f "$MOD/games.conf" ]; then
      cp -f "$MOD/games.conf" "$GC"
      notify
      echo "OK"
    else
      echo "ERR 模块内 games.conf 不存在"; exit 1
    fi
    ;;

  running)
    # 列出当前运行中的第三方应用（方案C）
    ps -A -o NAME 2>/dev/null | \
      grep -E '^(com|me|org|io|cn)\.' | \
      grep -v ':' | \
      grep -vE '^(com\.android|com\.miui|com\.mediatek|com\.xiaomi|com\.google\.android)' | \
      sort -u
    ;;

  candidates)
    # 候选应用列表：未在白名单 + 关键词游戏优先排序
    # 输出：优先级<TAB>包名  （0=关键词命中/运行中，1=运行中，2=其他）
    rebuild
    inlist=/tmp/mt_inlist.$$
    cp "$GL" "$inlist" 2>/dev/null
    ps -A -o NAME 2>/dev/null | grep -E '^(com|me|org|io|cn)\.' | grep -v ':' | sort -u > /tmp/mt_run.$$ 2>/dev/null
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u > /tmp/mt_all.$$ 2>/dev/null
    awk '
      FILENAME==ARGV[1] { inl[$0]=1; next }
      FILENAME==ARGV[2] { run[$0]=1; next }
      FILENAME==ARGV[3] {
        pkg=$0
        if (pkg in inl) next
        kw = (pkg ~ /game|tmgp|miHoYo|Hoyo|netease|kurogame|hypergryph|papegames|pubg|sgame|lolm|mihoyo|Yuanshen|hkrpg|Nap|bh3|l22|nshm|yysls|mingchao|haru/) ? 0 : 2
        if (kw == 0 && (pkg in run)) pr = 0
        else if (kw == 0) pr = 1
        else if (pkg in run) pr = 2
        else pr = 3
        printf "%d\t%s\n", pr, pkg
      }' "$inlist" /tmp/mt_run.$$ /tmp/mt_all.$$ | sort -n
    rm -f "$inlist" /tmp/mt_run.$$ /tmp/mt_all.$$
    ;;

  reload)
    notify
    echo "OK"
    ;;

  *)
    echo "用法: gamectl.sh {list|add|del|check|count|restore|reload}"
    exit 1
    ;;
esac
