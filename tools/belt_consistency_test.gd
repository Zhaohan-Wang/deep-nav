extends SceneTree
## MultiMesh 中每颗三维岩块与复合碰撞体必须逐颗对应 BeltLayout。

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
		var visual_seen: Dictionary={}
		for child: Node in field.get_children():
			if not child is MultiMeshInstance3D: continue
			var batch:=child as MultiMeshInstance3D
			var belt_id:=str(batch.get_meta("belt_id",""))
			var indices:=batch.get_meta("sample_indices",PackedInt32Array()) as PackedInt32Array
			var positions:=batch.get_meta("sample_positions",PackedVector3Array()) as PackedVector3Array
			if batch.multimesh==null or batch.multimesh.instance_count!=indices.size() or positions.size()!=indices.size():
				failures.append("%s invalid batch %s" % [mission.id,batch.name]); continue
			for i: int in range(indices.size()):
				var key:="%s:%d" % [belt_id,indices[i]]
				if not expected.has(key):
					failures.append("%s unexpected 3D sample %s" % [mission.id,key]); continue
				if visual_seen.has(key): failures.append("%s duplicate visual %s" % [mission.id,key])
				visual_seen[key]=true
				var sample: Dictionary=expected[key]
				# Dummy headless renderer 不保存 MultiMesh GPU transform，使用同批写入的采样元数据核对。
				var position:=positions[i]
				# MultiMesh 实例变换由渲染服务器以 float32 保存；允许不可见的亚毫米量化误差。
				if position.distance_to(Vector3(sample["position"]))>0.002:
					failures.append("%s position mismatch %s" % [mission.id,key])
		var collision_seen: Dictionary={}
		for node: Node in field.find_children("*","CollisionShape3D",true,false):
			if not node.has_meta("sample_index"): continue
			var key:="%s:%d" % [str(node.get_meta("belt_id")),int(node.get_meta("sample_index"))]
			collision_seen[key]=true
		for key: String in expected:
			var sample: Dictionary=expected[key]
			if not visual_seen.has(key): failures.append("%s missing visual %s" % [mission.id,key])
			if bool(sample["hits_flight"])!=collision_seen.has(key):
				failures.append("%s collision mismatch %s" % [mission.id,key])
		if visual_seen.size()!=expected.size(): failures.append("%s sample count %d/%d" % [mission.id,visual_seen.size(),expected.size()])
		print("BELT_LAYOUT_OK %s samples=%d colliders=%d" % [mission.id,visual_seen.size(),collision_seen.size()])
		host.queue_free(); await process_frame
	if not failures.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1); return
	print("BELT_CONSISTENCY_OK missions=%d" % Catalog.all().size())
	quit(0)
