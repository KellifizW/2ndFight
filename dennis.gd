extends CharacterBody2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")

var walk_speed = 150  # 走路速度（前進）
var back_speed = walk_speed * 0.75  # 後退速度
var jump_dir: float = 0.0  # 跳躍方向
var is_jumping: bool = false  # 是否跳躍
var is_dashing: bool = false  # 是否前撤
var is_backdashing: bool = false  # 是否後撤
var is_attacking: bool = false  # 是否攻擊
var attack_time: float = 0.4  # 攻擊動畫持續時間
var attack_timer: float = 0.0  # 攻擊計時器
var dash_speed = 130  # 前撤速度
var backdash_speed = 110  # 後撤速度
var dash_time = 0.35  # 前撤持續時間
var backdash_time = 0.4  # 後撤持續時間
var dash_timer = 0.0  # Dash計時器
var double_tap_timer = 0.3  # 雙擊時間窗口
var last_input_dir = 0  # 上一次方向輸入
var pending_dash_dir: int = 0  # 待確認方向
var neutral_timer: float = 0.0  # 中立計時器
var push_speed = walk_speed * 0.5  # 推力速度
var crouch_pressed: bool = false  # 蹲伏狀態
var is_being_pushed: bool = false  # 是否正在被推
var is_hit: bool = false  # 是否受擊
var is_knockfly: bool = false  # 是否被擊飛
var hit_timer: float = 0.0  # 受擊計時器
var knockfly_timer: float = 0.0  # 擊飛計時器
var knockfly_speed: float = -200.0  # 擊飛後退速度

signal hit_detected(target: String)  # 新增信號，用來通知打擊偵測

func _ready():
	animation_tree.active = true
	animation_state.travel("Walk")  # 初始動畫
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)  # 新增連接 Hitbox 的 area_entered 信號

