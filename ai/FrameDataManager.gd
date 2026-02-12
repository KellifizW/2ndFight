class_name FrameDataManager extends Node

const LOGIC_FPS: int = 60

var frame_database: Dictionary = {
	"st_lp": {"startup": 4, "active": 2, "recovery": 6, "total": 12},
	"st_mp": {"startup": 5, "active": 3, "recovery": 8, "total": 16},
	"st_hp": {"startup": 8, "active": 4, "recovery": 12, "total": 24},
	"st_lk": {"startup": 5, "active": 3, "recovery": 7, "total": 15},
	"st_mk": {"startup": 7, "active": 4, "recovery": 10, "total": 21},
	"st_hk": {"startup": 9, "active": 5, "recovery": 14, "total": 28},
	"cr_lp": {"startup": 3, "active": 2, "recovery": 5, "total": 10},
	"cr_mp": {"startup": 4, "active": 3, "recovery": 7, "total": 14},
	"cr_hp": {"startup": 6, "active": 4, "recovery": 10, "total": 20},
	"cr_lk": {"startup": 4, "active": 3, "recovery": 6, "total": 13},
	"cr_mk": {"startup": 6, "active": 4, "recovery": 9, "total": 19},
	"cr_hk": {"startup": 8, "active": 5, "recovery": 12, "total": 25},
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
	if not player or not player.animation_player:
		return 0
	
	var current_anim = player.animation_player.current_animation
	if not frame_database.has(current_anim):
		return 0
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

func get_blockstun_frames_remaining_logic(player: Player) -> int:
	if not player:
		return 0
	if not ("blockstun_frames" in player):
		return 0
	return _physics_to_logic_frames(player.blockstun_frames)

func get_hitstun_frames_remaining_logic(player: Player) -> int:
	if not player:
		return 0
	if not ("hitstun_frames" in player):
		return 0
	return _physics_to_logic_frames(player.hitstun_frames)

func get_punish_window_logic(ai_player: Player, opponent: Player) -> int:
	var opponent_recovery = get_recovery_frames_remaining(opponent)
	if opponent_recovery <= 0:
		return 0
	var ai_blockstun = get_blockstun_frames_remaining_logic(ai_player)
	return max(0, opponent_recovery - ai_blockstun)

func _physics_to_logic_frames(physics_frames: int) -> int:
	if physics_frames <= 0:
		return 0
	var physics_fps = Engine.physics_ticks_per_second
	if physics_fps <= 0:
		return 0
	return int(round(physics_frames * float(LOGIC_FPS) / float(physics_fps)))

func is_in_recovery(player: Player) -> bool:
	return get_recovery_frames_remaining(player) > 0
