class_name Movement extends Node2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null

# 移植 PhysicsBody 的物理變數
var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var walk_speed: float = 100.0  # 適配 20x70 角色
var back_speed: float = walk_speed * 0.75  # 75.0
var jump_vertical_speed: float = -650.0  # 跳躍垂直速度（像素/秒）
var jump_horizontal_speed: float = 110.0  # 前跳/後跳水平速度
var jump_dir: float = 0.0
var is_jumping: bool = false
var is_dashing: bool = false
var is_backdashing: bool = false
var is_attacking: bool = false
var attack_time: float = 0.4
var attack_timer: float = 0.0
var dash_speed: float = 160.0
var backdash_speed: float = 130.0
var dash_time: float = 0.35
var backdash_time: float = 0.4
var dash_timer: float = 0.0
var double_tap_timer: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0
var is_crouching: bool = false
var is_hit: bool = false
var is_knockfly: bool = false
var arena_left: float = 0.0
var arena_right: float = 480.0  # 適配 480x240 視圖
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
var just_jumped: bool = false  # 防止過早落地

signal block_detected(target: String, block_type: String)

func _ready():
	if animation_tree:
		animation_tree.active = true
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
	prev_position = global_position
	var world = get_tree().get_first_node_in_group("world")
	if world:
		fixed_position = Vector2i(int(global_position.x * world.SIMULATION_SCALE), world.FLOOR_Y)  # 設置初始 y 為地板高度
	else:
		print("Warning: World node not found in group 'world' for %s" % name)

func _physics_process(delta):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	
	var current_position = global_position
	var is_landing = self is Player and get("is_landing") if is_class("Player") else false
	
	# 更新計時器
	if neutral_timer > 0:
		neutral_timer -= delta
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
			update_facing_direction()
	if dash_timer > 0:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			is_backdashing = false
			fixed_velocity.x = 0
			print("Debug: Dash/Backdash ended, resetting velocity for %s" % name)
	
	# 獲取輸入
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	is_crouching = crouch_pressed
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_powerkk = move_set.is_powerkk if move_set else false
	var is_spnk = move_set.is_spnk if move_set else false
	
	# 設置格擋狀態
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back):
		if input_dir * facing_direction < 0:
			is_holding_back = true
		else:
			is_holding_back = false
		if crouch_pressed:
			is_crouch_blocking = (input_dir * facing_direction < 0)
		else:
			is_crouch_blocking = false
	else:
		if not (is_hit or is_knockfly):
			is_holding_back = false
			is_crouch_blocking = false
	
	# 雙擊檢測
	if is_on_floor() and not is_dashing and not is_backdashing and not is_attacking and not is_jumping and not is_crouching and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back):
		if neutral_timer > 0 and input_dir != 0 and input_dir == last_input_dir and pending_dash_dir == input_dir:
			if input_dir * facing_direction > 0:
				is_dashing = true
				dash_timer = dash_time
				fixed_velocity.x = int(dash_speed * world.SIMULATION_SCALE * input_dir)
				print("Debug: Dash initiated, fixed_velocity.x=%s, input_dir=%s, facing_direction=%s" % [fixed_velocity.x, input_dir, facing_direction])
			else:
				is_backdashing = true
				dash_timer = backdash_time
				fixed_velocity.x = int(backdash_speed * world.SIMULATION_SCALE * input_dir)
				print("Debug: Backdash initiated, fixed_velocity.x=%s, input_dir=%s, facing_direction=%s" % [fixed_velocity.x, input_dir, facing_direction])
			neutral_timer = 0.0
			pending_dash_dir = 0
		elif input_dir != last_input_dir:
			if last_input_dir != 0 and input_dir == 0:
				neutral_timer = double_tap_timer
				pending_dash_dir = last_input_dir
			last_input_dir = input_dir
	
	# 處理移動邏輯
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back):
		if input_dir != 0:
			var move_speed = walk_speed if input_dir * facing_direction > 0 else back_speed
			fixed_velocity.x = int(move_speed * world.SIMULATION_SCALE * input_dir)
			print("Debug: Moving, fixed_velocity.x=%s, input_dir=%s, facing_direction=%s" % [fixed_velocity.x, input_dir, facing_direction])
		else:
			fixed_velocity.x = 0
	else:
		if not is_jumping and not is_dashing and not is_backdashing:
			fixed_velocity.x = 0
	
	# 跳躍邏輯
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing and not is_attacking and not is_powerkk and not is_spnk and not (is_hit or is_knockfly or is_blocking or is_push_back):
		jump_dir = input_dir
		fixed_velocity.y = int(jump_vertical_speed * world.SIMULATION_SCALE)
		if jump_dir != 0:
			var jump_speed = jump_horizontal_speed if jump_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
			fixed_velocity.x = int(jump_speed * world.SIMULATION_SCALE * jump_dir)
		else:
			fixed_velocity.x = 0
		fixed_position.y = world.FLOOR_Y - 1000
		is_jumping = true
		just_jumped = true
		print("Debug: Jump initiated, fixed_velocity.y=%s, fixed_velocity.x=%s, fixed_position.y=%s, jump_dir=%s" % [fixed_velocity.y, fixed_velocity.x, fixed_position.y, jump_dir])
	
	# 應用重力
	if not is_on_floor():
		add_gravity(world.GRAVITY, delta)
	else:
		if not just_jumped:
			fixed_velocity.y = 0
			fixed_position.y = world.FLOOR_Y
	
	# 更新位置
	fixed_position += Vector2i(round(fixed_velocity.x * delta), round(fixed_velocity.y * delta))
	
	# 地板限制
	if not just_jumped and fixed_position.y >= world.FLOOR_Y:
		fixed_position.y = world.FLOOR_Y
		fixed_velocity.y = 0
		if is_jumping:
			is_jumping = false
			fixed_velocity.x = 0
			print("Debug: Landing, resetting is_jumping for %s" % name)
	
	# 設置顯示位置
	global_position = world.to_scaled_vector2(fixed_position)
	
	# 重置 just_jumped 標誌
	if just_jumped and fixed_velocity.y > 0:
		just_jumped = false
	
	# 更新動畫和朝向
	if is_on_floor() and was_in_air and not is_landing and not (is_powerkk or is_spnk):
		update_facing_direction()
	was_in_air = not is_on_floor()
	if is_on_floor() and prev_position.x != global_position.x and not (is_powerkk or is_spnk) and not is_landing:
		update_facing_direction()
	prev_position = global_position
	post_physics_process(delta)

# 移植 PhysicsBody.AddGravity
func add_gravity(gravity: int, delta: float) -> void:
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	fixed_velocity.y += int(gravity * delta)

# 移植 PhysicsBody.IsOnGround
func is_on_floor() -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		return false
	return fixed_position.y >= world.FLOOR_Y and not just_jumped

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
			initial_blockstun = 0.1
			block_timer = 0.1
			block_type = "proximity"
			fixed_velocity.x = 0
			fixed_velocity.y = 0
			block_detected.emit(name, block_type)
			print("Debug: Proximity block triggered, is_holding_back=" + str(is_holding_back) + ", is_crouch_blocking=" + str(is_crouch_blocking))

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false

func update_facing_direction():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_move = move_set and (move_set.is_powerkk or move_set.is_spnk)
	var is_attacking_state = is_attacking and attack_timer > 0
	if is_special_move or is_attacking_state:
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
