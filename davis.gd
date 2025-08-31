extends CharacterBody2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
@onready var collision_polygon = $CollisionPolygon2D

var walk_speed = 150
var back_speed = walk_speed * 0.75
var jump_dir: float = 0.0
var is_jumping: bool = false
var is_dashing: bool = false
var is_backdashing: bool = false
var is_attacking: bool = false
var attack_time: float = 0.4
var attack_timer: float = 0.0
var dash_speed = 130
var backdash_speed = 110
var dash_time = 0.35
var backdash_time = 0.4
var dash_timer = 0.0
var double_tap_timer = 0.3
var last_input_dir = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0
var push_speed = walk_speed * 0.5
var crouch_pressed: bool = false
var is_being_pushed: bool = false
var is_hit: bool = false
var is_knockfly: bool = false
var hit_timer: float = 0.0
var knockfly_timer: float = 0.0
var knockfly_speed: float = -200.0
var debug_time: float = 0.0

signal hit_detected(target: String)

func _ready():
	animation_tree.active = true
	animation_state.travel("Walk")
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)

func _physics_process(delta):
	debug_time += delta
	is_being_pushed = false

	print("[%.2f] Davis State: pos=%.2f, vel=%.2f, input_dir=%d, is_dashing=%s, is_backdashing=%s, is_attacking=%s, is_jumping=%s, is_on_floor=%s" % 
		[debug_time, position.x, velocity.x, last_input_dir, is_dashing, is_backdashing, is_attacking, is_jumping, is_on_floor()])

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
	crouch_pressed = Input.is_action_pressed("crouch")
	var jump_pressed = Input.is_action_pressed("jump")
	var attack_pressed = Input.is_action_just_pressed("attack")
	var right_pressed = Input.is_action_pressed("move_right")
	var left_pressed = Input.is_action_pressed("move_left")

	if is_hit or is_knockfly:
		if is_knockfly:
			velocity.x = knockfly_speed
		else:
			velocity.x = 0
		move_and_slide()
		return

	if is_attacking:
		velocity.x = 0
		velocity.y += 1300 * delta
		move_and_slide()
		return

	if attack_pressed and is_on_floor() and not is_dashing and not is_backdashing and not crouch_pressed and not is_jumping:
		is_attacking = true
		attack_timer = attack_time
		animation_state.travel("St_mp")
		velocity.x = 0
		move_and_slide()
		return

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
					animation_state.travel("Dash")
				elif current_input_dir < 0:
					is_backdashing = true
					dash_timer = backdash_time
					is_being_pushed = false
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

	if jump_pressed and is_on_floor() and not crouch_pressed and not is_dashing and not is_backdashing:
		jump_dir = input_dir
		velocity.y = -400
		is_jumping = true
		is_being_pushed = false
		var target_jump_state = ""
		if jump_dir > 0:
			target_jump_state = "Jump_F"
		elif jump_dir < 0:
			target_jump_state = "Jump_B"
		else:
			target_jump_state = "Jump_V"
		animation_state.travel(target_jump_state)

	move_and_slide()

	for i in get_slide_collision_count():
		var slide_collision = get_slide_collision(i)
		var collider = slide_collision.get_collider()
		if collider is CharacterBody2D and collider != self:
			if not collider.is_attacking and not is_attacking:
				var push_direction = sign(velocity.x)
				if push_direction != 0 and get_instance_id() < collider.get_instance_id():
					var old_pos = collider.position.x
					collider.is_being_pushed = true
					collider.position.x += push_direction * push_speed * 3 * delta
					collider.move_and_slide()
					print("[%.2f] Dynamic Collision: collider=%s, push_direction=%d, old_pos=%.2f, new_pos=%.2f, collider_vel=%.2f" % 
						[debug_time, collider.name, push_direction, old_pos, collider.position.x, collider.velocity.x])

	if not is_attacking:
		var push_direction = 0
		if is_dashing:
			push_direction = 1
		elif is_backdashing:
			push_direction = -1
		elif input_dir != 0:
			push_direction = input_dir
		
		if push_direction != 0:
			var space_state = get_world_2d().direct_space_state
			var shape = ConvexPolygonShape2D.new()
			var points = collision_polygon.polygon
			var expanded_points = []
			for point in points:
				expanded_points.append(point * 1.5)  # 擴大 1.5 倍
			shape.points = expanded_points
			var shape_transform = Transform2D(0, global_position)
			var query = PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform = shape_transform
			query.collision_mask = 1
			var collisions = space_state.intersect_shape(query)
			
			var collision_names = []
			for collision in collisions:
				collision_names.append(collision.collider.name)
			print("[%.2f] Static Push: push_direction=%d, collisions=%s, self_pos=%.2f, self_vel=%.2f, shape_points=%s, shape_transform=%s" % 
				[debug_time, push_direction, collision_names, position.x, velocity.x, shape.points, shape_transform])
			
			for collision in collisions:
				var collider = collision.collider
				if collider is CharacterBody2D and collider != self and not collider.is_attacking and not collider.is_being_pushed and get_instance_id() < collider.get_instance_id():
					var relative_pos = collider.position.x - position.x
					var effective_push_direction = push_direction
					if velocity.x == 0:
						effective_push_direction = -sign(relative_pos) if abs(relative_pos) > 0.1 else push_direction
					var old_pos = collider.position.x
					collider.is_being_pushed = true
					collider.position.x += effective_push_direction * push_speed * 3 * delta
					collider.move_and_slide()
					print("[%.2f] Static Push Applied: collider=%s, effective_push_direction=%d, relative_pos=%.2f, old_pos=%.2f, new_pos=%.2f, collider_vel=%.2f, collider_pushed=%s" % 
						[debug_time, collider.name, effective_push_direction, relative_pos, old_pos, collider.position.x, collider.velocity.x, collider.is_being_pushed])

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
		hit_timer = 0.28
		is_being_pushed = false
		animation_state.travel("hit")
		print("[%.2f] Davis Hit: hit_timer=%.2f" % [debug_time, hit_timer])

func take_knockfly():
	if not is_hit and not is_knockfly and is_on_floor():
		is_knockfly = true
		knockfly_timer = 0.75
		is_being_pushed = false
		animation_state.travel("knockfly")
		print("[%.2f] Davis Knockfly: knockfly_timer=%.2f" % [debug_time, knockfly_timer])

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		hit_detected.emit(target.name)
		target.take_hit()
		print("[%.2f] Hit Detected: target=%s" % [debug_time, target.name])
