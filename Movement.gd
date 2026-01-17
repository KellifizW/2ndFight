class_name Movement extends Node2D

@onready var player: Player = owner as Player

var is_crouch_transition_played: bool = false
var healthbar: Node = null
var world: Node

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var groundsmoke: GPUParticles2D = $groundsmoke if has_node("groundsmoke") else null

# ── Controllers (自動化管理) ───────────────
@onready var animation_controller = $AnimationController if has_node("AnimationController") else null
@onready var dash_controller = $DashController if has_node("DashController") else null
@onready var blocking_controller = $BlockingController if has_node("BlockingController") else null
@onready var knockfly_controller = $KnockflyController if has_node("KnockflyController") else null

# ── 基本狀態 ──────────────────────────────
@export var landing_duration: float = 0.2
var is_layground: bool = false
@export var layground_duration: float = 0.2
var layground_timer: float = 0.0
var is_knockfly_animation_finished: bool = false

# ── 蹲姿專用旗標（修正版） ───────────────────
var was_crouching_last_frame: bool = false
var is_crouch_held: bool = false

# ── Knockfly 物理參數（預設值） ────────────
@export_group("Knockfly Physics")
@export var default_knockfly_gravity: float = 1700000.0
@export var default_knockfly_vertical_speed: float = -400.0
@export var default_knockfly_horizontal_speed: float = 6000.0
@export var default_air_friction: float = 200.0
@export var default_knockfly_duration: float = 0.4

# ── Knockfly 執行時實際值 ─────────────────
var knockfly_gravity: float = default_knockfly_gravity
var knockfly_vertical_speed: float = default_knockfly_vertical_speed
var knockfly_horizontal_speed: float = default_knockfly_horizontal_speed
var air_friction: float = default_air_friction
var knockfly_duration: float = default_knockfly_duration
@export var air_hit_backjump_speed: float = 400.0
@export var air_hit_backjump_duration: float = 0.2
@export var air_hit_backjump_up_speed: float = -800.0
var is_air_hit_backjump: bool = false
var air_hit_backjump_timer: float = 0.0
var pending_jump_b_seek: float = -1.0

# ── 空中受擊專用 ─────────────────────────
var is_air_hit_knockfly: bool = false
var knockfly_velocity_x: float = 0.0
var knockfly_accumulated_distance: float = 0.0
var knockfly_max_distance: float = 150.0

# ── 核心物理變數 ──────────────────────────
var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0

# ── 移動參數 ──────────────────────────────
var walk_speed: float = 270.0
var back_speed: float = walk_speed * 0.75
var jump_vertical_speed: float = -2100.0
var jump_horizontal_speed: float = 350.0
var jump_dir: float = 0.0
var is_jumping: bool = false

# ── 衝刺參數 ──────────────────────────────
var is_dashing: bool = false
var is_backdashing: bool = false
var is_attacking: bool = false
var dash_speed: float = 500.0
var backdash_speed: float = 400.0
var dash_time: float = 0.35
var backdash_time: float = 0.35
var dash_timer: float = 0.0
var double_tap_timer: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0

# ── 狀態旗標 ──────────────────────────────
var is_crouching: bool = false
var is_hit: bool = false
var is_knockfly: bool = false
var hit_timer: float = 0.0
var block_timer: float = 0.0
var knockfly_timer: float = 0.0

# ── Proximity Block 專用旗標 ──
var is_proximity_blocking: bool = false

# ── 推擠參數 ──────────────────────────────
@export_group("Push Parameters")
@export var block_push_distance: float = 250.0
var is_immune_to_floor_snap: bool = false
var floor_snap_immunity_timer: float = 0.0
@export var floor_snap_immunity_duration: float = 0.1
var block_push_timer: float = 0.0
var initial_blockstun: float = 0.0
var block_push_velocity: float = 0.0
@export var hit_push_distance: float = 250.0
var hit_push_timer: float = 0.0
var initial_hitstun: float = 0.0
var hit_push_velocity: float = 0.0

# ── 方向與防禦 ───────────────────────────
var facing_direction: float = 1.0
var dash_direction: float = 0.0
var is_blocking: bool = false
var is_holding_back: bool = false
var is_crouch_blocking: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"

# ── 追蹤變數 ──────────────────────────────
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false
var is_push_back: bool = false
var push_back_timer: float = 0.0
var initial_push_back: float = 0.0
var push_back_velocity: float = 0.0
var just_jumped: bool = false
var landing_facing_lock: bool = false
var jump_delay_timer: float = 0.0
@export var jump_delay_duration: float = 0.067

