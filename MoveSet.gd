class_name MoveSet extends Node

# ============================================================
# MOVE DATA STRUCTURE - Single source of truth
# ============================================================

class MoveData:
	var name: String
	var character_requirement: String  # "DAV", "DEN", or "*"
	var damage: float
	var knockback: float
	var hitstun: int = 18  # 🟢 新增: 被击中後的參數(邏輯幀)，預設 18
	var blockstun: int = 10  # 🟢 新增: 被格擋後的參数(邏輯幀)，預設 10
	var duration: float
	var move_distance: float
	var jump_delay: float
	var jump_speed: float
	var is_freeze: bool
	var is_projectile: bool
	var gravity: float = 0.0
	var sound_type: String  # "special" or "fireball"
	var penetrable: bool = false  # For pushbox penetration
	var acceleration_curve: String = "none"  # "none", "decelerate", "accelerate", "three_phase"
	# Three-phase movement parameters (for three_phase curve)
	var stationary_ratio: float = 0.0  # 不動階段的時間比例 (0.0-1.0)
	var acceleration_ratio: float = 0.0  # 加速階段的時間比例 (0.0-1.0)
	var deceleration_ratio: float = 0.0  # 減速階段的時間比例 (0.0-1.0)
	# Knockfly-specific parameters (for DP and similar moves)
	var knockfly_gravity: float = 0.0
	var knockfly_vertical_speed: float = 0.0
	var knockfly_horizontal_speed: float = 0.0
	
	func _init(
		p_name: String,
		p_char: String,
		p_damage: float,
		p_knockback: float,
		p_duration: float,
		p_move_distance: float,
		p_jump_delay: float = 0.0,
		p_jump_speed: float = 0.0,
		p_is_freeze: bool = false,
		p_is_projectile: bool = false,
		p_gravity: float = 0.0,
		p_sound: String = "special",
		p_penetrable: bool = false,
		p_acceleration_curve: String = "none",
		p_stationary_ratio: float = 0.0,
		p_acceleration_ratio: float = 0.0,
		p_deceleration_ratio: float = 0.0,
		p_knockfly_gravity: float = 0.0,
		p_knockfly_vertical_speed: float = 0.0,
		p_knockfly_horizontal_speed: float = 0.0,
		p_hitstun: int = 18,  # 🟢 新增: 預設 18
		p_blockstun: int = 10  # 🟢 新增: 預設 10
	):
		name = p_name
		character_requirement = p_char
		damage = p_damage
		knockback = p_knockback
		hitstun = p_hitstun  # 🟢 新增
		blockstun = p_blockstun  # 🟢 新增
		duration = p_duration
		move_distance = p_move_distance
		jump_delay = p_jump_delay
		jump_speed = p_jump_speed
		is_freeze = p_is_freeze
		is_projectile = p_is_projectile
		gravity = p_gravity
		sound_type = p_sound
		penetrable = p_penetrable
		acceleration_curve = p_acceleration_curve
		stationary_ratio = p_stationary_ratio
		acceleration_ratio = p_acceleration_ratio
		deceleration_ratio = p_deceleration_ratio
		knockfly_gravity = p_knockfly_gravity
		knockfly_vertical_speed = p_knockfly_vertical_speed
		knockfly_horizontal_speed = p_knockfly_horizontal_speed

# ============================================================
# RUNTIME STATE - Only track active move states
# ============================================================

class MoveState:
	var active_move: MoveData
	var timer: float = 0.0
	var jump_timer: float = 0.0
	var has_jumped: bool = false
	var initial_facing: float = 0.0
	var initial_parent_scale_x: float = 0.0
	var initial_sprite_scale_x: float = 0.0
	# Acceleration curve tracking
	var initial_speed: float = 0.0
	var total_duration: float = 0.0
	
	func reset() -> void:
		active_move = null
		timer = 0.0
		jump_timer = 0.0
		has_jumped = false

