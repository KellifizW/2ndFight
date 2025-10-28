class_name Movement extends Node2D

var world: Node
@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
@export var landing_duration: float = 0.2
var is_layground: bool = false
@export var layground_duration: float = 0.3833
var layground_timer: float = 0.0
@export var knockfly_gravity: float = 3000000.0
@export var knockfly_duration: float = 0.3833
var is_knockfly_animation_finished: bool = false  # 新增：追蹤 knockfly 動畫是否完成

var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var walk_speed: float = 100.0
var back_speed: float = walk_speed * 0.75
var jump_vertical_speed: float = -810.0
var jump_horizontal_speed: float = 120.0
var jump_dir: float = 0.0
var is_jumping: bool = false
var is_dashing: bool = false
var is_backdashing: bool = false
var is_attacking: bool = false
var dash_speed: float = 170.0
var backdash_speed: float = 140.0
var dash_time: float = 0.35
var backdash_time: float = 0.35
var dash_timer: float = 0.0
var double_tap_timer: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0
var is_crouching: bool = false
var is_hit: bool = false
var is_knockfly: bool = false
var arena_left: float = 0.0
var arena_right: float = 480.0
var hit_timer: float = 0.0
var block_timer: float = 0.0
var knockfly_timer: float = 0.0
var knockfly_push_speed: float = 300.0
var knockfly_velocity_x: float = 0.0
@export var block_push_distance: float = 20.0
var block_push_timer: float = 0.0
var initial_blockstun: float = 0.0
var block_push_velocity: float = 0.0
@export var hit_push_distance: float = 20.0
var hit_push_timer: float = 0.0
var initial_hitstun: float = 0.0
var hit_push_velocity: float = 0.0
var facing_direction: float = 1.0
var dash_direction: float = 0.0
var is_blocking: bool = false
var is_holding_back: bool = false
var is_crouch_blocking: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false
var air_hit_knockfly_distance: float = 10.0
var is_air_hit_knockfly: bool = false
var is_push_back: bool = false
var push_back_timer: float = 0.0
var initial_push_back: float = 0.0
var push_back_velocity: float = 0.0
var knockfly_accumulated_distance: float = 0.0
var knockfly_max_distance: float = 150.0
var just_jumped: bool = false
var landing_facing_lock: bool = false
var jump_delay_timer: float = 0.0
@export var jump_delay_duration: float = 0.067

signal block_detected(target: String, block_type: String)
var animation_conditions: Array = [
	"Walk", "Crouch", "Dash", "Backdash",
	"st_mp", "st_mk", "cr_mp", "cr_mk",
	"Jump_F", "Jump_B", "Jump_V",
	"hit", "knockfly", "block", "cr_block",
	"powerkk", "spnk", "fireball",
	"jump_mp", "jump_mk", "landing", "wakeup", "super", "dp", "layground"
]

var anim_resets: Dictionary = {
	"layground": func(): 
		is_layground = false
		is_knockfly = false
		is_knockfly_animation_finished = false
		_update_animation_state(0, false)
		print("Debug: Layground ended for %s, transitioning to wakeup/idle at %s ms" % [name, Time.get_ticks_msec()]),
	"knockfly": func():
		if is_on_floor():
			fixed_velocity = Vector2i.ZERO
			is_knockfly = false
			is_layground = true
			layground_timer = layground_duration
			is_knockfly_animation_finished = false
			_update_animation_state(0, false)
			print("Debug: Knockfly landed, transitioning to layground for %s, timer: %s at %s ms" % [name, layground_duration, Time.get_ticks_msec()])
		else:
			is_knockfly_animation_finished = true
			if animation_player:
				animation_player.stop()  # 停止動畫以保持最後一幀
			print("Debug: Knockfly animation finished but still in air, holding last frame for %s at %s ms" % [name, Time.get_ticks_msec()]),
	"st_mp": func():
		is_attacking = false
		update_facing_direction()
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
		print("Debug: Animation %s finished for %s, is_attacking=%s at %s ms" % ["st_mp", name, is_attacking, Time.get_ticks_msec()]),
	# 添加其他通用重置，例如 "hit": func(): is_hit = false, 等（根據你的需求擴展）
}


