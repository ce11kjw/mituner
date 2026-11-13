#!/system/bin/sh
# 机型伪装脚本
# 作者: 呆呆 | QQ:891354018 | 群:774886621
# 用法:
#   sh spoof.sh list               列出所有预设（含恢复选项）
#   sh spoof.sh current            查询当前伪装状态（含原机型）
#   sh spoof.sh apply <id>         应用伪装（id=__restore__ 表示恢复）
#   sh spoof.sh status             简化状态（旧版兼容）
#   sh spoof.sh boot_apply         开机时调用

MOD_DIR="/data/adb/modules/webui_info"
SETTINGS_FILE="$MOD_DIR/settings.conf"
PROP_FILE="$MOD_DIR/system.prop"
ACTION="$1"
MODEL_ID="$2"

read_setting() {
    local key="$1"
    [ -f "$SETTINGS_FILE" ] && grep -E "^${key}=" "$SETTINGS_FILE" | head -1 | cut -d'=' -f2-
}

write_setting() {
    local key="$1"
    local val="$2"
    [ ! -f "$SETTINGS_FILE" ] && touch "$SETTINGS_FILE"
    if grep -q "^${key}=" "$SETTINGS_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$SETTINGS_FILE"
    else
        echo "${key}=${val}" >> "$SETTINGS_FILE"
    fi
}

backup_orig_once() {
    if [ -z "$(read_setting 'orig_model')" ]; then
        write_setting "orig_model" "$(getprop ro.product.model)"
        write_setting "orig_brand" "$(getprop ro.product.brand)"
        write_setting "orig_manufacturer" "$(getprop ro.product.manufacturer)"
        write_setting "orig_device" "$(getprop ro.product.device)"
        write_setting "orig_name" "$(getprop ro.product.name)"
        write_setting "orig_marketname" "$(getprop ro.product.marketname)"
    fi
}

# ============ 预设清单（id|分类|名称|品牌|型号）============
PRESETS="oneplus_ace6_extreme|一加 Ace 系列|一加 Ace 6 至尊版|OnePlus|PKW110
oneplus_ace6t|一加 Ace 系列|一加 Ace 6T|OnePlus|PKE110
oneplus_ace6|一加 Ace 系列|一加 Ace 6|OnePlus|PKD110
oneplus_ace5_extreme|一加 Ace 系列|一加 Ace 5 至尊版|OnePlus|PKB110
iqoo15_ultra|iQOO 数字旗舰|iQOO 15 Ultra|iQOO|V2456A
iqoo15|iQOO 数字旗舰|iQOO 15|iQOO|V2455A
iqoo13|iQOO 数字旗舰|iQOO 13|iQOO|V2401A
iqoo_neo11|iQOO Neo 系列|iQOO Neo11|iQOO|V2440A
iqoo_neo10_pro_plus|iQOO Neo 系列|iQOO Neo10 Pro+|iQOO|V2435A
iqoo_neo10|iQOO Neo 系列|iQOO Neo10|iQOO|V2422A
iqoo_z11|iQOO Z 系列|iQOO Z11|iQOO|V2445A
iqoo_z11x|iQOO Z 系列|iQOO Z11x|iQOO|V2446A
iqoo_z11_turbo|iQOO Z 系列|iQOO Z11 Turbo|iQOO|V2447A
redmagic_11s_pro_plus|红魔手机|红魔 11S Pro+|Nubia|NX799S
redmagic_11_air|红魔手机|红魔 11 Air|Nubia|NX780A
redmagic_10s_pro_plus|红魔手机|红魔 10S Pro+|Nubia|NX789S
redmagic_10_pro|红魔手机|红魔 10 Pro|Nubia|NX789J
redmagic_tab5_pro|红魔平板|红魔游戏平板5 Pro|Nubia|NX736J
legion_y700_5|联想拯救者平板|拯救者 Y700 五代|Lenovo|TB-321FU
rog_8_pro|其他旗舰|ROG 8 Pro|asus|AI2401
xiaomi_14_ultra|其他旗舰|小米 14 Ultra|Xiaomi|24030PN60C"

