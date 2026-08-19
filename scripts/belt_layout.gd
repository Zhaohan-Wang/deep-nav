class_name BeltLayout
extends RefCounted
## 小行星带的唯一布局算法。三维、星图与审核图必须读取同一批样本，不能各自随机。

const FLIGHT_HIT_SLAB: float = 2.8


static func samples(belt: BeltData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mid_rock_ratio: float = clampf(belt.flight_rock_ratio, 0.12, 0.82)
	var mid_debris_ratio: float = 0.22 if belt.shape == BeltData.Shape.SPLINE or belt.shape == BeltData.Shape.BAND else 0.12
	var mid_rocks: int = maxi(2,int(round(float(belt.rock_count)*mid_rock_ratio)))
	var mid_debris: int = maxi(1,int(round(float(belt.debris_count)*mid_debris_ratio)))
	var volume_rocks: int = maxi(0,belt.rock_count-mid_rocks)
	var volume_debris: int = maxi(0,belt.debris_count-mid_debris)+(32 if belt.is_boundary else 24)
	var cursor := 0
	cursor = _append(result,belt,cursor,mid_rocks,true,0.52,1.12,14.0)
	cursor = _append(result,belt,cursor,mid_debris,true,0.28,0.56,8.0)
	cursor = _append(result,belt,cursor,volume_rocks,false,0.38,0.88,10.0)
	_append(result,belt,cursor,volume_debris,false,0.16,0.42,6.0)
	return result


static func visual_rng(belt: BeltData,index: int) -> RandomNumberGenerator:
	return _rng(belt,index,7919)


static func _append(result: Array[Dictionary],belt: BeltData,cursor: int,count: int,
		flight_layer: bool,radius_min: float,radius_max: float,damage: float) -> int:
	for local_index: int in range(count):
		var index := cursor+local_index
		var rng := _rng(belt,index,1013)
		var position := belt.sample_xz(rng)
		position.y = _sample_mid_y(rng) if flight_layer else _sample_volume_y(rng,_height_span(belt))
		var radius := _sample_radius(rng,radius_min,radius_max) * maxf(belt.rock_scale, 0.25)
		var hit_radius := radius*1.24
		result.append({
			"index":index,
			"position":position,
			"radius":radius,
			"hit_radius":hit_radius,
			"hits_flight":absf(position.y)-hit_radius<=FLIGHT_HIT_SLAB,
			"damage":damage,
		})
	return cursor+count


static func _rng(belt: BeltData,index: int,salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(belt.seed_value)*1000003+index*9176+salt
	return rng


static func _height_span(belt: BeltData) -> float:
	if belt.is_boundary: return 28.0
	if belt.shape == BeltData.Shape.BAND or belt.shape == BeltData.Shape.SPLINE: return 15.0
	return 22.0


static func _sample_radius(rng: RandomNumberGenerator,radius_min: float,radius_max: float) -> float:
	var t := rng.randf(); t*=t
	return lerpf(radius_min,radius_max,t)


static func _sample_mid_y(rng: RandomNumberGenerator) -> float:
	return clampf(rng.randfn(0.0,0.95),-2.4,2.4)


static func _sample_volume_y(rng: RandomNumberGenerator,span: float) -> float:
	for attempt: int in range(8):
		var y := clampf(rng.randfn(0.0,span*0.48),-span*1.25,span*1.25)
		if absf(y)>=4.6: return y
	return span*0.62 if rng.randf()<0.5 else -span*0.62
