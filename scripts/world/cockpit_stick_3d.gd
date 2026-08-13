class_name CockpitStick3D
extends Node3D
## 驾驶舱 3D 摇杆（占位版）：底座 + 防尘罩 + 杆身 + 握把，随输入前后左右倾斜。
## 画在驾驶员页最上层的独立透明视口里，压过 Pad View / 仪表；领航员画面看不到。
## 之后猴子手 / 正式摇杆素材到位时，把模型挂到 _pivot 下即可继承倾斜动作。

## 驾驶舱专属渲染层（位值）。
const RENDER_LAYER: int = 2
## 前后最大倾角（弧度），推油门时向前压杆。
const MAX_PITCH: float = 0.34
## 左右最大倾角（弧度）。
const MAX_ROLL: float = 0.30
## 倾斜跟随速度。
const FOLLOW: float = 12.0

const COL_BASE: Color = Color(0.13, 0.15, 0.19)
const COL_BOOT: Color = Color(0.09, 0.10, 0.13)
const COL_STICK: Color = Color(0.55, 0.58, 0.64)
## 握把用琥珀色，与仪表配色呼应。
const COL_GRIP: Color = Color(0.91, 0.63, 0.29)
const COL_BUTTON: Color = Color(0.83, 0.36, 0.42)

## 可倾斜部分（杆身 + 握把）的挂点。
var _pivot: Node3D


func _ready() -> void:
	# 画面底部中央，握把露在仪表台下缘附近。独立 overlay 用 64° 标定，避免跟窗外 50° 镜头绑在一起往下沉。
	position = Vector3(0.0, -0.53, -0.85)
	scale = Vector3(0.75, 0.75, 0.75)
	_build()


func _build() -> void:
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.12
	base_mesh.bottom_radius = 0.155
	base_mesh.height = 0.045
	_add_mesh(self, base_mesh, COL_BASE, Vector3.ZERO)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 0.022, 0.0)
	add_child(_pivot)

	var boot_mesh := CylinderMesh.new()
	boot_mesh.top_radius = 0.028
	boot_mesh.bottom_radius = 0.085
	boot_mesh.height = 0.065
	_add_mesh(_pivot, boot_mesh, COL_BOOT, Vector3(0.0, 0.032, 0.0))

	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.018
	stick_mesh.bottom_radius = 0.023
	stick_mesh.height = 0.15
	_add_mesh(_pivot, stick_mesh, COL_STICK, Vector3(0.0, 0.12, 0.0))

	var grip_mesh := SphereMesh.new()
	grip_mesh.radius = 0.045
	grip_mesh.height = 0.09
	_add_mesh(_pivot, grip_mesh, COL_GRIP, Vector3(0.0, 0.21, 0.0))

	var button_mesh := SphereMesh.new()
	button_mesh.radius = 0.013
	button_mesh.height = 0.026
	_add_mesh(_pivot, button_mesh, COL_BUTTON, Vector3(0.0, 0.252, 0.010))


func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	# 舱内道具不吃场景光，直接用平色 + 屏幕像素化 shader 统一质感。
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.layers = RENDER_LAYER
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	inst.position = pos
	parent.add_child(inst)
	return inst


func _process(delta: float) -> void:
	# 前推 = 油门正向；左转输入为正，杆向左倾。
	var throttle: float = Game.throttle
	var turn: float = Input.get_axis("turn_right", "turn_left")
	var target := Vector3(-throttle * MAX_PITCH, 0.0, turn * MAX_ROLL)
	var weight: float = 1.0 - exp(-delta * FOLLOW)
	_pivot.rotation = _pivot.rotation.lerp(target, weight)
