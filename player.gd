class_name Player extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

@export var player_id: String = "p1"
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 20.0
@export var landing_duration: float = 0.2  # 落地動畫持續時間
@onready var move_set = $MoveSet if has_node("MoveSet") else null

var current_mode: String = "ground_stand"
var attack_type: String = "none"
var is_landing: bool = false
var is_wakeup: bool = false
var is_wakeup_locked: bool = false
var is_air_attacking: bool = false
var is_special_moving: bool = false
var debug_jump_sequence: bool = true  # 控制跳躍序列除錯
var landing_lock_timer: float = 0.0  # 鎖定過渡計時器，防止 Walk 自動覆蓋

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
		var hit_shape = $Hitbox.get_node_or_null("HitShape")
		if hit_shape and hit_shape is CollisionShape2D:
			hit_shape.disabled = true
	if animation_tree and not animation_tree.animation_finished.is_connected(_on_animation_tree_finished):
		animation_tree.animation_finished.connect(_on_animation_tree_finished)
		animation_tree.active = true
		animation_state.travel("Walk")
	add_to_group("players")

func get_input() -> Dictionary:
	if is_knockfly or is_wakeup or is_hit:
		return {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"attack_pressed": false,
			"attack_type": "none",
			"blockstun_duration": 0.2,
			"damage": 0.0,
			"spm1_pressed": false
		}
	if is_ai_controlled:
		var ai_behavior = $AIBehavior if has_node("AIBehavior") else null
		if ai_behavior:
			return ai_behavior.get_ai_input()
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
	var input_dict = {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"attack_pressed": attack_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed
	}
	if move_set and move_set.is_spmove:
		return {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"attack_pressed": false,
			"attack_type": "none",
			"blockstun_duration": 0.2,
			"damage": 0.0,
			"spm1_pressed": false
		}
	return input_dict

