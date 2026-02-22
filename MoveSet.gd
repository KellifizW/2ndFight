class_name MoveSet extends Node

const SpecialMoveData = preload("res://data/SpecialMoveData.gd")

# 【Frame-based 計時系統】
static var PHYSICS_FPS: int = 120  # 動態設置為實際物理 FPS（由 _ready 更新）
const LOGIC_FPS: int = 60  # 遊戲邏輯基準 FPS（用於動畫時長轉換）

# ============================================================
# SPECIAL MOVE DATA (Resource-driven) - Now Exportable!
# ============================================================

# ✨ 新：在 Inspector 中直観地管理特殊招式资源（像 AttackData 一样）
@export var special_moves_data: Array[SpecialMoveData] = []
@export var startup_logs: bool = false

# 【旧版本缓冲】保留硬编码路径作为后备
const LEGACY_SPECIAL_MOVE_RESOURCES: Array[String] = [
	"res://data/specials/dav_powerkk.tres",
	"res://data/specials/dav_super.tres",
	"res://data/specials/dav_dp.tres",
	"res://data/specials/dav_dpL.tres",
	"res://data/specials/dav_dpM.tres",
	"res://data/specials/dav_dpH.tres",
	"res://data/specials/dav_100p.tres",
	"res://data/specials/den_spnk.tres",
	"res://data/specials/den_hdk.tres",
	"res://data/specials/dav_fireball.tres",
	"res://data/specials/dav_fireballL.tres",
	"res://data/specials/dav_fireballM.tres",
	"res://data/specials/dav_fireballH.tres",
	"res://data/specials/den_fireball.tres"
]

# ============================================================
# RUNTIME STATE - Only track active move states
# ============================================================

class MoveState:
	var active_move
	var timer: int = 0  # Frame-based timer
	var total_duration_frames: int = 0  # Full move duration (physics frames)
	var movement_duration_frames: int = 0  # Movement duration (physics frames)
	var start_frame: int = -1  # Global frame when move started (hitstop-aware)
	# ✅ 【新增】出招者跳躍系統
	var caster_jump_timer: int = 0  # 出招者跳躍延遲計時器（Frame-based）
	var caster_has_jumped: bool = false  # 出招者是否已跳躍
	# ✅ 【新增】軌跡延遲系統
	var trajectory_timer: int = 0  # 軌跡開始延遲計時器（Frame-based）
	var trajectory_started: bool = false  # 軌跡是否已開始
	# 向後兼容的跳躍變數（映射到新系統）
	var jump_timer: int:
		get: return caster_jump_timer
		set(value): caster_jump_timer = value
	var has_jumped: bool:
		get: return caster_has_jumped
		set(value): caster_has_jumped = value
	var projectile_spawned: bool = false
	var initial_facing: float = 0.0
	var initial_parent_scale_x: float = 0.0
	var initial_sprite_scale_x: float = 0.0
	# Acceleration curve tracking
	var initial_speed: float = 0.0
	var total_duration: float = 0.0
	
	func reset() -> void:
		active_move = null
		timer = 0
		total_duration_frames = 0
		movement_duration_frames = 0
		start_frame = -1
		caster_jump_timer = 0
		caster_has_jumped = false
		trajectory_timer = 0
		trajectory_started = false
		projectile_spawned = false

# ============================================================
# MOVE DEFINITIONS (Resource-driven)
# ============================================================

# move_library: { move_id: Array[SpecialMoveData] }
var move_library: Dictionary = {}
var current_move_state: MoveState = MoveState.new()

@export var fireball_y_offset: float = -40.0
@export var fireball_x_offset: float = 40.0
@export var super_freeze_time: float = 0.3

# Global state flags
var is_spmove: bool = false
var is_special_moving: bool = false
var is_spmove_animation_playing: bool = false

@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready() -> void:
	_initialize_move_library()
	
	# 【初始化物理 FPS】
	PHYSICS_FPS = Engine.physics_ticks_per_second
	
	if not parent or not hitbox or not animation_player or not sprite:
		push_warning("MoveSet initialization failed: missing required nodes")
	
	if animation_player and not animation_player.animation_finished.is_connected(_on_spmove_animation_finished):
		animation_player.animation_finished.connect(_on_spmove_animation_finished)
	
	if parent.has_signal("hit_detected"):
		parent.hit_detected.connect(_on_hit_detected)
	
	var special_player = parent.get_node_or_null("SpecialCallPlayer")
	var fireball_player = parent.get_node_or_null("FireballCallPlayer")
	if special_player: special_player.volume_db = 0.0
	if fireball_player: fireball_player.volume_db = 0.0

