# Changelog

## [v4.0.1] - 2026-11-14

### 🐛 融合版修复

v4.0.0 发布后实测发现 3 个融合遗留问题，全部修复。

---

### 1️⃣ battd 路径不匹配（关键）

**问题**：`supervisor.sh` 里 `BIN=$DIR/battd`（=`/data/adb/battery-manager/battd`），
但模块里的二进制在 `/data/adb/modules/mituner/bin/battd`，导致守护报
`bin missing: /data/adb/battery-manager/battd`。

**修法**：沿用 ChargeControl 原生设计 —— **开机时自动同步到数据目录**：
- `bin/battd` → `/data/adb/battery-manager/battd`（sha256 比对，不一致才覆盖）
- `bin/power-sampler.sh` → 同目录
- `supervisor.sh` 保持原样（不改脚本，减少维护成本）

### 2️⃣ ensure_battd 改成走 supervisor

原来直接 `setsid battd &`，**没有守护**（进程挂了不会自动拉起）。

现在：`ensure_battd()` → `supervisor.sh start` → supervisor 拉起 battd 并持续监控。
实测日志：`supervisor start pid=16549` → `started battd pid=16567`。

### 3️⃣ WebUI 不随模块升级更新

battd 的网页在 `/data/adb/battery-manager/webroot/`，**模块升级不会同步**。
→ 新增 sha256 比对同步（在 `ensure_battd` 里）。

---

### 🔪 杀进程自杀坑（又踩了）

用 `for d in /proc/*; do ... kill -9 $pid` 清理 battd 时，
**把自己的 MCP shell 也杀了**（因为命令行里含 "battd" 字符串）。

**正确做法**：用 `/proc/$pid/exe` 的 readlink 精确匹配：
```sh
for d in /proc/[0-9]*; do
  lnk=$(readlink "$d/exe" 2>/dev/null) || continue
  case "$lnk" in *"/bin/battd"*) kill -9 "${d#/proc/}";; esac
done
```

---

### ✅ 验收结果

| 组件 | 状态 |
|---|---|
| MiTuner service | ✓ 15159 |
| MiTuner hotupdate | ✓ 15131 |
| ChargeControl supervisor | ✓ 16549 |
| ChargeControl battd | ✓ 16567 |
| battd API | ✓ 6419 字节 |
| InkVault scripts | ✓ 15 个 |
| 游戏白名单 | ✓ 109 款 |

**电池数据实测**：21% / 36°C / 放电中 / 上限 80% / SoC 51° / 充电IC 40° / 87 循环 / 健康 100 / 剩 713 次

**API 全部可用**：
```
/api/status    6419 B
/api/history   1374 B
/api/export    3390 B
/api/log       1792 B
/api/calibrate  124 B
```

**MiTuner 原功能回归全部通过**：
内存 AVAIL=7311 / 刷新率 144Hz / IO none / GPU dummy / 电池 87 循环 / 网络 cubic

**WebUI**：主 79907B（8 页）/ 隐藏 65609B / 电池 53675B

---


## [v4.0.0] - 2026-11-14

### 🎉 三模块融合

用户要求把 **InkVault（墨匣，游戏隐藏）** 和 **ChargeControl（电池管家）** 融合进 MiTuner。

**融合前的技术评估**（重要）：

| 模块 | 规模 | 性质 |
|---|---|---|
| MiTuner | 20 个 shell 脚本 | 纯脚本，轮询 |
| InkVault | 15 个 shell 脚本（~2000 行）+ UI | 纯脚本 |
| ChargeControl | **4465 行 C 代码** → 777KB 静态 ELF | 常驻 daemon |

⇒ ChargeControl 的核心 **battd 是编译的 C 二进制**，不可能用 shell 复现（曲线/统计/校准/事件快照）。

---

### 融合方案（用户选定）

1. **保留 battd 二进制**（不重写 C 代码）
2. **充电控制全部交给 battd**（删除 MiTuner 的 chargectl 竞争）
3. **UI 用 iframe 内嵌原生界面**（保证功能 100% 可用）
4. **8 个标签页**：状态 / 参数 / 游戏 / 调优 / **电池** / **隐藏** / 系统 / 日志

---

### 新增：电池页（ChargeControl 融合）

