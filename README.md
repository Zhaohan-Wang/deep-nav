# DeepNav

<p align="center">
  <img src="docs/readme/hero.jpg" alt="DeepNav 标题页" width="920">
</p>

两人、两块屏、两只鼠标。领航员看星图并投放航点，驾驶员坐在驾驶舱里执行机动。同一艘飞船，同一段时限，必须靠沟通把船送到目的地。

标题页打开 **实验模式** 后，同一套流程会按会话写原始日志，方便现场采集。

<p align="center">
  <img src="docs/readme/gameplay.jpg" alt="领航员星图与驾驶员驾驶舱分屏" width="920">
</p>

## 玩法

| 席位 | 看什么 | 做什么 |
| --- | --- | --- |
| **领航员** | 大范围星图与航线 | 在地图上点击放置航点，规划绕行与恢复 |
| **驾驶员** | 船内第一人称像素太空 | `W A S D` 推进、刹车、转向，跟随航点飞行 |

启动后两只物理鼠标分别控制席位 A / 席位 B 的虚拟光标。岗位由任务开始前的认领决定：谁点了领航员卡，谁的屏幕就显示星图。

| 操作 | 作用 |
| --- | --- |
| 星图左键 | 放置航点（冷却 2 秒，最大距离 72 世界单位） |
| `W A S D` | 驾驶员推进 / 刹车 / 转向 |
| `E` | 升起或降下领航甲板 |
| `R` | 重置当前飞行 |
| `F4` | 交换两块屏上的岗位画面 |
| `F6` | 校正鼠标与屏幕对应关系 |

航点不能丢到边界排斥区外。解体不会直接结束任务：训练关回起点，正式关回到最近一座已抵达的**中继站**。时限耗尽才判负。

## 流程

`标题` → `选关` → `认领岗位` → `飞行` → `结算` → `量表` → 下一关；第五关量表提交后进入 `感谢游玩`

<p align="center">
  <img src="docs/readme/level_select.jpg" alt="选关页按顺序解锁任务" width="920">
</p>

进度只存在本次运行的内存里。从标题页重新开始，或退出后再进，都会从训练关归零。当前关无论成功、超时还是其他结果，填完量表后就会锁住，只能进入下一关。

<p align="center">
  <img src="docs/readme/role_claim.jpg" alt="两屏分别认领领航员与驾驶员" width="920">
</p>

认领必须分清是屏幕 A 还是屏幕 B 点的。同一岗位不能被两边同时占住；点关闭可以退回重选。两边都认领后才能出发。

## 五关

每关只练一件协作问题。训练关短、开阔、不设中继站；后面四关按阶段横向展开，16:9 只是一次可见范围，不是整张地图。

| 训练航道 | 织环航道 | 折光走廊 |
| :---: | :---: | :---: |
| <img src="docs/readme/mission_practice.jpg" alt="训练航道首图" width="280"> | <img src="docs/readme/mission_level_1.jpg" alt="织环航道首图" width="280"> | <img src="docs/readme/mission_level_2.jpg" alt="折光走廊首图" width="280"> |
| 建立分工：短航点、冷却、跟随 | 开阔进场后绕过单一环带 | 两段错位碎石门，减速再转向 |

| 寂井侧翼 | 潮汐远航 |
| :---: | :---: |
| <img src="docs/readme/mission_level_3.jpg" alt="寂井侧翼首图" width="280"> | <img src="docs/readme/mission_level_4.jpg" alt="潮汐远航首图" width="280"> |
| 单一校准走廊，导航读数可能异常 | 先建立稳定节奏，再在剪切后恢复 |

关卡设计理由、边界规则和小行星带不可直穿的检查见 [关卡设计](docs/mission_design.md)。审核路线只画在 `artifacts/maps/` 的开发图里，实验界面不会展示。

## 结算与量表

任务结束先看结果图，再各自填两页量表。量表用平铺选项和圆形滑钮，不用下拉弹窗，避免挡住虚拟光标。

| 成功 | 失败 |
| :---: | :---: |
| <img src="docs/readme/result_success.jpg" alt="任务成功结算" width="440"> | <img src="docs/readme/result_failure.jpg" alt="任务失败结算" width="440"> |

<p align="center">
  <img src="docs/readme/survey.jpg" alt="任务结束量表第一页" width="720">
</p>

第五关双方都提交后，进入感谢页。可以从这里返回标题，或直接退出。

<p align="center">
  <img src="docs/readme/thank_you.jpg" alt="感谢游玩页面" width="920">
</p>

## 实验数据

标题页打开 **实验模式** 再点开始，会新建一份只追加、不覆盖的 session。调试模式不会混入正式样本：两个开关同时打开时，实验模式优先，并关掉调试显示。

数据写在游戏可写目录：

`user://experiments/deepnav_<UTC时间>/raw/`

macOS 上大致对应：

- 编辑器运行：`~/Library/Application Support/Godot/app_userdata/DeepNav/experiments/`
- 导出的 `.app`：`~/Library/Application Support/DeepNav/experiments/`

`raw/` 里有：

- `session.csv`：会话元数据
- `events.csv`：航点、碰撞、中继站、任务结束、量表提交
- `frames.csv`：船体位置、航向、油门、耐久与当前航点

标题页的 **打开数据文件夹** 会先创建 `user://experiments/`，再用系统文件管理器打开，行为和 [Dyadic Force](https://github.com/Zhaohan-Wang/dyadic-force) 一致。

## 运行

- 引擎：**Godot 4.6**（Forward Plus + Jolt）
- 主场景：`scenes/title_screen.tscn`
- 双屏必须用独立进程，不要用编辑器里的「嵌入游戏」播放

```bash
# 把 GODOT_BIN 指到 Godot.app 里的可执行文件
export GODOT_BIN="/Applications/Godot_mono.app/Contents/MacOS/Godot"

tools/run.sh
```

现场两块扩展屏、两只外接鼠标时，macOS 会通过 `native/macos` 的 HID 桥按物理设备分流原始输入。需要重编桥接进程时：

```bash
tools/build_macos_hid_bridge.sh
```

## 校验

改关卡或交互后，按 [制作循环](docs/development_loop.md) 走，不要跳过失败阶段继续堆功能。

```bash
tools/validate_project.sh
tools/validate_runtime.sh
```

成功标志：

```text
DEEP_NAV_FULL_VALIDATION_OK
DEEP_NAV_RUNTIME_VALIDATION_OK
```

## 架构

- Autoload：`Game` / `Displays` / `RawMice` / `ExperimentLog`
- 关卡目录：`scripts/mission_catalog.gd`
- 双屏与虚拟光标：`scripts/display_coordinator.gd`
- 实验写盘：`scripts/experiment_log.gd`

共用页按 1920×1080 设计；进入岗位页后切到 960×540，再放大铺满整块屏，和早期并排双视图的排版一致。