func _initialize_move_library() -> void:
	move_library.clear()
	
	# 【优先】使用 export 导入的资源 (Inspector 中手动设置)
	var resources_to_load: Array = special_moves_data.duplicate()
	
	# 【后备】如果 export 未设置，使用旧版本硬编码路径
	if resources_to_load.is_empty():
		if startup_logs:
			print("[MoveSet] 检测到 special_moves_data 为空，自动加载旧版本资源...")
		for path in LEGACY_SPECIAL_MOVE_RESOURCES:
			var resource = load(path)
			if resource != null:
				resources_to_load.append(resource)
	
	# 构建 move_library
	for resource in resources_to_load:
		if resource == null:
			push_warning("MoveSet: Null resource in special_moves_data")
			continue
		if not resource is SpecialMoveData:
			push_warning("MoveSet: Resource is not SpecialMoveData: %s" % resource)
			continue
		var move_id = resource.move_id
		if move_id == "":
			push_warning("MoveSet: SpecialMoveData missing move_id")
			continue
		if not move_library.has(move_id):
			move_library[move_id] = []
		move_library[move_id].append(resource)
	
	if startup_logs:
		print("[MoveSet] Library initialized with %d move types: %s" % [move_library.size(), move_library.keys()])

func has_move_id(move_id: String) -> bool:
	return move_library.has(move_id)

func has_move_for_character(move_id: String, character_id: String) -> bool:
	return get_move_data_for_character(move_id, character_id) != null

func get_move_data_for_character(move_id: String, character_id: String):
	if not move_library.has(move_id):
		return null
	var candidates: Array = move_library[move_id]
	var fallback = null
	for entry in candidates:
		if entry.character_requirement == character_id:
			return entry
		if entry.character_requirement == "*":
			fallback = entry
	return fallback

# ============================================================
# START SPECIAL MOVE (Generic, handles ALL moves)
# ============================================================

