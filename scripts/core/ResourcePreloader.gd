extends Node
class_name ResourcePreloadManager

## ResourcePreloadManager - 資源預載與預熱系統
##
## 職責: 在遊戲啟動時預載所有特效和投射物資源，並預熱 GPU shader 編譯
## - 使用 preload() 在編譯時載入資源（零運行時開銷）
## - 預熱實例化：創建並短暫保留實例以觸發 shader 編譯
## - 提供統一的資源獲取接口

# ═══════════════════════════════════════════════════════════════════════════
# 編譯時預載（使用 preload，零運行時開銷）
# ═══════════════════════════════════════════════════════════════════════════

const VFX_HIT: PackedScene = preload("res://scenes/vfx/vfx_hit.tscn")
const VFX_BLOCK: PackedScene = preload("res://scenes/vfx/vfx_blk.tscn")
const VFX_SPAWNFIRE: PackedScene = preload("res://scenes/vfx/spawnfire.tscn")
const FIREBALL_DAV: PackedScene = preload("res://scenes/projectiles/DAV_fireball.tscn")
const FIREBALL_DEN: PackedScene = preload("res://scenes/projectiles/DEN_fireball.tscn")

# 資源映射（用於接口查詢/測試）
var preloaded_resources: Dictionary = {
	"vfx_hit": VFX_HIT,
	"vfx_block": VFX_BLOCK,
	"vfx_spawnfire": VFX_SPAWNFIRE,
	"fireball_DAV": FIREBALL_DAV,
	"fireball_DEN": FIREBALL_DEN
}

var _warmup_instances: Array[Node] = []
var _cleanup_scheduled: bool = false

# ═══════════════════════════════════════════════════════════════════════════
# 初始化與預熱
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_warmup_resources()

func _warmup_resources() -> void:
	"""預熱全域 VFX/投射物：實例化並啟動粒子以觸發 GPU shader 編譯"""
	var start_time = Time.get_ticks_msec()

	Debug.log("[ResourcePreloadManager] 開始預熱資源（觸發 shader 編譯）...")

	# 預熱命中/格擋/角色施法特效
	_warmup_scene("VFX", "hit", VFX_HIT)
	_warmup_scene("VFX", "block", VFX_BLOCK)
	_warmup_scene("VFX", "spawnfire", VFX_SPAWNFIRE)

	# 預熱 Fireball 投射物
	_warmup_scene("Fireball", "DAV", FIREBALL_DAV)
	_warmup_scene("Fireball", "DEN", FIREBALL_DEN)

	_schedule_warmup_cleanup()

	var elapsed = Time.get_ticks_msec() - start_time
	Debug.log("[ResourcePreloadManager] 預熱排程完成 (耗時 %d ms)" % elapsed)

func warmup_character_vfx(character_root: Node, character_label: String = "") -> void:
	"""預熱已生成角色身上的內嵌 VFX（例如 groundsmoke / spawnfire 子節點）。"""
	if character_root == null:
		return
	var label = character_label if character_label != "" else character_root.name
	var particle_count = _warmup_character_particles_recursive(character_root, label)
	if particle_count > 0:
		_schedule_warmup_cleanup()
		Debug.log("  ✓ 已預熱角色 VFX: %s (%d particles)" % [label, particle_count])

func _warmup_scene(category: String, resource_name: String, scene: PackedScene) -> void:
	if scene == null:
		return
	var instance = scene.instantiate()
	if instance == null:
		return
	_prepare_warmup_instance(instance)
	_mute_audio_recursive(instance)
	add_child(instance)
	_warmup_instances.append(instance)
	var particle_count = _prime_particles_recursive(instance)
	Debug.log("  ✓ 已預熱 %s: %s (%d particles)" % [category, resource_name, particle_count])

