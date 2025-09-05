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
var push_speed = walk_speed * 0.5 # 推力速度
var crouch_pressed: bool = false # 蹲伏狀態
var is_hit: bool = false # 是否受擊
var is_knockfly: bool = false # 是否被擊飛
var hit_timer: float = 0.0 # 受擊計時器
var knockfly_timer: float = 0.0 # 擊飛計時器
var knockfly_speed: float = -200.0 # 擊飛後退速度
signal hit_detected(target: String)

func _ready():
	animation_tree.active = true
	animation_state.travel("Walk")
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	add_to_group("players")
	prev_position = global_position
	if collision_shape and collision_shape.shape is RectangleShape2D:
		colbox_half_width = collision_shape.shape.extents.x
		colbox_half_height = collision_shape.shape.extents.y
		print("Debug: CollisionShape2D initialized. Half width: %s, Half height: %s, Layer: %s, Mask: %s" % [colbox_half_width, colbox_half_height, collision_layer, collision_mask])
	else:
		print("Warning: CollisionShape2D not found or not RectangleShape2D. Pushback may not work correctly.")

func _physics_process(delta):
	var current_position = global_position
	is_being_pushed = false
	
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
	crouch_pressed = Input.is_action_pressed("crouch")
	var jump_pressed = Input.is_action_pressed("jump")
	var attack_pressed = Input.is_action_just_pressed("attack")
	var right_pressed = Input.is_action_pressed("move_right")
	var left_pressed = Input.is_action_pressed("move_left")
	
	# 受擊或擊飛鎖定移動
	if is_hit or is_knockfly:
		if is_knockfly:
			velocity.x = knockfly_speed
		else:
			velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		_update_animation_state(input_dir, jump_pressed, crouch_pressed)
		prev_position = current_position
		return
	
	# 攻擊時鎖定移動
	if is_attacking:
		velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		_update_animation_state(input_dir, jump_pressed, crouch_pressed)
		prev_position = current_position
		return
	
	# 檢測攻擊輸入
	if attack_pressed and is_on_floor() and not is_dashing and not is_backdashing and not crouch_pressed and not is_jumping:
		is_attacking = true
		attack_timer = attack_time
		velocity.x = 0
		move_and_slide()
		print("Debug: Attack triggered, playing St_mp")
		_update_animation_state(input_dir, jump_pressed, crouch_pressed)
		prev_position = current_position
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
			velocity.y = -450
			is_jumping = true
			is_being_pushed = false
			print("Debug: Jump triggered, direction: %s" % jump_dir)
	
	# 執行移動
	move_and_slide()
	
	# 記錄跳躍時的 XY 座標
	if is_jumping and not is_on_floor():
		print("Debug: %s jump position: x=%s, y=%s" % [name, global_position.x, global_position.y])
	
	# 移植自長版的推開邏輯
	var all_players = get_tree().get_nodes_in_group("players")
	var arena_left = 0.0
	var arena_right = ProjectSettings.get_setting("display/window/size/viewport_width")
	print("Debug: Arena boundaries: left=%s, right=%s" % [arena_left, arena_right])
	
	for other in all_players:
		if other == self:
			continue
		# 跳躍時跳過互推
		if not is_on_floor() or not other.is_on_floor():
			print("Debug: Skipping pushback for %s and %s due to airborne state" % [name, other.name])
			continue
		if is_dashing or is_backdashing or is_attacking or is_hit or is_knockfly:
			print("Debug: %s skipped pushback due to state (dashing: %s, backdashing: %s, attacking: %s, hit: %s, knockfly: %s)" % [name, is_dashing, is_backdashing, is_attacking, is_hit, is_knockfly])
			continue
		if other.is_dashing or other.is_backdashing or other.is_attacking or other.is_hit or other.is_knockfly:
			print("Debug: %s skipped pushback due to other state (dashing: %s, backdashing: %s, attacking: %s, hit: %s, knockfly: %s)" % [other.name, other.is_dashing, other.is_backdashing, other.is_attacking, other.is_hit, other.is_knockfly])
			continue
		var sprite_offset = sprite.position
		var other_sprite_offset = other.sprite.position
		var leftA = global_position.x - colbox_half_width + sprite_offset.x
		var rightA = global_position.x + colbox_half_width + sprite_offset.x
		var upA = global_position.y - colbox_half_height + sprite_offset.y
		var downA = global_position.y + colbox_half_height + sprite_offset.y
		var leftB = other.global_position.x - other.colbox_half_width + other_sprite_offset.x
		var rightB = other.global_position.x + other.colbox_half_width + other_sprite_offset.x
		var upB = other.global_position.y - other.colbox_half_height + other_sprite_offset.y
		var downB = other.global_position.y + other.colbox_half_height + other_sprite_offset.y
		print("Debug: %s collision box: left=%s, right=%s, up=%s, down=%s" % [name, leftA, rightA, upA, downA])
		print("Debug: %s collision box: left=%s, right=%s, up=%s, down=%s" % [other.name, leftB, rightB, upB, downB])
		print("Debug: Overlap check: rightA-leftB=%s, leftA-rightB=%s" % [rightA - leftB, leftA - rightB])
		var epsilon = 2.0
		if not (rightA >= leftB - epsilon and leftA <= rightB + epsilon and downA >= upB - epsilon and upA <= downB + epsilon):
			print("Debug: No overlap detected between %s and %s" % [name, other.name])
			continue
		var overlap = min(rightA - leftB, rightB - leftA)
		if overlap < -epsilon:
			print("Debug: Overlap < -epsilon between %s and %s" % [name, other.name])
			continue
		overlap = max(overlap, 8.0)
		var prevXA = prev_position.x
		var prevXB = other.prev_position.x
		var pushbackDirA = (-1 if prevXB > prevXA else 1)
		if prevXA == prevXB:
			pushbackDirA = (-1 if other.global_position.x > global_position.x else 1)
		var push_distance = overlap / 2.0
		if velocity.x * pushbackDirA > 0:
			push_distance += abs(velocity.x) * delta * 2
		if other.velocity.x * -pushbackDirA > 0:
			push_distance += abs(other.velocity.x) * delta * 2
		var new_self_x = global_position.x + pushbackDirA * push_distance
		var new_other_x = other.global_position.x - pushbackDirA * push_distance
		var sprite_width = sprite.texture.get_width() if sprite.texture else 20.0
		var other_sprite_width = other.sprite.texture.get_width() if other.sprite.texture else 20.0
		var can_push_self = new_self_x >= arena_left + colbox_half_width and new_self_x <= arena_right - colbox_half_width
		var can_push_other = new_other_x >= arena_left + other.colbox_half_width and new_other_x <= arena_right - other.colbox_half_width
		var distance_before = abs(global_position.x - other.global_position.x)
		if can_push_self:
			global_position.x = new_self_x
		else:
			global_position.x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
			print("Debug: %s pushback restricted by boundary at x=%s" % [name, new_self_x])
		if can_push_other:
			other.global_position.x = new_other_x
		else:
			other.global_position.x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
			print("Debug: %s pushback restricted by boundary at x=%s" % [other.name, new_other_x])
		is_being_pushed = true
		other.is_being_pushed = true
		var distance_after = abs(global_position.x - other.global_position.x)
		print("Debug: Pushback applied. Self: %s, Other: %s, Overlap: %s, Push dir: %s, Distance: %s, Distance change: %s -> %s" % [global_position, other.global_position, overlap, pushbackDirA, push_distance, distance_before, distance_after])
	
	_update_animation_state(input_dir, jump_pressed, crouch_pressed)
	prev_position = current_position