**关键数据用 MiTuner 风格**：
- 电量 / 状态 / 电压 / 电流 / 功率
- 温度 SoC / 电池 / 充电IC / 机身
- 健康度 / 循环次数 / 容量 / 剩余寿命
- 充电上限 / 停充状态

**充电控制**（直接调 battd API）：
- 充电上限滑块（50-100%）
- 温度保护滑块（35-60°C）
- 暂停/恢复、充满一次、电池校准、导出数据

**完整仪表盘**（iframe 嵌入 `http://127.0.0.1:8800/`）：
- 功率路径图
- 温度分布
- 硬件耗电（屏幕/WiFi/CPU…）
- 充电画像（电压-电量曲线）
- 充电会话
- 电池寿命
- 停充事件快照

> battd 提供 **100+ 个字段**：CPU 8 核频率、GPU Mali-G715、UFS 型号、
> 内存详情、PD 协议、zram 压缩比、电池内阻、JEITA 档位…

**实测**：`/api/status` 返回 6418 字节，全部数据正常。

---

### 新增：隐藏页（InkVault 融合）

**快速状态**：
- 序列号 / MAC / 机型 / 市场名
- Bootloader / vbmeta / SELinux
- SU / Frida 暴露检测

**完整控制台**（iframe 嵌入 InkVault 原生 UI，8 个 tab）：
- `sys` 系统信息
- `apps` 应用列表
- `spoof` 机型伪装（预设一加/小米等）
- `clean` 游戏缓存清理（16 款游戏）
- `toolbox` 工具箱（SSAID 重置 / 指纹 / chroot）
- `device` 设备标识（MAC / SN）
- `about` 关于

**一键加固**：BL 伪装 + tmp 元数据清理 + SELinux 策略修复。

> 15 个脚本全部融合：`envhide` `hideenv` `spoof` `fp` `ssaid` `sepolicy`
> `games` `cleaner` `sysclean` `device` `settings` `chroot` `sysinfo`

---

### 修改

- **删除 MiTuner 的充电控制**：`service.sh` 里的 `applycap` 调用已移除，
  避免与 battd 抢 `input_suspend` 节点
- **`service.sh` 新增 `ensure_battd()`**：开机自动拉起 battd
- **InkVault 的 `MOD_DIR`** 从 `/data/adb/modules/webui_info` 改为 `/data/adb/modules/mituner`

---

### 备份（可回滚）

融合前完整备份在 `/data/adb/mituner-fusion-backup/`：
- `mituner-v3.0.0-*.tgz`（v3 模块）
- `mituner-config-*.tgz`（配置）
- `MiTuner-v3.0.0.zip`（可直接刷回）
- `props-*.txt`（199 行系统属性快照）
- `system-nodes-*.txt`（充电/刷新率节点原值）
- `modules-list-*.txt`（19 个已装模块）

---

### 实测结果

| 项目 | 结果 |
|---|---|
| battd | ✓ pid 25307，端口 8800 |
| `/api/status` | ✓ 6418 字节，100+ 字段 |
| `/api/history` | ✓ 534 字节 |
| InkVault `device.sh` | ✓ 返回完整设备信息 |
| InkVault `hideenv.sh` | ✓ 返回暴露项 |
| InkVault `games.sh` | ✓ 16 款游戏 |
| MiTuner 原有 | ✓ 109 游戏 / 内存 / 刷新率 / 状态机 |
| HTML 结构 | ✓ 280 div 平衡，8 nav，8 pane |
| 所有 id | ✓ JS 引用 100% 匹配 |

---

## [v3.0.0] - 2026-11-14

8 个新功能（内存/刷新率/电池/IO/进程/自启/网络/温控）+ 6 标签页。

---

## [v2.0.0] - 2026-11-14

参数滑块、三态自定义、GPU、充电、散热器、后台限制、日志、温度。

---

## [v1.3.0] - 2026-11-14

混合检测（30 秒延迟）、添加游戏分组、修 3 bug。

---

## [v1.2.0] - 2026-11-14

热更新（9 秒）、WebUI 游戏管理。

---

## [v1.1.0] - 2026-11-14

109 款 3A 游戏，修正则失效。

---

## [v1.0.0] - 2026-11-14

首版：三态调度 + 基础优化。

---

## 版本号规则

`v主.次.修订` — 主=架构变更，次=新功能，修订=bug 修复