func _start_special(move_name: String) -> void:
	var character_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	var source_move = get_move_data_for_character(move_name, character_id)
	if source_move == null:
		push_error("Move '%s' not found in move library" % move_name)
		return
	
	print("[MoveSet._start_special] Starting move: %s (player: %s)" % [move_name, parent.name])
	
	# Fresh AnimationPlayer lookup: @onready may cache null due to load order; re-fetch at call time.
	var ap = animation_player
	if ap == null:
		ap = parent.get_node_or_null("AnimationPlayer")
		if ap != null:
			print("  [MoveSet] Cached animation_player was null; resolved via fresh get_node_or_null.")
	
	# 為輕中重版本（fireballL/M/H, dpL/M/H）確定有效動畫名稱。
	# 如果專屬動畫不存在，則 fallback 到基礎動畫（"fireball"/"dp"）。
	var anim_name = move_name
	if move_name.length() > 1 and move_name[-1] in ["L", "M", "H"]:
		var base_name = move_name.left(move_name.length() - 1)
		if not (ap and ap.has_animation(move_name)):
			anim_name = base_name
			print("  [ANIM_FALLBACK] '%s' animation not found, using base '%s'" % [move_name, base_name])
	
	var move_data = source_move.duplicate(true)
	
	# State check
	if parent.is_attacking or is_spmove:
		print("[MoveSet] %s cannot use %s: already attacking or in special move" % [parent.name, move_name])
		return
	
	# Align duration to animation length only when duration_frames == 0
	var duration_logic_frames = int(round(move_data.duration_frames))
	var duration_physics_frames = int(round(move_data.duration_frames * 2.0))
	if duration_logic_frames <= 0 and ap and ap.has_animation(anim_name):
		var anim = ap.get_animation(anim_name)
		duration_logic_frames = int(round(anim.length * LOGIC_FPS))
		duration_physics_frames = int(round(anim.length * PHYSICS_FPS))
		move_data.duration_frames = duration_logic_frames
	elif duration_logic_frames > 0:
		duration_physics_frames = int(round(duration_logic_frames * 2.0))

	# Set up move state
	is_spmove = true
	is_special_moving = true
	is_spmove_animation_playing = true
	
	current_move_state.active_move = move_data
	current_move_state.projectile_spawned = false
	# move_data.duration 是邏輯幀數（60 FPS），需轉為物理幀數 (120 FPS)
	current_move_state.timer = duration_physics_frames
	current_move_state.total_duration_frames = duration_physics_frames
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	current_move_state.start_frame = frame_counter.get_current_frame() if frame_counter else -1
	
	# ✅ 【新增】出招者跳躍系統初始化
	if move_data.caster_jump_enabled:
		var caster_jump_delay_physics = int(round(move_data.caster_jump_delay_frames * 2.0))
		current_move_state.caster_jump_timer = caster_jump_delay_physics
		current_move_state.caster_has_jumped = false
		print("[CASTER_JUMP] %s: Enabled | delay=%d frames | vertical_speed=%.1f | gravity=%.1f" % [
			move_name, caster_jump_delay_physics, move_data.caster_jump_vertical_speed, move_data.caster_jump_gravity
		])
	else:
		current_move_state.caster_jump_timer = 0
		current_move_state.caster_has_jumped = false
	
	# ✅ 【新增】軌跡延遲系統初始化
	if move_data.trajectory_delay_frames > 0:
		var trajectory_delay_physics = int(round(move_data.trajectory_delay_frames * 2.0))
		current_move_state.trajectory_timer = trajectory_delay_physics
		current_move_state.trajectory_started = false
		print("[TRAJECTORY_DELAY] %s: %d frames before movement starts" % [move_name, trajectory_delay_physics])
	else:
		current_move_state.trajectory_timer = 0
		current_move_state.trajectory_started = true  # 立即開始
	current_move_state.initial_facing = parent.facing_direction
	current_move_state.initial_parent_scale_x = parent.scale.x
	current_move_state.initial_sprite_scale_x = sprite.scale.x
	
	var seat = parent.seat if "seat" in parent else "?"
	# 移除舊的 jump_delay 日志（已被 caster_jump 系統取代）
	
	# Projectile spawning is now handled via AnimationPlayer Call Method (_spawn_fireball)
	
	# Update parent
	parent.current_damage = move_data.damage
	parent.attack_type = move_name
	if "hit_response_handler" in parent and parent.hit_response_handler:
		parent.hit_response_handler.reset_multi_hit_state()
	
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	if "is_special_moving" in parent:
		parent.is_special_moving = true
	
	# Calculate velocity
	var movement_logic_frames = move_data.movement_duration_frames if move_data.movement_duration_frames > 0 else duration_logic_frames
	var movement_physics_frames = int(round(movement_logic_frames * 2.0)) if movement_logic_frames > 0 else 0
	current_move_state.movement_duration_frames = movement_physics_frames
	current_move_state.total_duration = float(movement_physics_frames)

	var world = get_tree().get_first_node_in_group("world")
	if world and move_data.move_distance > 0:
		# 🔴 【關鍵修復】move_data.duration 是那輯幀數，需轉換為秒數
		var duration_seconds = movement_logic_frames / 60.0  # 邏輯幀 -> 秒
		var base_speed = 0.0
		if duration_seconds > 0:
			base_speed = (move_data.move_distance / duration_seconds) * world.SIMULATION_SCALE * parent.facing_direction
		current_move_state.initial_speed = base_speed
		current_move_state.total_duration = float(movement_physics_frames)  # 移動用時
		
		# ✅ 【修正】使用枚舉型加速度，並處理軌跡延遲
		if move_data.trajectory_delay_frames > 0:
			# 如果有軌跡延遲，初始速度為 0
			parent.fixed_velocity.x = 0
		elif move_data.acceleration_curve == SpecialMoveData.AccelerationCurve.ACCELERATE:
			parent.fixed_velocity.x = 0  # Start from zero for acceleration
		elif move_data.acceleration_curve == SpecialMoveData.AccelerationCurve.DECELERATE:
			parent.fixed_velocity.x = int(base_speed)  # Start at full speed for deceleration
		elif move_data.acceleration_curve == SpecialMoveData.AccelerationCurve.THREE_PHASE:
			parent.fixed_velocity.x = 0  # Start stationary for three-phase
		else:  # NONE
			parent.fixed_velocity.x = int(base_speed)  # Constant speed
	else:
		parent.fixed_velocity = Vector2i.ZERO
		current_move_state.initial_speed = 0.0
		current_move_state.total_duration = 0.0
	
	# Play animation via AnimationTree state machine (same as normal attacks)
	var seat_str = parent.seat if "seat" in parent else "?"
	if ap and ap.has_animation(anim_name):
		var anim = ap.get_animation(anim_name)
		# Timer 已在前面對齊動畫長度
		print("[MoveSet DEBUG] Animation '%s' loaded | Duration: %.3fs | Timer: %d frames @%d FPS (physics)" % [anim_name, anim.length, current_move_state.timer, 120])
		
		# 🟢 【詳細除錯】移動參數分析
		if move_data.move_distance > 0:
			var d_secs = move_data.duration_frames / 60.0  # 🔴 duration 是邏輯幀數，轉換為秒
			var spd_sec = move_data.move_distance / d_secs if d_secs > 0 else 0.0
			var spd_frame = spd_sec / 120.0  # pixel per 120 FPS physics frame
			print("  [MOVE DEBUG] 移動距離: %.1f px, 時長: %.3f s (%d logical frames), 速度: %.1f px/s (%.3f px/frame @120FPS physics)" % [move_data.move_distance, d_secs, int(move_data.duration_frames), spd_sec, spd_frame])
	else:
		print("[MoveSet._start_special] ⚠️  WARNING: Animation '%s' not found! (Seat: %s)" % [anim_name, seat_str])
	
	# Use AnimationTree.travel() (prevents dual playback with AnimationPlayer)
	# parent is Movement which has animation_state
	if parent and "animation_state" in parent:
		var current_anim_state: String = parent.animation_state.get_current_node() if parent.animation_state else "(unknown)"
		print("[MoveSet._start_special] 🎬 Playing '%s' (anim='%s') | Current AnimTree state: '%s' | Seat: %s" % [move_name, anim_name, current_anim_state, seat_str])
		
		# 🟢 強制重置：如果已經在同一招式狀態，需要直接通過AnimationPlayer強制重啟
		if current_anim_state == anim_name:
			print("  ⚠️  Already in '%s' state! Forcing reset via AnimationPlayer..." % anim_name)
			# 直接用 AnimationPlayer.play() 強制重新開始動畫（這會重置播放位置到第0幀）
			if ap:
				ap.play(anim_name)
				print("  ✓ AnimationPlayer.play('%s') called - animation restarted from frame 0" % anim_name)
		else:
			# 正常情況：使用 travel()
			parent.animation_state.travel(anim_name)
			print("  ✓ AnimTree travel() called | New state: '%s'" % anim_name)
	else:
		print("[MoveSet._start_special] Fallback: Playing via AnimationPlayer.play(): %s" % anim_name)
		if ap:
			ap.play(anim_name)
	
	# Freeze if needed
	if move_data.is_freeze:
		freeze_game(super_freeze_time)
	
	# Play sound
	var sound_player = parent.get_node_or_null("FireballCallPlayer" if move_data.is_projectile else "SpecialCallPlayer")
	if sound_player:
		sound_player.volume_db = 0.0
		sound_player.play()
	
	print("[MoveSet] ✅ Started %s! Char: %s, Duration: %.3f, Seat: %s" % [move_name, character_id, current_move_state.timer, seat_str])