func _warmup_character_particles_recursive(root: Node, label: String) -> int:
	var particle_count := 0
	if root is GPUParticles2D:
		var copy = root.duplicate()
		if copy:
			copy.name = "Warmup_%s_%s" % [label, root.name]
			_prepare_warmup_instance(copy)
			add_child(copy)
			_warmup_instances.append(copy)
			particle_count += _prime_particles_recursive(copy)
	for child in root.get_children():
		particle_count += _warmup_character_particles_recursive(child, label)
	return particle_count

func _prepare_warmup_instance(instance: Node) -> void:
	# Keep the object renderable for shader/material compilation while making it
	# invisible to the player and far away from the arena.
	if instance is Node2D:
		var node_2d := instance as Node2D
		node_2d.position = Vector2(-10000.0, -10000.0)
		if node_2d is CanvasItem:
			var canvas_item := node_2d as CanvasItem
			canvas_item.visible = true
			canvas_item.modulate = Color(1.0, 1.0, 1.0, 0.0)
	elif instance is CanvasItem:
		var direct_canvas_item := instance as CanvasItem
		direct_canvas_item.visible = true
		direct_canvas_item.modulate = Color(1.0, 1.0, 1.0, 0.0)

func _mute_audio_recursive(root: Node) -> void:
	if root is AudioStreamPlayer:
		var audio := root as AudioStreamPlayer
		audio.autoplay = false
		audio.volume_db = -80.0
	elif root is AudioStreamPlayer2D:
		var audio_2d := root as AudioStreamPlayer2D
		audio_2d.autoplay = false
		audio_2d.volume_db = -80.0
	for child in root.get_children():
		_mute_audio_recursive(child)

func _prime_particles_recursive(root: Node) -> int:
	var particle_count := 0
	if root is GPUParticles2D:
		var particles := root as GPUParticles2D
		particles.emitting = true
		particles.restart()
		particle_count += 1
	for child in root.get_children():
		particle_count += _prime_particles_recursive(child)
	return particle_count

func _schedule_warmup_cleanup() -> void:
	if _cleanup_scheduled:
		return
	_cleanup_scheduled = true
	call_deferred("_cleanup_warmup_instances_deferred")

func _cleanup_warmup_instances_deferred() -> void:
	# Leave warmup instances alive for a couple of frames so RenderingServer has a
	# chance to compile/process their materials before first real gameplay usage.
	if get_tree():
		await get_tree().process_frame
	if get_tree():
		await get_tree().process_frame
	for instance in _warmup_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_warmup_instances.clear()
	_cleanup_scheduled = false

# ═══════════════════════════════════════════════════════════════════════════
# 資源獲取接口
# ═══════════════════════════════════════════════════════════════════════════

func get_vfx_scene(vfx_type: String) -> PackedScene:
	"""
	獲取 VFX 特效場景 (已預載和預熱)
	@param vfx_type: "hit" 或 "block"
	@return: 預載的 PackedScene
	"""
	if vfx_type == "hit":
		return VFX_HIT
	elif vfx_type == "block":
		return VFX_BLOCK
	elif vfx_type == "spawnfire":
		return VFX_SPAWNFIRE
	else:
		push_error("[ResourcePreloadManager] 未知的 VFX 類型: %s" % vfx_type)
		return null

func get_fireball_scene(character_id: String) -> PackedScene:
	"""
	獲取 Fireball 投射物場景 (已預載和預熱)
	@param character_id: "DAV" 或 "DEN"
	@return: 預載的 PackedScene
	"""
	if character_id == "DAV":
		return FIREBALL_DAV
	elif character_id == "DEN":
		return FIREBALL_DEN
	else:
		push_error("[ResourcePreloadManager] 未知的角色 ID: %s" % character_id)
		return null

func has_vfx(vfx_type: String) -> bool:
	"""檢查 VFX 資源是否已載入"""
	return vfx_type in ["hit", "block", "spawnfire"]

func has_fireball(character_id: String) -> bool:
	"""檢查 Fireball 資源是否已載入"""
	return character_id in ["DAV", "DEN"]
