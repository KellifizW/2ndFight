extends Node
class_name ResourcePreloadManager

## ResourcePreloadManager - 資源預載與預熱系統
##
## 職責: 在遊戲啟動時預載所有特效和投射物資源，並預熱 GPU shader 編譯
## - 使用 preload() 在編譯時載入資源（零運行時開銷）
## - 預熱實例化：創建並立即銷毀實例以觸發 shader 編譯
## - 提供統一的資源獲取接口

# ═══════════════════════════════════════════════════════════════════════════
# 編譯時預載（使用 preload，零運行時開銷）
# ═══════════════════════════════════════════════════════════════════════════

const VFX_HIT: PackedScene = preload("res://scenes/vfx/vfx_hit.tscn")
const VFX_BLOCK: PackedScene = preload("res://scenes/vfx/vfx_blk.tscn")
const FIREBALL_DAV: PackedScene = preload("res://scenes/projectiles/DAV_fireball.tscn")
const FIREBALL_DEN: PackedScene = preload("res://scenes/projectiles/DEN_fireball.tscn")

# 資源映射（用於接口查詢）
var preloaded_resources: Dictionary = {
	"vfx_hit": VFX_HIT,
	"vfx_block": VFX_BLOCK,
	"fireball_DAV": FIREBALL_DAV,
	"fireball_DEN": FIREBALL_DEN
}

# ═══════════════════════════════════════════════════════════════════════════
# 初始化與預熱
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_warmup_resources()

func _warmup_resources() -> void:
	"""預熱所有資源：實例化並立即銷毀以觸發 GPU shader 編譯"""
	var start_time = Time.get_ticks_msec()
	
	Debug.log("[ResourcePreloadManager] 開始預熱資源（觸發 shader 編譯）...")
	
	# 預熱 VFX 特效
	_warmup_vfx("hit", VFX_HIT)
	_warmup_vfx("block", VFX_BLOCK)
	
	# 預熱 Fireball 投射物
	_warmup_fireball("DAV", FIREBALL_DAV)
	_warmup_fireball("DEN", FIREBALL_DEN)
	
	var elapsed = Time.get_ticks_msec() - start_time
	Debug.log("[ResourcePreloadManager] 預熱完成 (耗時 %d ms)" % elapsed)

func _warmup_vfx(name: String, scene: PackedScene) -> void:
	"""預熱 VFX：實例化、啟動粒子、等待一幀、銷毀"""
	var instance = scene.instantiate()
	add_child(instance)
	
	# 啟動所有 GPUParticles2D 以觸發 shader 編譯
	for child in instance.get_children():
		if child is GPUParticles2D:
			child.emitting = true
			child.restart()
	
	# 立即銷毀（shader 已編譯）
	instance.queue_free()
	Debug.log("  ✓ 已預熱 VFX: %s" % name)

func _warmup_fireball(name: String, scene: PackedScene) -> void:
	"""預熱 Fireball：實例化並立即銷毀"""
	var instance = scene.instantiate()
	add_child(instance)
	
	# 啟動所有粒子效果
	if instance.has_node("GPUParticles2D"):
		var particles = instance.get_node("GPUParticles2D")
		if particles is GPUParticles2D:
			particles.emitting = true
			particles.restart()
	
	# 立即銷毀
	instance.queue_free()
	Debug.log("  ✓ 已預熱 Fireball: %s" % name)

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
	return vfx_type in ["hit", "block"]

func has_fireball(character_id: String) -> bool:
	"""檢查 Fireball 資源是否已載入"""
	return character_id in ["DAV", "DEN"]