# ============================================================
# INPUT HANDLERS (Clean, DRY)
# ============================================================

func start_powerkk() -> void:
	_start_special("powerkk")

func start_spnk() -> void:
	_start_special("spnk")

func start_super() -> void:
	_start_special("super")

func start_dp() -> void:
	_start_special("dp")

func start_dpL() -> void:
	_start_special("dpL")

func start_dpM() -> void:
	_start_special("dpM")

func start_dpH() -> void:
	_start_special("dpH")

func start_hdk() -> void:
	_start_special("hdk")

func _can_start_fireball(variant: String) -> bool:
	if parent.is_attacking or is_spmove:
		print("[MoveSet] %s: Cannot start %s - is_attacking=%s, is_spmove=%s" % [parent.name, variant, parent.is_attacking, is_spmove])
		return false
	if parent.active_fireball != null and is_instance_valid(parent.active_fireball):
		print("[MoveSet] %s: Cannot start %s - active_fireball already exists" % [parent.name, variant])
		return false
	return true

func start_fireball() -> void:
	if not _can_start_fireball("fireball"): return
	print("[MoveSet] %s: Starting fireball (AI=%s)" % [parent.name, parent.is_ai_controlled])
	_start_special("fireball")

func start_fireballL() -> void:
	if not _can_start_fireball("fireballL"): return
	print("[MoveSet] %s: Starting fireballL" % parent.name)
	_start_special("fireballL")

func start_fireballM() -> void:
	if not _can_start_fireball("fireballM"): return
	print("[MoveSet] %s: Starting fireballM" % parent.name)
	_start_special("fireballM")

func start_fireballH() -> void:
	if not _can_start_fireball("fireballH"): return
	print("[MoveSet] %s: Starting fireballH" % parent.name)
	_start_special("fireballH")

# === Freeze logic ===
func freeze_game(duration: float) -> void:
	var tween = create_tween().set_ignore_time_scale(true)
	Engine.time_scale = 0.0
	tween.tween_interval(duration)
	tween.tween_property(Engine, "time_scale", 1.0, 0.1)
	tween.tween_callback(resume_after_freeze)

func resume_after_freeze() -> void:
	if animation_player and animation_player.current_animation == "super":
		animation_player.play()

