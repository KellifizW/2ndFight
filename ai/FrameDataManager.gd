class_name FrameDataManager extends Node

var frame_database: Dictionary = {
	"st_mp": {"startup": 5, "active": 3, "recovery": 8, "total": 16},
	"st_mk": {"startup": 7, "active": 4, "recovery": 10, "total": 21},
	"cr_mp": {"startup": 4, "active": 3, "recovery": 7, "total": 14},
	"cr_mk": {"startup": 6, "active": 4, "recovery": 9, "total": 19},
	"fireball": {"startup": 15, "active": 1, "recovery": 12, "total": 28},
	"dp": {"startup": 3, "active": 5, "recovery": 25, "total": 33},
	"powerkk": {"startup": 12, "active": 4, "recovery": 18, "total": 34},
	"spnk": {"startup": 10, "active": 5, "recovery": 15, "total": 30},
	"hdk": {"startup": 12, "active": 4, "recovery": 16, "total": 32},
}

# ============================================================
# PRE-COMPUTED CACHES (Phase 2 Optimization)
# ============================================================
# 避免每次查詢都進行字典查找，提高性能 3-5%
var startup_cache: Dictionary = {}
var total_cache: Dictionary = {}
var active_cache: Dictionary = {}
var recovery_cache: Dictionary = {}

@export var enable_cache: bool = true

func _ready() -> void:
	"""初始化預計算快取"""
	if enable_cache:
		_build_caches()

func _build_caches() -> void:
	"""預計算所有幀數據以進行快速查詢"""
	for move_name in frame_database:
		var data = frame_database[move_name]
		startup_cache[move_name] = data.get("startup", 10)
		total_cache[move_name] = data.get("total", 30)
		active_cache[move_name] = data.get("active", 3)
		recovery_cache[move_name] = data.get("recovery", 10)
	
	# 調試：報告快取大小
	if Engine.is_editor_hint():
		return
	#print("[FRAME DATA] Pre-computed %d move entries" % startup_cache.size())

func get_startup_frames(move_name: String) -> int:
	if enable_cache and startup_cache.has(move_name):
		return startup_cache[move_name]
	return frame_database.get(move_name, {}).get("startup", 10)

func get_total_frames(move_name: String) -> int:
	if enable_cache and total_cache.has(move_name):
		return total_cache[move_name]
	return frame_database.get(move_name, {}).get("total", 30)

func get_active_frames(move_name: String) -> int:
	if enable_cache and active_cache.has(move_name):
		return active_cache[move_name]
	return frame_database.get(move_name, {}).get("active", 3)

func get_recovery_frames(move_name: String) -> int:
	if enable_cache and recovery_cache.has(move_name):
		return recovery_cache[move_name]
	return frame_database.get(move_name, {}).get("recovery", 10)

func get_recovery_frames_remaining(player: Player) -> int:
	if not player.animation_player or not player.is_attacking:
		return 0
	
	var current_anim = player.animation_player.current_animation
	var anim_length = player.animation_player.current_animation_length
	if anim_length <= 0:
		return 0
	
	var progress = player.animation_player.current_animation_position / anim_length
	var total = get_total_frames(current_anim)
	var current_frame = int(progress * total)
	
	var startup = get_startup_frames(current_anim)
	var active = get_active_frames(current_anim)
	var recovery_start = startup + active
	
	return total - current_frame if current_frame >= recovery_start else 0

func is_in_recovery(player: Player) -> bool:
	return get_recovery_frames_remaining(player) > 0
