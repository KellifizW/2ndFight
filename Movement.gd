class_name Movement extends CharacterBody2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
@onready var sprite = $Sprite2D
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var walk_speed: float = 120.0
var back_speed: float = walk_speed * 0.75
var jump_horizontal_speed: float = 130.0
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
var hit_timer: float = 0.0
var block_timer: float = 0.0
var knockfly_timer: float = 0.0
var knockfly_speed: float = -300.0
@export var block_push_distance: float = 20.0  # 格擋後退總距離（像素）
var block_push_timer: float = 0.0      # 格擋後退計時器
var initial_blockstun: float = 0.0     # 初始blockstun時間
var block_push_velocity: float = 0.0   # 格擋後退速度
@export var hit_push_distance: float = 20.0  # 受擊後退總距離（像素）
var hit_push_timer: float = 0.0        # 受擊後退計時器
var initial_hitstun: float = 0.0       # 初始hitstun時間
var hit_push_velocity: float = 0.0     # 受擊後退速度
var facing_direction: float = 1.0
var dash_direction: float = 0.0
var is_blocking: bool = false
var is_holding_back: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false
# 新增：空中普通攻擊的 knockfly 後退距離和標誌
var air_hit_knockfly_distance: float = 10.0
var is_air_hit_knockfly: bool = false
signal block_detected(target: String, block_type: String)

func _ready():
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	else:
		print("Warning: AnimationTree not found for %s" % name)
	if has_node("Pushbox") and $Pushbox.shape is RectangleShape2D:
		var collision_scale = $Pushbox.scale
		colbox_half_width = $Pushbox.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = $Pushbox.shape.size.y * collision_scale.y / 2.0
	else:
		print("Warning: Pushbox not found or invalid for %s" % name)
	if has_node("Hurtbox"):
		$Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		$Hurtbox.area_exited.connect(_on_hurtbox_area_exited)
	prev_position = global_position
	update_facing_direction()

func _physics_process(delta):
	var current_position = global_position
	
	if neutral_timer > 0:
		neutral_timer -= delta
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
			print("Debug: Attack ended, is_attacking set to false for %s" % name)
	if hit_timer > 0:
		hit_timer -= delta
		if hit_timer <= 0:
			is_hit = false
			hit_push_timer = 0.0
			hit_push_velocity = 0.0
			initial_hitstun = 0.0
			print("Debug: Hitstun ended for %s" % name)
	if block_timer > 0:
		block_timer -= delta
		if block_timer <= 0:
			is_blocking = false
			block_type = "none"
			block_push_timer = 0.0
			block_push_velocity = 0.0
			initial_blockstun = 0.0
			print("Debug: Block ended, is_blocking set to false for %s" % name)
	if knockfly_timer > 0:
		knockfly_timer -= delta
		if knockfly_timer <= 0 and is_knockfly:
			var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
			if healthbar and healthbar.current_health <= 0:
				print("Debug: Health is zero, staying in knockfly for %s" % name)
			else:
				is_knockfly = false
				is_air_hit_knockfly = false  # 重置空中普通攻擊標誌
				print("Debug: Knockfly ended, transitioning to wakeup for %s" % name)
	
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	
	is_crouching = crouch_pressed
	
	# 從 MoveSet 獲取特殊招式狀態
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_powerkk = move_set.is_powerkk if move_set else false
	var is_spnk = move_set.is_spnk if move_set else false
	
	# 只有在非攻擊狀態時才檢查 is_holding_back
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not is_crouching and not jump_pressed and not is_powerkk and not is_spnk:
		if input_dir * facing_direction < 0:
			is_holding_back = true
			print("Debug: Holding back detected for %s" % name)
		else:
			is_holding_back = false
	
	# 動態獲取邊界變數
	var arena_left = 0.0
	var arena_right = ProjectSettings.get_setting("display/window/size/viewport_width")
	if is_class("Fighter"):
		var arena_left_value = get("arena_left")
		var arena_right_value = get("arena_right")
		if arena_left_value != null:
			arena_left = arena_left_value
		if arena_right_value != null:
			arena_right = arena_right_value
	
	if is_hit or is_knockfly:
		if is_knockfly:
			if is_air_hit_knockfly and not is_on_floor():  # 空中普通攻擊 knockfly
				if knockfly_timer > 0:
					var deceleration_rate = 2.0 * air_hit_knockfly_distance / (knockfly_timer * knockfly_timer)
					var current_speed = (2.0 * air_hit_knockfly_distance / knockfly_timer) - (deceleration_rate * (knockfly_timer - (knockfly_timer - delta)))
					if current_speed < 0:
						current_speed = 0
					velocity.x = -facing_direction * current_speed
					print("Debug: Air hit knockfly for %s, velocity.x=%s, remaining=%s, current_speed=%s" % [name, velocity.x, knockfly_timer, current_speed])
				else:
					velocity.x = 0
			else:  # 特殊招式或地面 knockfly
				velocity.x = knockfly_speed * facing_direction
		else:
			if hit_push_timer > 0:
				hit_push_timer -= delta
				if hit_push_velocity > 0:
					var deceleration_rate = 2.0 * hit_push_distance / (initial_hitstun * initial_hitstun)
					hit_push_velocity -= deceleration_rate * delta
					if hit_push_velocity < 0:
						hit_push_velocity = 0
				velocity.x = -facing_direction * hit_push_velocity
				print("Debug: Hit push active for %s, velocity.x=%s, initial_hitstun=%s, remaining=%s, current_speed=%s" % [name, velocity.x, initial_hitstun, hit_push_timer, hit_push_velocity])
			else:
				velocity.x = 0
				hit_push_velocity = 0
		velocity.y += 1300 * delta
		move_and_slide()
		global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
		return
	
	if is_blocking:
		if block_push_timer > 0:
			block_push_timer -= delta
			if block_push_velocity > 0:
				var deceleration_rate = 2.0 * block_push_distance / (initial_blockstun * initial_blockstun)
				block_push_velocity -= deceleration_rate * delta
				if block_push_velocity < 0:
					block_push_velocity = 0
			velocity.x = -facing_direction * block_push_velocity
			print("Debug: Block push active for %s, velocity.x=%s, initial_blockstun=%s, remaining=%s, current_speed=%s" % [name, velocity.x, initial_blockstun, block_push_timer, block_push_velocity])
		else:
			velocity.x = 0
			block_push_velocity = 0
		velocity.y += 1300 * delta
		move_and_slide()
		global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
		return
	
	var current_input_dir = input_dir
	if current_input_dir != last_input_dir:
		if last_input_dir == 0 and current_input_dir != 0:
			if pending_dash_dir == current_input_dir and neutral_timer > 0 and is_on_floor() and not is_crouching and not is_jumping:
				if current_input_dir * facing_direction > 0:
					is_dashing = true
					dash_timer = dash_time
					dash_direction = current_input_dir
					print("Debug: Dash triggered, direction: %s for %s" % [current_input_dir, name])
				elif current_input_dir * facing_direction < 0:
					is_backdashing = true
					dash_timer = backdash_time
					print("Debug: Backdash triggered, direction: %s for %s" % [current_input_dir, name])
				pending_dash_dir = 0
				neutral_timer = 0
			else:
				pending_dash_dir = current_input_dir
				neutral_timer = 0
		elif current_input_dir == 0 and last_input_dir != 0:
			neutral_timer = double_tap_timer
		else:
			pending_dash_dir = current_input_dir
			neutral_timer = 0
		last_input_dir = current_input_dir
	
	if is_dashing:
		velocity.x = dash_speed * dash_direction
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			velocity.x = 0
			dash_direction = 0.0
			print("Debug: Dash ended for %s" % name)
	elif is_backdashing:
		velocity.x = backdash_speed * -facing_direction
		dash_timer -= delta
		if dash_timer <= 0:
			is_backdashing = false
			velocity.x = 0
			print("Debug: Backdash ended for %s" % name)
	else:
		if is_on_floor():
			if is_crouching:
				velocity.x = 0
			elif not is_attacking and not is_powerkk and not is_spnk and input_dir != 0:
				if input_dir * facing_direction > 0:
					velocity.x = walk_speed * input_dir
				else:
					velocity.x = back_speed * input_dir
			else:
				velocity.x = 0
			jump_dir = 0.0
			is_jumping = false
		else:
			velocity.x = jump_dir * jump_horizontal_speed
		velocity.y += 1800 * delta
	
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing and not is_attacking and not is_powerkk and not is_spnk:
		jump_dir = input_dir
		velocity.y = -600
		is_jumping = true
		print("Debug: Jump triggered, direction: %s for %s" % [jump_dir, name])
	
	move_and_slide()
	
	global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
	
	if is_jumping and not is_on_floor():
		print("Debug: %s jump position: x=%s, y=%s" % [name, global_position.x, global_position.y])
	
	post_physics_process(delta)
	
	if is_on_floor() and was_in_air and not (is_powerkk or is_spnk):  # 修改：招式期間不更新
		update_facing_direction()
		print("Debug: Landing, forcing facing direction update for %s" % name)
	
	was_in_air = not is_on_floor()
	
	if is_on_floor() and prev_position.x != global_position.x and not (is_powerkk or is_spnk):  # 修改：招式期間不更新
		update_facing_direction()
	
	prev_position = global_position