# ============================================================
# STOP ALL SPECIAL MOVES
# ============================================================

func stop_special_move() -> void:
	if not is_spmove:
		return
	
	var move_name = current_move_state.active_move.move_id if current_move_state.active_move else "UNKNOWN"
	var seat_str = parent.seat if "seat" in parent else "?"
	var call_stack = get_stack()  # 获取调用栈
	var caller = ""
	if call_stack.size() > 1:
		caller = call_stack[1].source  # 显示调用者的源文件
	
	# 检查此时parent是否处于knockfly或其他状态
	var parent_state = ""
	if "is_knockfly" in parent:
		parent_state += "knockfly=%s " % parent.is_knockfly
	if "is_hit" in parent:
		parent_state += "is_hit=%s " % parent.is_hit
	if "is_jumping" in parent:
		parent_state += "jumping=%s " % parent.is_jumping
	if "fixed_velocity" in parent:
		parent_state += "vel.y=%d" % parent.fixed_velocity.y
	
	print("[STOP_MOVE] 🛑 '%s' | Seat: %s | Caller: %s | Parent state: %s" % [move_name, seat_str, caller, parent_state])
	
	is_spmove = false
	is_special_moving = false
	is_spmove_animation_playing = false
	
	animation_player.stop()
	
	if "is_facing_locked" in parent:
		parent.is_facing_locked = false
	if "is_special_moving" in parent:
		parent.is_special_moving = false
	
	parent.force_update_facing_direction()
	
	# ========== 【關鍵修改】Jump保護邏輯 ==========
	# 如果特殊招式執行過jump（如DP），檢查是否已經著地
	var has_jumped = current_move_state.has_jumped if current_move_state else false
	var seat_for_log = parent.seat if "seat" in parent else "?"
	var vel_before = parent.fixed_velocity.y if "fixed_velocity" in parent else 0
	var world = get_tree().get_first_node_in_group("world")
	var is_on_ground = parent.fixed_position.y >= (world.FLOOR_Y if world else 200000)
	
	print("[STOP_MOVE_DEBUG] %s: has_jumped=%s, vel_before=%d, is_on_ground=%s, knockfly=%s" % [
		seat_for_log, has_jumped, vel_before, is_on_ground, parent.is_knockfly
	])
	
	# 【業界標準】DP動畫包含著地幀（extended animation）
	# 如果DP已經著地，不要恢復is_jumping
	# 如果DP還在空中，保留is_jumping讓下一幀著地
	if has_jumped and not is_on_ground:
		# 還在空中，保留jumping狀態
		print("[STOP_MOVE_DEBUG] %s: PRESERVED is_jumping=true (still in air)" % seat_for_log)
		parent.is_jumping = true
	elif has_jumped and is_on_ground:
		# 已經著地，清除jumping狀態以防止多餘著地動畫
		print("[STOP_MOVE_DEBUG] %s: CLEARED is_jumping (already on ground)" % seat_for_log)
		parent.is_jumping = false
	else:
		# 沒有jump過的特殊招式（如火球），清零速度
		if not parent.is_knockfly:
			parent.fixed_velocity = Vector2i.ZERO
			print("[STOP_MOVE_DEBUG] %s: CLEARED velocity (no jump executed)" % seat_for_log)
		else:
			print("[STOP_MOVE_DEBUG] %s: PRESERVED velocity (knockfly active)" % seat_for_log)
	
	# 重設move狀態
	current_move_state.reset()
	if "hit_response_handler" in parent and parent.hit_response_handler:
		parent.hit_response_handler.reset_multi_hit_state()

