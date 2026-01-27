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

# Handler instances
var input_handler: InputHandler
var animation_manager: AnimationManager
var dash_handler: DashHandler
var jump_handler: JumpHandler
var blocking_handler: BlockingHandler
var facing_handler: FacingHandler
var walk_handler: WalkHandler
var knockfly_handler: KnockflyHandler
var gravity_handler: GravityHandler
var timer_handler: TimerHandler
var landing_handler: LandingHandler

# ── 基本狀態 ──────────────────────────────
@export var landing_duration: float = 0.2
@export var layground_duration: float = 0.2
var is_layground: bool = false
var layground_timer: float = 0.0
var is_knockfly_animation_finished: bool = false

# ── 蹲姿 ──────────────────────────────────
var was_crouching_last_frame: bool = false
var is_crouch_held: bool = false
var is_crouching: bool = false

# ── 跳躍 ──────────────────────────────────
var jump_vertical_speed: float = -2300.0
var jump_horizontal_speed: float = 450.0
var jump_dir: float = 0.0
var jump_delay_timer: float = 0.0
var just_jumped: bool = false
var is_jumping: bool = false
@export var jump_delay_duration: float = 0.067

# ── 衝刺 ──────────────────────────────────
var is_dashing: bool = false
var is_backdashing: bool = false
var dash_speed: float = 2100.0
var backdash_speed: float = 1000.0
var dash_time: float = 0.35
var backdash_time: float = 0.35
var dash_timer: float = 0.0
var dash_direction: float = 0.0
var double_tap_timer: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0
# Dash deceleration variables
var dash_initial_speed: float = 0.0
var dash_total_time: float = 0.0

# ── 移動速度 ──────────────────────────────
var walk_speed: float = 360.0
var back_speed: float = 240.0

# ── 击飛物理 ──────────────────────────────
@export_group("Knockfly Physics")
@export var default_knockfly_gravity: float = 1900000.0
@export var default_knockfly_vertical_speed: float = -400.0
@export var default_knockfly_horizontal_speed: float = 6000.0
@export var default_air_friction: float = 200.0
@export var default_knockfly_duration: float = 0.4

var knockfly_gravity: float = 1700000.0
var knockfly_vertical_speed: float = -400.0
var knockfly_horizontal_speed: float = 6000.0
var air_friction: float = 200.0
var knockfly_duration: float = 0.4
var knockfly_velocity_x: float = 0.0
var knockfly_accumulated_distance: float = 0.0
var knockfly_max_distance: float = 150.0
var is_knockfly: bool = false
var knockfly_timer: float = 0.0

# ── 空中受擊 ──────────────────────────────
var is_air_hit_backjump: bool = false
var air_hit_backjump_timer: float = 0.0
@export var air_hit_backjump_speed: float = 400.0
@export var air_hit_backjump_duration: float = 0.2
@export var air_hit_backjump_up_speed: float = -800.0
var pending_jump_b_seek: float = -1.0
var is_air_hit_knockfly: bool = false

# ── 傷害與防禦 ────────────────────────────
var is_hit: bool = false
var hit_timer: float = 0.0
var is_blocking: bool = false
var block_timer: float = 0.0
var is_holding_back: bool = false
var is_crouch_blocking: bool = false
var is_proximity_blocking: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"

# ── 推擠系統 ──────────────────────────────
@export_group("Push Parameters")
@export var block_push_distance: float = 250.0
@export var hit_push_distance: float = 250.0
@export var floor_snap_immunity_duration: float = 0.1

var initial_hitstun: float = 0.0
var hit_push_velocity: float = 0.0
var hit_push_timer: float = 0.0
var initial_blockstun: float = 0.0
var block_push_velocity: float = 0.0
var block_push_timer: float = 0.0
var initial_push_back: float = 0.0
var push_back_velocity: float = 0.0
var is_immune_to_floor_snap: bool = false
var floor_snap_immunity_timer: float = 0.0

# ── 核心物理 ──────────────────────────────
var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var facing_direction: float = 1.0
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false

# ── 狀態旗標 ──────────────────────────────
var is_attacking: bool = false
var is_push_back: bool = false
var push_back_timer: float = 0.0
var landing_facing_lock: bool = false

# ── 動畫條件（已替換 Crouch 為 cr_down 和 cr_idle） ──
var animation_conditions: Array = [
	"Walk", "cr_down", "cr_idle", "Dash", "Backdash",
	"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
	"cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
	"Jump_F", "Jump_B", "Jump_V",
	"hit", "knockfly", "block", "cr_block",
	"powerkk", "spnk", "fireball",
	"jump_mp", "jump_mk", "landing", "wakeup", "super", "dp", "hdk", "layground"
]

