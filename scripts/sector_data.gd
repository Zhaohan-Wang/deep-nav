class_name SectorData
extends Resource
## 一关扇区：少量天体 + 若干小行星带 + 一份合同目标。素材按关卡取用，不一次铺满。

@export var id: String = ""
@export var display_name: String = ""
@export var briefing: String = ""
@export var objective_hint: String = ""
## 参与者在选关页可以看到的中性文案。与研究设计说明分开，避免暴露实验操纵。
@export var participant_name: String = ""
@export var participant_briefing: String = ""
@export var participant_hint: String = ""
@export var world_half: float = 96.0
## 领航星图一次显示的纵向半径。整关可以远大于一屏，由星图跟随飞船分段推进。
@export var map_view_half: float = 82.0
@export var spawn_position: Vector3 = Vector3(0.0, 0.0, 64.0)
@export var spawn_heading: float = 0.0
@export var bodies: Array[CelestialBodyData] = []
@export var belts: Array[BeltData] = []
@export var objective_body_id: String = ""
@export var dock_range: float = 6.0
## 实验与流程元数据：仅供研究人员调试与自动审核，不能直接进入参与者界面。
@export var order_index: int = 0
@export var short_name: String = ""
@export_multiline var design_intent: String = ""
@export var challenge_type: String = "navigation"
@export var time_limit_s: float = 120.0
## 0 表示不按解体次数结束；当前实验统一由任务时限判负。
@export var max_attempts: int = 0
@export var disturbance_slots: PackedStringArray = PackedStringArray()
## 每个扰动槽在世界坐标中的预定触发中心；与 disturbance_slots 按下标对应。
@export var disturbance_anchors: PackedVector3Array = PackedVector3Array()
## 关键事件后允许暂停、回顾和进入微问卷的自然安全门。
@export var safe_gate_points: PackedVector3Array = PackedVector3Array()
@export var route_checkpoints: PackedVector3Array = PackedVector3Array()
## 参与者可见的中继站。一关最多两个；解体后回到最后抵达的一座，没到过就回起点。
@export var relay_stations: PackedVector3Array = PackedVector3Array()


func public_display_name() -> String:
	return participant_name if not participant_name.is_empty() else "航行任务 %02d" % order_index