# ============================================================
# UNIFIED MOVE PROCESSING
# ============================================================

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		push_warning("World node missing")
		return false

	# Hit stop 期間：凍結特殊招式內部計時與位移，確保 frame 對齊
	if _is_hitstop_active():
		return is_spmove
	
	# ✅ 【新增】出招者跳躍保護：即使被擊中也要執行跳躍邏輯
	if is_spmove and current_move_state.active_move and current_move_state.active_move.caster_jump_enabled:
		_process_caster_jump(delta, world, current_move_state.active_move)
	
	# 如果被擊中或被擊飛，停止其他處理
	if parent.is_hit or parent.is_knockfly:
		if is_spmove: stop_special_move()
		return false
	
	if not is_valid_state:
		# Removed verbose logging - this is normal behavior during action commitment
		return false
	
	# Input triggers
	if _handle_input(input_data, world):
		return true
	
	# If no active move, nothing to process
	if not is_spmove or current_move_state.active_move == null:
		return false
	
	var move = current_move_state.active_move
	
	# ✅ 【新增】處理軌跡延遲（在移動開始前的等待時間）
	if not current_move_state.trajectory_started:
		current_move_state.trajectory_timer -= 1
		if current_move_state.trajectory_timer <= 0:
			current_move_state.trajectory_started = true
			print("[TRAJECTORY_START] %s: Movement begins now!" % move.move_id)
			# 初始化速度（根據加速度曲線）
			if move.acceleration_curve == SpecialMoveData.AccelerationCurve.DECELERATE:
				parent.fixed_velocity.x = int(current_move_state.initial_speed)
			elif move.acceleration_curve == SpecialMoveData.AccelerationCurve.NONE:
				parent.fixed_velocity.x = int(current_move_state.initial_speed)
			# ACCELERATE 和 THREE_PHASE 維持 0
		else:
			# 還在等待，速度保持 0
			parent.fixed_velocity.x = 0
	
	# Handle projectile spawning
	if move.is_projectile:
		_process_projectile_spawn(delta, world)
	
	# ✅ 【移除舊的 _process_jump 調用】已被 caster_jump 系統取代
	# 舊的 jump 邏輯已在 process_move() 開始時執行
	
	# 【重要】重力現在由 GravitySystem 統一管理，在 Movement._handle_gravity() 中應用
	# 此處不再重複應用重力，避免計算重複
	# if move.gravity > 0:
	#	_apply_gravity(delta, world, move.gravity)
	
	var elapsed_frames = current_move_state.total_duration_frames - current_move_state.timer
	var movement_active = current_move_state.movement_duration_frames > 0 and elapsed_frames < current_move_state.movement_duration_frames
	if not movement_active:
		parent.fixed_velocity.x = 0
	# ✅ 【修正】使用枚舉型加速度曲線，並處理軌跡延遲
	if movement_active and move.acceleration_curve != SpecialMoveData.AccelerationCurve.NONE and current_move_state.total_duration > 0 and current_move_state.trajectory_started:
		# 🔴 【關鍵修復】elapsed_ratio 現在正確地基於幀數計算（不混亂秒數和幀數）
		var elapsed_ratio = elapsed_frames / current_move_state.total_duration
		
		if move.acceleration_curve == SpecialMoveData.AccelerationCurve.ACCELERATE:
			# Quadratic acceleration: speed increases from 0 to max
			var speed_multiplier = elapsed_ratio * elapsed_ratio
			parent.fixed_velocity.x = int(current_move_state.initial_speed * speed_multiplier)
		elif move.acceleration_curve == SpecialMoveData.AccelerationCurve.DECELERATE:
			# Quadratic deceleration: speed decreases from max to 0
			var remaining_ratio = current_move_state.timer / current_move_state.total_duration
			var speed_multiplier = remaining_ratio * remaining_ratio
			parent.fixed_velocity.x = int(current_move_state.initial_speed * speed_multiplier)
		elif move.acceleration_curve == SpecialMoveData.AccelerationCurve.THREE_PHASE:
			# Three-phase movement: stationary → acceleration → deceleration
			var stat_end = move.stationary_ratio
			var accel_end = stat_end + move.acceleration_ratio
			var decel_end = accel_end + move.deceleration_ratio
			
			if elapsed_ratio < stat_end:
				# Phase 1: Stationary (不動)
				parent.fixed_velocity.x = 0
			elif elapsed_ratio < accel_end:
				# Phase 2: Explosive burst with immediate max speed then deceleration (瞬間爆發最高速然後減速)
				var phase_progress = (elapsed_ratio - stat_end) / move.acceleration_ratio
				# Start at max speed and decelerate throughout
				var remaining = 1.0 - phase_progress
				var speed_multiplier = remaining * remaining  # Quadratic deceleration from max
				parent.fixed_velocity.x = int(current_move_state.initial_speed * (1.0 + speed_multiplier) * 3.5)
			elif elapsed_ratio < decel_end:
				# Phase 3: Deceleration (減速)
				var phase_progress = (elapsed_ratio - accel_end) / move.deceleration_ratio
				var remaining = 1.0 - phase_progress
				var speed_multiplier = remaining * remaining  # Quadratic deceleration
				parent.fixed_velocity.x = int(current_move_state.initial_speed * speed_multiplier * 2.0)
			else:
				# Safety: should not reach here
				parent.fixed_velocity.x = 0
	
	# Update position
	parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
	parent.global_position = world.to_scaled_vector2(parent.fixed_position)
	
	# Update timer (FRAME-BASED)
	current_move_state.timer -= 1
	
	# Check if move is finished
	if current_move_state.timer <= 0:
		stop_special_move()
	
	return true