func _physics_process(delta):
	# 重置推力狀態（每幀開始時假設無推力）
	is_being_pushed = false

	# 更新計時器
	if neutral_timer > 0:
		neutral_timer -= delta
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
	if hit_timer > 0:
		hit_timer -= delta
		if hit_timer <= 0:
			is_hit = false
			animation_state.travel("Walk")
	if knockfly_timer > 0:
		knockfly_timer -= delta
		if knockfly_timer <= 0:
			if is_knockfly:
				is_knockfly = false
				animation_state.travel("wakeup")
			else:
				animation_state.travel("Walk")

	var input_dir = 0
	crouch_pressed = Input.is_action_pressed("crouch_p2")
	var jump_pressed = Input.is_action_pressed("jump_p2")
	var attack_pressed = Input.is_action_just_pressed("attack_p2")
	var right_pressed = Input.is_action_pressed("move_right_p2")
	var left_pressed = Input.is_action_pressed("move_left_p2")

	# 受擊或擊飛鎖定移動
	if is_hit or is_knockfly:
		if is_knockfly:
			velocity.x = knockfly_speed
		else:
			velocity.x = 0
		move_and_slide()
		return

	# 攻擊時鎖定移動
	if is_attacking:
		velocity.x = 0
		velocity.y += 1300 * delta  # 保持重力
		move_and_slide()
		return

	# 檢測攻擊輸入
	if attack_pressed and is_on_floor() and not is_dashing and not is_backdashing and not crouch_pressed and not is_jumping:
		is_attacking = true
		attack_timer = attack_time
		animation_state.travel("St_mp")
		velocity.x = 0
		move_and_slide()
		return

	# 雙擊檢測邏輯
	var current_input_dir = 0
	if right_pressed and left_pressed:
		current_input_dir = 0
	elif right_pressed and not left_pressed:
		current_input_dir = 1
	elif left_pressed and not right_pressed:
		current_input_dir = -1
	
	if current_input_dir != last_input_dir:
		if last_input_dir == 0 and current_input_dir != 0:
			if pending_dash_dir == current_input_dir and neutral_timer > 0 and is_on_floor() and not crouch_pressed and not is_jumping:
				if current_input_dir > 0:
					is_dashing = true
					dash_timer = dash_time
					is_being_pushed = false  # 重置推力狀態
					animation_state.travel("Dash")
				elif current_input_dir < 0:
					is_backdashing = true
					dash_timer = backdash_time
					is_being_pushed = false  # 重置推力狀態
					animation_state.travel("Backdash")
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
		velocity.x = dash_speed
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			velocity.x = 0
		$Sprite2D.flip_h = false
	elif is_backdashing:
		velocity.x = -backdash_speed
		dash_timer -= delta
		if dash_timer <= 0:
			is_backdashing = false
			velocity.x = 0
		$Sprite2D.flip_h = false
	else:
		# 正常移動邏輯
		if crouch_pressed and is_on_floor():
			input_dir = 0
		else:
			if right_pressed and left_pressed:
				input_dir = 0
			elif right_pressed:
				input_dir = 1
				$Sprite2D.flip_h = false
			elif left_pressed:
				input_dir = -1
				$Sprite2D.flip_h = false
			else:
				input_dir = 0

		# 設置速度
		if is_on_floor():
			if input_dir > 0:
				velocity.x = input_dir * walk_speed
			elif input_dir < 0:
				velocity.x = input_dir * back_speed
			else:
				velocity.x = 0
			jump_dir = 0.0  # 落地時重置跳躍方向
			is_jumping = false
		else:
			velocity.x = jump_dir * walk_speed  # 空中保持跳躍開始時的水平速度

	velocity.y += 1300 * delta  # 重力

	# 跳躍處理
	if jump_pressed and is_on_floor() and not crouch_pressed and not is_dashing and not is_backdashing:
		jump_dir = input_dir
		velocity.y = -400
		is_jumping = true
		is_being_pushed = false  # 跳躍時重置推力狀態
		var target_jump_state = ""
		if jump_dir > 0:
			target_jump_state = "Jump_F"
		elif jump_dir < 0:
			target_jump_state = "Jump_B"
		else:
			target_jump_state = "Jump_V"
		animation_state.travel(target_jump_state)

	# 執行移動並檢測碰撞
	move_and_slide()

	# 檢查碰撞並應用推力
	for i in get_slide_collision_count():
		var slide_collision = get_slide_collision(i)
		var collider = slide_collision.get_collider()
		if collider is CharacterBody2D and collider != self:
			if collider.is_on_floor() and not collider.is_dashing and not collider.is_backdashing and not collider.is_attacking and not is_attacking:
				var push_direction = sign(velocity.x)
				if push_direction != 0:
					collider.is_being_pushed = true
					collider.velocity.x = push_direction * push_speed
					collider.move_and_slide()

	_update_animation_state(input_dir, jump_pressed, crouch_pressed)

func _update_animation_state(dir_x: float, jump_pressed: bool, crouch_pressed: bool) -> void:
	var curr_state = animation_state.get_current_node()
	var on_floor = is_on_floor()

	if is_attacking or is_dashing or is_backdashing or is_hit or is_knockfly:
		return

	if crouch_pressed and on_floor:
		if curr_state != "Crouch":
			animation_state.travel("Crouch")
		return

	if not on_floor:
		if is_jumping:
			pass
		return

	if curr_state != "Walk":
		animation_state.travel("Walk")
	animation_tree.set("parameters/Walk/blend_position", dir_x)

func take_hit():
	if not is_hit and not is_knockfly and is_on_floor():
		is_hit = true
		hit_timer = 0.28  # 與 hit 動畫長度一致
		is_being_pushed = false  # 受擊時重置推力狀態
		animation_state.travel("hit")

func take_knockfly():
	if not is_hit and not is_knockfly and is_on_floor():
		is_knockfly = true
		knockfly_timer = 0.75  # 與 knockfly 動畫長度一致
		is_being_pushed = false  # 擊飛時重置推力狀態
		animation_state.travel("knockfly")

func _on_hitbox_area_entered(area: Area2D):  # 新增函數，用來偵測打擊
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		hit_detected.emit(target.name)
		target.take_hit()