func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	var retry_count: int = 0
	while not world and retry_count < 5:
		await get_tree().create_timer(0.1).timeout
		world = get_tree().get_first_node_in_group("world")
		retry_count += 1
	
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	
	if has_node("Pushbox") and $Pushbox.shape is RectangleShape2D:
		var collision_scale: Vector2 = $Pushbox.scale
		colbox_half_width = $Pushbox.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = $Pushbox.shape.size.y * collision_scale.y / 2.0
	
	if has_node("Hurtbox"):
		$Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		$Hurtbox.area_exited.connect(_on_hurtbox_area_exited)
	
	if animation_player:
		animation_player.speed_scale = 1.0
		animation_player.animation_finished.connect(_on_animation_player_finished)
	
	prev_position = global_position
	fixed_position = Vector2i(int(global_position.x * (world.SIMULATION_SCALE if world else 1000)), world.FLOOR_Y if world else 200000)
	update_facing_direction()
	knockfly_timer = 0.0
	layground_timer = 0.0
	is_knockfly_animation_finished = false
	
	# Initialize controllers if they exist
	if blocking_controller:
		blocking_controller._ready()

func _physics_process(delta: float) -> void:
	var input_data: Dictionary = get_input()
	var input_dir: int = input_data["input_dir"]
	var crouch_pressed: bool = input_data["crouch_pressed"]
	var jump_pressed: bool = input_data["jump_pressed"]
	is_crouching = crouch_pressed
	
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_moving: bool = move_set.is_special_moving if move_set and "is_special_moving" in move_set else false
	
	var scale_factor: float = world.SIMULATION_SCALE if world else 1000.0
	var floor_y: int = world.FLOOR_Y if world else 200000
	
	# ── 蹲姿狀態檢測（加強版：確保從任何狀態進入蹲下都強制播放 cr_down） ──
	if is_on_floor() and crouch_pressed and not is_blocking:
		if not was_crouching_last_frame:
			is_crouch_transition_played = false
			is_crouch_held = true
		else:
			is_crouch_transition_played = false
	was_crouching_last_frame = (is_on_floor() and crouch_pressed and not is_blocking)
	
	_handle_timers(delta)
	if blocking_controller:
		blocking_controller._handle_blocking(input_dir, is_special_moving)
	if dash_controller:
		dash_controller._handle_dash(input_dir, scale_factor, is_special_moving)
		dash_controller._handle_dash_timer(delta)
		dash_controller._handle_walk(input_dir, scale_factor, is_special_moving)
	_handle_jump(jump_pressed, input_dir, scale_factor, floor_y, is_special_moving)
	if knockfly_controller:
		knockfly_controller._handle_knockfly_layground(delta, floor_y)
	_handle_gravity(delta, move_set)
	
	fixed_position += Vector2i(roundi(fixed_velocity.x * delta), roundi(fixed_velocity.y * delta))
	
	_handle_landing(input_data, floor_y, delta)
	
	global_position = world.to_scaled_vector2(fixed_position) if world else Vector2(float(fixed_position.x) / 1000.0, float(fixed_position.y) / 1000.0)
	
	if just_jumped and fixed_velocity.y > 0:
		just_jumped = false
	
	if floor_snap_immunity_timer > 0:
		floor_snap_immunity_timer -= delta
		if floor_snap_immunity_timer <= 0:
			is_immune_to_floor_snap = false
	
	var is_landing_state: bool = ("is_landing" in self and self.is_landing and "landing_lock_timer" in self and self.landing_lock_timer > 0)
	if not (is_attacking or landing_facing_lock or is_landing_state):
		update_facing_direction()
	if is_on_floor() and was_in_air and not is_landing_state and not is_special_moving and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	was_in_air = not is_on_floor()
	if is_on_floor() and prev_position.x != global_position.x and not is_special_moving and not is_landing_state and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	
	prev_position = global_position
	
	if not ("landing_lock_timer" in self and self.landing_lock_timer > 0) and not is_layground:
		if animation_controller:
			animation_controller._update_animation_state(input_dir, crouch_pressed)
	
	post_physics_process(delta)

func _handle_timers(delta: float) -> void:
	if neutral_timer > 0:
		neutral_timer = max(0, neutral_timer - delta)
		if neutral_timer == 0:
			pending_dash_dir = 0
	
	if jump_delay_timer > 0:
		jump_delay_timer = max(0, jump_delay_timer - delta)
		if jump_delay_timer == 0:
			fixed_velocity.y = int(jump_vertical_speed * (world.SIMULATION_SCALE if world else 1000))
			just_jumped = true
			fixed_position.y = (world.FLOOR_Y if world else 200000) - 1
	
	if air_hit_backjump_timer > 0:
		air_hit_backjump_timer = max(0, air_hit_backjump_timer - delta)
		if air_hit_backjump_timer == 0:
			is_air_hit_backjump = false
			fixed_velocity = Vector2i.ZERO

func _handle_jump(jump_pressed: bool, input_dir: int, scale_factor: float, floor_y: int, is_special_moving: bool) -> void:
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing and not is_attacking and not is_special_moving and not (is_hit or is_knockfly or is_blocking or is_push_back or is_layground) and jump_delay_timer <= 0:
		jump_dir = input_dir
		is_jumping = true
		landing_facing_lock = true
		jump_delay_timer = jump_delay_duration
		fixed_position.y = floor_y - 1
		fixed_velocity.y = 0
		if jump_dir != 0:
			var jump_speed: float = jump_horizontal_speed if jump_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
			fixed_velocity.x = int(jump_speed * scale_factor * jump_dir)
		else:
			fixed_velocity.x = 0

