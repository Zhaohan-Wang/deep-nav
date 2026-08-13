class_name CelestialBodyData
extends Resource
## 一颗天体在星图与 3D 世界中的共享描述。

enum Kind {
	PLANET,
	STAR,
	HAZARD,
	DESTINATION,
	ROCK,
}

@export var id: String = ""
@export var display_name: String = ""
@export var scene_path: String = ""
@export var world_position: Vector3 = Vector3.ZERO
@export var map_pixels: int = 36
@export var world_radius: float = 6.0
@export var collision_radius: float = 5.0
@export var seed_value: int = 100
@export var kind: Kind = Kind.PLANET
@export var visual: String = "rock"
@export var spin_speed: float = 0.10