# ============================================================
# MOVE DEFINITIONS
# ============================================================

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
	# DAV moves
	move_library["powerkk"] = MoveData.new(
		"powerkk", "DAV", 12.0, 600.0, 56.0, 150.0, 0.0, 0.0, false, false, 0.0, "special", false, "three_phase", 0.25, 0.2, 0.55, 0.0, 0.0, 0.0, 39, 23
	)
	move_library["super"] = MoveData.new(
		"super", "DAV", 5.0, 200.0, 156.0, 200.0, 54.0, -210.0, true, false, 200000.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 27, 18
	)
	move_library["dp"] = MoveData.new(
		"dp", "DAV", 5.0, 320.0, 54.0, 200.0, 4.0, -2000.0, false, false, 6200000.0, "special", true, "none", 0.0, 0.0, 0.0,
		6200000.0, -2700.0, 20.0, 39, 23  # 🟢 knockfly_horizontal_speed: 100→20 (防止閃飛太遠)
	)
	
	# DEN moves
	move_library["spnk"] = MoveData.new(
		"spnk", "DEN", 12.0, 280.0, 72.0, 250.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 27, 23
	)
	move_library["hdk"] = MoveData.new(
		"hdk", "DEN", 3.0, 290.0, 66.0, 200.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 27, 23
	)
	
	# Universal moves
	move_library["fireball"] = MoveData.new(
		"fireball", "*", 10.0, 80.0, 18.0, 0.0, 0.0, 0.0, false, true, 0.0, "fireball", true, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 24, 14
	)

# ============================================================
# START SPECIAL MOVE (Generic, handles ALL moves)
# ============================================================

func _start_special(move_name: String) -> void:
	if move_name not in move_library:
		push_error("Move '%s' not found in move library" % move_name)
		return
	
	print("[MoveSet._start_special] Starting move: %s (player: %s)" % [move_name, parent.name])
	
	var move_data: MoveData = move_library[move_name]
	var character_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	
	# Character requirement check
	if move_data.character_requirement != "*" and character_id != move_data.character_requirement:
		print("[MoveSet] %s tried to use %s but character doesn't match (requires %s)" % [parent.name, move_name, move_data.character_requirement])
		return
	
	# State check
	if parent.is_attacking or is_spmove:
		print("[MoveSet] %s cannot use %s: already attacking or in special move" % [parent.name, move_name])
		return
	
	# Set up move state
	is_spmove = true
	is_special_moving = true
	is_spmove_animation_playing = true
	
	current_move_state.active_move = move_data
	# 🟢 將邏輯幀轉換為秒數（邏輯幀基於 60 FPS）
	current_move_state.timer = move_data.duration / 60.0
	# 🟢 將邏輯幀轉換為秒數
	current_move_state.jump_timer = move_data.jump_delay / 60.0
	current_move_state.has_jumped = false
	current_move_state.initial_facing = parent.facing_direction
	current_move_state.initial_parent_scale_x = parent.scale.x
	current_move_state.initial_sprite_scale_x = sprite.scale.x
	
	# Projectile spawning is now handled via AnimationPlayer Call Method (_spawn_fireball)
	
	# Update parent
	parent.current_damage = move_data.damage
	parent.attack_type = move_name
	
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	if "is_special_moving" in parent:
		parent.is_special_moving = true
	
	# Calculate velocity
	var world = get_tree().get_first_node_in_group("world")
	if world and move_data.move_distance > 0:
		var base_speed = (move_data.move_distance / (move_data.duration / 60.0)) * world.SIMULATION_SCALE * parent.facing_direction
		current_move_state.initial_speed = base_speed
		current_move_state.total_duration = move_data.duration / 60.0  # 🟢 轉換為秒數
		
		# Set initial velocity based on acceleration curve
		if move_data.acceleration_curve == "accelerate":
			parent.fixed_velocity.x = 0  # Start from zero for acceleration
		elif move_data.acceleration_curve == "decelerate":
			parent.fixed_velocity.x = int(base_speed)  # Start at full speed for deceleration
		elif move_data.acceleration_curve == "three_phase":
			parent.fixed_velocity.x = 0  # Start stationary for three-phase
		else:
			parent.fixed_velocity.x = int(base_speed)  # Constant speed
	else:
		parent.fixed_velocity = Vector2i.ZERO
		current_move_state.initial_speed = 0.0
		current_move_state.total_duration = 0.0
	
	# Play animation via AnimationTree state machine (same as normal attacks)
	if animation_player and animation_player.has_animation(move_name):
		var anim = animation_player.get_animation(move_name)
		current_move_state.timer = anim.length
		print("[MoveSet._start_special] Animation '%s' found, length: %.3f seconds" % [move_name, anim.length])
	else:
		print("[MoveSet._start_special] WARNING: Animation '%s' not found!" % move_name)
	
	# Use AnimationTree.travel() (prevents dual playback with AnimationPlayer)
	# parent is Movement which has animation_state
	if parent and "animation_state" in parent:
		print("[MoveSet._start_special] Playing via AnimationTree.travel(): %s" % move_name)
		parent.animation_state.travel(move_name)
	else:
		print("[MoveSet._start_special] Fallback: Playing via AnimationPlayer.play(): %s" % move_name)
		animation_player.play(move_name)
	
	# Freeze if needed
	if move_data.is_freeze:
		freeze_game(super_freeze_time)
	
	# Play sound
	var sound_player = parent.get_node_or_null("FireballCallPlayer" if move_data.is_projectile else "SpecialCallPlayer")
	if sound_player:
		sound_player.volume_db = 0.0
		sound_player.play()
	
	print("[MoveSet] Started %s! Character: %s, Duration: %.3f" % [move_name, character_id, current_move_state.timer])

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

