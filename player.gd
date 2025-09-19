class_name Player extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

@export var player_id: String = "p1"
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 20.0
@onready var move_set = $MoveSet if has_node("MoveSet") else null

func _ready():
	super._ready()
	var debug_node = get_tree().get_first_node_in_group("debug_node")
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
		var hit_shape = $Hitbox.get_node_or_null("HitShape")
		if debug_node:
			debug_node.log_initialization(self, hit_shape, $Proximitybox.get_node_or_null("ProxShape"), move_set)
	else:
		if debug_node:
			debug_node.log_initialization(self, null, null, move_set)
	if has_node("Proximitybox"):
		var prox_shape = $Proximitybox.get_node_or_null("ProxShape")
		if debug_node:
			debug_node.log_initialization(self, $Hitbox.get_node_or_null("HitShape"), prox_shape, move_set)
	else:
		if debug_node:
			debug_node.log_initialization(self, $Hitbox.get_node_or_null("HitShape"), null, move_set)
	add_to_group("players")

func _get_collision_layer_indices(value: int) -> Array:
	var indices = []
	for i in range(32):
		if value & (1 << i):
			indices.append(i + 1)
	return indices

func get_input() -> Dictionary:
	var debug_node = get_tree().get_first_node_in_group("debug_node")
	if is_ai_controlled:
		var ai_behavior = $AIBehavior if has_node("AIBehavior") else null
		if ai_behavior:
			return ai_behavior.get_ai_input()
		else:
			if debug_node:
				debug_node.log_initialization(self, null, null, null)  # Warning for AIBehavior
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
	var debug_node = get_tree().get_first_node_in_group("debug_node")
	var input_data = get_input()
	
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping and not is_blocking and not is_attacking
	
	var hit_shape = $Hitbox.get_node_or_null("HitShape") if has_node("Hitbox") else null
	if hit_shape and hit_shape is CollisionShape2D:
		var anim_state = "none"
		if animation_state:
			anim_state = animation_state.get_current_node() if animation_state.get_current_node() else "none"
		if move_set and (move_set.is_powerkk or move_set.is_spnk) or is_attacking:
			if debug_node:
				debug_node.log_hitbox_state(self, hit_shape, true, anim_state)
	
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_state):
		return
	
	if input_data.attack_pressed and is_valid_state:
		current_damage = input_data.damage
		is_attacking = true
		attack_timer = attack_time
		velocity.x = 0
		if hit_shape and hit_shape is CollisionShape2D:
			if debug_node:
				var anim_state = animation_state.get_current_node() if animation_state else "none"
				debug_node.log_hitbox_state(self, hit_shape, true, anim_state)
		var prox_shape = $Proximitybox.get_node_or_null("ProxShape") if has_node("Proximitybox") else null
		if prox_shape and prox_shape is CollisionShape2D:
			prox_shape.disabled = false
			if debug_node:
				var anim_state = animation_state.get_current_node() if animation_state else "none"
				debug_node.log_proximitybox_state(self, prox_shape, true, anim_state)
	
	if is_attacking and attack_timer <= 0:
		is_attacking = false
		if hit_shape and hit_shape is CollisionShape2D:
			if debug_node:
				var anim_state = animation_state.get_current_node() if animation_state else "none"
				debug_node.log_hitbox_state(self, hit_shape, false, anim_state)
		var prox_shape = $Proximitybox.get_node_or_null("ProxShape") if has_node("Proximitybox") else null
		if prox_shape and prox_shape is CollisionShape2D:
			prox_shape.disabled = true
			if debug_node:
				var anim_state = animation_state.get_current_node() if animation_state else "none"
				debug_node.log_proximitybox_state(self, prox_shape, false, anim_state)
	
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var debug_node = get_tree().get_first_node_in_group("debug_node")
	var curr_state = "none"
	if animation_state:
		curr_state = animation_state.get_current_node() if animation_state.get_current_node() else "none"
	var target_state = "Walk"
	var on_floor = is_on_floor()
	var anim_dir = dir_x * facing_direction
	var anim_jump_dir = jump_dir * facing_direction

	if is_knockfly:
		target_state = "knockfly"
	elif is_hit:
		target_state = "hit"
	elif move_set and move_set.is_spmove and not is_hit and not is_knockfly:
		target_state = "powerkk" if player_id == "p1" else "spnk"
	elif is_blocking:
		if is_crouching:
			target_state = "cr_block"
		else:
			target_state = "block"
	elif is_attacking:
		target_state = "St_mp"
	elif is_dashing:
		target_state = "Dash"
	elif is_backdashing:
		target_state = "Backdash"
	elif crouch_input and on_floor and not is_blocking:
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
	animation_tree.set("parameters/conditions/block", is_blocking and not is_crouching)
	animation_tree.set("parameters/conditions/cr_block", is_blocking and is_crouching)
	animation_tree.set("parameters/conditions/powerkk", target_state == "powerkk" and player_id == "p1")
	animation_tree.set("parameters/conditions/spnk", target_state == "spnk" and player_id == "p2")

	if curr_state != target_state:
		animation_state.travel(target_state)
		if debug_node:
			debug_node.log_animation_switch(self, target_state, sprite.scale.x)

	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)

	if is_jumping and on_floor:
		is_jumping = false
		if debug_node:
			debug_node.log_landing(self)

func _on_hitbox_area_entered(area: Area2D):
	var debug_node = get_tree().get_first_node_in_group("debug_node")
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		var damage = current_damage
		var hit_shape = $Hitbox.get_node_or_null("HitShape") if has_node("Hitbox") else null
		var anim_state = "none"
		if animation_state:
			anim_state = animation_state.get_current_node() if animation_state.get_current_node() else "none"
		if debug_node:
			debug_node.log_hit_detected(self, target, blockstun_duration, damage, target.is_blocking and target.block_type == "ordinary", hit_shape, anim_state)
		if damage > 0:
			var skip_target_push = target.is_at_corner()
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
				velocity.x = -push_back_velocity * facing_direction
				velocity.y = 0
				if debug_node:
					debug_node.log_corner_push(self, push_duration, velocity.x)

func get_facing_multiplier() -> float:
	return facing_direction