func _physics_process(delta):
	super._physics_process(delta)
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	
	var input_data = get_input()
	var is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup
	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup
	var hit_shape = $Hitbox.get_node_or_null("HitShape") if has_node("Hitbox") else null
	if hit_shape and hit_shape is CollisionShape2D:
		if move_set and (move_set.is_powerkk or move_set.is_spnk) or is_attacking:
			pass
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_ground_state):
		return
	if input_data.attack_pressed and is_valid_ground_state:
		current_damage = input_data.damage
		is_attacking = true
		attack_timer = attack_time
		attack_type = input_data.attack_type
		fixed_velocity.x = 0
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = false
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = false
	elif input_data.attack_pressed and is_valid_air_state:
		current_damage = input_data.damage
		is_air_attacking = true
		attack_type = "jump_mk"
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = false
	if is_attacking and attack_timer <= 0:
		is_attacking = false
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = true
		update_facing_direction()
	# 更新 landing_lock_timer
	if landing_lock_timer > 0:
		landing_lock_timer -= delta
		if debug_jump_sequence:
			print("Debug Jump Seq [%s]: Landing locked (remaining: %.2f sec)." % [name, landing_lock_timer])
	# 新增：檢查 landing 動畫期間的輸入以打斷
	if is_landing and landing_lock_timer > 0:
		if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.attack_pressed or input_data.spm1_pressed:
			is_landing = false
			landing_lock_timer = 0.0
			landing_facing_lock = false  # 釋放面向鎖定，允許立即轉向
			update_facing_direction()  # 打斷時立即更新面向
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Landing interrupted by input, transitioning to '%s'." % [name, animation_state.get_current_node() if animation_state else "none"])
			return
	# 檢查落地邏輯
	if not is_jumping and is_on_floor():
		var curr_state = animation_state.get_current_node() if animation_state else "none"
		if curr_state in ["Jump_V", "Jump_F", "Jump_B", "jump_mk"] and not is_wakeup and not is_hit and not is_knockfly:
			if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.attack_pressed or input_data.spm1_pressed:
				is_landing = false
				landing_facing_lock = false  # 釋放面向鎖定，允許立即轉向
				update_facing_direction()  # 跳過landing時立即更新面向
				_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
				if debug_jump_sequence:
					print("Debug Jump Seq [%s]: Input detected on landing, skipping 'landing' to '%s'." % [name, animation_state.get_current_node() if animation_state else "none"])
			else:
				is_landing = true
				animation_state.travel("landing")
				landing_lock_timer = landing_duration
				if debug_jump_sequence:
					print("Debug Jump Seq [%s]: Landing detected, transitioning to 'landing' state (lock: %.2f sec)." % [name, landing_duration])
			return
		# 修改：當 curr_state == "landing" 時，不設 is_landing = false，讓它繼續播放
		elif curr_state == "landing":
			return  # 防止干擾 landing 播放
		else:
			is_landing = false
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	if is_wakeup:
		fixed_velocity = Vector2i.ZERO
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var curr_state = animation_state.get_current_node() if animation_state else "none"
	var on_floor = is_on_floor()
	var relative_jump_dir = jump_dir * facing_direction
	# 先檢查優先狀態（如 hit, knockfly, attacking 等），允許它們打斷 landing
	if not on_floor and (is_jumping or is_air_attacking):
		is_landing = false
		if is_air_attacking:
			var target_state = "jump_mk"
			if curr_state != "jump_mk":
				animation_state.travel("jump_mk")
				if debug_jump_sequence:
					print("Debug Jump Seq [%s]: Air attack, transitioning to 'jump_mk'." % name)
			return
		if is_jumping and relative_jump_dir == 0 and curr_state != "Jump_V":
			animation_state.travel("Jump_V")
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Neutral jump, transitioning to 'Jump_V'." % name)
		elif is_jumping and relative_jump_dir > 0 and curr_state != "Jump_F":
			animation_state.travel("Jump_F")
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Forward jump, transitioning to 'Jump_F'." % name)
		elif is_jumping and relative_jump_dir < 0 and curr_state != "Jump_B":
			animation_state.travel("Jump_B")
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Backward jump, transitioning to 'Jump_B'." % name)
		return
	if move_set and move_set.is_spmove and not is_hit and not is_knockfly:
		current_mode = "attack"
		var target_state = "powerkk" if player_id == "p1" else "spnk"
		attack_type = target_state
		is_landing = false
		is_wakeup = false
		if curr_state != target_state:
			animation_state.travel(target_state)
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Special move, transitioning to '%s'." % [name, target_state])
		return
	if is_knockfly:
		current_mode = "knockfly"
		is_landing = false
		is_wakeup = false
		is_wakeup_locked = false
		var target_state = "knockfly"
		if curr_state != target_state:
			animation_state.travel(target_state)
		return
	elif is_wakeup and is_wakeup_locked:
		current_mode = "wakeup"
		is_landing = false
		var target_state = "wakeup"
		if curr_state != target_state:
			animation_state.travel(target_state)
		return
	if is_attacking and on_floor and attack_timer > 0:
		var target_state = "St_mp"
		if curr_state != target_state:
			animation_state.travel(target_state)
			print("Debug: Transition to attack %s for %s" % [target_state, name])
		return
	if is_dashing and on_floor:
		var target_state = "Dash"
		if curr_state != target_state:
			animation_state.travel(target_state)
			print("Debug: Transition to Dash for %s" % name)
		return
	if is_backdashing and on_floor:
		var target_state = "Backdash"
		if curr_state != target_state:
			animation_state.travel(target_state)
			print("Debug: Transition to Backdash for %s" % name)
		return
	if is_blocking and on_floor:
		var block_target = "cr_block" if crouch_input else "block"
		if curr_state != block_target:
			animation_state.travel(block_target)
		return
	if is_hit and on_floor:
		if curr_state != "hit":
			animation_state.travel("hit")
		return
	# 恢復：檢查 landing_lock_timer，防止 landing 被 Walk 自動覆蓋（放在優先狀態後）
	if is_landing and landing_lock_timer > 0:
		if debug_jump_sequence:
			print("Debug Jump Seq [%s]: Landing lock active (%.2f sec left), current state: %s, facing: %.1f." % [name, landing_lock_timer, curr_state, facing_direction])
		return
	if is_landing and on_floor and not is_dashing and not is_backdashing and not is_wakeup and not is_hit and not is_knockfly:
		current_mode = "landing"
		is_wakeup = false
		is_wakeup_locked = false
		var target_state = "landing"
		if curr_state != target_state:
			animation_state.travel(target_state)
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Entering 'landing' state from current: %s." % [name, curr_state])
		return
	if on_floor and not is_landing and not is_knockfly and not is_wakeup and not is_air_attacking and not (move_set and move_set.is_spmove) and not is_hit and not is_blocking and not is_attacking and not is_dashing and not is_backdashing:
		var target_state = ""
		if crouch_input:
			target_state = "Crouch"
		else:
			target_state = "Walk"
			animation_tree.set("parameters/Walk/blend_position", dir_x * facing_direction)  # 修正：使用相對方向，確保前進/後退動畫正確
		if curr_state != target_state:
			animation_state.travel(target_state)
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Default ground transition to '%s' (dir_x: %s, crouch: %s)." % [name, target_state, dir_x, crouch_input])
		return
	super._update_animation_state(dir_x, crouch_input)

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		var damage = current_damage
		var hit_shape = $Hitbox.get_node_or_null("HitShape") if has_node("Hitbox") else null
		if damage > 0:
			var world = get_tree().get_first_node_in_group("world")
			if not world:
				print("Warning: World node not found in group 'world' for %s" % name)
				return
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze()
			var push_manager = get_tree().get_first_node_in_group("push_manager")
			var skip_target_push = push_manager.is_at_corner(target) if push_manager else false
			target.take_hit(blockstun_duration, damage, skip_target_push)
			var is_blocked = target.is_blocking and target.block_type == "ordinary"
			hit_detected.emit(target.name, blockstun_duration, is_blocked)
			if skip_target_push:
				var push_duration: float
				if damage >= 20.0:
					push_duration = 0.4
				elif is_blocked:
					push_duration = 0.267
				else:
					push_duration = 0.35
				fixed_velocity.y = 0

