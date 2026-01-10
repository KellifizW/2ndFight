class_name PhysicsHandler extends Node
# 引用父節點（Movement）
var movement: Movement
# ── 核心物理變數 ──────────────────────────
var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
# ── Knockfly 物理參數（預設值） ────────────
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
# ── 空中受擊專用 ─────────────────────────
var is_air_hit_knockfly: bool = false
var knockfly_velocity_x: float = 0.0
var knockfly_accumulated_distance: float = 0.0
var knockfly_max_distance: float = 150.0
# ── 移動參數 ──────────────────────────────
var walk_speed: float = 270.0
var back_speed: float = walk_speed * 0.75
var jump_vertical_speed: float = -2100.0
var jump_horizontal_speed: float = 350.0
var jump_dir: float = 0.0
# ── 衝刺參數 ──────────────────────────────
var dash_speed: float = 500.0
var backdash_speed: float = 400.0
var dash_time: float = 0.35
var backdash_time: float = 0.35
var dash_timer: float = 0.0
var double_tap_timer: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0
# ── 狀態旗標（物理相關） ──────────────────
var just_jumped: bool = false
var jump_delay_timer: float = 0.0
@export var jump_delay_duration: float = 0.067
var is_immune_to_floor_snap: bool = false
var floor_snap_immunity_timer: float = 0.0
@export var floor_snap_immunity_duration: float = 0.1
# ── 推擠參數 ──────────────────────────────
@export_group("Push Parameters")
@export var block_push_distance: float = 250.0
var block_push_timer: float = 0.0
var initial_blockstun: float = 0.0
var block_push_velocity: float = 0.0
@export var hit_push_distance: float = 250.0
var hit_push_timer: float = 0.0
var initial_hitstun: float = 0.0
var hit_push_velocity: float = 0.0
var is_push_back: bool = false
var push_back_timer: float = 0.0
var initial_push_back: float = 0.0
var push_back_velocity: float = 0.0
# ── 追蹤變數 ──────────────────────────────
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false
# ── 初始化 ────────────────────────────────
func _ready() -> void:
	movement = get_parent() as Movement
	if movement.world:
		fixed_position = Vector2i(int(movement.global_position.x * movement.world.SIMULATION_SCALE), movement.world.FLOOR_Y)
		prev_position = movement.global_position
# ── 物理更新（原 _physics_process 的物理部分） ──
func update_physics(delta: float, input_data: Dictionary, is_special_moving: bool) -> void:
	var input_dir: int = input_data["input_dir"]
	var crouch_pressed: bool = input_data["crouch_pressed"]
	var jump_pressed: bool = input_data["jump_pressed"]
	var scale_factor: float = movement.world.SIMULATION_SCALE if movement.world else 1000.0
	var floor_y: int = movement.world.FLOOR_Y if movement.world else 200000
	_handle_timers(delta)
	_handle_dash(input_dir, scale_factor, is_special_moving)
	_handle_walk(input_dir, scale_factor, is_special_moving)
	_handle_jump(jump_pressed, input_dir, scale_factor, floor_y, is_special_moving)
	_handle_knockfly_layground(delta, floor_y)
	_handle_gravity(delta, movement.get_node_or_null("MoveSet"))
	fixed_position += Vector2i(roundi(fixed_velocity.x * delta), roundi(fixed_velocity.y * delta))
	_handle_landing(input_data, floor_y, delta)
	movement.global_position = movement.world.to_scaled_vector2(fixed_position) if movement.world else Vector2(float(fixed_position.x) / 1000.0, float(fixed_position.y) / 1000.0)
	if just_jumped and fixed_velocity.y > 0:
		just_jumped = false
	if floor_snap_immunity_timer > 0:
		floor_snap_immunity_timer -= delta
	if floor_snap_immunity_timer <= 0:
		is_immune_to_floor_snap = false
	was_in_air = not movement.is_on_floor()
	if movement.is_on_floor() and prev_position.x != movement.global_position.x and not is_special_moving:
		movement.update_facing_direction()
	prev_position = movement.global_position
	var push_manager = get_tree().get_first_node_in_group("push_manager")
	if push_manager:
		push_manager._physics_process(delta)