func start_hdk() -> void:
	_start_special("hdk")

func start_fireball() -> void:
	if parent.is_attacking or is_spmove:
		print("[MoveSet] %s: Cannot start fireball - is_attacking=%s, is_spmove=%s" % [parent.name, parent.is_attacking, is_spmove])
		return
	# 檢查是否已有活躍的 fireball（同一時間只能有一個）
	if parent.active_fireball != null and is_instance_valid(parent.active_fireball):
		print("[MoveSet] %s: Cannot start fireball - active_fireball already exists" % parent.name)
		return
	print("[MoveSet] %s: Starting fireball (AI=%s)" % [parent.name, parent.is_ai_controlled])
	_start_special("fireball")

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
	
	is_spmove = false
	is_special_moving = false
	is_spmove_animation_playing = false
	
	animation_player.stop()
	
	if "is_facing_locked" in parent:
		parent.is_facing_locked = false
	if "is_special_moving" in parent:
		parent.is_special_moving = false
	
	parent.force_update_facing_direction()
	
	# 如果玩家处于 knockfly 状态，不清零速度（保留击飞的垂直/水平速度）
	if not parent.is_knockfly:
		parent.fixed_velocity = Vector2i.ZERO
	
	var world = get_tree().get_first_node_in_group("world")
	if world and parent.is_jumping and parent.fixed_position.y >= world.FLOOR_Y:
		parent.is_jumping = false
		parent.fixed_velocity.y = 0
		parent.fixed_position.y = world.FLOOR_Y
	
	current_move_state.reset()

