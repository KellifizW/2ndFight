class_name PushHandler extends Node

@export var push_distance_multiplier: float = 0.5
@export var PUSH_FRICTION: float = 66.0
@export var ground_push_trigger_distance: float = 2.0
@export var air_push_trigger_distance: float = 9.0
@export var corner_y_trigger_distance: float = 26.0
@export var collision_epsilon: float = 2.0

@onready var parent = get_parent()

func _physics_process(delta: float):
	if not parent:
		return
	
	# 處理 hit push、block push、push back 計時器（從 Movement.gd 抽取）
	if parent.is_push_back:
		if parent.push_back_timer > 0:
			parent.velocity.x = -parent.push_back_velocity * parent.facing_direction
			parent.push_back_timer -= delta
			if parent.push_back_timer <= 0:
				parent.is_push_back = false
				parent.push_back_velocity = 0.0
				parent.initial_push_back = 0.0
				parent.velocity.x = 0
	# hit push
	if parent.hit_timer > 0:
		parent.hit_timer -= delta
		if parent.hit_push_timer > 0:
			parent.velocity.x = -parent.hit_push_velocity * parent.facing_direction * (parent.hit_push_timer / parent.initial_hitstun)
			parent.hit_push_timer -= delta
		if parent.hit_timer <= 0:
			parent.is_hit = false
			parent.hit_push_timer = 0.0
			parent.hit_push_velocity = 0.0
			parent.initial_hitstun = 0.0
			parent.velocity.x = 0  # 確保 hit push 結束時清零 velocity.x
	# block push
	if parent.block_timer > 0:
		parent.block_timer -= delta
		if parent.block_push_timer > 0:
			parent.velocity.x = -parent.block_push_velocity * parent.facing_direction * (parent.block_push_timer / parent.initial_blockstun)
			parent.block_push_timer -= delta
		if parent.block_timer <= 0:
			parent.is_blocking = false
			parent.is_crouch_blocking = false
			parent.block_type = "none"
			parent.block_push_timer = 0.0
			parent.block_push_velocity = 0.0
			parent.initial_blockstun = 0.0
			parent.velocity.x = 0  # 確保 block push 結束時清零 velocity.x，避免持續滑動
	# knockfly push (部分從 Movement.gd)
	if parent.knockfly_timer > 0:
		parent.knockfly_timer -= delta
		if parent.is_air_hit_knockfly:
			parent.velocity.x = parent.knockfly_velocity_x * (parent.knockfly_timer / parent.knockfly_duration)
		else:
			parent.velocity.x = parent.knockfly_velocity_x * pow(parent.knockfly_timer / parent.knockfly_duration, 2)
		var delta_x = abs(parent.global_position.x - parent.prev_position.x)
		parent.knockfly_accumulated_distance += delta_x
		if parent.knockfly_accumulated_distance >= parent.knockfly_max_distance:
			parent.velocity.x = 0
			parent.knockfly_velocity_x = 0.0
		if parent.knockfly_timer <= 0 and parent.is_knockfly:
			var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % parent.name) if get_tree().get_first_node_in_group("ui") else null
			if healthbar and healthbar.current_health <= 0:
				pass
			else:
				parent.velocity.x = 0
				parent.knockfly_velocity_x = 0.0
				parent.knockfly_accumulated_distance = 0.0
				if parent.animation_player:
					parent.animation_player.speed_scale = 1.0
	
	# 處理角色間碰撞推開（從 Fighter.gd 的 post_physics_process 抽取）
	parent.is_being_pushed = false
	var all_players = get_tree().get_nodes_in_group("players")
	for other in all_players:
		if other == parent:
			continue
		var sprite_offset = parent.sprite.position
		var other_sprite_offset = other.sprite.position
		var leftA = parent.global_position.x - parent.colbox_half_width + sprite_offset.x
		var rightA = parent.global_position.x + parent.colbox_half_width + sprite_offset.x
		var upA = parent.global_position.y - parent.colbox_half_height + sprite_offset.y
		var downA = parent.global_position.y + parent.colbox_half_height + sprite_offset.y
		var leftB = other.global_position.x - other.colbox_half_width + other_sprite_offset.x
		var rightB = other.global_position.x + other.colbox_half_width + other_sprite_offset.x
		var upB = other.global_position.y - other.colbox_half_height + other_sprite_offset.y
		var downB = other.global_position.y + other.colbox_half_height + other_sprite_offset.y
		var overlap_x = min(rightA - leftB, rightB - leftA)
		var overlap_y = min(downA - upB, downB - upA)
		var relative_pos_x = parent.global_position.x - other.global_position.x
		var push_distance = max(overlap_x, 12.0) * push_distance_multiplier
		var self_at_left = abs(parent.global_position.x - (parent.arena_left + parent.colbox_half_width)) < collision_epsilon
		var self_at_right = abs(parent.global_position.x - (parent.arena_right - parent.colbox_half_width)) < collision_epsilon
		var other_at_left = abs(other.global_position.x - (parent.arena_left + other.colbox_half_width)) < collision_epsilon
		var other_at_right = abs(other.global_position.x - (parent.arena_right - other.colbox_half_width)) < collision_epsilon
		var is_corner = self_at_left or self_at_right or other_at_left or other_at_right
		var x_trigger_distance = air_push_trigger_distance if (parent.is_jumping or other.is_jumping) else ground_push_trigger_distance
		var has_x_overlap = rightA >= leftB - x_trigger_distance and leftA <= rightB + x_trigger_distance
		var y_trigger_distance = ground_push_trigger_distance
		if has_x_overlap:
			if is_corner and (parent.is_jumping or other.is_jumping):
				y_trigger_distance = corner_y_trigger_distance
			elif parent.is_jumping or other.is_jumping:
				y_trigger_distance = air_push_trigger_distance
			else:
				y_trigger_distance = ground_push_trigger_distance
		var is_overlapping = has_x_overlap and (downA >= upB - y_trigger_distance and upA <= downB + y_trigger_distance)
		if is_overlapping:
			if parent.is_jumping or other.is_jumping:
				push_distance += PUSH_FRICTION * delta * 1.5
			else:
				push_distance += PUSH_FRICTION * delta
			var new_self_x = parent.global_position.x
			var new_other_x = other.global_position.x
			if other_at_right and relative_pos_x > 0:
				new_self_x -= push_distance
				new_other_x = parent.arena_right - other.colbox_half_width
			elif other_at_left and relative_pos_x < 0:
				new_self_x += push_distance
				new_other_x = parent.arena_left + other.colbox_half_width
			elif self_at_right and relative_pos_x < 0:
				new_other_x += push_distance
				new_self_x = parent.arena_right - parent.colbox_half_width
			elif self_at_left and relative_pos_x > 0:
				new_other_x -= push_distance
				new_self_x = parent.arena_left + parent.colbox_half_width
			else:
				if relative_pos_x > 0:
					new_self_x += push_distance * 0.5
					new_other_x -= push_distance * 0.5
				else:
					new_self_x -= push_distance * 0.5
					new_other_x += push_distance * 0.5
			new_self_x = clamp(new_self_x, parent.arena_left + parent.colbox_half_width, parent.arena_right - parent.colbox_half_width)
			new_other_x = clamp(new_other_x, parent.arena_left + other.colbox_half_width, parent.arena_right - other.colbox_half_width)
			parent.global_position.x = new_self_x
			other.global_position.x = new_other_x
			parent.is_being_pushed = true
			other.is_being_pushed = true
	# 最後夾住位置（從 Fighter.gd 抽取）
	parent.global_position.x = clamp(parent.global_position.x, parent.arena_left + parent.colbox_half_width, parent.arena_right - parent.colbox_half_width)

func is_at_corner() -> bool:
	var self_at_left = abs(parent.global_position.x - (parent.arena_left + parent.colbox_half_width)) < collision_epsilon
	var self_at_right = abs(parent.global_position.x - (parent.arena_right - parent.colbox_half_width)) < collision_epsilon
	return self_at_left or self_at_right
