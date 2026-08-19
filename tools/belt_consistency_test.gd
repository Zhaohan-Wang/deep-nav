extends SceneTree
## 三维岩块节点必须逐颗对应 BeltLayout；星图和审核图也直接读取这份布局。

const Catalog = preload("res://scripts/mission_catalog.gd")
const Layout = preload("res://scripts/belt_layout.gd")
const FieldScript = preload("res://scripts/world/asteroid_field.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: PackedStringArray=[]
	for mission: SectorData in Catalog.all():
		var host:=Node3D.new(); root.add_child(host)
		var field:=Node3D.new(); field.set_script(FieldScript); host.add_child(field)
		field.call("setup",mission.belts,Vector3(0.4,0.7,0.5))
		await process_frame
		var expected: Dictionary={}
		for belt: BeltData in mission.belts:
			for sample: Dictionary in Layout.samples(belt):
				expected["%s:%d" % [belt.id,int(sample["index"])]]=sample
		var seen:=0
		for child: Node in field.get_children():
			if not child.has_meta("sample_index"): continue
			var key:="%s:%d" % [str(child.get_meta("belt_id")),int(child.get_meta("sample_index"))]
			if not expected.has(key):
				failures.append("%s unexpected 3D sample %s" % [mission.id,key]); continue
			var sample: Dictionary=expected[key]
			var node3d:=child as Node3D
			if node3d.position.distance_to(Vector3(sample["position"]))>0.0001:
				failures.append("%s position mismatch %s" % [mission.id,key])
			var should_collide:=bool(sample["hits_flight"])
			var has_collision:=false
			for sub: Node in child.get_children():
				if sub is StaticBody3D: has_collision=true
			if should_collide!=has_collision:
				failures.append("%s collision mismatch %s" % [mission.id,key])
			seen+=1
		if seen!=expected.size(): failures.append("%s sample count %d/%d" % [mission.id,seen,expected.size()])
		print("BELT_LAYOUT_OK %s samples=%d" % [mission.id,seen])
		host.queue_free(); await process_frame
	if not failures.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1); return
	print("BELT_CONSISTENCY_OK missions=%d" % Catalog.all().size())
	quit(0)
