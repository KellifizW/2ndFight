class_name MoveSet extends Node

# ============================================================
# MOVE DATA STRUCTURE - Single source of truth
# ============================================================

class MoveData:
	var name: String
	var character_requirement: String  # "DAV", "DEN", or "*"
	var damage: float
	var knockback: float
	var duration: float
	var move_distance: float
	var jump_delay: float
	var jump_speed: float
	var is_freeze: bool
	var is_projectile: bool
	var gravity: float = 0.0
	var sound_type: String  # "special" or "fireball"
	var penetrable: bool = false  # For pushbox penetration
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
		p_knockfly_gravity: float = 0.0,
		p_knockfly_vertical_speed: float = 0.0,
		p_knockfly_horizontal_speed: float = 0.0
	):
		name = p_name
		character_requirement = p_char
		damage = p_damage
		knockback = p_knockback
		duration = p_duration
		move_distance = p_move_distance
		jump_delay = p_jump_delay
		jump_speed = p_jump_speed
		is_freeze = p_is_freeze
		is_projectile = p_is_projectile
		gravity = p_gravity
		sound_type = p_sound
		penetrable = p_penetrable
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
	var spawn_timer: float = 0.0  # For projectiles
	
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
@export var fireball_spawn_delay: float = 0.2667
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
		"powerkk", "DAV", 12.0, 300.0, 0.933, 300.0, 0.0, 0.0, false, false, 0.0, "special", false
	)
	move_library["super"] = MoveData.new(
		"super", "DAV", 5.0, 200.0, 2.6, 200.0, 0.9, -210.0, true, false, 200000.0, "special", false
	)
	move_library["dp"] = MoveData.new(
		"dp", "DAV", 5.0, 320.0, 0.9, 100.0, 0.0667, -2000.0, false, false, 6000000.0, "special", true,
		6000000.0, -2500.0, 100.0
	)
	
	# DEN moves
	move_library["spnk"] = MoveData.new(
		"spnk", "DEN", 12.0, 280.0, 1.2, 250.0, 0.0, 0.0, false, false, 0.0, "special", false
	)
	move_library["hdk"] = MoveData.new(
		"hdk", "DEN", 15.0, 290.0, 1.1, 200.0, 0.0, 0.0, false, false, 0.0, "special", false
	)
	
	# Universal moves
	move_library["fireball"] = MoveData.new(
		"fireball", "*", 10.0, 150.0, 0.3, 0.0, 0.0, 0.0, false, true, 0.0, "fireball", true
	)

# ============================================================
# START SPECIAL MOVE (Generic, handles ALL moves)
# ============================================================

func _start_special(move_name: String) -> void:
	if move_name not in move_library:
		push_error("Move '%s' not found in move library" % move_name)
		return
	
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
	current_move_state.timer = move_data.duration
	current_move_state.jump_timer = move_data.jump_delay
	current_move_state.has_jumped = false
	current_move_state.initial_facing = parent.facing_direction
	current_move_state.initial_parent_scale_x = parent.scale.x
	current_move_state.initial_sprite_scale_x = sprite.scale.x
	
	if move_data.is_projectile:
		current_move_state.spawn_timer = fireball_spawn_delay
	
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
		parent.fixed_velocity.x = int((move_data.move_distance / move_data.duration) * world.SIMULATION_SCALE * parent.facing_direction)
	else:
		parent.fixed_velocity = Vector2i.ZERO
	
	# Play animation
	if animation_player and animation_player.has_animation(move_name):
		var anim = animation_player.get_animation(move_name)
		current_move_state.timer = anim.length
	
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
	if not is_valid_state: return false
	
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
		# DP is detected by InputManager motion, but consume st_mp that triggers it
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("st_mp")
		start_dp()
		return true
	
	if input_data.get("spm2_pressed", false):
		print("[MoveSet._handle_input] %s spm2_pressed detected (AI=%s)" % [parent.name, parent.is_ai_controlled])
		# Consume the buffered input (fireball uses st_mp)
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("st_mp")
		start_fireball()
		return true
	
	if input_data.get("spm1_pressed", false) and not parent.is_attacking and not is_spmove:
		# Consume appropriate button
		if controller and controller.has_method("consume_button_input"):
			if parent.character_id == "DAV":
				controller.consume_button_input("st_mp")  # powerkk uses st_mp
			elif parent.character_id == "DEN":
				controller.consume_button_input("st_mk")  # spnk uses st_mk
		
		if parent.character_id == "DAV":
			start_powerkk()
		elif parent.character_id == "DEN":
			start_spnk()
		return true
	
	if input_data.get("spm3_pressed", false) and parent.character_id == "DEN" and not parent.is_attacking and not is_spmove:
		# Consume the buffered input (hdk uses st_mk)
		if controller and controller.has_method("consume_button_input"):
			controller.consume_button_input("st_mk")
		start_hdk()
		return true
	
	return false

func _process_projectile_spawn(delta: float, _world: Node) -> void:
	current_move_state.spawn_timer -= delta
	
	if current_move_state.spawn_timer <= 0 and current_move_state.spawn_timer > -delta:
		print("[MoveSet._process_projectile_spawn] %s attempting to spawn fireball" % parent.name)
		var scene_path = "res://%s_fireball.tscn" % parent.character_id
		var fireball_scene: PackedScene = load(scene_path)
		if fireball_scene == null:
			push_error("Cannot load fireball scene: %s" % scene_path)
			stop_special_move()
			return
		
		var fb = fireball_scene.instantiate()
		fb.direction = parent.facing_direction
		fb.owner_character_id = parent.character_id
		fb.fireball_owner = parent
		fb.global_position = parent.global_position + Vector2(fireball_x_offset * parent.facing_direction, fireball_y_offset)
		get_tree().current_scene.add_child(fb)
		print("[MoveSet] %s spawned fireball: %s at position %s" % [parent.name, scene_path, fb.global_position])

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
	if is_spmove_animation_playing and anim_name in move_library:
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