func _ready():
	world = get_tree().get_first_node_in_group("world")
	var retry_count = 0
	while not world and retry_count < 5:
		world = get_tree().get_first_node_in_group("world")
		if not world:
			await get_tree().create_timer(0.1).timeout
			retry_count += 1
	if world:
		print("Debug: World node found for %s after %d attempts at %s ms" % [name, retry_count, Time.get_ticks_msec()])
	else:
		push_error("Error: World node still not found for %s after %d retries" % [name, retry_count])
	
	if animation_tree:
		animation_tree.active = true
		if animation_state:
			animation_state.travel("Walk")
	if has_node("Pushbox") and $Pushbox.shape is RectangleShape2D:
		var collision_scale = $Pushbox.scale
		colbox_half_width = $Pushbox.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = $Pushbox.shape.size.y * collision_scale.y / 2.0
	if has_node("Hurtbox"):
		$Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		$Hurtbox.area_exited.connect(_on_hurtbox_area_exited)
	if animation_player:
		animation_player.speed_scale = 1.0
		if not animation_player.animation_finished.is_connected(_on_animation_player_finished):
			animation_player.animation_finished.connect(_on_animation_player_finished)
	prev_position = global_position
	if world:
		fixed_position = Vector2i(int(global_position.x * world.SIMULATION_SCALE), world.FLOOR_Y)
		update_facing_direction()
	else:
		fixed_position = Vector2i(int(global_position.x * 1000), 200000)
		print("Debug: Fallback position set for %s due to missing world at %s ms" % [name, Time.get_ticks_msec()])
	knockfly_timer = 0.0
	layground_timer = 0.0
	is_knockfly_animation_finished = false  # 初始化動畫完成標誌