func _update_animation_state(dir_x: float, jump_pressed: bool, crouch_pressed: bool) -> void:
	var curr_state = animation_state.get_current_node()
	var on_floor = is_on_floor()
	var target_state = "Walk"  # 預設目標狀態，從這裡開始計算

	# 先計算目標狀態（這是新邏輯：根據優先順序決定）
	if is_knockfly:
		target_state = "knockfly"
	elif is_hit:
		target_state = "hit"
	elif is_attacking:
		target_state = "St_mp"
	elif is_dashing:
		target_state = "Dash"
	elif is_backdashing:
		target_state = "Backdash"
	elif crouch_pressed and on_floor:
		target_state = "Crouch"
	elif not on_floor and is_jumping:
		if jump_dir > 0:
			target_state = "Jump_F"
		elif jump_dir < 0:
			target_state = "Jump_B"
		else:
			target_state = "Jump_V"
	# else: 保持為"Walk"（地面正常移動）

	# 持續設定條件參數（這是關鍵修正：每幀都更新，維持狀態）
	# 不再在開頭強制設false，而是基於實際情況設true/false
	animation_tree.set("parameters/conditions/Walk", target_state == "Walk")
	animation_tree.set("parameters/conditions/Crouch", target_state == "Crouch")
	animation_tree.set("parameters/conditions/Dash", is_dashing)  # 維持原邏輯
	animation_tree.set("parameters/conditions/Backdash", is_backdashing)
	animation_tree.set("parameters/conditions/St_mp", is_attacking)
	animation_tree.set("parameters/conditions/Jump_F", target_state == "Jump_F")
	animation_tree.set("parameters/conditions/Jump_B", target_state == "Jump_B")
	animation_tree.set("parameters/conditions/Jump_V", target_state == "Jump_V")
	animation_tree.set("parameters/conditions/hit", is_hit)
	animation_tree.set("parameters/conditions/knockfly", is_knockfly)

	# 只在需要時切換狀態（避免重複travel導致跳幀）
	if curr_state != target_state:
		animation_state.travel(target_state)
		print("Debug: Animation switched to %s" % target_state)  # 幫助你追蹤

	# 如果是Walk，設定blend_position（維持原邏輯）
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", dir_x)

	# 額外檢查：落地時重置跳躍旗標（維持原邏輯）
	if is_jumping and on_floor:
		is_jumping = false
		print("Debug: Landing, resetting is_jumping")

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