# 写入指定机型的 prop 配置
write_prop() {
    local id="$1"
    # 先校验 id 是否存在，避免未知 id 时先把 system.prop 清空
    case "$id" in
        oneplus_ace6_extreme|oneplus_ace6t|oneplus_ace6|oneplus_ace5_extreme|iqoo15_ultra|iqoo15|iqoo13|iqoo_neo11|iqoo_neo10_pro_plus|iqoo_neo10|iqoo_z11|iqoo_z11x|iqoo_z11_turbo|redmagic_11s_pro_plus|redmagic_11_air|redmagic_10s_pro_plus|redmagic_10_pro|redmagic_tab5_pro|legion_y700_5|rog_8_pro|xiaomi_14_ultra) ;;
        *) return 1 ;;
    esac
    # 写临时文件再原子替换，避免中途失败留下空文件
    local TMP="${PROP_FILE}.tmp.$$"

    case "$id" in
        oneplus_ace6_extreme)
            cat > "$TMP" <<'EOF'
ro.product.model=PKW110
ro.product.brand=OnePlus
ro.product.manufacturer=OnePlus
ro.product.device=OP5FA9L1
ro.product.name=OnePlus Ace 6 Pro
ro.product.marketname=一加 Ace 6 至尊版
EOF
            LABEL="一加 Ace 6 至尊版"; BRAND="OnePlus"; MODEL="PKW110" ;;
        oneplus_ace6t)
            cat > "$TMP" <<'EOF'
ro.product.model=PKE110
ro.product.brand=OnePlus
ro.product.manufacturer=OnePlus
ro.product.device=OP5F92L1
ro.product.name=OnePlus Ace 6T
ro.product.marketname=一加 Ace 6T
EOF
            LABEL="一加 Ace 6T"; BRAND="OnePlus"; MODEL="PKE110" ;;
        oneplus_ace6)
            cat > "$TMP" <<'EOF'
ro.product.model=PKD110
ro.product.brand=OnePlus
ro.product.manufacturer=OnePlus
ro.product.device=OP5F89L1
ro.product.name=OnePlus Ace 6
ro.product.marketname=一加 Ace 6
EOF
            LABEL="一加 Ace 6"; BRAND="OnePlus"; MODEL="PKD110" ;;
        oneplus_ace5_extreme)
            cat > "$TMP" <<'EOF'
ro.product.model=PKB110
ro.product.brand=OnePlus
ro.product.manufacturer=OnePlus
ro.product.device=OP5F71L1
ro.product.name=OnePlus Ace 5 Pro
ro.product.marketname=一加 Ace 5 至尊版
EOF
            LABEL="一加 Ace 5 至尊版"; BRAND="OnePlus"; MODEL="PKB110" ;;
        iqoo15_ultra)
            cat > "$TMP" <<'EOF'
ro.product.model=V2456A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2456A_EX
ro.product.name=iQOO 15 Ultra
ro.product.marketname=iQOO 15 Ultra
EOF
            LABEL="iQOO 15 Ultra"; BRAND="iQOO"; MODEL="V2456A" ;;
        iqoo15)
            cat > "$TMP" <<'EOF'
ro.product.model=V2455A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2455A_EX
ro.product.name=iQOO 15
ro.product.marketname=iQOO 15
EOF
            LABEL="iQOO 15"; BRAND="iQOO"; MODEL="V2455A" ;;
        iqoo13)
            cat > "$TMP" <<'EOF'
ro.product.model=V2401A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2401A_EX
ro.product.name=iQOO 13
ro.product.marketname=iQOO 13
EOF
            LABEL="iQOO 13"; BRAND="iQOO"; MODEL="V2401A" ;;
        iqoo_neo11)
            cat > "$TMP" <<'EOF'
ro.product.model=V2440A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2440A_EX
ro.product.name=iQOO Neo11
ro.product.marketname=iQOO Neo11
EOF
            LABEL="iQOO Neo11"; BRAND="iQOO"; MODEL="V2440A" ;;
        iqoo_neo10_pro_plus)
            cat > "$TMP" <<'EOF'
ro.product.model=V2435A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2435A_EX
ro.product.name=iQOO Neo10 Pro+
ro.product.marketname=iQOO Neo10 Pro+
EOF
            LABEL="iQOO Neo10 Pro+"; BRAND="iQOO"; MODEL="V2435A" ;;
        iqoo_neo10)
            cat > "$TMP" <<'EOF'
ro.product.model=V2422A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2422A_EX
ro.product.name=iQOO Neo10
ro.product.marketname=iQOO Neo10
EOF
            LABEL="iQOO Neo10"; BRAND="iQOO"; MODEL="V2422A" ;;
        iqoo_z11)
            cat > "$TMP" <<'EOF'
