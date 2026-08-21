# DeepNav 程序内问卷实施说明

> 当前实施版本：岗位专属训练理解 `training-role-comprehension-4.1`；正常关基线状态 `baseline-state-1.0`；事件责任归因 `event-attribution-5.0`；归因后状态信任 `post-attribution-state-4.2`
> 此前试运行数据已清空，不提供旧字段兼容或迁移。

## 1. 总体结构

程序把正式关的“本关责任归因”和“归因后状态信任”分成连续两个阶段：

| 时点 | 内容 | 是否打断游戏 |
| --- | --- | --- |
| 训练关结束 | 操作理解检查 | 只在关卡结束后 |
| 正式任务 01 结束 | 三个对象的基线状态评价，不填写事件责任 | 只在自然结算后 |
| 正式任务 02–03 唯一核心异常后的航段结束 | 异常觉察、100 分责任预算、归因信心、三个对象的状态信任 | 只在自然结算后 |

每名参与者只在第二、三关各填写一次事件特定责任预算，共 2 次。异常出现时不暂停、不弹问卷；系统先完整记录异常后的应对、恢复、安全门到达或失败，再在自然结算后展示标准化回顾。

## 2. 基线与事件后状态短测

### 2.1 训练关

操作理解采用“是／不确定／否”，两边只显示自己岗位的四题。

领航员字段：

```text
navigator_can_place_waypoint
navigator_knows_map_toggle
navigator_knows_waypoint_constraints
navigator_knows_route_guidance
```

驾驶员字段：

```text
pilot_knows_flight_controls
pilot_knows_waypoint_flying
pilot_knows_flight_status
pilot_knows_status_communication
```

任一参与者对自己的岗位题选择“不确定”或“否”，`training_review_required=true`。双方提交后进入实验员复核；本关不计完成，重新说明该参与者对应岗位的规则后重试。另一岗位题不会显示、不会校验，也不会写入该参与者答案。

### 2.2 搭档状态

```text
partner_state_reliability
partner_state_reliance
```

两项分别保存，不合成为总分。题目统一以“我的搭档（本关角色）”为对象，不把航点或飞船异常预先写成某个角色的操作错误：

```text
经过刚才的任务经历，我认为我的搭档（领航员／驾驶员）仍然能够可靠地履行自己的任务职责。
在接下来的航行中，我愿意继续依赖我的搭档（领航员／驾驶员）提供的判断或操作。
```

### 2.3 系统状态

```text
navigation_state_reliability
navigation_state_reliance
ship_state_reliability
ship_state_reliance
```

四项分别保存，不生成系统总分。搭档、领航系统和飞船控制系统三个题块按参与者稳定随机顺序展示，并保存为 `trust_block_order`。

所有状态题采用 1—7 分：1＝完全不同意，4＝既不同意也不反对，7＝完全同意。正式任务 01 以 `baseline_state` 保存同一组对象特定题目；正式任务 02、03 在责任归因后以 `post_attribution_state` 保存，从而保留可比较的正常条件基线。

## 3. 关末画面保存

正式任务 02、03 在目标异常提示已经进入双方真实界面后，分别保存两个参与者当时实际看到的异常画面。分配器只显示本人画面，不显示后台坐标、偏移向量、外力箭头或研究者诊断。正式任务 01 不展示意义不明的结尾截图，只保存行为基线与状态评价。

每关记录：

```text
event_id
mission_id
mission_label
elapsed
outcome
attempt_number
participant_id
role
participant_view_image
```

第二关 `waypoint_drift`、第三关 `ship_shear` 仍在原因提示出现前另外保存目标事件证据，用于确认实验操纵实际触发；责任预算页面不重复磁暴、太阳风等原因文字。

如果第二、第三关在目标事件发生前结束，或事件画面没有成功保存，结果页后直接进入实验员复核并重试，不展示责任分配和状态信任，本关不推进。

## 4. 两个目标异常的事件归因

每名参与者只在正式任务 02、03 的核心异常后各填写一次。第二关客观回顾“刚才发生了一次航点位置偏移”，第三关客观回顾“刚才发生了一次飞船横向偏移”；两页均不重复具体原因或原因不明。正式任务 01 只保留正常协作行为基线，不施测事件责任分配。

## 5. 100 分责任预算分配器

五类责任对象为：

```text
我自己（本关正式角色）
我的搭档（本关正式角色）
领航系统
飞船控制系统
外部环境
```

自己和搭档的角色从本关记录自动读取。参与者不自行选择角色。

五项从 0 分开始，共享同一个 100 分预算。每项提供：

- 横向拖动条；
- `＋5`；
- `－5`。

所有数值以 5 分为步长。页面实时显示：

```text
已分配：n分 / 100分
剩余可分配：100-n分
```

程序规则：

- 五项合计不能超过 100；
- 增加某项时，只能使用剩余分数；
- 已经分满后，不会自动减少其他项目；
- 必须先手动减少其他项目，才能把分数加到新项目；
- “重新分配”把本关五项恢复为 0，并增加 `reset_count`；
- 合计不足 100 时不能提交；
- 不做后台归一化；
- 不提供“无法判断”第六责任对象。

五类对象按参与者随机一次，同一参与者在两次异常归因中保持相同顺序。顺序保存为 `item_display_order`。

## 6. 归因信心

每次分配满 100 分后回答：

> 你对刚才的责任分配有多大把握？

采用 7 点评分：

1. 完全没有把握；
2. 比较没有把握；
3. 有点没有把握；
4. 一般；
5. 有一些把握；
6. 比较有把握；
7. 非常有把握。

未完成 100 分分配时不能确认。参与者先确认满 100 分的责任分配，系统锁定五项分数后再显示信心题；未填写信心时不能提交本关归因。

## 7. 逐关归因数据

每个参与者、每个目标异常关单独生成一条责任分配 `survey_submit`，问卷变体为：

```text
event_responsibility_100
```

每条答案至少包含：

```text
instrument_version
pair_id
participant_id
role
experimental_condition
event_type
event_id
mission_id
attempt_number

responsibility_self
responsibility_partner
responsibility_navigation_system
responsibility_ship_system
responsibility_environment

attribution_confidence
response_time
item_display_order
reset_count
screenshot_available
```

提交前校验：

```text
responsibility_self
+ responsibility_partner
+ responsibility_navigation_system
+ responsibility_ship_system
+ responsibility_environment
= 100
```

主要归因指标为 `responsibility_partner`，其余四项作为独立结果保留。`attribution_confidence` 不加入责任点总和。

## 8. 研究表述边界

当前工具是为本实验开发的程序内状态短测和事件责任预算分配器：

- 不等同于完整 CDS-II；
- 不等同于完整人—自动化信任标准量表；
- 不应表述为未经删改的标准量表；
- 正式报告应给出题目、角色化措辞、施测时点、随机顺序、计分和缺失规则。
