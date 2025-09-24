class_name Player extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

@export var player_id: String = "p1"
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 20.0
@onready var move_set = $MoveSet if has_node("MoveSet") else null

var current_mode: String = "ground_stand"
var attack_type: String = "none"
var is_landing: bool = false
var is_wakeup: bool = false
var is_wakeup_locked: bool = false  # 新增鎖定，避免 wakeup 重置

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
		var hit_shape = $Hitbox.get_node_or_null("HitShape")
		if hit_shape and hit_shape is CollisionShape2D:
			hit_shape.disabled = true
	if animation_tree and not animation_tree.animation_finished.is_connected(_on_animation_tree_finished):
		animation_tree.animation_finished.connect(_on_animation_tree_finished)
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
	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup
	var hit_shape = $Hitbox.get_node_or_null("HitShape") if has_node("Hitbox") else null
	if hit_shape and hit_shape is CollisionShape2D:
		if move_set and (move_set.is_powerkk or move_set.is_spnk) or is_attacking:
			pass
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_state):
		return
	if input_data.attack_pressed and is_valid_state:
		current_damage = input_data.damage
		is_attacking = true
		attack_timer = attack_time
		attack_type = input_data.attack_type
		velocity.x = 0
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = false
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = false
	if is_attacking and attack_timer <= 0:
		is_attacking = false
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = true
		update_facing_direction()
	if is_jumping and is_on_floor():
		is_jumping = false
		is_landing = true
		if input_data.input_dir != 0 or input_data.crouch_pressed:
			is_landing = false
	if is_wakeup:
		velocity = Vector2.ZERO
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var curr_state = animation_state.get_current_node() if animation_state else "none"
	var on_floor = is_on_floor()
	
	if move_set and move_set.is_spmove and not is_hit and not is_knockfly:
		current_mode = "attack"
		var target_state = "powerkk" if player_id == "p1" else "spnk"
		attack_type = target_state
		is_landing = false
		is_wakeup = false
		if animation_tree and animation_state and curr_state != target_state:
			animation_tree.set("parameters/conditions/powerkk", target_state == "powerkk" and player_id == "p1")
			animation_tree.set("parameters/conditions/spnk", target_state == "spnk" and player_id == "p2")
			animation_tree.set("parameters/conditions/Walk", false)
			animation_tree.set("parameters/conditions/hit", false)
			animation_tree.set("parameters/conditions/block", false)
			animation_tree.set("parameters/conditions/cr_block", false)
			animation_tree.set("parameters/conditions/wakeup", false)
			animation_tree.set("parameters/conditions/landing", false)
			animation_state.travel(target_state)
		return
	
	if is_knockfly:
		current_mode = "knockfly"
		is_landing = false
		is_wakeup = false
		is_wakeup_locked = false
	elif is_wakeup and is_wakeup_locked:
		current_mode = "wakeup"
		is_landing = false
	elif is_landing and on_floor and not is_dashing and not is_backdashing:
		current_mode = "landing"
		is_wakeup = false
		is_wakeup_locked = false
	
	super._update_animation_state(dir_x, crouch_input)
	
	var target_state = animation_state.get_current_node() if animation_state else "Walk"
	if current_mode == "wakeup" and is_wakeup_locked:
		target_state = "wakeup"
	elif current_mode == "landing":
		target_state = "landing"
	
	if animation_tree and animation_state and curr_state != target_state:
		animation_tree.set("parameters/conditions/wakeup", target_state == "wakeup")
		animation_tree.set("parameters/conditions/landing", target_state == "landing")
		animation_state.travel(target_state)

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		var damage = current_damage
		var hit_shape = $Hitbox.get_node_or_null("HitShape") if has_node("Hitbox") else null
		if damage > 0:
			var skip_target_push = target.get_node("PushHandler").is_at_corner()  # 修改為引用 PushHandler 的 is_at_corner()
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
				is_push_back = true
				initial_push_back = push_duration
				push_back_timer = push_duration
				push_back_velocity = 2.0 * corner_push_distance / push_duration
				velocity.x = -push_back_velocity * get_facing_multiplier()
				velocity.y = 0

func _on_animation_tree_finished(anim_name: String):
	var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
	if anim_name == "knockfly" and is_knockfly:
		if healthbar and healthbar.current_health <= 0:
			return
		is_knockfly = false
		is_wakeup = true
		is_wakeup_locked = true
		velocity = Vector2.ZERO
		animation_state.travel("wakeup")
	elif anim_name == "wakeup" and is_wakeup:
		is_wakeup = false
		is_wakeup_locked = false
		_update_animation_state(0, false)
	elif anim_name == "landing" and is_landing:
		is_landing = false
		_update_animation_state(0, false)
	elif anim_name == "St_mp":
		update_facing_direction()

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()