ro.product.model=V2445A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2445A_EX
ro.product.name=iQOO Z11
ro.product.marketname=iQOO Z11
EOF
            LABEL="iQOO Z11"; BRAND="iQOO"; MODEL="V2445A" ;;
        iqoo_z11x)
            cat > "$TMP" <<'EOF'
ro.product.model=V2446A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2446A_EX
ro.product.name=iQOO Z11x
ro.product.marketname=iQOO Z11x
EOF
            LABEL="iQOO Z11x"; BRAND="iQOO"; MODEL="V2446A" ;;
        iqoo_z11_turbo)
            cat > "$TMP" <<'EOF'
ro.product.model=V2447A
ro.product.brand=iQOO
ro.product.manufacturer=vivo
ro.product.device=PD2447A_EX
ro.product.name=iQOO Z11 Turbo
ro.product.marketname=iQOO Z11 Turbo
EOF
            LABEL="iQOO Z11 Turbo"; BRAND="iQOO"; MODEL="V2447A" ;;
        redmagic_11s_pro_plus)
            cat > "$TMP" <<'EOF'
ro.product.model=NX799S
ro.product.brand=Nubia
ro.product.manufacturer=ZTE
ro.product.device=NX799S
ro.product.name=NX799S
ro.product.marketname=红魔11S Pro+
EOF
            LABEL="红魔 11S Pro+"; BRAND="Nubia"; MODEL="NX799S" ;;
        redmagic_11_air)
            cat > "$TMP" <<'EOF'
ro.product.model=NX780A
ro.product.brand=Nubia
ro.product.manufacturer=ZTE
ro.product.device=NX780A
ro.product.name=NX780A
ro.product.marketname=红魔11 Air
EOF
            LABEL="红魔 11 Air"; BRAND="Nubia"; MODEL="NX780A" ;;
        redmagic_10s_pro_plus)
            cat > "$TMP" <<'EOF'
ro.product.model=NX789S
ro.product.brand=Nubia
ro.product.manufacturer=ZTE
ro.product.device=NX789S
ro.product.name=NX789S
ro.product.marketname=红魔10S Pro+
EOF
            LABEL="红魔 10S Pro+"; BRAND="Nubia"; MODEL="NX789S" ;;
        redmagic_10_pro)
            cat > "$TMP" <<'EOF'
ro.product.model=NX789J
ro.product.brand=Nubia
ro.product.manufacturer=ZTE
ro.product.device=NX789J
ro.product.name=NX789J
ro.product.marketname=红魔10 Pro
EOF
            LABEL="红魔 10 Pro"; BRAND="Nubia"; MODEL="NX789J" ;;
        redmagic_tab5_pro)
            cat > "$TMP" <<'EOF'
ro.product.model=NX736J
ro.product.brand=Nubia
ro.product.manufacturer=ZTE
ro.product.device=NX736J
ro.product.name=NX736J
ro.product.marketname=红魔游戏平板5 Pro
EOF
            LABEL="红魔游戏平板5 Pro"; BRAND="Nubia"; MODEL="NX736J" ;;
        legion_y700_5)
            cat > "$TMP" <<'EOF'
ro.product.model=Lenovo TB-321FU
ro.product.brand=Lenovo
ro.product.manufacturer=LENOVO
ro.product.device=TB321FU
ro.product.name=TB321FU
ro.product.marketname=拯救者Y700五代
EOF
            LABEL="拯救者 Y700 五代"; BRAND="Lenovo"; MODEL="TB-321FU" ;;
        rog_8_pro)
            cat > "$TMP" <<'EOF'
ro.product.model=ASUS_AI2401_C
ro.product.brand=asus
ro.product.manufacturer=asus
ro.product.device=AI2401
ro.product.name=ASUS_AI2401_C
ro.product.marketname=ROG Phone 8 Pro
EOF
            LABEL="ROG 8 Pro"; BRAND="asus"; MODEL="AI2401" ;;
        xiaomi_14_ultra)
            cat > "$TMP" <<'EOF'
ro.product.model=24030PN60C
ro.product.brand=Xiaomi
ro.product.manufacturer=Xiaomi
ro.product.device=aurora
ro.product.name=aurora
ro.product.marketname=Xiaomi 14 Ultra
EOF
            LABEL="小米 14 Ultra"; BRAND="Xiaomi"; MODEL="24030PN60C" ;;
        *)
            return 1 ;;
    esac
    # 原子替换（同一分区 rename 是原子的）
    mv -f "$TMP" "$PROP_FILE" 2>/dev/null || { rm -f "$TMP"; return 1; }
    chmod 644 "$PROP_FILE"
    return 0
}