func _on_animation_tree_finished(anim_name: String):
	var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
	if anim_name == "knockfly" and is_knockfly:
		if healthbar and healthbar.current_health <= 0:
			return
		is_knockfly = false
		is_wakeup = true
		is_wakeup_locked = true
		fixed_velocity = Vector2i.ZERO
		animation_state.travel("wakeup")
	elif anim_name == "wakeup" and is_wakeup:
		is_wakeup = false
		is_wakeup_locked = false
		is_landing = false
		_update_animation_state(0, false)
	elif anim_name == "landing" and is_landing:
		is_landing = false
		landing_lock_timer = 0.0
		landing_facing_lock = false  # 釋放面向鎖定，允許正常更新
		if debug_jump_sequence:
			print("Debug Jump Seq [%s]: 'landing' animation finished, lock released, transitioning to default state." % [name])
		update_facing_direction()
		_update_animation_state(0, false)
	elif anim_name == "St_mp":
		is_attacking = false
		update_facing_direction()
		_update_animation_state(0, false)
	elif anim_name == "jump_mk" and is_air_attacking:
		is_air_attacking = false
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = true
		if is_on_floor():
			var input_data = get_input()
			if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.attack_pressed or input_data.spm1_pressed:
				is_landing = false
				_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
				if debug_jump_sequence:
					print("Debug Jump Seq [%s]: Input detected on jump_mk landing, skipping 'landing' to '%s'." % [name, animation_state.get_current_node() if animation_state else "none"])
			else:
				is_landing = true
				animation_state.travel("landing")
				landing_lock_timer = landing_duration
				if debug_jump_sequence:
					print("Debug Jump Seq [%s]: Jump attack landed, transitioning to 'landing' (lock: %.2f sec)." % [name, landing_duration])
		else:
			is_landing = false
			_update_animation_state(0, false)
	elif anim_name in ["jump_v", "Jump_V", "Jump_F", "Jump_B"] and is_on_floor():
		is_jumping = false
		var input_data = get_input()
		if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.attack_pressed or input_data.spm1_pressed:
			is_landing = false
			landing_facing_lock = false  # 釋放面向鎖定，允許立即轉向
			update_facing_direction()  # 跳過landing時立即更新面向
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Input detected on jump landing, skipping 'landing' to '%s'." % [name, animation_state.get_current_node() if animation_state else "none"])
		else:
			is_landing = true
			animation_state.travel("landing")
			landing_lock_timer = landing_duration
			if debug_jump_sequence:
				print("Debug Jump Seq [%s]: Jump animation '%s' finished on floor, transitioning to 'landing' (lock: %.2f sec)." % [name, anim_name, landing_duration])
	elif anim_name in ["Dash", "Backdash"]:
		is_dashing = false
		is_backdashing = false
		_update_animation_state(0, false)

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()