func _handle_gravity(delta: float, move_set) -> void:
	if jump_delay_timer <= 0 and not is_on_floor() and not is_knockfly:
		var gravity: int = world.GRAVITY if world else 1800000
		if move_set and move_set.is_super:
			gravity = move_set.super_gravity
		fixed_velocity.y += int(gravity * delta)
	else:
		if not just_jumped and not is_knockfly:
			fixed_velocity.y = 0
			fixed_position.y = world.FLOOR_Y if world else 200000

func _handle_landing(input_data: Dictionary, floor_y: int, delta: float) -> void:
	if not just_jumped and fixed_position.y >= floor_y and jump_delay_timer <= 0 and fixed_velocity.y >= 0 and is_jumping:
		fixed_position.y = floor_y
		fixed_velocity.y = 0
		is_jumping = false
		just_jumped = false
		fixed_velocity.x = 0
		neutral_timer = 0.0
		pending_dash_dir = 0
		last_input_dir = 0
		landing_facing_lock = false
		
		var move_set = $MoveSet if has_node("MoveSet") else null
		if move_set and move_set.is_spmove:
			if "is_landing" in self:
				self.is_landing = false
				self.landing_lock_timer = 0.0
		else:
			if "is_landing" in self and "landing_lock_timer" in self:
				if not (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed):
					self.is_landing = true
					self.landing_lock_timer = landing_duration
		
		if groundsmoke:
			groundsmoke.scale.x = facing_direction
			groundsmoke.restart()
		
		if animation_controller:
			animation_controller._update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	var push_manager = get_tree().get_first_node_in_group("push_manager")
	if push_manager:
		push_manager._physics_process(delta)

func _on_animation_player_finished(anim_name: String) -> void:
	if animation_controller:
		animation_controller._on_animation_player_finished(anim_name)

func is_on_floor() -> bool:
	if jump_delay_timer > 0 or just_jumped:
		return false
	return fixed_position.y >= (world.FLOOR_Y if world else 200000)

func get_input() -> Dictionary:
	var input_dir: int = 0
	var crouch_pressed: bool = false
	var jump_pressed: bool = false
	
	if Input.is_action_pressed("ui_right"):
		input_dir += 1
	if Input.is_action_pressed("ui_left"):
		input_dir -= 1
	if Input.is_action_pressed("ui_down"):
		crouch_pressed = true
	if Input.is_action_just_pressed("ui_up"):
		jump_pressed = true
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed
	}

func update_hitbox_position() -> void:
	pass

func post_physics_process(_delta: float) -> void:
	pass

func get_facing_multiplier() -> float:
	return facing_direction

func get_is_dashing() -> bool:
	return is_dashing

func get_is_backdashing() -> bool:
	return is_backdashing

func get_is_attacking() -> bool:
	return is_attacking

func get_is_hit() -> bool:
	return is_hit

func get_is_knockfly() -> bool:
	return is_knockfly

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		if blocking_controller:
			blocking_controller._on_hurtbox_area_entered(area)

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		if blocking_controller:
			blocking_controller._on_hurtbox_area_exited(area)

func _set_facing(new_facing: float) -> void:
	facing_direction = new_facing
	scale.x = sign(new_facing)
	scale.y = 1
	sprite.scale.x = 1.0
	rotation_degrees = 0
	update_hitbox_position()

func update_facing_direction() -> void:
	var is_landing_state = ("is_landing" in self and self.is_landing and "landing_lock_timer" in self and self.landing_lock_timer > 0)
	if is_attacking or landing_facing_lock or is_landing_state or is_layground:
		return
	
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for p in players:
		if p != self:
			other_player = p
			break
	
	if not other_player:
		_set_facing(1.0)
		return
	
	var self_left = global_position.x - colbox_half_width
	var self_right = global_position.x + colbox_half_width
	var other_left = other_player.global_position.x - other_player.colbox_half_width
	var other_right = other_player.global_position.x - other_player.colbox_half_width
	var epsilon = 1.0
	
	if self_left > other_right + epsilon:
		_set_facing(-1.0)
	elif self_right < other_left - epsilon:
		_set_facing(1.0)
	else:
		var push_manager = get_tree().get_first_node_in_group("push_manager")
		var is_at_left_corner = push_manager.is_at_corner(self) if push_manager else false
		if is_at_left_corner:
			_set_facing(-1.0 if global_position.x > other_player.global_position.x else 1.0)
		else:
			_set_facing(facing_direction)

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	if animation_controller:
		animation_controller._set_animation_conditions(target_state, on_floor, crouch_input)

func _compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	if animation_controller:
		return animation_controller._compute_target_state(_dir_x, crouch_input, on_floor, anim_jump_dir)
	return "Walk"

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	if animation_controller:
		animation_controller._update_animation_state(dir_x, crouch_input)
