extends Node2D

class_name VFXImpact

var facing_direction: float = 1.0

static func spawn_vfx(parent: Node, vfx_type: String, position: Vector2, facing: float = 1.0) -> VFXImpact:
	var vfx_scene_path: String
	if vfx_type == "block":
		vfx_scene_path = "res://vfx_blk.tscn"
	else:
		vfx_scene_path = "res://vfx_hit.tscn"
	
	var vfx_scene = load(vfx_scene_path)
	if not vfx_scene:
		push_error("Error: Failed to load VFX scene %s" % vfx_scene_path)
		return null
	
	var vfx = vfx_scene.instantiate() as VFXImpact
	if not vfx:
		push_error("Error: Failed to instantiate VFX from %s" % vfx_scene_path)
		return null
	
	parent.add_child(vfx)
	vfx.init_vfx(position, facing)
	return vfx

func init_vfx(position: Vector2, facing: float) -> void:
	facing_direction = facing
	global_position = position
	scale.x = facing_direction
	
	# 自動尋找並啟動所有 GPUParticles2D 子節點
	for child in get_children():
		if child is GPUParticles2D:
			var particles: GPUParticles2D = child
			particles.scale.x = facing_direction
			particles.local_coords = true
			
			# 調整方向（如果 process_material 有 direction 屬性）
			if particles.process_material and "direction" in particles.process_material:
				var dir = particles.process_material.direction
				particles.process_material.direction = Vector3(dir.x * facing_direction, dir.y, dir.z)
			
			# 調整旋轉（某些粒子可能依賴旋轉）
			if facing_direction < 0:
				particles.rotation = PI
			
			particles.restart()
			particles.emitting = true
	
	print("Debug: %s VFX spawned at %s (facing: %s) with %d particles at %s ms" % [
		"Block" if "blk" in get_scene_file_path() else "Hit",
		global_position,
		facing_direction,
		get_children().filter(func(c): return c is GPUParticles2D).size(),
		Time.get_ticks_msec()
	])

func _process(_delta):
	var all_finished = true
	for child in get_children():
		if child is GPUParticles2D and child.emitting:
			all_finished = false
			break
	
	if all_finished and get_child_count() > 0:
		queue_free()
		print("Debug: VFX_impact all particles finished, freeing node at %s" % global_position)