func _physics_process(delta):
	var current_position = global_position
	var is_landing: bool = ("is_landing" in self and self.is_landing)
	
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
			fixed_velocity.y = int(jump_vertical_speed * (self.world.SIMULATION_SCALE if self.world else 1000))
			just_jumped = true
			fixed_position.y = (self.world.FLOOR_Y if self.world else 200000) - 1
			print("Debug: Jump initiated for %s, vertical_speed=%s at %s ms" % [name, jump_vertical_speed, Time.get_ticks_msec()])
	
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	is_crouching = crouch_pressed
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_moving = move_set.is_special_moving if move_set and "is_special_moving" in move_set else false
	
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_special_moving and not (is_hit or is_knockfly or is_layground):
		if input_dir * facing_direction < 0:
			is_holding_back = true
			is_crouch_blocking = crouch_pressed and input_dir * facing_direction < 0
		else:
			is_holding_back = false
			is_crouch_blocking = false
	else:
		if not (is_hit or is_knockfly or is_blocking or is_layground):
			is_holding_back = false
			is_crouch_blocking = false
	
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_special_moving and not (is_hit or is_knockfly or is_blocking or is_push_back or is_layground) and not is_crouching:
		if neutral_timer > 0 and input_dir != 0 and pending_dash_dir == input_dir:
			if input_dir * facing_direction > 0:
				is_dashing = true
				dash_timer = dash_time
				fixed_velocity.x = int(dash_speed * (self.world.SIMULATION_SCALE if self.world else 1000) * input_dir)
				neutral_timer = 0.0
				pending_dash_dir = 0
				last_input_dir = 0
				landing_facing_lock = true
				print("Debug: Dash initiated for %s, direction=%s at %s ms" % [name, input_dir, Time.get_ticks_msec()])
			else:
				if not (is_blocking and is_opponent_proximity and block_type == "proximity"):
					is_backdashing = true
					dash_timer = backdash_time
					fixed_velocity.x = int(backdash_speed * (self.world.SIMULATION_SCALE if self.world else 1000) * input_dir)
					neutral_timer = 0.0
					pending_dash_dir = 0
					last_input_dir = 0
					landing_facing_lock = true
					print("Debug: Backdash initiated for %s, direction=%s at %s ms" % [name, input_dir, Time.get_ticks_msec()])
				neutral_timer = 0.0
				pending_dash_dir = 0
				last_input_dir = 0
		elif input_dir != last_input_dir:
			if last_input_dir != 0 and input_dir == 0:
				neutral_timer = double_tap_timer
				pending_dash_dir = last_input_dir
			last_input_dir = input_dir
	
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_special_moving and not (is_hit or is_knockfly or is_blocking or is_push_back or is_layground) and not is_crouching:
		if input_dir != 0:
			if input_dir * facing_direction < 0 and is_blocking and is_opponent_proximity and block_type == "proximity":
				fixed_velocity.x = 0
			else:
				var move_speed = walk_speed if input_dir * facing_direction > 0 else back_speed
				fixed_velocity.x = int(move_speed * (self.world.SIMULATION_SCALE if self.world else 1000) * input_dir)
		else:
			fixed_velocity.x = 0
	else:
		if not (is_jumping or is_dashing or is_backdashing or is_hit or is_knockfly or is_blocking or is_push_back or jump_delay_timer > 0 or is_special_moving or is_layground):
			fixed_velocity.x = 0
	
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing and not is_attacking and not is_special_moving and not (is_hit or is_knockfly or is_blocking or is_push_back or is_layground) and jump_delay_timer <= 0:
		jump_dir = input_dir
		is_jumping = true
		landing_facing_lock = true
		jump_delay_timer = jump_delay_duration
		fixed_position.y = (self.world.FLOOR_Y if self.world else 200000) - 1
		fixed_velocity.y = 0
		if jump_dir != 0:
			var jump_speed = jump_horizontal_speed if jump_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
			fixed_velocity.x = int(jump_speed * (self.world.SIMULATION_SCALE if self.world else 1000) * jump_dir)
		else:
			fixed_velocity.x = 0
	
	# 修改 knockfly 和 layground 邏輯
	if is_knockfly:
		knockfly_timer -= delta
		fixed_velocity.y += int(knockfly_gravity * delta)
		print("Debug: Knockfly falling with custom gravity: %s for %s at %s ms" % [knockfly_gravity, name, Time.get_ticks_msec()])

		# 檢查是否著地
		if is_on_floor():
			fixed_velocity = Vector2i.ZERO
			is_knockfly = false
			is_layground = true
			layground_timer = layground_duration
			is_knockfly_animation_finished = false
			_update_animation_state(0, false)
			print("Debug: Knockfly landed, transitioning to layground for %s, timer: %s at %s ms" % [name, layground_duration, Time.get_ticks_msec()])
		elif knockfly_timer <= 0 and not is_on_floor():
			# 動畫完成但仍在空中，保持 knockfly 狀態
			is_knockfly_animation_finished = true
			fixed_velocity.x = 0
			print("Debug: Knockfly animation finished but still in air for %s, maintaining knockfly state at %s ms" % [name, Time.get_ticks_msec()])

	if is_layground:
		layground_timer -= delta
		fixed_velocity = Vector2i.ZERO
		if layground_timer <= 0:
			is_layground = false
			is_knockfly = false
			is_knockfly_animation_finished = false
			_update_animation_state(0, false)
			print("Debug: Layground ended for %s, transitioning to wakeup/idle at %s ms" % [name, Time.get_ticks_msec()])
	
	if jump_delay_timer <= 0 and not is_on_floor() and not is_knockfly:
		var gravity = self.world.GRAVITY if self.world else 1800000
		if has_node("MoveSet") and $MoveSet.is_super:
			gravity = $MoveSet.super_gravity
		if not world:
			push_error("Error: Applying gravity without world node for %s" % name)
			print("Debug: Applying gravity without world node for %s, using fallback gravity at %s ms" % [name, Time.get_ticks_msec()])
		add_gravity(gravity, delta)
	else:
		if not just_jumped and not is_knockfly:
			fixed_velocity.y = 0
			fixed_position.y = (self.world.FLOOR_Y if self.world else 200000)
	
	fixed_position += Vector2i(round(fixed_velocity.x * delta), round(fixed_velocity.y * delta))
	
	if not just_jumped and fixed_position.y >= (self.world.FLOOR_Y if self.world else 200000) and jump_delay_timer <= 0 and fixed_velocity.y >= 0 and is_jumping:
		fixed_position.y = (self.world.FLOOR_Y if self.world else 200000)
		fixed_velocity.y = 0
		is_jumping = false
		just_jumped = false
		fixed_velocity.x = 0
		neutral_timer = 0.0
		pending_dash_dir = 0
		last_input_dir = 0
		landing_facing_lock = false
		if "is_landing" in self and "landing_lock_timer" in self:
			if not (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed):
				self.is_landing = true
				self.landing_lock_timer = landing_duration
				_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
				print("Debug: Landing initiated for %s at %s ms" % [name, Time.get_ticks_msec()])
		
		var push_manager = get_tree().get_first_node_in_group("push_manager")
		if push_manager:
			push_manager._physics_process(delta)
	
	global_position = (self.world.to_scaled_vector2(fixed_position) if self.world else Vector2(float(fixed_position.x) / 1000.0, float(fixed_position.y) / 1000.0))
	
	if just_jumped and fixed_velocity.y > 0:
		just_jumped = false
	
	var is_attacking_state = is_attacking
	var is_landing_state = ("is_landing" in self and self.is_landing and "landing_lock_timer" in self and self.landing_lock_timer > 0)
	if not (is_attacking_state or landing_facing_lock or is_landing_state):
		update_facing_direction()
	
	if is_on_floor() and was_in_air and not is_landing_state and not is_special_moving and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	was_in_air = not is_on_floor()
	if is_on_floor() and prev_position.x != global_position.x and not is_special_moving and not is_landing_state and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	prev_position = global_position
	
	if not ("landing_lock_timer" in self and self.landing_lock_timer > 0) and not is_layground:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	post_physics_process(delta)

