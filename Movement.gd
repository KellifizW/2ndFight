class_name Movement extends Node2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null

# Physics variables
var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var walk_speed: float = 100.0
var back_speed: float = walk_speed * 0.75
var jump_vertical_speed: float = -650.0
var jump_horizontal_speed: float = 110.0
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
@export var knockfly_duration: float = 0.75
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
@export var jump_delay_duration: float = 0.1

signal block_detected(target: String, block_type: String)

func _ready():
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
	# Defer world-dependent initialization
	call_deferred("_initialize_world")

func _initialize_world():
	var world = get_tree().get_first_node_in_group("world")
	if world:
		fixed_position = Vector2i(int(global_position.x * world.SIMULATION_SCALE), world.FLOOR_Y)
		update_facing_direction()
	else:
		print("Error: World node not found in group 'world' for %s during deferred initialization" % name)
		# Fallback: Set default position
		fixed_position = Vector2i(int(global_position.x * 1000), 200000)

func _physics_process(delta):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		# Log warning only once per frame to avoid spam
		if not has_meta("world_warning_logged"):
			print("Warning: World node not found in group 'world' for %s" % name)
			set_meta("world_warning_logged", true)
		return
	
	# Reset warning flag for next frame
	if has_meta("world_warning_logged"):
		remove_meta("world_warning_logged")
	
	var current_position = global_position
	var is_landing: bool = ("is_landing" in self and self.is_landing)
	
	# Update timers
	if neutral_timer > 0:
		neutral_timer -= delta
	if dash_timer > 0:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			is_backdashing = false
			fixed_velocity.x = 0
			print("Debug: Dash/Backdash ended, resetting velocity for %s" % name)
	
	# Update jump delay timer
	if jump_delay_timer > 0:
		jump_delay_timer -= delta
		if jump_delay_timer <= 0:
			fixed_velocity.y = int(jump_vertical_speed * world.SIMULATION_SCALE)
			just_jumped = true
			fixed_position.y = world.FLOOR_Y - 1
			print("Debug: Jump vertical physics activated after delay, fixed_velocity.y=%s" % fixed_velocity.y)
	
	# Get input
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	is_crouching = crouch_pressed
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_powerkk = move_set.is_powerkk if move_set else false
	var is_spnk = move_set.is_spnk if move_set else false
	
	# Set blocking state
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_powerkk and not is_spnk and not (is_hit or is_knockfly):
		if input_dir * facing_direction < 0:
			is_holding_back = true
			is_crouch_blocking = crouch_pressed and input_dir * facing_direction < 0
			print("Debug: Block state updated, is_holding_back=%s, is_crouch_blocking=%s, input_dir=%s, crouch_pressed=%s" % [is_holding_back, is_crouch_blocking, input_dir, crouch_pressed])
		else:
			is_holding_back = false
			is_crouch_blocking = false
	else:
		if not (is_hit or is_knockfly or is_blocking):
			is_holding_back = false
			is_crouch_blocking = false
	
	# Double-tap detection
	if is_on_floor() and not is_dashing and not is_backdashing and not is_attacking and not is_jumping and not is_crouching and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back):
		if neutral_timer > 0 and input_dir != 0 and input_dir == last_input_dir and pending_dash_dir == input_dir:
			if input_dir * facing_direction > 0:
				is_dashing = true
				dash_timer = dash_time
				fixed_velocity.x = int(dash_speed * world.SIMULATION_SCALE * input_dir)
				print("Debug: Dash initiated, fixed_velocity.x=%s, input_dir=%s, facing_direction=%s" % [fixed_velocity.x, input_dir, facing_direction])
			else:
				if not (is_blocking and is_opponent_proximity and block_type == "proximity"):
					is_backdashing = true
					dash_timer = backdash_time
					fixed_velocity.x = int(backdash_speed * world.SIMULATION_SCALE * input_dir)
					print("Debug: Backdash initiated, fixed_velocity.x=%s, input_dir=%s, facing_direction=%s" % [fixed_velocity.x, input_dir, facing_direction])
				else:
					print("Debug: Backdash blocked due to proximity block for %s" % name)
			neutral_timer = 0.0
			pending_dash_dir = 0
		elif input_dir != last_input_dir:
			if last_input_dir != 0 and input_dir == 0:
				neutral_timer = double_tap_timer
				pending_dash_dir = last_input_dir
			last_input_dir = input_dir
	
	# Process movement logic
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back) and not is_crouching:
		if input_dir != 0:
			if input_dir * facing_direction < 0 and is_blocking and is_opponent_proximity and block_type == "proximity":
				fixed_velocity.x = 0
				print("Debug: Backward movement blocked due to proximity block for %s" % name)
			else:
				var move_speed = walk_speed if input_dir * facing_direction > 0 else back_speed
				fixed_velocity.x = int(move_speed * world.SIMULATION_SCALE * input_dir)
				print("Debug: Moving, fixed_velocity.x=%s, input_dir=%s, facing_direction=%s" % [fixed_velocity.x, input_dir, facing_direction])
		else:
			fixed_velocity.x = 0
	else:
		if not (is_jumping or is_dashing or is_backdashing or is_hit or is_knockfly or is_blocking or is_push_back or jump_delay_timer > 0 or ("is_special_moving" in self and self.is_special_moving)):
			fixed_velocity.x = 0
	
	# Jump logic
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing and not is_attacking and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back) and jump_delay_timer <= 0:
		jump_dir = input_dir
		is_jumping = true
		landing_facing_lock = true
		jump_delay_timer = jump_delay_duration
		fixed_position.y = world.FLOOR_Y - 1
		fixed_velocity.y = 0
		if jump_dir != 0:
			var jump_speed = jump_horizontal_speed if jump_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
			fixed_velocity.x = int(jump_speed * world.SIMULATION_SCALE * jump_dir)
		else:
			fixed_velocity.x = 0
		print("Debug: Jump initiated with delay, fixed_velocity.x=%s, fixed_position.y=%s, jump_dir=%s, timer=%.2fs" % [fixed_velocity.x, fixed_position.y, jump_dir, jump_delay_duration])
	
	# Apply gravity
	if jump_delay_timer <= 0 and not is_on_floor():
		add_gravity(world.GRAVITY, delta)
	else:
		if not just_jumped:
			fixed_velocity.y = 0
			fixed_position.y = world.FLOOR_Y
	
	# Update position
	fixed_position += Vector2i(round(fixed_velocity.x * delta), round(fixed_velocity.y * delta))
	
	# Floor constraint
	if not just_jumped and fixed_position.y >= world.FLOOR_Y and jump_delay_timer <= 0 and fixed_velocity.y >= 0 and is_jumping:
		fixed_position.y = world.FLOOR_Y
		fixed_velocity.y = 0
		is_jumping = false
		just_jumped = false
		fixed_velocity.x = 0
		neutral_timer = 0.0
		pending_dash_dir = 0
		last_input_dir = 0
		landing_facing_lock = false
		print("Debug: Landing, resetting is_jumping and dash detection vars for %s" % name)
		
		# Force push check on landing
		var push_manager = get_tree().get_first_node_in_group("push_manager")
		if push_manager:
			push_manager._physics_process(delta)
			print("Debug: Forced PushManager check on landing for %s" % name)
	
	# Set display position
	global_position = world.to_scaled_vector2(fixed_position)
	
	# Reset just_jumped
	if just_jumped and fixed_velocity.y > 0:
		just_jumped = false
	
	# Update facing
	var is_special_move = move_set and (move_set.is_powerkk or move_set.is_spnk)
	var is_attacking_state = is_attacking
	if not (is_special_move or is_attacking_state or is_hit or is_knockfly or is_blocking or is_jumping or is_landing) and not landing_facing_lock:
		update_facing_direction()
	
	# Update animation and facing
	if is_on_floor() and was_in_air and not is_landing and not (is_powerkk or is_spnk) and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	was_in_air = not is_on_floor()
	if is_on_floor() and prev_position.x != global_position.x and not (is_powerkk or is_spnk) and not is_landing and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	prev_position = global_position
	post_physics_process(delta)

func _on_animation_player_finished(anim_name: String) -> void:
	if anim_name == "st_mp" and is_attacking:
		is_attacking = false
		update_facing_direction()
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
		print("Debug: Attack animation 'st_mp' finished, resetting is_attacking for %s" % name)

func add_gravity(gravity: int, delta: float) -> void:
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	fixed_velocity.y += int(gravity * delta)

func is_on_floor() -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		return false
	if jump_delay_timer > 0 or just_jumped:
		return false
	return fixed_position.y >= world.FLOOR_Y

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
			print("Debug: Proximity block triggered, is_holding_back=%s, is_crouch_blocking=%s" % [is_holding_back, is_crouch_blocking])

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false
		if is_blocking and block_type == "proximity":
			is_blocking = false
			is_crouch_blocking = false
			block_type = "none"
			print("Debug: Proximity block ended for %s" % name)

func update_facing_direction():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_move = move_set and (move_set.is_powerkk or move_set.is_spnk)
	var is_attacking_state = is_attacking
	if is_special_move or is_attacking_state or landing_facing_lock:
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
		if self_left > other_right:
			facing_direction = -1.0
			scale.x = -1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
		elif self_right < other_left:
			facing_direction = 1.0
			scale.x = 1
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

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	pass
