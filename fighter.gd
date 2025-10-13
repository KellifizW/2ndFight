class_name Fighter extends Movement

@onready var collision_shape = $Pushbox
@onready var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
@onready var hitbox = $Hitbox/HitShape if has_node("Hitbox/HitShape") else null
@onready var proximitybox = $Proximitybox/ProxShape if has_node("Proximitybox/ProxShape") else null

var is_being_pushed: bool = false
var current_damage: float = 0.0
var air_hit_knockfly_speed: float = 53.33
@export var air_knockback_horizontal_speed: float = 100.0
@export var air_knockback_vertical_speed: float = -300.0
@export var air_friction: float = 10.0
@export var min_hitstun_duration: float = 8.0 / 60.0

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

func _physics_process(delta):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	super._physics_process(delta)

	if (is_knockfly or is_hit) and not is_on_floor():
		var friction_amount = int(air_friction * world.SIMULATION_SCALE * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)

	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping

	if is_hit or is_knockfly or is_blocking:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	else:
		if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_state:
			current_damage = input_data.damage
			is_attacking = true
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func post_physics_process(delta):
	pass

func take_hit(hitstun_duration: float = 0.35, blockstun_duration: float = 0.267, damage: float = 10.0, skip_push: bool = false):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	var input_data = get_input()

	if is_attacking:
		is_attacking = false
	if is_spmove:
		move_set.stop_special_move()

	if is_blocking or ((is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove):
		is_blocking = true
		is_crouch_blocking = input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0
		initial_blockstun = max(blockstun_duration, min_hitstun_duration)
		block_timer = initial_blockstun
		block_type = "ordinary"
		fixed_velocity.x = 0
		fixed_velocity.y = 0
		if not skip_push:
			block_push_timer = initial_blockstun
			block_push_velocity = 2.0 * block_push_distance * world.SIMULATION_SCALE / initial_blockstun
		block_detected.emit(name, block_type)
		_update_animation_state(0, input_data.crouch_pressed)
		return

	if not is_on_floor():
		update_facing_direction()

	if healthbar:
		healthbar.take_damage(damage)
		var facing_mult = get_facing_multiplier()

		if damage > 10.0 or healthbar.current_health <= 0:
			is_knockfly = true
			knockfly_timer = max(knockfly_duration, min_hitstun_duration)
			if not skip_push:
				knockfly_velocity_x = -knockfly_push_speed * world.SIMULATION_SCALE * facing_mult
			return

		is_hit = true
		initial_hitstun = max(hitstun_duration, min_hitstun_duration)
		hit_timer = initial_hitstun
		if is_on_floor():
			if not skip_push:
				hit_push_timer = initial_hitstun
				hit_push_velocity = 2.0 * hit_push_distance * world.SIMULATION_SCALE / initial_hitstun
			fixed_velocity.x = 0
			fixed_velocity.y = 0
		else:
			fixed_velocity.y = int(air_knockback_vertical_speed * world.SIMULATION_SCALE)
			fixed_velocity.x = int(-air_knockback_horizontal_speed * world.SIMULATION_SCALE * facing_mult)
	else:
		is_hit = true
		initial_hitstun = max(hitstun_duration, min_hitstun_duration)
		hit_timer = initial_hitstun
		if not skip_push:
			hit_push_timer = initial_hitstun
			hit_push_velocity = 2.0 * hit_push_distance * world.SIMULATION_SCALE / initial_hitstun
		fixed_velocity.x = 0
		fixed_velocity.y = 0

	_update_animation_state(0, input_data.crouch_pressed)

func take_knockfly():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
		is_knockfly = true
		knockfly_timer = max(knockfly_duration, min_hitstun_duration)
		_update_animation_state(0, is_crouching)

func get_contact_point(hit_area: Area2D, hurt_area: Area2D) -> Vector2:
	var hit_shape_node = hit_area.get_node_or_null("HitShape") as CollisionShape2D
	var hurt_shape_node = hurt_area.get_node_or_null("HurtShape") as CollisionShape2D

	if not hit_shape_node or not hurt_shape_node or not (hit_shape_node.shape is RectangleShape2D) or not (hurt_shape_node.shape is RectangleShape2D):
		print("Warning: Invalid shapes for contact point calculation in get_contact_point for %s" % name)
		return (hit_area.global_position + hurt_area.global_position) / 2.0

	var world = get_tree().get_first_node_in_group("world")
	var SIMULATION_SCALE = world.SIMULATION_SCALE if world else 1000.0
	var TOLERANCE = 2.0 * SIMULATION_SCALE

	var hit_shape_pos = hit_shape_node.global_position
	var hit_half_size = hit_shape_node.shape.extents * abs(hit_shape_node.global_scale)
	var hit_left = (hit_shape_pos.x - hit_half_size.x) * SIMULATION_SCALE
	var hit_right = (hit_shape_pos.x + hit_half_size.x) * SIMULATION_SCALE
	var hit_bottom = (hit_shape_pos.y - hit_half_size.y) * SIMULATION_SCALE
	var hit_top = (hit_shape_pos.y + hit_half_size.y) * SIMULATION_SCALE

	var hurt_shape_pos = hurt_shape_node.global_position
	var hurt_half_size = hurt_shape_node.shape.extents * abs(hurt_shape_node.global_scale)
	var hurt_left = (hurt_shape_pos.x - hurt_half_size.x) * SIMULATION_SCALE
	var hurt_right = (hurt_shape_pos.x + hurt_half_size.x) * SIMULATION_SCALE
	var hurt_bottom = (hurt_shape_pos.y - hurt_half_size.y) * SIMULATION_SCALE
	var hurt_top = (hurt_shape_pos.y + hurt_half_size.y) * SIMULATION_SCALE

	var overlap_left = max(int(hit_left), int(hurt_left))
	var overlap_right = min(int(hit_right), int(hurt_right))
	var overlap_bottom = max(int(hit_bottom), int(hurt_bottom))
	var overlap_top = min(int(hit_top), int(hurt_top))

	if overlap_left <= overlap_right + TOLERANCE and overlap_bottom <= overlap_top + TOLERANCE:
		var median_x = (overlap_left + overlap_right) / 2.0 / SIMULATION_SCALE
		var median_y = (overlap_bottom + overlap_top) / 2.0 / SIMULATION_SCALE
		var contact_point = Vector2(median_x, median_y)
		print("Debug: Contact point calculated: %s" % contact_point)
		return contact_point

	print("Warning: No overlap detected in get_contact_point for %s vs %s" % [hit_area.get_parent().name, hurt_area.get_parent().name])
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.set_shape(hit_shape_node.shape)
	query.transform = hit_shape_node.global_transform
	query.collision_mask = hurt_area.collision_layer
	var result = space_state.intersect_shape(query, 1)
	if result and result[0].has("point"):
		var collision_point = result[0].point
		print("Debug: Physics query found collision point: %s" % collision_point)
		return collision_point

	var hurt_left_edge = Vector2(hurt_shape_pos.x - hurt_half_size.x, hurt_shape_pos.y)
	var point_query = PhysicsPointQueryParameters2D.new()
	point_query.position = hurt_left_edge
	point_query.collision_mask = hit_area.collision_layer
	var point_result = space_state.intersect_point(point_query, 1)
	if point_result and point_result[0].has("collider"):
		var collision_point = hurt_left_edge
		print("Debug: Point query found collision at Hurtbox left edge: %s" % collision_point)
		return collision_point

	print("Warning: Physics query failed, using fallback midpoint position")
	return (hit_area.global_position + hurt_area.global_position) / 2.0