func _on_animation_player_finished(anim_name: String):
	if anim_name in anim_resets:
		anim_resets[anim_name].call()

func add_gravity(gravity: int, delta: float) -> void:
	fixed_velocity.y += int(gravity * delta)
	print("Debug: Gravity applied for %s, gravity=%s, delta=%s, new_velocity_y=%s at %s ms" % [name, gravity, delta, fixed_velocity.y, Time.get_ticks_msec()])

func is_on_floor() -> bool:
	if jump_delay_timer > 0 or just_jumped:
		return false
	return fixed_position.y >= (self.world.FLOOR_Y if self.world else 200000)

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

func update_hitbox_position():
	pass

func post_physics_process(delta):
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
		if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_blocking:
			is_blocking = true
			is_crouch_blocking = get_input().crouch_pressed and get_input().input_dir * facing_direction < 0
			block_type = "proximity"
			fixed_velocity.x = 0
			fixed_velocity.y = 0
			block_detected.emit(name, block_type)
			print("Debug: Proximity block detected for %s at %s ms" % [name, Time.get_ticks_msec()])

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false
		if is_blocking and block_type == "proximity":
			is_blocking = false
			is_crouch_blocking = false
			block_type = "none"
			print("Debug: Proximity block ended for %s at %s ms" % [name, Time.get_ticks_msec()])