func _handle_input(input_data: Dictionary, _world: Node) -> bool:
	var controller = parent.get_node_or_null("PlayerController")
	var attack_type = input_data.get("attack_type", "none")
	
	if input_data.get("super_pressed", false) and not parent.is_attacking and not is_spmove:
		# Consume the buffered input
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("super")
		start_super()
		return true
	
	# 【最高優先級】100p 多段連打 - 必須在所有其他特殊招式之前檢查
	if attack_type == "100p" and parent.character_id == "DAV" and not parent.is_attacking and not is_spmove:
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("100p")  # Consume the special move buffer
			controller.consume_button_input("st_mk")  # Also consume trigger button
		_start_special("100p")  # 直接啟動100p動畫
		return true
	
	if input_data.get("dp_pressed", false) and not parent.is_attacking and not is_spmove:
		var dv: String = input_data.get("dp_variant", "dp")
		if dv == "": dv = "dp"
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input(dv)   # Consume the L/M/H or generic dp buffer
			# Also consume old "dp" slot if different (AI/legacy path)
			if dv != "dp": controller.consume_button_input("dp")
			# Consume trigger button based on strength
			if dv.ends_with("L"): controller.consume_button_input("st_lp")
			elif dv.ends_with("H"): controller.consume_button_input("st_hp")
			else: controller.consume_button_input("st_mp")
		match dv:
			"dpL": start_dpL()
			"dpH": start_dpH()
			"dpM": start_dpM()
			_:    start_dp()
		return true
	
	if input_data.get("spm2_pressed", false) and not parent.is_attacking and not is_spmove:
		var fv: String = input_data.get("fireball_variant", "fireball")
		if fv == "": fv = "fireball"
		if parent.is_ai_controlled:
			print("[MoveSet._handle_input] %s spm2_pressed detected (AI=true, variant=%s)" % [parent.name, fv])
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input(fv)   # Consume the L/M/H or generic fireball buffer
			if fv != "fireball": controller.consume_button_input("fireball")
			if fv.ends_with("L"): controller.consume_button_input("st_lp")
			elif fv.ends_with("H"): controller.consume_button_input("st_hp")
			else: controller.consume_button_input("st_mp")
		match fv:
			"fireballL": start_fireballL()
			"fireballH": start_fireballH()
			"fireballM": start_fireballM()
			_:           start_fireball()
		return true
	
	if input_data.get("spm1_pressed", false) and not parent.is_attacking and not is_spmove:
		# 只有在 attack_type 不是 100p 時才執行 powerkk/spnk
		# （如果是100p，會在上面已經處理過了）
		if attack_type != "100p":
			# Consume appropriate buffered special move
			if controller and controller.has_method("consume_button_input"):
				if parent.character_id == "DAV":
					controller.consume_button_input("powerkk")  # Consume the special move buffer
					controller.consume_button_input("st_mp")  # Also consume trigger button
				elif parent.character_id == "DEN":
					controller.consume_button_input("spnk")  # Consume the special move buffer
					controller.consume_button_input("st_mk")  # Also consume trigger button
			
			if parent.character_id == "DAV":
				start_powerkk()
			elif parent.character_id == "DEN":
				start_spnk()
			return true
	
	if input_data.get("spm3_pressed", false) and parent.character_id == "DEN" and not parent.is_attacking and not is_spmove:
		# Consume buffered HDK
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("hdk")  # Consume the special move buffer
			controller.consume_button_input("st_mk")  # Also consume trigger button
		start_hdk()
		return true
	
	return false

func _process_projectile_spawn(_delta: float, _world: Node) -> void:
	# Projectile spawning is now handled via AnimationPlayer Call Method
	# This function is deprecated and can be removed after animation setup
	pass

func execute_fireball_spawn() -> void:
	if not is_spmove or current_move_state.active_move == null:
		return
	var _fid = current_move_state.active_move.move_id
	if not (_fid == "fireball" or _fid.begins_with("fireball")):
		return
	if current_move_state.projectile_spawned:
		return
	current_move_state.projectile_spawned = true
	
	# 使用預載和預熱的資源（零卡頓）
	var preloader = get_tree().get_first_node_in_group("resource_preloader")
	if not preloader:
		push_error("ResourcePreloadManager not found")
		return
	
	var fireball_scene: PackedScene = preloader.get_fireball_scene(parent.character_id)
	if not fireball_scene:
		push_error("Fireball scene not found for character: %s" % parent.character_id)
		return
	
	var fb = fireball_scene.instantiate()
	fb.direction = parent.facing_direction
	fb.owner_character_id = parent.character_id
	fb.fireball_owner = parent
	# 🟢 fireball 現在從 _get_fireball_params_from_moveset() 讀取所有參數（單一來源）
	fb.global_position = parent.global_position + Vector2(fireball_x_offset * parent.facing_direction, fireball_y_offset)
	get_tree().current_scene.add_child(fb)
	parent.active_fireball = fb
	print("[MoveSet.execute_fireball_spawn] Fireball spawned for %s, params from MoveSet" % parent.name)