# ============================================================
# UNIFIED MOVE PROCESSING
# ============================================================

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if parent.is_hit or parent.is_knockfly:
		if is_spmove: stop_special_move()
		return false
	if not is_valid_state:
		# Removed verbose logging - this is normal behavior during action commitment
		return false
	
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		push_warning("World node missing")
		return false
	
	# Input triggers
	if _handle_input(input_data, world):
		return true
	
	# If no active move, nothing to process
	if not is_spmove or current_move_state.active_move == null:
		return false
	
	var move = current_move_state.active_move
	
	# Handle projectile spawning
	if move.is_projectile:
		_process_projectile_spawn(delta, world)
	
	# Handle jump logic
	if move.jump_delay > 0:
		_process_jump(delta, world, move)
	
	# Handle gravity
	if move.gravity > 0:
		_apply_gravity(delta, world, move.gravity)
	else:
		_apply_gravity(delta, world, world.GRAVITY if world else 0.0)
	
	# Update velocity based on acceleration curve
	if move.acceleration_curve != "none" and current_move_state.total_duration > 0:
		var elapsed_time = current_move_state.total_duration - current_move_state.timer
		var elapsed_ratio = elapsed_time / current_move_state.total_duration
		
		if move.acceleration_curve == "accelerate":
			# Quadratic acceleration: speed increases from 0 to max
			var speed_multiplier = elapsed_ratio * elapsed_ratio
			parent.fixed_velocity.x = int(current_move_state.initial_speed * speed_multiplier)
		elif move.acceleration_curve == "decelerate":
			# Quadratic deceleration: speed decreases from max to 0
			var remaining_ratio = current_move_state.timer / current_move_state.total_duration
			var speed_multiplier = remaining_ratio * remaining_ratio
			parent.fixed_velocity.x = int(current_move_state.initial_speed * speed_multiplier)
		elif move.acceleration_curve == "three_phase":
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
	
	# Update timer
	current_move_state.timer -= delta
	
	# Check if move is finished
	if current_move_state.timer <= 0:
		stop_special_move()
	
	return true

func _handle_input(input_data: Dictionary, _world: Node) -> bool:
	var controller = parent.get_node_or_null("PlayerController")
	
	if input_data.get("super_pressed", false) and not parent.is_attacking and not is_spmove:
		# Consume the buffered input
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("super")
		start_super()
		return true
	
	if input_data.get("dp_pressed", false) and not parent.is_attacking and not is_spmove:
		# Consume buffered DP special move (detected by motion input)
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("dp")  # Consume the special move buffer
			controller.consume_button_input("st_mp")  # Also consume trigger button
		start_dp()
		return true
	
	if input_data.get("spm2_pressed", false) and not parent.is_attacking and not is_spmove:
		if parent.is_ai_controlled:
			print("[MoveSet._handle_input] %s spm2_pressed detected (AI=true)" % parent.name)
		# Consume buffered fireball (detected by motion input)
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("fireball")  # Consume the special move buffer
			controller.consume_button_input("st_mp")  # Also consume trigger button
		start_fireball()
		return true
	
	if input_data.get("spm1_pressed", false) and not parent.is_attacking and not is_spmove:
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

func _process_projectile_spawn(delta: float, _world: Node) -> void:
	# Projectile spawning is now handled via AnimationPlayer Call Method
	# This function is deprecated and can be removed after animation setup
	pass

func execute_fireball_spawn() -> void:
	if not is_spmove or current_move_state.active_move == null or current_move_state.active_move.name != "fireball":
		return
	
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

func _process_jump(delta: float, world: Node, move: MoveData) -> void:
	current_move_state.jump_timer -= delta
	
	if current_move_state.jump_timer <= 0 and not parent.is_jumping and parent.fixed_position.y == world.FLOOR_Y and not current_move_state.has_jumped:
		parent.fixed_velocity.y = int(move.jump_speed * world.SIMULATION_SCALE)
		parent.fixed_position.y = world.FLOOR_Y - 1
		parent.is_jumping = true
		current_move_state.has_jumped = true

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
	print("[MoveSet._on_spmove_animation_finished] Animation finished: %s (is_spmove=%s)" % [anim_name, is_spmove])
	if is_spmove_animation_playing and anim_name in move_library:
		print("[MoveSet._on_spmove_animation_finished] ✓ Special move animation completed: %s" % anim_name)
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
		return current_move_state.active_move.name
	return ""

# ============================================================
# HELPER: Check if specific move is active
# ============================================================

func is_move_active(move_name: String) -> bool:
	return is_spmove and current_move_state.active_move and current_move_state.active_move.name == move_name