# ── 計時器處理 ────────────────────────────
func _handle_timers(delta: float) -> void:
	if neutral_timer > 0:
		neutral_timer -= delta
		if neutral_timer <= 0:
			neutral_timer = 0.0
			pending_dash_dir = 0
	if dash_timer > 0:
		dash_timer -= delta
		if dash_timer <= 0:
			movement.is_dashing = false
			movement.is_backdashing = false
			fixed_velocity.x = 0
			neutral_timer = 0.0
			pending_dash_dir = 0
			last_input_dir = 0
			movement.landing_facing_lock = false
	if jump_delay_timer > 0:
		jump_delay_timer -= delta
		if jump_delay_timer <= 0:
			fixed_velocity.y = int(jump_vertical_speed * (movement.world.SIMULATION_SCALE if movement.world else 1000))
			just_jumped = true
			fixed_position.y = (movement.world.FLOOR_Y if movement.world else 200000) - 1
	if air_hit_backjump_timer > 0:
		air_hit_backjump_timer -= delta
		if air_hit_backjump_timer <= 0:
			is_air_hit_backjump = false
			fixed_velocity.x = 0
			fixed_velocity.y = 0
# ── 衝刺處理 ──────────────────────────────
func _handle_dash(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if movement.is_on_floor() and not movement.is_attacking and not movement.is_dashing and not movement.is_backdashing and not is_special_moving and not (movement.is_hit or movement.is_knockfly or movement.is_blocking or is_push_back or movement.is_layground) and not movement.is_crouching:
		if neutral_timer > 0 and input_dir != 0 and pending_dash_dir == input_dir:
			if input_dir * movement.facing_direction > 0:
				movement.is_dashing = true
				dash_timer = dash_time
				fixed_velocity.x = int(dash_speed * scale_factor * input_dir)
				if movement.groundsmoke:
					movement.groundsmoke.scale.x = movement.facing_direction
					movement.groundsmoke.restart()
			elif not (movement.is_blocking and movement.is_opponent_proximity and movement.block_type == "proximity"):
				movement.is_backdashing = true
				dash_timer = backdash_time
				fixed_velocity.x = int(backdash_speed * scale_factor * input_dir)
				if movement.groundsmoke:
					movement.groundsmoke.scale.x = movement.facing_direction
					movement.groundsmoke.restart()
			neutral_timer = 0.0
			pending_dash_dir = 0
			last_input_dir = 0
			movement.landing_facing_lock = true
		elif input_dir != last_input_dir:
			if last_input_dir != 0 and input_dir == 0:
				neutral_timer = double_tap_timer
				pending_dash_dir = last_input_dir
			last_input_dir = input_dir
# ── 走路處理 ──────────────────────────────
func _handle_walk(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if movement.is_on_floor() and not movement.is_attacking and not movement.is_dashing and not movement.is_backdashing and not is_special_moving and not (movement.is_hit or movement.is_knockfly or movement.is_blocking or is_push_back or movement.is_layground) and not movement.is_crouching:
		if input_dir != 0:
			if movement.is_proximity_blocking and input_dir * movement.facing_direction < 0:
				fixed_velocity.x = 0
			else:
				var move_speed: float = walk_speed if input_dir * movement.facing_direction > 0 else back_speed
				fixed_velocity.x = int(move_speed * scale_factor * input_dir)
		else:
			fixed_velocity.x = 0
	else:
		# 修正：hit/block 狀態下不強制清零，讓 pushback 持續
		if not (movement.is_hit or movement.is_blocking):
			if not (movement.is_jumping or movement.is_dashing or movement.is_backdashing or movement.is_hit or movement.is_knockfly or movement.is_blocking or is_push_back or jump_delay_timer > 0 or is_special_moving or movement.is_layground):
				fixed_velocity.x = 0
# ── 跳躍處理 ──────────────────────────────
func _handle_jump(jump_pressed: bool, input_dir: int, scale_factor: float, floor_y: int, is_special_moving: bool) -> void:
	if jump_pressed and movement.is_on_floor() and not movement.is_crouching and not movement.is_dashing and not movement.is_backdashing and not movement.is_attacking and not is_special_moving and not (movement.is_hit or movement.is_knockfly or movement.is_blocking or is_push_back or movement.is_layground) and jump_delay_timer <= 0:
		jump_dir = input_dir
		movement.is_jumping = true
		movement.landing_facing_lock = true
		jump_delay_timer = jump_delay_duration
		fixed_position.y = floor_y - 1
		fixed_velocity.y = 0
		if jump_dir != 0:
			var jump_speed: float = jump_horizontal_speed if jump_dir * movement.facing_direction > 0 else jump_horizontal_speed * 0.75
			fixed_velocity.x = int(jump_speed * scale_factor * jump_dir)
		else:
			fixed_velocity.x = 0
# ── Knockfly 和 Layground 處理 ────────────
func _handle_knockfly_layground(delta: float, floor_y: int) -> void:
	if is_air_hit_backjump:
		air_hit_backjump_timer -= delta
		var gravity: int = movement.world.GRAVITY if movement.world else 6000000
		fixed_velocity.y += int(gravity * delta)
		var friction_amount = int(default_air_friction * (movement.world.SIMULATION_SCALE if movement.world else 1000.0) * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)
		if air_hit_backjump_timer <= 0 or movement.is_on_floor():
			is_air_hit_backjump = false
			movement.is_hit = true
			return
	if movement.is_knockfly:
		movement.knockfly_timer -= delta
		fixed_velocity.y += int(knockfly_gravity * delta)
		var friction_amount = int(air_friction * (movement.world.SIMULATION_SCALE if movement.world else 1000.0) * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)
		if movement.is_on_floor():
			fixed_velocity = Vector2i.ZERO
			movement.is_knockfly = false
			movement.is_layground = true
			movement.layground_timer = movement.layground_duration
			movement.is_knockfly_animation_finished = false
			movement._update_animation_state(0, false)
			return
		if movement.knockfly_timer <= 0 and not movement.is_on_floor():
			movement.is_knockfly_animation_finished = true
			fixed_velocity.x = 0
			return
	if movement.is_layground:
		movement.layground_timer -= delta
		fixed_velocity = Vector2i.ZERO
		if movement.layground_timer <= 0:
			movement._reset_layground_with_health_check()
# ── 重力處理 ──────────────────────────────
func _handle_gravity(delta: float, move_set) -> void:
	if jump_delay_timer <= 0 and not movement.is_on_floor() and not movement.is_knockfly:
		var gravity: int = movement.world.GRAVITY if movement.world else 1800000
		if move_set and move_set.is_super:
			gravity = move_set.super_gravity
		fixed_velocity.y += int(gravity * delta)
	else:
		if not just_jumped and not movement.is_knockfly:
			fixed_velocity.y = 0
			fixed_position.y = movement.world.FLOOR_Y if movement.world else 200000
# ── 落地處理（修正：hit/block 狀態下不強制清零水平速度，讓 pushback 持續） ──────────────────────────────
func _handle_landing(input_data: Dictionary, floor_y: int, delta: float) -> void:
	if not just_jumped and fixed_position.y >= floor_y and jump_delay_timer <= 0 and fixed_velocity.y >= 0 and movement.is_jumping:
		fixed_position.y = floor_y
		fixed_velocity.y = 0
		movement.is_jumping = false
		just_jumped = false
		# 修正：如果角色在 hit 或 block 狀態，保留水平速度，讓 pushback 正常後退
		if not (movement.is_hit or movement.is_blocking):
			if not (movement.is_dashing or movement.is_backdashing or movement.is_special_moving or movement.is_jumping or dash_timer > 0):
				fixed_velocity.x = 0
		neutral_timer = 0.0
		pending_dash_dir = 0
		last_input_dir = 0
		movement.landing_facing_lock = false
		var move_set = movement.get_node_or_null("MoveSet")
		if move_set and move_set.is_spmove:
			if "is_landing" in movement.get_parent():
				movement.get_parent().is_landing = false
				movement.get_parent().landing_lock_timer = 0.0
		else:
			if "is_landing" in movement.get_parent() and "landing_lock_timer" in movement.get_parent():
				if not (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed):
					movement.get_parent().is_landing = true
					movement.get_parent().landing_lock_timer = movement.get_parent().landing_duration
		if movement.groundsmoke:
			movement.groundsmoke.scale.x = movement.facing_direction
			movement.groundsmoke.restart()
		movement._update_animation_state(input_data.input_dir, input_data.crouch_pressed)