func update_facing_direction():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_attacking_state = is_attacking
	var is_landing_state = ("is_landing" in self and self.is_landing and "landing_lock_timer" in self and self.landing_lock_timer > 0)
	
	if is_attacking_state or landing_facing_lock or is_landing_state or is_layground:
		return
	
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for player in players:
		if player != self:
			other_player = player
			break
	
	if other_player:
		var self_left = global_position.x - colbox_half_width
		var self_right = global_position.x + colbox_half_width
		var other_left = other_player.global_position.x - other_player.colbox_half_width
		var other_right = other_player.global_position.x + other_player.colbox_half_width
		
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
				print("Debug: Facing forced to -1 for %s at left corner, position=%s, other_position=%s at %s ms" % [name, global_position.x, other_player.global_position.x, Time.get_ticks_msec()])
			elif is_at_left_corner and global_position.x <= other_player.global_position.x:
				facing_direction = 1.0
				scale.x = 1
				scale.y = 1
				sprite.scale.x = 1.0
				rotation_degrees = 0
				print("Debug: Facing forced to 1 for %s at left corner, position=%s, other_position=%s at %s ms" % [name, global_position.x, other_player.global_position.x, Time.get_ticks_msec()])
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
		print("Debug: No other player found for %s, default facing=1 at %s ms" % [name, Time.get_ticks_msec()])

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	for c in animation_conditions:
		var condition_value: bool = (target_state == c)
		# 添加特定條件調整（例如 Walk 需要額外檢查）
		if c == "Walk":
			condition_value = condition_value and on_floor and not crouch_input
		elif c == "Crouch":
			condition_value = condition_value
		elif c == "cr_block":
			condition_value = condition_value and is_crouch_blocking and crouch_input
		# ... 可以根據需要添加更多特定調整，保持靈活
		animation_tree.set("parameters/conditions/" + c, condition_value)
		
func _compute_target_state(dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	var move_set = $MoveSet if has_node("MoveSet") else null
	var player_id = get_parent().player_id if get_parent() and "player_id" in get_parent() else "unknown"
	
	if is_layground:
		return "layground"
	if is_knockfly:
		return "knockfly"  # 無論動畫是否完成，knockfly 狀態優先
	if "is_wakeup_locked" in self and self.is_wakeup_locked:
		return "wakeup"
	if move_set and move_set.is_spmove:
		if move_set.is_super:
			return "super"
		elif player_id == "p1" and move_set.is_powerkk:
			return "powerkk"
		elif player_id == "p1" and move_set.is_dp:
			return "dp"
		elif player_id == "p2" and move_set.is_spnk:
			return "spnk"
		elif move_set.is_fireball:
			return "fireball"
	if is_hit:
		return "hit" if on_floor else "Jump_B"
	if is_blocking:
		return "cr_block" if is_crouch_blocking and crouch_input else "block"
	if is_attacking:
		var atype = get("attack_type") if "attack_type" in self else "none"
		if atype in ["st_mp", "st_mk", "cr_mp", "cr_mk", "super", "dp"]:
			return atype
		return "Walk"
	if is_dashing:
		return "Dash"
	if is_backdashing:
		return "Backdash"
	if crouch_input and on_floor and not is_blocking:
		return "Crouch"
	if not on_floor and (is_jumping or ("is_air_attacking" in self and self.is_air_attacking)):
		if "is_air_attacking" in self and (self.is_air_attacking or ("has_air_attacked" in self and self.has_air_attacked)):
			return get("attack_type") if "attack_type" in self else "jump_mp"
		else:
			if anim_jump_dir > 0:
				return "Jump_F"
			elif anim_jump_dir < 0:
				return "Jump_B"
			else:
				return "Jump_V"
	return "Walk"

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var curr_state = animation_state.get_current_node() if animation_state else ""
	var on_floor = is_on_floor()
	var anim_dir = dir_x * facing_direction
	var anim_jump_dir = jump_dir * facing_direction
	
	var target_state = _compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	if target_state == "Walk" and not on_floor and is_jumping:
		if anim_jump_dir > 0:
			target_state = "Jump_F"
		elif anim_jump_dir < 0:
			target_state = "Jump_B"
		else:
			target_state = "Jump_V"
	
	_set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		if target_state == "knockfly" and is_knockfly_animation_finished and not is_on_floor():
			# 保持 knockfly 最後一幀，不重新播放
			pass
		else:
			animation_state.travel(target_state)
			if target_state == "layground":
				print("Debug: Transitioned to layground animation for %s at %s ms" % [name, Time.get_ticks_msec()])
			print("Debug: Animation state changed for %s from %s to %s at %s ms" % [name, curr_state, target_state, Time.get_ticks_msec()])
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
	if is_jumping and on_floor:
		is_jumping = false
		print("Debug: Jumping ended for %s at %s ms" % [name, Time.get_ticks_msec()])
