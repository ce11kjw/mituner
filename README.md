# MiTuner — 系统调优模块

> 不降频、不减性能，只减少浪费。游戏放开、日常平衡、息屏省电。

[![Platform](https://img.shields.io/badge/platform-Android%2013%2B-22d3ee)]()
[![Root](https://img.shields.io/badge/root-APatch%20%7C%20KernelSU%20%7C%20Magisk-a3e635)]()
[![SoC](https://img.shields.io/badge/SoC-MTK%20%7C%20%E9%80%9A%E7%94%A8-a78bfa)]()
[![Games](https://img.shields.io/badge/games-109%20AAA-f43f5e)]()

---

## 核心思路

市面上大多数"优化模块"做的是**降频省电**：砍 CPU 上限、关加速机制。
代价是卡顿——点开 App 要等、滑动掉帧。

**MiTuner 走的是另一条路：不碰性能上限，只减少浪费。**

| 做法 | 效果 |
|---|---|
| 降低 `swappiness` | 少把活跃内存挤进 zram，App 切回来不用重新解压（**这是"点开微信卡1-2秒"的元凶**）|
| 保留文件缓存 | App 启动时大量 `stat`/`open` 命中缓存，**冷启动更快** |
| 优化 IO 预读 | 减少无效预读，加快资源加载 |
| 提高调度响应 | `schedutil` 升降频更快，减少"点了没反应" |
| 按场景差异化 | 游戏时进一步放开，息屏时收紧省电 |

**性能上限完全不动** —— CPU 频率、温控策略都交给系统和你的原有调度模块。

---

## 三态调度

模块每 5 秒检测一次，自动切换：

### 🎮 游戏模式（GAME）

**触发条件**（满足其一）：
1. 前台应用在**游戏白名单**里（**内置 109 款大型/3A 游戏**）
2. 白名单没命中，但 **GPU 负载 > 60%** 且前台不是桌面/微信/飞书等

**策略**：
- `swappiness` **40**（宁可多占内存，减少回收卡顿）
- `vfs_cache_pressure` **60**（极力保留缓存）
- IO 预读 **512KB**（加快场景/资源加载）
- `schedutil.rate_limit` **200us**（最快响应）
- 保持 CPU 下限（进游戏瞬间不掉帧）

### 💡 日常模式（NORMAL）

亮屏、非游戏。

- `swappiness` **60** / `vfs_cache_pressure` **80**
- IO 预读 **256KB** / `schedutil.rate_limit` **500us**

### 🔋 息屏模式（IDLE）

屏幕熄灭（Asleep / Dozing）。

- `swappiness` **80** / `vfs_cache_pressure` **120**
- IO 预读 **128KB**（省电）
- `schedutil.rate_limit` **2000us**（减少唤醒 = 省电）
- **降低 CPU 下限**（c0=220M / c1=400M / c2=1200M）
- 轮询降到 10 秒/次

> 唤醒秒响应：从 IDLE 醒来时立即切回，不做二次确认，无延迟。

---

## 内置游戏白名单（109 款）

只收录**大型/3A 游戏**（开放世界、FPS、MOBA、动作竞技等重负载）。
小型休闲游戏不会拖累性能，不需要纳入。

### 腾讯（25 款）
**MOBA/竞技**：王者荣耀、王者荣耀体验服、英雄联盟手游、王者荣耀国际版(HoK)、传说对决、金铲铲之战

**FPS/射击**：和平精英、PUBG Mobile、PUBG 台服/韩服/NewState、使命召唤手游、COD Warzone、三角洲行动、暗区突围（国服/海外）、穿越火线、高能英雄、NIKKE、Fortnite、Free Fire、Mobile Legends、LOL 手游国际版

**动作/RPG**：DNF 手游、火影忍者、QQ 飞车、极品飞车集结、元梦之星、光遇腾讯版、我的世界腾讯版、梦幻西游三维、QQ炫舞、节奏大师、美职篮全明星、部落冲突、荒野乱斗

### 米哈游（14 款）
原神（国服/国际/B服/米服）、崩坏：星穹铁道（国服/B服/国际）、绝区零（国服/B服/国际）、崩坏3（国服/米服/B服/国际）

### 网易（27 款）
**开放世界**：逆水寒（国服/米服/国际）、燕云十六声（国服/台服）、七日世界、哈利波特：魔法觉醒

**动作竞技**：永劫无间（国服/米服）、第五人格（国服/米服）、荒野行动（多渠道）、决战！平安京

**其他**：明日之后、蛋仔派对、光遇（网易版/多渠道/国际）、梦幻西游、巅峰极速、王牌竞速、全明星街球派对

### 库洛（5 款）
鸣潮（国服/国际）、战双帕弥什（国服/米服/阿里）

### 其他大厂（38 款）
- **鹰角**：明日方舟（国服/B服/国际）
- **叠纸**：恋与深空、无限暖暖
- **深蓝互动**：重返未来：1999
- **完美世界**：幻塔（多渠道）
- **其他**：碧蓝航线、航海王热血航线、我的世界（国际/网易）、Apex 英雄手游、棕色尘埃2、创造与魔法、超自然行动组、三国杀、JJ象棋

---

## 安装

### 要求

- Android 13+
- Root：**APatch / KernelSU / Magisk** 任一
- 无需特定 SoC（MTK / 高通都能用）

### 步骤

1. 从 [Releases](../../releases) 下载 `MiTuner-vX.Y.Z.zip`
2. 在 Root 管理器里安装
3. **重启手机**

---

## WebUI

在 APatch / KernelSU 管理器的模块页面点开本模块即可。
基于 `window.ksu.exec` 桥，**不需要额外端口**。

**显示内容：**
- 当前档位（游戏 / 日常 / 息屏）
- 前台应用、屏幕状态、GPU 负载
- 守护进程是否在跑
- **完整游戏白名单列表**（109 款，当前命中的高亮显示）
- 当前全部参数值（对比原厂值）

---

## 自定义游戏白名单

编辑 `/data/adb/mituner/games.conf`，**加一行包名即可，无需重启**（模块会自动重载）：

```sh
# 一行一个包名，支持 # 注释
com.example.mygame          # 我的游戏
com.another.game
```

查看包名的方法：
```bash
# 方法1：开游戏后看当前前台
dumpsys window | grep mCurrentFocus

# 方法2：列出所有已安装的第三方应用
pm list packages -3
```

改完等 5 秒（下一次检测）就会生效，日志里会打 `白名单重载: N 个`。

---

## 其他配置

`/data/adb/mituner/settings.conf`（改完重启生效）：

```sh
# 白名单没命中时的自动识别：1=开 0=关
AUTO_GAME=1
# 自动识别的 GPU 负载阈值（%）
AUTO_GPU_TH=60

# 息屏时 CPU 下限
IDLE_MIN_C0=220000
IDLE_MIN_C1=400000
IDLE_MIN_C2=1200000

# IO 预读（KB）
NORMAL_RA=256
GAME_RA=512
IDLE_RA=128
```

---

## 效果实测

Redmi K60 Ultra（MT6985 / 15GB / Android 16）：

| 参数 | 原厂 | 日常 | 游戏 | 息屏 |
|---|---|---|---|---|
| swappiness | 100 | 60 | 40 | 80 |
| vfs_cache_pressure | 100 | 80 | 60 | 120 |
| read_ahead_kb | 1024 | 256 | 512 | 128 |
| schedutil.rate_limit | 1000us | 500us | 200us | 2000us |
| CPU 下限 c0/c1/c2 | 原厂 | 原厂 | 原厂 | 降低 |

**验证结果**：三态参数全部正确应用；109 款游戏白名单精确匹配；微信/相机等普通应用不误判。

---

## 不做什么（重要）

为了和你的其他调度模块共存，MiTuner **明确不碰**这些：

| 不碰的东西 | 原因 |
|---|---|
| ❌ `scaling_max_freq`（CPU 频率上限） | 那是 CTS 等调度模块的职责 |
| ❌ `scaling_governor` | 同上 |
| ❌ 温控配置 `thermal-*.conf` | MIUI 加密，且改了有风险 |
| ❌ 被其他模块 `chattr +i` 锁的文件 | 改了会冲突 |

**只改内核暴露的可调参数**，全部可逆，卸载即恢复。

---

## 排查

### 看日志
```bash
tail -f /data/local/tmp/mituner.log
```

### 看状态
```bash
cat /data/adb/mituner/state        # 当前档位
cat /data/adb/mituner/fb_flag      # 前台包名
cat /data/adb/mituner/games.list   # 清洗后的白名单
cat /proc/sys/vm/swappiness        # 当前值
```

### 常见问题

**Q: 游戏没被识别？**

```bash
# 1. 确认当前前台包名
dumpsys window | grep mCurrentFocus

# 2. 检查是否在白名单
grep -Fx "你的包名" /data/adb/mituner/games.list

# 3. 不在的话加进 games.conf（无需重启）
```

**Q: 和 CTS 模块冲突吗？**

不冲突。MiTuner 不碰 CPU 频率上限和 governor，
只调 VM / IO / schedutil 的响应速度，两者作用层面不同。

**Q: 卡顿改善了吗？**

如果主要卡顿来自内存回收（`swappiness=100` 导致频繁 zram 换页），
改成 60 会有明显改善。在 WebUI 里看 `swappiness` 是否已生效。

---

## 卸载

Root 管理器里移除，或：

```bash
su -c 'rm -rf /data/adb/modules/mituner'
```

`uninstall.sh` 会从 `/data/adb/mituner/orig.conf` 还原**全部原始参数**并停止守护。

---

## 技术细节

### 为什么 `swappiness=100` 会导致卡顿

Android 用 zram 把不活跃内存压缩存放。`swappiness=100` 意味着
**哪怕内存还很充裕，系统也很积极地往 zram 挤**。

App 被换出后，切回前台时要解压 —— 这就是"点开微信要等 1-2 秒"。

实测本机 15GB 内存，`MemAvailable` 常年 6-7GB，完全不需要这么激进。

### 为什么提高 `rate_limit_us` 反而省电

`schedutil` 的 `rate_limit_us` 是"两次调频之间最小间隔"。
值越小调频越频繁（响应快但唤醒多），值越大越迟钝（响应慢但省电）。

- 游戏：200us（宁可多唤醒也要快）
- 日常：500us（平衡）
- 息屏：2000us（没人看屏幕，随便迟钝）

### 白名单匹配为什么不正则

109 个包名拼成正则会有 3KB+，且末尾 `|` 容易触发
`grep: empty (sub)expression`（v1.0.0 踩过这个坑）。

改用**清洗成纯列表 + `grep -Fx` 整行精确匹配**：
- 无正则编译开销
- 不会误匹配（`com.a.game` 不会命中 `com.a.game2`）
- 特殊字符无风险

### 三态判定的优先级

```
屏幕非亮?  -> IDLE（最高优先级）
  否
前台在游戏白名单? -> GAME
  否
GPU > 60% 且前台不是桌面/IM/系统? -> GAME
  否
-> NORMAL
```

自动识别的 GAME 需要**连续 2 次命中**（间隔 3 秒）才切换，防误判。
但从 IDLE 醒来时**立即切换**，不等二次确认。

---

## License

MIT

## 作者

aplm123
