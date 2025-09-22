class_name Fighter extends Movement

@onready var collision_shape = $Pushbox
@onready var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
var is_being_pushed: bool = false
var push_distance_multiplier: float = 0.5
var PUSH_FRICTION: float = 66.0
@export var ground_push_trigger_distance: float = 2.0
@export var air_push_trigger_distance: float = 9.0
@export var corner_y_trigger_distance: float = 26.0
@export var collision_epsilon: float = 2.0
var current_damage: float = 0.0
var air_hit_knockfly_speed: float = 53.33

func _ready():
	super._ready()
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var collision_scale = collision_shape.scale
		colbox_half_width = collision_shape.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = collision_shape.shape.size.y * collision_scale.y / 2.0
	else:
		print("Warning: CollisionShape2D not found or invalid for %s" % name)
	if not healthbar:
		print("Warning: Healthbar not found for %s" % name)
	add_to_group("players")

func is_at_corner() -> bool:
	var self_at_left = abs(global_position.x - (arena_left + colbox_half_width)) < collision_epsilon
	var self_at_right = abs(global_position.x - (arena_right - colbox_half_width)) < collision_epsilon
	return self_at_left or self_at_right

func _physics_process(delta):
	super._physics_process(delta)
	
	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping
	
	if is_hit or is_knockfly or is_blocking:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	else:
		if input_data.attack_pressed and is_valid_state:
			current_damage = input_data.damage
			is_attacking = true
			attack_timer = attack_time
			velocity.x = 0
			if has_node("Proximitybox/ProxShape"):
				$Proximitybox/ProxShape.disabled = false
				print("Debug: ProximityBox enabled during attack for %s" % name)
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func post_physics_process(delta):
	is_being_pushed = false
	
	var all_players = get_tree().get_nodes_in_group("players")
	
	for other in all_players:
		if other == self:
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
		
		var overlap_x = min(rightA - leftB, rightB - leftA)
		var overlap_y = min(downA - upB, downB - upA)
		var relative_pos_x = global_position.x - other.global_position.x
		var push_distance = max(overlap_x, 12.0) * push_distance_multiplier
		
		var self_at_left = abs(global_position.x - (arena_left + colbox_half_width)) < collision_epsilon
		var self_at_right = abs(global_position.x - (arena_right - colbox_half_width)) < collision_epsilon
		var other_at_left = abs(other.global_position.x - (arena_left + other.colbox_half_width)) < collision_epsilon
		var other_at_right = abs(other.global_position.x - (arena_right - other.colbox_half_width)) < collision_epsilon
		var is_corner = self_at_left or self_at_right or other_at_left or other_at_right
		
		var x_trigger_distance = air_push_trigger_distance if (is_jumping or other.is_jumping) else ground_push_trigger_distance
		var has_x_overlap = rightA >= leftB - x_trigger_distance and leftA <= rightB + x_trigger_distance
		
		var y_trigger_distance = ground_push_trigger_distance
		if has_x_overlap:
			if is_corner and (is_jumping or other.is_jumping):
				y_trigger_distance = corner_y_trigger_distance
			elif is_jumping or other.is_jumping:
				y_trigger_distance = air_push_trigger_distance
			else:
				y_trigger_distance = ground_push_trigger_distance
		
		var is_overlapping = has_x_overlap and (downA >= upB - y_trigger_distance and upA <= downB + y_trigger_distance)
		
		if is_overlapping:
			if is_jumping or other.is_jumping:
				push_distance += PUSH_FRICTION * delta * 1.5
			else:
				push_distance += PUSH_FRICTION * delta
			
			var new_self_x = global_position.x
			var new_other_x = other.global_position.x
			
			if other_at_right and relative_pos_x > 0:
				new_self_x -= push_distance
				new_other_x = arena_right - other.colbox_half_width
			elif other_at_left and relative_pos_x < 0:
				new_self_x += push_distance
				new_other_x = arena_left + other.colbox_half_width
			elif self_at_right and relative_pos_x < 0:
				new_other_x += push_distance
				new_self_x = arena_right - colbox_half_width
			elif self_at_left and relative_pos_x > 0:
				new_other_x -= push_distance
				new_self_x = arena_left + colbox_half_width
			else:
				if relative_pos_x > 0:
					new_self_x += push_distance * 0.5
					new_other_x -= push_distance * 0.5
				else:
					new_self_x -= push_distance * 0.5
					new_other_x += push_distance * 0.5
				
			new_self_x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
			new_other_x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
			
			global_position.x = new_self_x
			other.global_position.x = new_other_x
			
			is_being_pushed = true
			other.is_being_pushed = true
	
	global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	print("Debug: Fighter _update_animation_state called, dir_x=" + str(dir_x) + ", crouch_input=" + str(crouch_input) + ", is_blocking=" + str(is_blocking) + ", is_crouch_blocking=" + str(is_crouch_blocking))
	var curr_state = animation_state.get_current_node() if animation_state else ""
	var on_floor = is_on_floor()
	var target_state = "Walk"

	var anim_dir = dir_x * facing_direction
	var anim_jump_dir = jump_dir * facing_direction

	if is_knockfly:
		target_state = "knockfly"
	elif is_hit:
		if is_on_floor():
			target_state = "hit"
		else:
			target_state = "Jump_B"  # Modified to play Jump_B when hit in air
	elif is_blocking:
		if is_crouch_blocking:
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
	animation_tree.set("parameters/conditions/hit", target_state == "hit")
	animation_tree.set("parameters/conditions/knockfly", is_knockfly)
	animation_tree.set("parameters/conditions/block", is_blocking and not is_crouch_blocking)
	animation_tree.set("parameters/conditions/cr_block", is_blocking and is_crouch_blocking)
	animation_tree.set("parameters/conditions/powerkk", false)

	if curr_state != target_state:
		animation_state.travel(target_state)
		print("Debug: Animation switched to %s for %s" % [target_state, name])

	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)

	if is_jumping and on_floor:
		is_jumping = false
		print("Debug: Landing, resetting is_jumping for %s" % name)