func get_input() -> Dictionary:
	return {}

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	pass

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
		print("Debug: %s's Hurtbox detected %s's ProximityBox" % [name, area.get_parent().name])
		if is_holding_back and is_on_floor() and not is_blocking:
			is_blocking = true
			initial_blockstun = 0.1
			block_timer = 0.1
			block_type = "proximity"
			velocity.x = 0
			velocity.y = 0
			print("Debug: Proximity block triggered for %s" % name)
			block_detected.emit(name, block_type)

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false
		print("Debug: %s's Hurtbox no longer detects %s's ProximityBox" % [name, area.get_parent().name])

func update_facing_direction():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_move = move_set and (move_set.is_powerkk or move_set.is_spnk)  # 新增：檢查是否在特殊招式
	if is_special_move:
		return  # 招式期間不更新 facing_direction
	
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for player in players:
		if player != self:
			other_player = player
			break
	
	if other_player:
		var sprite_offset = sprite.position
		var other_sprite_offset = other_player.sprite.position
		var self_left = global_position.x - colbox_half_width + sprite_offset.x
		var self_right = global_position.x + colbox_half_width + sprite_offset.x
		var other_left = other_player.global_position.x - other_player.colbox_half_width + other_sprite_offset.x
		var other_right = other_player.global_position.x + other_player.colbox_half_width + other_sprite_offset.x
		
		if self_left > other_right:
			facing_direction = -1.0
			scale.x = -1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
			print("Debug: %s facing left, scale.x=%s, sprite.scale.x=%s" % [name, scale.x, sprite.scale.x])
		elif self_right < other_left:
			facing_direction = 1.0
			scale.x = 1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
			print("Debug: %s facing right, scale.x=%s, sprite.scale.x=%s" % [name, scale.x, sprite.scale.x])
		
		update_hitbox_position()
	else:
		facing_direction = 1.0
		scale.x = 1
		scale.y = 1
		sprite.scale.x = 1.0
		rotation_degrees = 0
		print("Debug: No other player found, %s defaults to facing right, sprite.scale.x=%s" % [name, sprite.scale.x])