func _process_caster_jump(_delta: float, world: Node, move) -> void:
	"""✅ 【新增】處理出招者跳躍系統（如升龍拳）"""
	current_move_state.caster_jump_timer -= 1  # Frame-based decrement
	
	# Jump 條件：計時到期 + 尚未跳過
	# 🔴 【特殊招式jump】不檢查is_on_floor()，因為DP可能在前一個jump中或animation中
	# 只要計時到期且未jump過，就執行jump
	var timer_ready = current_move_state.caster_jump_timer <= 0
	var not_jumped_yet = not current_move_state.caster_has_jumped
	
	var move_name = move.move_id if move else "unknown"
	var seat = parent.seat if "seat" in parent else "?"
	
	if timer_ready and not_jumped_yet:
		# ✅ caster_jump_vertical_speed 是邏輯值，乘以SIMULATION_SCALE得到固定點速度
		var scale = world.SIMULATION_SCALE if world else 1000
		parent.fixed_velocity.y = int(move.caster_jump_vertical_speed * scale)
		parent.fixed_position.y = world.FLOOR_Y - 1 if world else 199999
		parent.is_jumping = true
		current_move_state.caster_has_jumped = true
		print("[CASTER_JUMP_TRIGGERED] %s: %s | velocity.y=%d | vertical_speed=%.1f | is_on_floor=%s" % [
			seat, move_name, parent.fixed_velocity.y, move.caster_jump_vertical_speed, parent.is_on_floor()
		])
	elif timer_ready and current_move_state.caster_has_jumped:
		pass  # Already jumped
	elif current_move_state.caster_jump_timer > 0 and not current_move_state.caster_has_jumped:
		pass  # Waiting for jump timer

# @deprecated 向後兼容：保留舊的 _process_jump 函數名稱
func _process_jump(delta: float, world: Node, move) -> void:
	_process_caster_jump(delta, world, move)

func _apply_gravity(delta: float, world: Node, gravity: float) -> void:
	if parent.fixed_position.y < world.FLOOR_Y:
		parent.fixed_velocity.y += int(gravity * delta)
		if parent.fixed_position.y >= world.FLOOR_Y:
			parent.fixed_position.y = world.FLOOR_Y
			parent.fixed_velocity.y = 0
			parent.is_jumping = false
# ============================================================
# UTILITY FUNCTIONS
# ============================================================

func _on_spmove_animation_finished(anim_name: String) -> void:
	if is_spmove_animation_playing and has_move_id(anim_name):
		is_spmove_animation_playing = false
		if "is_special_moving" in parent:
			parent.is_special_moving = false
		
		if current_move_state.timer > 0:
			return
		
		stop_special_move()
		parent.force_update_facing_direction()

func _on_hit_detected(_target: String, _stun: float, is_blocked: bool, _was_stun: bool) -> void:
	# Hit detection for penetrable moves
	if current_move_state.active_move and current_move_state.active_move.penetrable:
		current_move_state.active_move.penetrable = not is_blocked

func get_special_damage() -> float:
	if is_spmove and current_move_state.active_move:
		return current_move_state.active_move.damage
	return 0.0

# ============================================================
# HELPER: Get active move name
# ============================================================

func get_active_move_name() -> String:
	if is_spmove and current_move_state.active_move:
		return current_move_state.active_move.move_id
	return ""

func get_active_move_elapsed_frames() -> int:
	if not is_spmove or current_move_state.active_move == null:
		return 0
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter and current_move_state.start_frame >= 0:
		return max(0, frame_counter.get_current_frame() - current_move_state.start_frame)
	return current_move_state.total_duration_frames - current_move_state.timer

func _is_hitstop_active() -> bool:
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter and "is_paused" in frame_counter:
		return frame_counter.is_paused
	var slowmo = get_tree().root.get_node_or_null("World/SlowMoController")
	if slowmo and "is_hit_slowmo" in slowmo:
		return slowmo.is_hit_slowmo
	return false

# ============================================================
# HELPER: Check if specific move is active
# ============================================================

func is_move_active(move_name: String) -> bool:
	return is_spmove and current_move_state.active_move and current_move_state.active_move.move_id == move_name
