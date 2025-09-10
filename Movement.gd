class_name Movement extends CharacterBody2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
var walk_speed: float = 150.0 # 走路速度（前進）
var back_speed: float = walk_speed * 0.75 # 後退速度
var jump_horizontal_speed: float = 130.0 # 跳躍水平速度
var jump_dir: float = 0.0 # 跳躍方向
var is_jumping: bool = false # 是否跳躍
var is_dashing: bool = false # 是否前撤
var is_backdashing: bool = false # 是否後撤
var is_attacking: bool = false # 是否攻擊
var attack_time: float = 0.4 # 攻擊動畫持續時間
var attack_timer: float = 0.0 # 攻擊計時器
var dash_speed: float = 130.0 # 前撤速度
var backdash_speed: float = 110.0 # 後撤速度
var dash_time: float = 0.35 # 前撤持續時間
var backdash_time: float = 0.4 # 後撤持續時間
var dash_timer: float = 0.0 # Dash計時器
var double_tap_timer: float = 0.3 # 雙擊時間窗口
var last_input_dir: int = 0 # 上一次方向輸入
var pending_dash_dir: int = 0 # 待確認方向
var neutral_timer: float = 0.0 # 中立計時器
var crouch_pressed: bool = false # 蹲伏狀態
var is_hit: bool = false # 是否受擊
var is_knockfly: bool = false # 是否被擊飛
var hit_timer: float = 0.0 # 受擊計時器
var block_timer: float = 0.0 # 格擋持續時間計時器
var knockfly_timer: float = 0.0 # 擊飛計時器
var knockfly_speed: float = -200.0 # 擊飛後退速度
var facing_direction: float = 1.0 # 角色面向（1.0 向右，-1.0 向左）
var dash_direction: float = 0.0 # Dash 方向
var is_blocking: bool = false # 是否在格擋狀態
var is_holding_back: bool = false # 是否按住遠離對手的方向

func _ready():
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	else:
		print("Warning: AnimationTree not found for %s" % name)

func _physics_process(delta):
	var current_position = global_position
	
	# 更新計時器
	if neutral_timer > 0:
		neutral_timer -= delta
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
			print("Debug: Attack ended, is_attacking set to false")
	if hit_timer > 0:
		hit_timer -= delta
		if hit_timer <= 0:
			is_hit = false
			print("Debug: Hit ended, is_hit set to false")
	if block_timer > 0:
		block_timer -= delta
		if block_timer <= 0:
			is_blocking = false
			print("Debug: Block ended, is_blocking set to false")
	if knockfly_timer > 0:
		knockfly_timer -= delta
		if knockfly_timer <= 0 and is_knockfly:
			is_knockfly = false
			print("Debug: Knockfly ended, transitioning to wakeup")
	
	# 獲取輸入
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	var attack_pressed = input_data["attack_pressed"]
	
	# 檢測是否按住遠離對手的方向
	is_holding_back = false
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not crouch_pressed and not jump_pressed:
		if input_dir * facing_direction < 0:
			is_holding_back = true
			print("Debug: Holding back detected")
	
	# 動態更新面向
	if is_on_floor():
		update_facing_direction()
	
	# 受擊、擊飛或格擋鎖定移動
	if is_hit or is_knockfly or is_blocking:
		if is_knockfly:
			velocity.x = knockfly_speed * facing_direction
		else:
			velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		_update_animation_state(input_dir, jump_pressed, crouch_pressed)
		return
	
	# 攻擊時鎖定移動
	if is_attacking:
		velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		_update_animation_state(input_dir, jump_pressed, crouch_pressed)
		return
	
	# 檢測攻擊輸入
	if attack_pressed and is_on_floor() and not is_dashing and not is_backdashing and not crouch_pressed and not is_jumping:
		is_attacking = true
		attack_timer = attack_time
		velocity.x = 0
		move_and_slide()
		print("Debug: Attack triggered, playing St_mp")
		_update_animation_state(input_dir, jump_pressed, crouch_pressed)
		return
	
	# 雙擊檢測邏輯
	var current_input_dir = input_dir
	if current_input_dir != last_input_dir:
		if last_input_dir == 0 and current_input_dir != 0:
			if pending_dash_dir == current_input_dir and neutral_timer > 0 and is_on_floor() and not crouch_pressed and not is_jumping:
				if current_input_dir * facing_direction > 0:
					is_dashing = true
					dash_timer = dash_time
					dash_direction = current_input_dir
					print("Debug: Dash triggered, direction: %s" % current_input_dir)
				elif current_input_dir * facing_direction < 0:
					is_backdashing = true
					dash_timer = backdash_time
					print("Debug: Backdash triggered, direction: %s" % current_input_dir)
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
			print("Debug: Dash ended")
	elif is_backdashing:
		velocity.x = backdash_speed * -facing_direction
		dash_timer -= delta
		if dash_timer <= 0:
			is_backdashing = false
			velocity.x = 0
			print("Debug: Backdash ended")
	else:
		# 正常移動處理
		if is_on_floor():
			if crouch_pressed:
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
		if jump_pressed and is_on_floor() and not crouch_pressed and not is_dashing and not is_backdashing:
			jump_dir = input_dir
			velocity.y = -600
			is_jumping = true
			print("Debug: Jump triggered, direction: %s" % jump_dir)
	
	# 執行移動
	move_and_slide()
	
	# 記錄跳躍時的 XY 座標
	if is_jumping and not is_on_floor():
		print("Debug: %s jump position: x=%s, y=%s" % [name, global_position.x, global_position.y])
	
	_update_animation_state(input_dir, jump_pressed, crouch_pressed)

