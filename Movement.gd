class_name Movement extends CharacterBody2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
var walk_speed: float = 150.0
var back_speed: float = walk_speed * 0.75
var jump_horizontal_speed: float = 130.0
var jump_dir: float = 0.0
var is_jumping: bool = false
var is_dashing: bool = false
var is_backdashing: bool = false
var is_attacking: bool = false
var attack_time: float = 0.4
var attack_timer: float = 0.0
var dash_speed: float = 130.0
var backdash_speed: float = 110.0
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
var knockfly_speed: float = -200.0
var facing_direction: float = 1.0
var dash_direction: float = 0.0
var is_blocking: bool = false
var is_holding_back: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"
signal block_detected(target: String, block_type: String)

func _ready():
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	else:
		print("Warning: AnimationTree not found for %s" % name)
	if has_node("Hurtbox"):
		$Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		$Hurtbox.area_exited.connect(_on_hurtbox_area_exited)

func _physics_process(delta):
	var current_position = global_position
	
	# 更新計時器
	if neutral_timer > 0:
		neutral_timer -= delta
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
			if has_node("Proximitybox/ProxShape"):
				$Proximitybox/ProxShape.disabled = true
				print("Debug: ProximityBox disabled after attack for %s" % name)
			print("Debug: Attack ended, is_attacking set to false for %s" % name)
	if hit_timer > 0:
		hit_timer -= delta
		if hit_timer <= 0:
			is_hit = false
			print("Debug: Hit taken for %s" % name)
	if block_timer > 0:
		block_timer -= delta
		if block_timer <= 0:
			is_blocking = false
			block_type = "none"
			print("Debug: Block ended, is_blocking set to false for %s" % name)
	if knockfly_timer > 0:
		knockfly_timer -= delta
		if knockfly_timer <= 0 and is_knockfly:
			var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
			if healthbar and healthbar.current_health <= 0:
				print("Debug: Health is zero, staying in knockfly for %s" % name)
			else:
				is_knockfly = false
				print("Debug: Knockfly ended, transitioning to wakeup for %s" % name)
	
	# 獲取輸入
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	
	# 更新蹲伏狀態
	is_crouching = crouch_pressed
	
	# 檢測是否按住遠離對手的方向
	is_holding_back = false
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not is_crouching and not jump_pressed:
		if input_dir * facing_direction < 0:
			is_holding_back = true
			print("Debug: Holding back detected for %s" % name)
	
	# 動態更新面向
	if is_on_floor():
		update_facing_direction()
	
	# 受擊或擊飛鎖定移動
	if is_hit or is_knockfly:
		if is_knockfly:
			velocity.x = knockfly_speed * facing_direction
		else:
			velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		return
	
	# 格擋鎖定移動
	if is_blocking:
		velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		return
	
	# 雙擊檢測邏輯
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
	
	# Dash 或 Backdash 處理
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
		# 正常移動處理
		if is_on_floor():
			if is_crouching:
				velocity.x = 0
			elif input_dir != 0:
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
	
	# 跳躍處理
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing:
		jump_dir = input_dir
		velocity.y = -600
		is_jumping = true
		print("Debug: Jump triggered, direction: %s for %s" % [jump_dir, name])
	
	# 執行移動
	move_and_slide()
	
	# 記錄跳躍時的 XY 座標
	if is_jumping and not is_on_floor():
		print("Debug: %s jump position: x=%s, y=%s" % [name, global_position.x, global_position.y])

func get_input() -> Dictionary:
	return {"input_dir": 0, "crouch_pressed": false, "jump_pressed": false, "attack_pressed": false}

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

func update_hitbox_position():
	pass

func update_facing_direction():
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for player in players:
		if player != self:
			other_player = player
			break
	
	if other_player:
		print("Debug: Updating facing direction for %s. Self x=%s, Other x=%s, Other name=%s" % [name, global_position.x, other_player.global_position.x, other_player.name])
		if global_position.x > other_player.global_position.x:
			facing_direction = -1.0
			$Sprite2D.flip_h = true
			print("Debug: %s facing left (flip_h = true)" % name)
		else:
			facing_direction = 1.0
			$Sprite2D.flip_h = false
			print("Debug: %s facing right (flip_h = false)" % name)
		update_hitbox_position()
	else:
		print("Warning: No other player found in group 'players' for %s" % name)