var anim_resets: Dictionary = {
	"layground": func(): _reset_layground_with_health_check(),
	"knockfly": func(): _reset_knockfly(),
	"st_mp": func(): _reset_attack()
}

func _reset_layground() -> void:
	is_layground = false
	is_knockfly = false
	is_knockfly_animation_finished = false
	_update_animation_state(0, false)

func _reset_knockfly() -> void:
	if is_on_floor():
		fixed_velocity = Vector2i.ZERO
		is_knockfly = false
		is_layground = true
		layground_timer = layground_duration
		is_knockfly_animation_finished = false
		_update_animation_state(0, false)
	else:
		is_knockfly_animation_finished = true
		if animation_player:
			animation_player.stop()

func _reset_attack() -> void:
	is_attacking = false
	update_facing_direction()
	if has_node("Hitbox/HitShape"):
		$Hitbox/HitShape.disabled = true

func _apply_air_friction(friction_coeff: float, delta: float) -> void:
	# Delegated to KnockflyHandler
	knockfly_handler.apply_air_friction(friction_coeff, delta)

func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	var retry_count: int = 0
	while not world and retry_count < 5:
		await get_tree().create_timer(0.1).timeout
		world = get_tree().get_first_node_in_group("world")
		retry_count += 1
	
	# Initialize handlers
	input_handler = InputHandler.new(self)
	animation_manager = AnimationManager.new(self)
	dash_handler = DashHandler.new(self)
	jump_handler = JumpHandler.new(self)
	blocking_handler = BlockingHandler.new(self)
	facing_handler = FacingHandler.new(self)
	walk_handler = WalkHandler.new(self)
	knockfly_handler = KnockflyHandler.new(self)
	gravity_handler = GravityHandler.new(self)
	timer_handler = TimerHandler.new(self)
	landing_handler = LandingHandler.new(self)
	
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
	_handle_blocking(input_dir, is_special_moving)
	_handle_dash(input_dir, scale_factor, is_special_moving)
	_handle_walk(input_dir, scale_factor, is_special_moving)
	_handle_jump(jump_pressed, input_dir, scale_factor, floor_y, is_special_moving)
	_handle_knockfly_layground(delta, floor_y)
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
		_update_animation_state(input_dir, crouch_pressed)
	
	post_physics_process(delta)

func _handle_timers(delta: float) -> void:
	timer_handler.handle_timers(delta)

func _handle_blocking(input_dir: int, is_special_moving: bool) -> void:
	blocking_handler.handle_blocking(input_dir, is_special_moving)

func _handle_dash(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	dash_handler.handle_dash(input_dir, scale_factor, is_special_moving)

func _handle_walk(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	walk_handler.handle_walk(input_dir, scale_factor, is_special_moving)

func _handle_jump(jump_pressed: bool, input_dir: int, scale_factor: float, floor_y: int, is_special_moving: bool) -> void:
	jump_handler.handle_jump(jump_pressed, input_dir, scale_factor, floor_y, is_special_moving)

func _handle_knockfly_layground(delta: float, floor_y: int) -> void:
	knockfly_handler.handle_knockfly_layground(delta, floor_y)

func _handle_gravity(delta: float, move_set) -> void:
	gravity_handler.handle_gravity(delta, move_set)

func _handle_landing(input_data: Dictionary, floor_y: int, delta: float) -> void:
	landing_handler.handle_landing(input_data, floor_y, delta)

func _on_animation_player_finished(anim_name: String) -> void:
	if anim_name in anim_resets:
		anim_resets[anim_name].call()
	if anim_name == "cr_down":
		is_crouch_transition_played = true
		if animation_state:
			animation_state.travel("cr_idle")

func is_on_floor() -> bool:
	if jump_delay_timer > 0 or just_jumped:
		return false
	return fixed_position.y >= (world.FLOOR_Y if world else 200000)

func get_input() -> Dictionary:
	return input_handler.get_input()

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
		is_opponent_proximity = true
		var player_seat = player.seat if player and "seat" in player else "?"
		print("[PROXIMITY] %s: 對手進入proximity range" % player_seat)

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false
		is_proximity_blocking = false
		var player_seat = player.seat if player and "seat" in player else "?"
		print("[PROXIMITY] %s: 對手離開proximity range" % player_seat)

func _set_facing(new_facing: float) -> void:
	facing_handler.set_facing(new_facing)

func update_facing_direction() -> void:
	facing_handler.update_facing_direction()

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	animation_manager.set_animation_conditions(target_state, on_floor, crouch_input)

func _compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	return animation_manager.compute_target_state(_dir_x, crouch_input, on_floor, anim_jump_dir)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	animation_manager.update_animation_state(dir_x, crouch_input)

func _reset_layground_with_health_check() -> void:
	knockfly_handler.reset_layground_with_health_check()
