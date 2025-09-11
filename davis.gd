class_name Davis extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

var current_damage: float = 0.0  # 記錄當前攻擊的傷害值
var is_powerkk: bool = false  # powerkk 狀態
var powerkk_time: float = 0.6  # powerkk 持續時間
var powerkk_timer: float = 0.0  # powerkk 計時器

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	else:
		print("Warning: Hitbox not found for %s" % name)
	$Sprite2D.flip_h = false
	facing_direction = 1.0
	add_to_group("players")
	update_hitbox_position()

func get_input() -> Dictionary:
	var input_dir = 0
	var crouch_pressed = Input.is_action_pressed("crouch")
	var jump_pressed = Input.is_action_pressed("jump")
	var attack_pressed = Input.is_action_just_pressed("attack")
	var right_pressed = Input.is_action_pressed("move_right")
	var left_pressed = Input.is_action_pressed("move_left")
	var spm1_pressed = Input.is_action_just_pressed("spmove1")
	
	if right_pressed and left_pressed:
		input_dir = 0
	elif right_pressed:
		input_dir = 1
	elif left_pressed:
		input_dir = -1
	
	var attack_type = "light" if attack_pressed else "none"
	var blockstun_duration = 0.2 if attack_type == "light" else 0.4
	var damage = 10.0 if attack_type == "light" else 0.0
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"attack_pressed": attack_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed
	}

func _physics_process(delta):
	super._physics_process(delta)
	var input_data = get_input()
	
	# 處理 powerkk 輸入
	if input_data.spm1_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping and not is_powerkk:
		is_powerkk = true
		powerkk_timer = powerkk_time
		velocity.x = 0  # 鎖定移動，忽略輸入
		if has_node("AnimationPlayer"):
			# 新增：設置 Sprite2D.scale.x 根據 facing_direction 翻轉動畫方向
			$Sprite2D.scale.x = facing_direction
			$AnimationPlayer.play("powerkk")  # 播放正向動畫，方向由 scale.x 控制
			print("Debug: Powerkk animation played with scale.x = %s for facing_direction %s" % [$Sprite2D.scale.x, facing_direction])
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = false
			print("Debug: Hitbox enabled for powerkk in %s" % name)
		move_and_slide()
		print("Debug: Powerkk triggered for %s" % name)
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
		return
	
	# 如果處於 powerkk，鎖定移動（忽略輸入）
	if is_powerkk:
		velocity.x = 0  # 持續鎖定，防止輸入影響軌跡
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			is_powerkk = false
			if has_node("Hitbox/HitShape"):
				$Hitbox/HitShape.disabled = true
				print("Debug: Hitbox disabled after powerkk for %s" % name)
			if has_node("AnimationPlayer"):
				var final_position = $Sprite2D.position
				$AnimationPlayer.stop()  # 停止動畫
				$Sprite2D.position = final_position  # 保留最終位置
				global_position.x += final_position.x  # 更新 CharacterBody2D 位置
				$Sprite2D.position.x = 0  # 重置 Sprite2D 相對位置
				$Sprite2D.scale.x = 1.0  # 恢復 scale.x，防止影響其他動畫
				print("Debug: Applied final position %s for %s after powerkk" % [global_position, name])
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	# 處理普通攻擊
	if input_data.attack_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping:
		current_damage = input_data.damage

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
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
	elif is_powerkk:
		target_state = "powerkk"
	elif crouch_input and on_floor:
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
	animation_tree.set("parameters/conditions/powerkk", is_powerkk)

	if curr_state != target_state:
		animation_state.travel(target_state)
		print("Debug: Animation switched to %s for %s" % [target_state, name])

	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)

	if is_jumping and on_floor:
		is_jumping = false
		print("Debug: Landing, resetting is_jumping for %s" % name)

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		if is_powerkk:
			target.take_knockfly()
			print("Debug: Powerkk hit detected on %s, triggering knockfly" % target.name)
		else:
			target.take_hit(blockstun_duration, current_damage)
			var is_blocked = target.is_blocking and target.block_type == "ordinary"
			hit_detected.emit(target.name, blockstun_duration, is_blocked)
			print("Debug: Hit detected on %s with blockstun duration %s, damage %s, is_blocked: %s" % [target.name, blockstun_duration, current_damage, is_blocked])
		current_damage = 0.0

func get_facing_multiplier() -> float:
	return 1.0

func update_hitbox_position():
	if has_node("Hitbox/HitShape"):
		$Hitbox.scale.x = facing_direction
	if has_node("Proximitybox/ProxShape"):
		$Proximitybox.scale.x = facing_direction
