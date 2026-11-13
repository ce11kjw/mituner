# MiTuner — 系统调优模块

> 不降频、不减性能，只减少浪费。游戏放开、日常平衡、息屏省电。

[![Platform](https://img.shields.io/badge/platform-Android%2013%2B-22d3ee)]()
[![Root](https://img.shields.io/badge/root-APatch%20%7C%20KernelSU%20%7C%20Magisk-a3e635)]()
[![SoC](https://img.shields.io/badge/SoC-MTK%20%7C%20%E9%80%9A%E7%94%A8-a78bfa)]()

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
1. 前台应用在**游戏白名单**里（预置 20+ 主流游戏）
2. 白名单没命中，但 **GPU 负载 > 60%** 且前台不是桌面/微信/飞书等

**策略**：
- `swappiness` **40**（宁可多占内存，减少回收卡顿）
- `vfs_cache_pressure` **60**（极力保留缓存）
- IO 预读 **512KB**（加快场景/资源加载）
- `schedutil.rate_limit` **200us**（最快响应）
- 保持 CPU 下限（进游戏瞬间不掉帧）
- `stune` 向前台倾斜（设备支持时）

### 💡 日常模式（NORMAL）

亮屏、非游戏。

- `swappiness` **60**
- `vfs_cache_pressure` **80**
- IO 预读 **256KB**
- `schedutil.rate_limit` **500us**

### 🔋 息屏模式（IDLE）

屏幕熄灭（Asleep / Dozing）。

- `swappiness` **80**（此时没交互，回收不影响体验）
- `vfs_cache_pressure` **120**
- IO 预读 **128KB**（省电）
- `schedutil.rate_limit` **2000us**（减少唤醒 = 省电）
- **降低 CPU 下限**（c0=220M / c1=400M / c2=1200M）
- 轮询降到 10 秒/次

> 唤醒秒响应：从 IDLE 醒来时立即切回，不做二次确认，无延迟。

---

## 安装

### 要求

- Android 13+
- Root：**APatch / KernelSU / Magisk** 任一
- 无需特定 SoC（MTK / 高通都能用，但 MTK 路径优化更好）

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
- 当前全部参数值（对比原厂值）
- CPU 频率上限（只读展示，说明本模块不干预）

---

## 配置

编辑 `/data/adb/mituner/settings.conf`（改完重启生效）：

```sh
# 游戏白名单，| 分隔
GAME_LIST="com.example.game1|com.example.game2"

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

**预置游戏白名单**（20+ 款）：
王者荣耀、和平精英、原神、崩铁、崩坏3、绝区零、明日方舟、重返未来1999、
第五人格、金铲铲、英雄联盟手游、使命召唤手游、PUBG、Free Fire、
Mobile Legends、Apex 手游、我的世界、DNF手游、哈利波特、QQ飞车 等。

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

**IDLE 实测**：7 项参数全部正确应用，状态机切换正常。

---

## 不做什么（重要）

为了和你的其他调度模块共存，MiTuner **明确不碰**这些：

| 不碰的东西 | 原因 |
|---|---|
| ❌ `scaling_max_freq`（CPU 频率上限） | 那是 CTS 等调度模块的职责 |
| ❌ `scaling_governor` | 同上 |
| ❌ 温控配置 `thermal-*.conf` | MIUI 加密，且改了有风险 |
| ❌ 内核参数 `chattr +i` 锁的文件 | CTS 已锁，改了会冲突 |
| ❌ GMS/系统服务 | 不动系统框架 |

**只改内核暴露的可调参数**，全部可逆，卸载即恢复。

---

## 排查

### 看日志
```bash
tail -f /data/local/tmp/mituner.log
```

### 看状态
```bash
cat /data/adb/mituner/state          # 当前档位
cat /data/adb/mituner/fb_flag        # 前台包名
cat /proc/sys/vm/swappiness          # 当前值
```

### 守护进程在跑吗
```bash
pgrep -f "mituner/service.sh"
```

### 常见问题

**Q: 游戏没被识别？**

1. 确认包名在白名单里：
   ```bash
   dumpsys window | grep mCurrentFocus
   ```
2. 加进 `settings.conf` 的 `GAME_LIST`
3. 或把 `AUTO_GPU_TH` 调低（如 40）让自动识别更容易触发

**Q: 和 CTS 模块冲突吗？**

不冲突。MiTuner 不碰 CPU 频率上限和 governor，
只调 VM / IO / schedutil 的响应速度，两者作用层面不同。

**Q: 跳帧/卡顿改善了吗？**

如果主要卡顿来自内存回收（`swappiness=100` 导致频繁 zram 换页），
改成 60 会有明显改善。可在 WebUI 里看 `swappiness` 是否已生效。

**Q: 想看省电效果？**

息屏 8 小时后对比电池耗电。IDLE 模式降低了 CPU 下限 + 减少唤醒频率。

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
