extends Node2D
class_name VFXImpact

@export var base_scale: Vector2 = Vector2.ONE

var facing_direction: float = 1.0

static func spawn_vfx(parent: Node, vfx_type: String, pos: Vector2, facing: float = 1.0) -> VFXImpact:
	# 使用預載和預熱的資源（零卡頓）
	var preloader = parent.get_tree().get_first_node_in_group("resource_preloader")
	if not preloader:
		push_error("Error: ResourcePreloadManager not found")
		return null
	
	var vfx_scene: PackedScene = preloader.get_vfx_scene(vfx_type)
	if not vfx_scene:
		push_error("Error: VFX scene not found for type: %s" % vfx_type)
		return null
	
	var vfx = vfx_scene.instantiate() as VFXImpact
	if not vfx:
		push_error("Error: Failed to instantiate VFX")
		return null
	
	parent.add_child(vfx)
	vfx.init_vfx(pos, facing)
	return vfx

func init_vfx(pos: Vector2, facing: float) -> void:
	facing_direction = facing
	
	global_position = pos
	
	# 關鍵修正：先套用美術在編輯器設定的 base_scale，再僅翻轉 X 軸方向
	# 這樣 scale 不會被強制覆蓋成 ±1，可自由調整為 0.5、1.5 等任意值
	scale = base_scale
	scale.x *= sign(facing_direction)
	
	# 處理所有 GPUParticles2D 子節點
	for child in get_children():
		if child is GPUParticles2D:
			var particles: GPUParticles2D = child
			
			# 保留粒子節點在場景中設定的原始 scale（若美術已調整大小）
			# 僅額外翻轉 X 軸，避免覆蓋自訂值
			particles.scale.x *= sign(facing_direction)
			
			particles.local_coords = true
			
			# 安全翻轉 direction（初始發射方向）
			if particles.process_material != null:
				var mat: ParticleProcessMaterial = particles.process_material
				if "direction" in mat:
					var dir: Vector3 = mat.direction
					mat.direction = Vector3(dir.x * sign(facing_direction), dir.y, dir.z)
			
			# 左向時額外旋轉 180 度，確保大多數不對稱粒子圖案正確鏡像
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