func take_hit(blockstun_duration: float = 0.2, damage: float = 10.0, skip_push: bool = false):
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove
	
	if not is_hit and not is_knockfly:
		if is_attacking:
			is_attacking = false
			attack_timer = 0.0
			print("Debug: Attack interrupted by hit for %s" % name)
		
		if is_spmove:
			move_set.stop_special_move()
			print("Debug: Special move interrupted by hit for %s" % name)
		
		var input_data = get_input()
		print("Debug: take_hit called, input_dir=" + str(input_data.input_dir) + ", crouch_pressed=" + str(input_data.crouch_pressed) + ", is_holding_back=" + str(is_holding_back) + ", facing_direction=" + str(get_facing_multiplier()))
		if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove:
			is_blocking = true
			is_crouch_blocking = is_crouch_blocking or (input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0)
			initial_blockstun = 0.4 if damage >= 20.0 else 0.267
			block_timer = initial_blockstun
			block_type = "ordinary"
			velocity.x = 0
			velocity.y = 0
			if not skip_push:
				block_push_timer = initial_blockstun
				block_push_velocity = 2.0 * block_push_distance / initial_blockstun
			print("Debug: Ordinary block successful, blockstun duration %s for %s, crouch_blocking=%s" % [initial_blockstun, name, is_crouch_blocking])
			block_detected.emit(name, block_type)
		else:
			print("Debug: No block triggered, proceeding to hit logic, is_on_floor=" + str(is_on_floor()))
			if not is_on_floor():
				update_facing_direction()
			if healthbar:
				healthbar.take_damage(damage)
				var facing_mult = get_facing_multiplier()
				if damage >= 20.0:
					is_knockfly = true
					knockfly_timer = knockfly_duration
					if not skip_push:
						knockfly_velocity_x = -knockfly_push_speed * facing_mult
					print("Debug: Special move hit, triggering knockfly for %s" % name)
				elif healthbar.current_health <= 0:
					is_knockfly = true
					knockfly_timer = knockfly_duration
					if not skip_push:
						knockfly_velocity_x = -knockfly_push_speed * facing_mult
					print("Debug: Health reached zero, triggering knockfly for %s" % name)
				else:
					if is_on_floor():
						is_hit = true
						initial_hitstun = 0.35
						hit_timer = initial_hitstun
						if not skip_push:
							hit_push_timer = initial_hitstun
							hit_push_velocity = 2.0 * hit_push_distance / initial_hitstun
						velocity.x = 0
						velocity.y = 0
						print("Debug: Ground hitstun triggered, duration %s for %s, damage %s" % [initial_hitstun, name, damage])
					else:
						is_jumping = true
						jump_dir = -facing_mult
						velocity.y = -300
						velocity.x = jump_dir * (jump_horizontal_speed / 2)
						is_hit = true
						initial_hitstun = 0.35
						hit_timer = initial_hitstun
						print("Debug: Air hit triggered passive back jump for %s, velocity.y=%s, velocity.x=%s" % [name, velocity.y, velocity.x])
			else:
				is_hit = true
				initial_hitstun = 0.35
				hit_timer = initial_hitstun
				if not skip_push:
					hit_push_timer = initial_hitstun
					hit_push_velocity = 2.0 * hit_push_distance / initial_hitstun
				print("Warning: No healthbar, hitstun triggered without damage for %s" % name)
		_update_animation_state(0, input_data.crouch_pressed)

func take_knockfly():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove
	
	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
			print("Debug: Special move interrupted by knockfly for %s" % name)
		is_knockfly = true
		knockfly_timer = knockfly_duration
		print("Debug: Knockfly taken for %s, knockfly_timer set to %.2f" % [name, knockfly_duration])
		_update_animation_state(0, is_crouching)
