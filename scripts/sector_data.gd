class_name SectorData
extends Resource
## 一关扇区：少量天体 + 若干小行星带 + 一份合同目标。素材按关卡取用，不一次铺满。

@export var id: String = ""
@export var display_name: String = ""
@export var briefing: String = ""
@export var objective_hint: String = ""
@export var world_half: float = 96.0
@export var spawn_position: Vector3 = Vector3(0.0, 0.0, 64.0)
@export var spawn_heading: float = 0.0
@export var bodies: Array[CelestialBodyData] = []
@export var belts: Array[BeltData] = []
@export var objective_body_id: String = ""
@export var dock_range: float = 6.0
