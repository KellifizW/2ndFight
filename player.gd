class_name Player extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

@export var player_id: String = "p1" # 用於區分玩家1或玩家2的輸入
@export var is_ai_controlled: bool = false  # 新增：AI控制開關
@onready var move_set = $MoveSet if has_node("MoveSet") else null

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	else:
		print("Warning: Hitbox not found for %s" % name)
	if move_set and player_id != "p1" and player_id != "p2":
		print("Warning: MoveSet node found for %s, but only P1 or P2 should have MoveSet" % name)
	add_to_group("players")

func get_input() -> Dictionary:
	if is_ai_controlled:  # 如果AI開關，呼叫AI子節點
		var ai_behavior = $AIBehavior if has_node("AIBehavior") else null
		if ai_behavior:
			return ai_behavior.get_ai_input()
		else:
			print("Warning: AIBehavior node not found for %s, falling back to manual input" % name)
	
	# 原來的玩家輸入邏輯（不變）
	var input_dir = 0
	var crouch_pressed = Input.is_action_pressed("crouch" + ("_p2" if player_id == "p2" else ""))
	var jump_pressed = Input.is_action_pressed("jump" + ("_p2" if player_id == "p2" else ""))
	var attack_pressed = Input.is_action_just_pressed("attack" + ("_p2" if player_id == "p2" else ""))
	var right_pressed = Input.is_action_pressed("move_right" + ("_p2" if player_id == "p2" else ""))
	var left_pressed = Input.is_action_pressed("move_left" + ("_p2" if player_id == "p2" else ""))
	var spm1_pressed = Input.is_action_just_pressed("spmove1" + ("_p2" if player_id == "p2" else "")) 
	
	if right_pressed and left_pressed:
		input_dir = 0
	elif right_pressed:
		input_dir = 1
	elif left_pressed:
		input_dir = -1
	
	var attack_type = "attack" if attack_pressed else "none"
	var blockstun_duration = 0.4 if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")) else 0.2
	var damage = move_set.get_special_damage() if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")) else (10.0 if attack_pressed else 0.0)
	
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
	
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping
	
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_state):
		return
	
	if input_data.attack_pressed and is_valid_state:
		current_damage = input_data.damage
		is_attacking = true
		attack_timer = attack_time
		velocity.x = 0
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = false
			print("Debug: Hitbox enabled during attack for %s" % name)
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = false
			print("Debug: ProximityBox enabled during attack for %s" % name)
	
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var was_special = move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2"))
	if was_special:
		var curr_state = animation_state.get_current_node() if animation_state else ""
		var target_state = "powerkk" if player_id == "p1" else "spnk"
		animation_tree.set("parameters/conditions/powerkk", player_id == "p1")
		animation_tree.set("parameters/conditions/spnk", player_id == "p2")
		if curr_state != target_state:
			animation_state.travel(target_state)
			print("Debug: Animation switched to %s for %s, sprite.scale.x=%s" % [target_state, name, sprite.scale.x])
	else:
		super._update_animation_state(dir_x, crouch_input)
		animation_tree.set("parameters/conditions/powerkk", false)
		animation_tree.set("parameters/conditions/spnk", false)
		if was_special:
			update_facing_direction()  # 特殊招式結束後更新面向
			print("Debug: Special move ended, updating facing direction for %s, sprite.scale.x=%s" % [name, sprite.scale.x])

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		var damage = current_damage
		target.take_hit(blockstun_duration, damage)
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		hit_detected.emit(target.name, blockstun_duration, is_blocked)
		print("Debug: Hit detected on %s with blockstun duration %s, damage %s, is_blocked: %s" % [target.name, blockstun_duration, damage, is_blocked])
		current_damage = 0.0
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
			print("Debug: Hitbox disabled after hit for %s" % name)

func get_facing_multiplier() -> float:
	return facing_direction

# 修改：移除 is_on_floor() 限制，並根據 damage 區分空中普通攻擊和特殊招式
func take_hit(blockstun_duration: float = 0.2, damage: float = 10.0):
	if not is_hit and not is_knockfly:
		if is_holding_back and is_opponent_proximity and is_on_floor():  # 空中不允許格擋
			is_blocking = true
			initial_blockstun = 0.267  # 固定0.267秒blockstun
			block_timer = initial_blockstun
			block_type = "ordinary"
			velocity.x = 0
			velocity.y = 0
			block_push_timer = initial_blockstun  # 同步計時器
			block_push_velocity = 2.0 * block_push_distance / initial_blockstun  # 初始速度（三角形平均，讓總距離精準）
			print("Debug: Ordinary block successful, blockstun duration %s for %s" % [initial_blockstun, name])
			block_detected.emit(name, block_type)
		else:
			if healthbar:
				healthbar.take_damage(damage)
				if damage == 20.0:  # powerkk 或 spnk，空中與地面一致
					is_knockfly = true
					knockfly_timer = 0.75
					print("Debug: Special move hit (powerkk/spnk), triggering knockfly for %s" % name)
				elif healthbar.current_health <= 0:  # 血量歸零，空中與地面一致
					is_knockfly = true
					knockfly_timer = 0.75
					print("Debug: Health reached zero, triggering knockfly for %s" % name)
				else:
					if is_on_floor():  # 地面普通攻擊：hitstun
						is_hit = true
						initial_hitstun = 0.35
						hit_timer = initial_hitstun
						hit_push_timer = initial_hitstun
						hit_push_velocity = 2.0 * hit_push_distance / initial_hitstun
						velocity.x = 0
						velocity.y = 0
						print("Debug: Ground hitstun triggered, duration %s for %s, damage %s" % [initial_hitstun, name, damage])
					else:  # 空中普通攻擊：knockfly，後退 40px
						is_knockfly = true
						knockfly_timer = 0.75
						# 設置空中普通攻擊的後退距離（在 Movement.gd 中處理速度）
						if "air_hit_knockfly_distance" in self:
							set("air_hit_knockfly_distance", 40.0)
						if "is_air_hit_knockfly" in self:
							set("is_air_hit_knockfly", true)
						velocity.x = 0
						velocity.y = 0
						print("Debug: Air hit by normal attack, triggering knockfly with 40px pushback for %s" % name)
			else:
				is_hit = true
				initial_hitstun = 0.35
				hit_timer = initial_hitstun
				hit_push_timer = initial_hitstun
				hit_push_velocity = 2.0 * hit_push_distance / initial_hitstun
				print("Warning: No healthbar, hitstun triggered without damage for %s" % name)
		_update_animation_state(0, is_crouching)
