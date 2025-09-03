extends Fighter

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
var walk_speed = 150 # 走路速度（前進）
var back_speed = walk_speed * 0.75 # 後退速度
var jump_dir: float = 0.0 # 跳躍方向
var is_jumping: bool = false # 是否跳躍
var is_dashing: bool = false # 是否前撤
var is_backdashing: bool = false # 是否後撤
var is_attacking: bool = false # 是否攻擊
var attack_time: float = 0.4 # 攻擊動畫持續時間
var attack_timer: float = 0.0 # 攻擊計時器
var dash_speed = 130 # 前撤速度
var backdash_speed = 110 # 後撤速度
var dash_time = 0.35 # 前撤持續時間
var backdash_time = 0.4 # 後撤持續時間
var dash_timer = 0.0 # Dash計時器
var double_tap_timer = 0.3 # 雙擊時間窗口
var last_input_dir = 0 # 上一次方向輸入
var pending_dash_dir: int = 0 # 待確認方向
var neutral_timer: float = 0.0 # 中立計時器
var crouch_pressed: bool = false # 蹲伏狀態
var is_hit: bool = false # 是否受擊
var is_knockfly: bool = false # 是否被擊飛
var hit_timer: float = 0.0 # 受擊計時器
var knockfly_timer: float = 0.0 # 擊飛計時器
var knockfly_speed: float = -200.0 # 擊飛後退速度
signal hit_detected(target: String)

func _ready():
	super._ready() # 調用父類的 _ready
	animation_tree.active = true
	animation_state.travel("Walk")
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)

func _physics_process(delta):
	super._physics_process(delta) # 調用父類的 _physics_process，執行推開邏輯
	
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
	if knockfly_timer > 0:
		knockfly_timer -= delta
		if knockfly_timer <= 0 and is_knockfly:
			is_knockfly = false
			print("Debug: Knockfly ended, transitioning to wakeup")
	
	# 獲取輸入
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
					is_being_pushed = false
					print("Debug: Dash triggered, direction: %s" % current_input_dir)
				elif current_input_dir < 0:
					is_backdashing = true
					dash_timer = backdash_time
					is_being_pushed = false
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
		velocity.x = dash_speed
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false
			velocity.x = 0
			$Sprite2D.flip_h = false
			print("Debug: Dash ended")
	elif is_backdashing:
		velocity.x = -backdash_speed
		dash_timer -= delta
		if dash_timer <= 0:
			is_backdashing = false
			velocity.x = 0
			$Sprite2D.flip_h = true
			print("Debug: Backdash ended")
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
				$Sprite2D.flip_h = true
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
			jump_dir = 0.0
			is_jumping = false
		else:
			velocity.x = jump_dir * walk_speed
		velocity.y += 1300 * delta
	
		# 跳躍處理
		if jump_pressed and is_on_floor() and not crouch_pressed and not is_dashing and not is_backdashing:
			jump_dir = input_dir
			velocity.y = -400
			is_jumping = true
			is_being_pushed = false
			print("Debug: Jump triggered, direction: %s" % jump_dir)
	
	# 執行移動
	move_and_slide()
	_update_animation_state(input_dir, jump_pressed, crouch_pressed)

func _update_animation_state(dir_x: float, jump_pressed: bool, crouch_pressed: bool) -> void:
	var curr_state = animation_state.get_current_node()
	var on_floor = is_on_floor()
	# 更新動畫樹條件
	animation_tree.set("parameters/conditions/Walk", false)
	animation_tree.set("parameters/conditions/Crouch", false)
	animation_tree.set("parameters/conditions/Dash", is_dashing)
	animation_tree.set("parameters/conditions/Backdash", is_backdashing)
	animation_tree.set("parameters/conditions/St_mp", is_attacking)
	animation_tree.set("parameters/conditions/Jump_F", is_jumping and jump_dir > 0)
	animation_tree.set("parameters/conditions/Jump_B", is_jumping and jump_dir < 0)
	animation_tree.set("parameters/conditions/Jump_V", is_jumping and jump_dir == 0)
	animation_tree.set("parameters/conditions/hit", is_hit)
	animation_tree.set("parameters/conditions/knockfly", is_knockfly)
	
	if is_knockfly and curr_state != "knockfly":
		animation_state.travel("knockfly")
		print("Debug: Animation switched to knockfly")
		return
	if is_hit and curr_state != "hit":
		animation_state.travel("hit")
		print("Debug: Animation switched to hit")
		return
	if is_attacking and curr_state != "St_mp":
		animation_state.travel("St_mp")
		print("Debug: Animation switched to St_mp")
		return
	if is_dashing and curr_state != "Dash":
		animation_state.travel("Dash")
		print("Debug: Animation switched to Dash")
		return
	if is_backdashing and curr_state != "Backdash":
		animation_state.travel("Backdash")
		print("Debug: Animation switched to Backdash")
		return
	if crouch_pressed and on_floor and curr_state != "Crouch":
		animation_state.travel("Crouch")
		animation_tree.set("parameters/conditions/Crouch", true)
		print("Debug: Animation switched to Crouch")
		return
	if is_jumping and on_floor:
		is_jumping = false
		print("Debug: Landing, resetting is_jumping")
	if not on_floor and is_jumping:
		var target_jump_state = "Jump_V"
		if jump_dir > 0:
			target_jump_state = "Jump_F"
		elif jump_dir < 0:
			target_jump_state = "Jump_B"
		if curr_state != target_jump_state:
			animation_state.travel(target_jump_state)
			print("Debug: Animation switched to %s" % target_jump_state)
		return
	if curr_state != "Walk":
		animation_state.travel("Walk")
		animation_tree.set("parameters/conditions/Walk", true)
		print("Debug: Animation switched to Walk")
	animation_tree.set("parameters/Walk/blend_position", dir_x)

func take_hit():
	if not is_hit and not is_knockfly and is_on_floor():
		is_hit = true
		hit_timer = 0.28
		is_being_pushed = false
		print("Debug: Hit taken, hit_timer set to 0.28")
		_update_animation_state(0, false, false)

func take_knockfly():
	if not is_hit and not is_knockfly and is_on_floor():
		is_knockfly = true
		knockfly_timer = 0.75
		is_being_pushed = false
		print("Debug: Knockfly taken, knockfly_timer set to 0.75")
		_update_animation_state(0, false, false)

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		hit_detected.emit(target.name)
		target.take_hit()
		print("Debug: Hit detected on %s" % target.name)

# 實現父類的虛擬方法
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