# ============ 命令: list - 输出所有预设 ============
cmd_list() {
    printf '{"presets":['
    FIRST=1
    # 系统分类（恢复原机型）
    if [ "$FIRST" = "1" ]; then FIRST=0; else printf ','; fi
    printf '{"id":"__restore__","category":"系统","label":"恢复原机型","brand":"","model":""}'
    # 其他预设
    echo "$PRESETS" | while IFS='|' read -r ID CAT LABEL BRAND MODEL; do
        [ -z "$ID" ] && continue
        printf ',{"id":"%s","category":"%s","label":"%s","brand":"%s","model":"%s"}' \
            "$ID" "$CAT" "$LABEL" "$BRAND" "$MODEL"
    done
    printf ']}'
}

# ============ 命令: current - 查询当前状态 ============
cmd_current() {
    local cur=$(read_setting current_spoof)
    local label=$(read_setting current_spoof_label)
    local orig_brand=$(read_setting orig_brand)
    local orig_model=$(read_setting orig_model)

    # 没备份过：用当前 getprop
    [ -z "$orig_brand" ] && orig_brand=$(getprop ro.product.brand)
    [ -z "$orig_model" ] && orig_model=$(getprop ro.product.model)

    if [ -n "$cur" ]; then
        # 当前在伪装中：从预设中找品牌型号
        local cur_brand="" cur_model=""
        echo "$PRESETS" | while IFS='|' read -r PID PCAT PLABEL PBRAND PMODEL; do
            [ "$PID" = "$cur" ] && echo "${PBRAND}|${PMODEL}"
        done | head -1 > /tmp/_spoof_cur.tmp 2>/dev/null
        if [ -f /tmp/_spoof_cur.tmp ]; then
            cur_brand=$(cut -d'|' -f1 /tmp/_spoof_cur.tmp)
            cur_model=$(cut -d'|' -f2 /tmp/_spoof_cur.tmp)
            rm -f /tmp/_spoof_cur.tmp
        fi
        printf '{"active":true,"id":"%s","label":"%s","brand":"%s","model":"%s","orig_brand":"%s","orig_model":"%s"}\n' \
            "$cur" "$label" "$cur_brand" "$cur_model" "$orig_brand" "$orig_model"
    else
        printf '{"active":false,"id":"","label":"原机型","brand":"%s","model":"%s","orig_brand":"%s","orig_model":"%s"}\n' \
            "$orig_brand" "$orig_model" "$orig_brand" "$orig_model"
    fi
}

# ============ 命令: apply - 应用伪装 ============
cmd_apply() {
    local id="$1"
    [ -z "$id" ] && { echo '{"ok":false,"error":"missing id"}'; exit 1; }

    backup_orig_once

    if [ "$id" = "__restore__" ]; then
        > "$PROP_FILE"
        write_setting "current_spoof" ""
        write_setting "current_spoof_label" ""
        echo '{"ok":true,"action":"restore","msg":"已恢复原机型，重启后生效"}'
        return
    fi

    if write_prop "$id"; then
        write_setting "current_spoof" "$id"
        write_setting "current_spoof_label" "$LABEL"
        printf '{"ok":true,"action":"apply","id":"%s","label":"%s","msg":"已应用 %s，重启后生效"}\n' \
            "$id" "$LABEL" "$LABEL"
    else
        echo '{"ok":false,"error":"未知机型 ID"}'
        exit 1
    fi
}

# ============ 开机时调用 ============
cmd_boot_apply() {
    local cur=$(read_setting current_spoof)
    if [ -n "$cur" ]; then
        backup_orig_once
        write_prop "$cur" >/dev/null 2>&1
        echo "[$(date)] 开机恢复机型: $cur" >> /data/local/tmp/webui_spoof.log
    fi
}

# ============ 旧版兼容: status ============
cmd_status() {
    cmd_current
}

case "$ACTION" in
    list)        cmd_list ;;
    current)     cmd_current ;;
    apply)       cmd_apply "$MODEL_ID" ;;
    status)      cmd_status ;;
    boot_apply)  cmd_boot_apply ;;
    *)
        echo '{"ok":false,"error":"unknown action - use: list | current | apply | status | boot_apply"}'
        exit 1 ;;
esac
