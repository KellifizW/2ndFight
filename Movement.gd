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
var is_immune_to_floor_snap: bool = false
var floor_snap_immunity_timer: float = 0.0
@export var floor_snap_immunity_duration: float = 0.1

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

# ── 動畫條件（已替換 Crouch 為 cr_down 和 cr_idle） ──
var animation_conditions: Array = [
	"Walk", "cr_down", "cr_idle", "Dash", "Backdash",
	"st_mp", "st_mk", "cr_mp", "cr_mk",
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
	if neutral_timer > 0:
		neutral_timer -= delta
		if neutral_timer <= 0:
			neutral_timer = 0.0
			pending_dash_dir = 0
	
	if dash_timer > 0:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			is_backdashing = false
			fixed_velocity.x = 0
			neutral_timer = 0.0
			pending_dash_dir = 0
			last_input_dir = 0
			landing_facing_lock = false
	
	if jump_delay_timer > 0:
		jump_delay_timer -= delta
		if jump_delay_timer <= 0:
			fixed_velocity.y = int(jump_vertical_speed * (world.SIMULATION_SCALE if world else 1000))
			just_jumped = true
			fixed_position.y = (world.FLOOR_Y if world else 200000) - 1
	
	if air_hit_backjump_timer > 0:
		air_hit_backjump_timer -= delta
		if air_hit_backjump_timer <= 0:
			is_air_hit_backjump = false
			fixed_velocity.x = 0
			fixed_velocity.y = 0

func _handle_blocking(input_dir: int, is_special_moving: bool) -> void:
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not is_special_moving and not (is_hit or is_knockfly or is_layground):
		is_holding_back = input_dir * facing_direction < 0
		is_crouch_blocking = is_crouching and is_holding_back
	else:
		if not (is_hit or is_knockfly or is_blocking or is_layground):
			is_holding_back = false
			is_crouch_blocking = false

func _handle_dash(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not is_special_moving and not (is_hit or is_knockfly or is_blocking or is_push_back or is_layground) and not is_crouching:
		if neutral_timer > 0 and input_dir != 0 and pending_dash_dir == input_dir:
			if input_dir * facing_direction > 0:
				is_dashing = true
				dash_timer = dash_time
				fixed_velocity.x = int(dash_speed * scale_factor * input_dir)
				if groundsmoke:
					groundsmoke.scale.x = facing_direction
					groundsmoke.restart()
			elif not (is_blocking and is_opponent_proximity and block_type == "proximity"):
				is_backdashing = true
				dash_timer = backdash_time
				fixed_velocity.x = int(backdash_speed * scale_factor * input_dir)
				if groundsmoke:
					groundsmoke.scale.x = facing_direction
					groundsmoke.restart()
			neutral_timer = 0.0
			pending_dash_dir = 0
			last_input_dir = 0
			landing_facing_lock = true
		elif input_dir != last_input_dir:
			if last_input_dir != 0 and input_dir == 0:
				neutral_timer = double_tap_timer
				pending_dash_dir = last_input_dir
			last_input_dir = input_dir

func _handle_walk(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not is_special_moving and not (is_hit or is_knockfly or is_blocking or is_push_back or is_layground) and not is_crouching:
		if input_dir != 0:
			if is_proximity_blocking and input_dir * facing_direction < 0:
				fixed_velocity.x = 0
			else:
				var move_speed: float = walk_speed if input_dir * facing_direction > 0 else back_speed
				fixed_velocity.x = int(move_speed * scale_factor * input_dir)
		else:
			fixed_velocity.x = 0
	else:
		if not (is_jumping or is_dashing or is_backdashing or is_hit or is_knockfly or is_blocking or is_push_back or jump_delay_timer > 0 or is_special_moving or is_layground):
			fixed_velocity.x = 0

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

func _handle_knockfly_layground(delta: float, floor_y: int) -> void:
	if is_air_hit_backjump:
		air_hit_backjump_timer -= delta
		var gravity: int = world.GRAVITY if world else 6000000
		fixed_velocity.y += int(gravity * delta)
		var friction_amount = int(default_air_friction * (world.SIMULATION_SCALE if world else 1000.0) * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)
		if air_hit_backjump_timer <= 0 or is_on_floor():
			is_air_hit_backjump = false
			is_hit = true
		return

	if is_knockfly:
		knockfly_timer -= delta
		fixed_velocity.y += int(knockfly_gravity * delta)
		var friction_amount = int(air_friction * (world.SIMULATION_SCALE if world else 1000.0) * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)

		# 關鍵修正：只要在 knockfly 狀態下著地，就強制進入 layground
		if is_on_floor():
			fixed_velocity = Vector2i.ZERO
			is_knockfly = false
			is_layground = true
			layground_timer = layground_duration
			is_knockfly_animation_finished = false
			_update_animation_state(0, false)
			return

		# timer 結束但仍在空中時，只標記動畫完成
		if knockfly_timer <= 0 and not is_on_floor():
			is_knockfly_animation_finished = true
			fixed_velocity.x = 0
			return

	if is_layground:
		layground_timer -= delta
		fixed_velocity = Vector2i.ZERO
		if layground_timer <= 0:
			_reset_layground_with_health_check()

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
		
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	var push_manager = get_tree().get_first_node_in_group("push_manager")
	if push_manager:
		push_manager._physics_process(delta)

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
		is_opponent_proximity = true
		var input_dir: int = get_input().input_dir
		if input_dir * facing_direction < 0 and is_on_floor() and not (is_hit or is_knockfly or is_layground):
			is_proximity_blocking = true
			fixed_velocity.x = 0

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false
		is_proximity_blocking = false

func update_facing_direction() -> void:
	var is_attacking_state = is_attacking
	var is_landing_state = ("is_landing" in self and self.is_landing and "landing_lock_timer" in self and self.landing_lock_timer > 0)
	if is_attacking_state or landing_facing_lock or is_landing_state or is_layground:
		return
	
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for p in players:
		if p != self:
			other_player = p
			break
	
	if other_player:
		var self_left = global_position.x - colbox_half_width
		var self_right = global_position.x + colbox_half_width
		var other_left = other_player.global_position.x - other_player.colbox_half_width
		var other_right = other_player.global_position.x - other_player.colbox_half_width
		var old_facing = facing_direction
		var epsilon = 1.0
		if self_left > other_right + epsilon:
			facing_direction = -1.0
			scale.x = -1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
		elif self_right < other_left - epsilon:
			facing_direction = 1.0
			scale.x = 1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
		else:
			var push_manager = get_tree().get_first_node_in_group("push_manager")
			var is_at_left_corner = push_manager.is_at_corner(self) if push_manager else false
			if is_at_left_corner and global_position.x > other_player.global_position.x:
				facing_direction = -1.0
				scale.x = -1
				scale.y = 1
				sprite.scale.x = 1.0
				rotation_degrees = 0
			elif is_at_left_corner and global_position.x <= other_player.global_position.x:
				facing_direction = 1.0
				scale.x = 1
				scale.y = 1
				sprite.scale.x = 1.0
				rotation_degrees = 0
			else:
				facing_direction = old_facing
				scale.x = sign(old_facing)
				scale.y = 1
				sprite.scale.x = 1.0
				rotation_degrees = 0
		update_hitbox_position()
	else:
		facing_direction = 1.0
		scale.x = 1
		scale.y = 1
		sprite.scale.x = 1.0
		rotation_degrees = 0

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	for c in animation_conditions:
		var condition_value: bool = (target_state == c)
		if c == "Walk":
			condition_value = condition_value and on_floor and not crouch_input
		elif c == "cr_block":
			condition_value = condition_value and is_crouch_blocking and crouch_input
		animation_tree.set("parameters/conditions/" + c, condition_value)

func _compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	if is_hit:
		return "hit" if on_floor else "Jump_B"
	
	var move_set = $MoveSet if has_node("MoveSet") else null
	
	if is_layground: return "layground"
	if is_knockfly: return "knockfly"
	if "is_wakeup_locked" in self and self.is_wakeup_locked: return "wakeup"
	
	if move_set and move_set.is_spmove:
		if move_set.is_super: return "super"
		elif player and move_set.is_powerkk and player.character_id == "DAV": return "powerkk"
		elif player and move_set.is_spnk and player.character_id == "DEN": return "spnk"
		elif move_set.is_hdk: return "hdk"          # ← 新增這一行
		elif player and move_set.is_dp and player.character_id == "DAV": return "dp"
		elif move_set.is_fireball: return "fireball"
	
	if is_proximity_blocking:
		return "cr_block" if is_crouching else "block"
	if is_blocking:
		return "cr_block" if is_crouch_blocking and crouch_input else "block"
	
	if is_attacking:
		var atype = get("attack_type") if "attack_type" in self else "none"
		if atype in ["st_mp", "st_mk", "cr_mp", "cr_mk", "super", "dp", "powerkk", "spnk", "fireball", "hdk"]:
			return atype
		return "Walk"
	
	if is_dashing: return "Dash"
	if is_backdashing: return "Backdash"
	
	if crouch_input and on_floor and not is_blocking:
		if not was_crouching_last_frame:
			animation_state.call_deferred("travel", "cr_down")
		return "cr_idle"
	
	if not on_floor and (is_jumping or ("is_air_attacking" in self and self.is_air_attacking)):
		if "is_air_attacking" in self and (self.is_air_attacking or ("has_air_attacked" in self and self.has_air_attacked)):
			return get("attack_type") if "attack_type" in self else "jump_mp"
		else:
			if anim_jump_dir > 0: return "Jump_F"
			elif anim_jump_dir < 0: return "Jump_B"
			else: return "Jump_V"
	
	return "Walk"

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var curr_state: String = animation_state.get_current_node() if animation_state else ""
	var on_floor: bool = is_on_floor()
	var anim_dir: float = dir_x * facing_direction
	var anim_jump_dir: float = jump_dir * facing_direction
	var target_state: String = _compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
	if healthbar and healthbar.current_health <= 0 and is_layground:
		target_state = "layground"
		animation_state.travel("layground")
		return
	
	if target_state == "Walk" and not on_floor and is_jumping:
		target_state = "Jump_F" if anim_jump_dir > 0 else ("Jump_B" if anim_jump_dir < 0 else "Jump_V")
	
	_set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		if not (target_state == "knockfly" and is_knockfly_animation_finished and not is_on_floor()):
			animation_state.travel(target_state)
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
	if is_jumping and on_floor:
		is_jumping = false

func _reset_layground_with_health_check() -> void:
	print("Debug: layground reset triggered for %s. Checking health before wakeup transition." % name)
	
	var player_healthbar = self.healthbar
	
	if player_healthbar and player_healthbar.current_health <= 0:
		print("Debug: %s 血量已歸零，保持躺地狀態，不觸發 wakeup。" % name)
		is_layground = true
		is_knockfly = false
		is_knockfly_animation_finished = false
		return
	
	print("Debug: %s 血量仍有剩餘，允許 wakeup。" % name)
	is_layground = false
	is_knockfly = false
	is_knockfly_animation_finished = false
	
	if "is_wakeup" in get_parent() and "is_wakeup_locked" in get_parent():
		get_parent().is_wakeup = true
		get_parent().is_wakeup_locked = true
		animation_state.travel("wakeup")
	
	_update_animation_state(0, false)