func _update_animation_state(dir_x: float, jump_pressed: bool, crouch_pressed: bool) -> void:
	var curr_state = animation_state.get_current_node()
	var on_floor = is_on_floor()
	var target_state = "Walk"

	var anim_dir = dir_x * facing_direction
	var anim_jump_dir = jump_dir * facing_direction

	if is_knockfly:
		target_state = "knockfly"
	elif is_hit:
		target_state = "hit"
	elif is_blocking:
		target_state = "block"
	elif is_attacking:
		target_state = "St_mp"
	elif is_dashing:
		target_state = "Dash"
	elif is_backdashing:
		target_state = "Backdash"
	elif crouch_pressed and on_floor:
		target_state = "Crouch"
	elif not on_floor and is_jumping:
		if anim_jump_dir > 0:
			target_state = "Jump_F"
		elif anim_jump_dir < 0:
			target_state = "Jump_B"
		else:
			target_state = "Jump_V"

	animation_tree.set("parameters/conditions/Walk", target_state == "Walk")
	animation_tree.set("parameters/conditions/Crouch", target_state == "Crouch")
	animation_tree.set("parameters/conditions/Dash", is_dashing)
	animation_tree.set("parameters/conditions/Backdash", is_backdashing)
	animation_tree.set("parameters/conditions/St_mp", is_attacking)
	animation_tree.set("parameters/conditions/Jump_F", target_state == "Jump_F")
	animation_tree.set("parameters/conditions/Jump_B", target_state == "Jump_B")
	animation_tree.set("parameters/conditions/Jump_V", target_state == "Jump_V")
	animation_tree.set("parameters/conditions/hit", is_hit)
	animation_tree.set("parameters/conditions/knockfly", is_knockfly)
	animation_tree.set("parameters/conditions/block", is_blocking)

	if curr_state != target_state:
		animation_state.travel(target_state)
		print("Debug: Animation switched to %s" % target_state)

	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)

	if is_jumping and on_floor:
		is_jumping = false
		print("Debug: Landing, resetting is_jumping")

func take_hit():
	if not is_hit and not is_knockfly and is_on_floor():
		if is_holding_back:
			is_blocking = true
			block_timer = 0.28
			velocity.x = 0
			velocity.y = 0
			print("Debug: Block successful, movement locked, playing block animation")
		else:
			is_hit = true
			hit_timer = 0.28
			print("Debug: Hit taken, hit_timer set to 0.28")
		_update_animation_state(0, false, false)

func take_knockfly():
	if not is_hit and not is_knockfly and is_on_floor():
		is_knockfly = true
		knockfly_timer = 0.75
		print("Debug: Knockfly taken, knockfly_timer set to 0.75")
		_update_animation_state(0, false, false)

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

func update_hitbox_position():
	if has_node("Hitbox/HitShape"):
		var hitbox = $Hitbox/HitShape
		$Hitbox.scale.x = facing_direction

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
