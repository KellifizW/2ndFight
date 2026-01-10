class_name PushManager extends Node

const SIMULATION_SCALE: float = 1000.0

@export var PUSH_FRICTION: float = 66.0
@export var collision_epsilon: float = 5.0
@export var arena_left: float = 0.0
@export var arena_right: float = 1600.0

var players: Array = []

class Collider:
	var center: Vector2i
	var size: Vector2i
	
	func _init(c: Vector2i, s: Vector2i):
		center = c
		size = s
	
	func is_overlapping(other: Collider, x_trigger: int = 0, y_trigger: int = 0) -> bool:
		var left_a = center.x - (size.x / 2)
		var right_a = center.x + (size.x / 2)
		var left_b = other.center.x - (other.size.x / 2)
		var right_b = other.center.x + (other.size.x / 2)
		var has_x_overlap = left_a <= right_b + x_trigger and right_a >= left_b - x_trigger
		
		var up_a = center.y - (size.y / 2)
		var down_a = center.y + (size.y / 2)
		var up_b = other.center.y - (other.size.y / 2)
		var down_b = other.center.y + (other.size.y / 2)
		var has_y_overlap = up_a <= down_b + y_trigger and down_a >= up_b - y_trigger
		
		return has_x_overlap and has_y_overlap

static func get_depth(a: Collider, b: Collider) -> Vector2i:
	var length = a.center - b.center
	var depth = (a.size + b.size) / 2
	depth.x -= abs(length.x)
	depth.y -= abs(length.y)
	depth.x = max(0, depth.x)
	depth.y = max(0, depth.y)
	return depth

func _ready() -> void:
	players = get_tree().get_nodes_in_group("players")
	add_to_group("push_manager")

func _physics_process(delta: float) -> void:
	players = get_tree().get_nodes_in_group("players")
	if players.size() < 2:
		return
	
	# 先處理所有計時器與推力衰減（重要：放在碰撞處理前面）
	for player in players:
		var ph = player.get_node_or_null("PhysicsHandler")
		if not ph:
			continue
		
		# 角落推回（corner pushback）
		if ph.is_push_back:
			if ph.push_back_timer > 0:
				ph.fixed_velocity.x = int(-ph.push_back_velocity * player.facing_direction * (ph.push_back_timer / ph.initial_push_back))
				ph.push_back_timer -= delta
			if ph.push_back_timer <= 0:
				ph.is_push_back = false
				ph.push_back_velocity = 0.0
				ph.initial_push_back = 0.0
				ph.fixed_velocity.x = 0
		
		# hit pushback
		if player.is_hit:
			if player.hit_timer > 0:
				player.hit_timer -= delta
			if ph.hit_push_timer > 0:
				ph.fixed_velocity.x = int(-ph.hit_push_velocity * player.facing_direction * (ph.hit_push_timer / ph.initial_hitstun))
				ph.hit_push_timer -= delta
			if player.hit_timer <= 0:
				player.is_hit = false
				ph.hit_push_timer = 0.0
				ph.hit_push_velocity = 0.0
				ph.initial_hitstun = 0.0
				ph.fixed_velocity.x = 0
		
		# block pushback
		if player.block_timer > 0:
			player.block_timer -= delta
			if ph.block_push_timer > 0:
				ph.fixed_velocity.x = int(-ph.block_push_velocity * player.facing_direction * (ph.block_push_timer / ph.initial_blockstun))
				ph.block_push_timer -= delta
			if player.block_timer <= 0:
				player.is_blocking = false
				player.is_crouch_blocking = false
				player.block_type = "none"
				ph.block_push_timer = 0.0
				ph.block_push_velocity = 0.0
				ph.initial_blockstun = 0.0
				ph.fixed_velocity.x = 0
		
		# knockfly 處理（保持原樣）
		if player.knockfly_timer > 0:
			player.knockfly_timer -= delta
			if ph.is_air_hit_knockfly:
				ph.fixed_velocity.x = int(ph.knockfly_velocity_x * (player.knockfly_timer / ph.knockfly_duration))
			else:
				ph.fixed_velocity.x = int(ph.knockfly_velocity_x * pow(player.knockfly_timer / ph.knockfly_duration, 2))
			
			var delta_x = abs(player.global_position.x - player.prev_position.x)
			ph.knockfly_accumulated_distance += delta_x
			
			if ph.knockfly_accumulated_distance >= ph.knockfly_max_distance:
				ph.fixed_velocity.x = 0
				ph.knockfly_velocity_x = 0.0
			
			if player.knockfly_timer <= 0 and player.is_knockfly:
				var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % player.name) if get_tree().get_first_node_in_group("ui") else null
				if healthbar and healthbar.current_health <= 0:
					pass
				else:
					ph.fixed_velocity.x = 0
					ph.knockfly_velocity_x = 0.0
					ph.knockfly_accumulated_distance = 0.0
				if player.animation_player:
					player.animation_player.speed_scale = 1.0
	
	# 再處理角色間推開（避免計時器與推開互相干擾）
	for i in range(players.size()):
		var parent = players[i]
		var move_set = parent.get_node_or_null("MoveSet")
		var is_penetrable = false
		
		if move_set:
			var player_id = parent.player_id if "player_id" in parent else "p1"
			is_penetrable = (player_id == "p1" and move_set.is_powerkk and move_set.is_powerkk_penetrable) or \
							(player_id == "p2" and move_set.is_spnk and move_set.is_spnk_penetrable) or \
							(move_set.is_dp and move_set.is_dp_penetrable)
		
		parent.is_being_pushed = false
		if is_penetrable or parent.skip_pushbox:
			continue
		
		for j in range(i + 1, players.size()):
			var other = players[j]
			var other_move_set = other.get_node_or_null("MoveSet")
			var other_is_penetrable = false
			
			if other_move_set:
				var other_player_id = other.player_id if "player_id" in other else "p1"
				other_is_penetrable = (other_player_id == "p1" and other_move_set.is_powerkk and other_move_set.is_powerkk_penetrable) or \
									  (other_player_id == "p2" and other_move_set.is_spnk and other_move_set.is_spnk_penetrable) or \
									  (other_move_set.is_dp and other_move_set.is_dp_penetrable)
			
			if other_is_penetrable or other.skip_pushbox:
				continue
			
			var ph_parent = parent.get_node_or_null("PhysicsHandler")
			var ph_other = other.get_node_or_null("PhysicsHandler")
			if not ph_parent or not ph_other:
				continue
			
			var fixed_position_a = Vector2i(round(parent.global_position.x * SIMULATION_SCALE), round(parent.global_position.y * SIMULATION_SCALE))
			var fixed_position_b = Vector2i(round(other.global_position.x * SIMULATION_SCALE), round(other.global_position.y * SIMULATION_SCALE))
			
			var pushbox_offset_a = parent.get_node("Pushbox").position if parent.has_node("Pushbox") else Vector2.ZERO
			var fixed_offset_a = Vector2i(round(pushbox_offset_a.x * SIMULATION_SCALE), round(pushbox_offset_a.y * SIMULATION_SCALE))
			
			var pushbox_offset_b = other.get_node("Pushbox").position if other.has_node("Pushbox") else Vector2.ZERO
			var fixed_offset_b = Vector2i(round(pushbox_offset_b.x * SIMULATION_SCALE), round(pushbox_offset_b.y * SIMULATION_SCALE))
			
			var side_a = Vector2i(int(parent.facing_direction), 1)
			var side_b = Vector2i(int(other.facing_direction), 1)
			
			var center_a = fixed_position_a + fixed_offset_a * side_a
			var size_a = Vector2i(round(ph_parent.colbox_half_width * 2 * SIMULATION_SCALE), round(ph_parent.colbox_half_height * 2 * SIMULATION_SCALE))
			var collider_a = Collider.new(center_a, size_a)
			
			var center_b = fixed_position_b + fixed_offset_b * side_b
			var size_b = Vector2i(round(ph_other.colbox_half_width * 2 * SIMULATION_SCALE), round(ph_other.colbox_half_height * 2 * SIMULATION_SCALE))
			var collider_b = Collider.new(center_b, size_b)
			
			if collider_a.is_overlapping(collider_b, 0, 0):
				var depth = get_depth(collider_a, collider_b)
				var overlap_fixed_x = depth.x
				var overlap_fixed_y = depth.y
				
				if overlap_fixed_x <= 0:
					continue
				
				var push_distance_fixed = overlap_fixed_x
				var normal_x: int
				if fixed_position_a.x > fixed_position_b.x:
					normal_x = -1
				elif fixed_position_a.x < fixed_position_b.x:
					normal_x = 1
				else:
					normal_x = 1 if is_at_corner(parent) else -1
				
				var epsilon_fixed = round(collision_epsilon * SIMULATION_SCALE)
				var arena_left_fixed = round(arena_left * SIMULATION_SCALE)
				var arena_right_fixed = round(arena_right * SIMULATION_SCALE)
				
				var half_a_fixed = size_a.x / 2
				var half_b_fixed = size_b.x / 2
				
				var self_at_left = abs(fixed_position_a.x - (arena_left_fixed + half_a_fixed)) < epsilon_fixed
				var self_at_right = abs(fixed_position_a.x - (arena_right_fixed - half_a_fixed)) < epsilon_fixed
				var other_at_left = abs(fixed_position_b.x - (arena_left_fixed + half_b_fixed)) < epsilon_fixed
				var other_at_right = abs(fixed_position_b.x - (arena_right_fixed - half_b_fixed)) < epsilon_fixed
				
				var unpush_self = (self_at_left and fixed_position_a.x >= fixed_position_b.x) or \
								  (self_at_right and fixed_position_a.x <= fixed_position_b.x)
				var unpush_other = (other_at_left and fixed_position_b.x >= fixed_position_a.x) or \
								   (other_at_right and fixed_position_b.x <= fixed_position_a.x)
				
				var push_vec_self = 0
				var push_vec_other = 0
				
				if unpush_self and overlap_fixed_y > 0:
					push_vec_self = 0
					var push_amount = push_distance_fixed * 1.2 + 1
					if self_at_left:
						push_vec_other = -push_amount
					elif self_at_right:
						push_vec_other = push_amount
				elif unpush_other and overlap_fixed_y > 0:
					push_vec_other = 0
					var push_amount = push_distance_fixed * 1.2 + 1
					if other_at_left:
						push_vec_self = -push_amount
					elif other_at_right:
						push_vec_self = push_amount
				else:
					var push_amount = push_distance_fixed * 0.6 + 1
					push_vec_self = normal_x * push_amount
					push_vec_other = -normal_x * push_amount
				
				if ph_parent.just_jumped or ("is_landing" in parent and parent.is_landing) or \
				   ph_other.just_jumped or ("is_landing" in other and other.is_landing):
					push_vec_self *= 1.0
					push_vec_other *= 1.0
				
				var new_self_fixed_x = fixed_position_a.x - push_vec_self
				var new_other_fixed_x = fixed_position_b.x - push_vec_other
				
				if overlap_fixed_y > 0:
					var world_node = get_tree().get_first_node_in_group("world")
					if world_node:
						if not ph_parent.is_immune_to_floor_snap and abs(ph_parent.fixed_position.y - world_node.FLOOR_Y) < round(collision_epsilon * SIMULATION_SCALE):
							ph_parent.fixed_position.y = world_node.FLOOR_Y
							ph_parent.fixed_velocity.y = 0
						if not ph_other.is_immune_to_floor_snap and abs(ph_other.fixed_position.y - world_node.FLOOR_Y) < round(collision_epsilon * SIMULATION_SCALE):
							ph_other.fixed_position.y = world_node.FLOOR_Y
							ph_other.fixed_velocity.y = 0
				
				ph_parent.fixed_position.x = new_self_fixed_x
				ph_other.fixed_position.x = new_other_fixed_x
				parent.global_position.x = new_self_fixed_x / SIMULATION_SCALE
				other.global_position.x = new_other_fixed_x / SIMULATION_SCALE
				
				parent.is_being_pushed = push_vec_self != 0
				other.is_being_pushed = push_vec_other != 0
	
	# 最大距離限制（只限制後退）
	if players.size() == 2:
		var ph0 = players[0].get_node_or_null("PhysicsHandler")
		var ph1 = players[1].get_node_or_null("PhysicsHandler")
		if not ph0 or not ph1:
			return
			
		var left_player = players[0] if ph0.fixed_position.x < ph1.fixed_position.x else players[1]
		var right_player = players[1] if ph0.fixed_position.x < ph1.fixed_position.x else players[0]
		
		var left_ph = left_player.get_node("PhysicsHandler")
		var right_ph = right_player.get_node("PhysicsHandler")
		
		var dist_pixels = abs(left_player.global_position.x - right_player.global_position.x)
		if dist_pixels > 1000.0 + collision_epsilon:
			var target_dist_fixed = round(1000.0 * SIMULATION_SCALE)
			
			if right_ph.fixed_velocity.x > 0:
				right_ph.fixed_velocity.x = 0
				right_ph.fixed_position.x = left_ph.fixed_position.x + target_dist_fixed
				right_player.global_position.x = right_ph.fixed_position.x / SIMULATION_SCALE
			
			if left_ph.fixed_velocity.x < 0:
				left_ph.fixed_velocity.x = 0
				left_ph.fixed_position.x = right_ph.fixed_position.x - target_dist_fixed
				left_player.global_position.x = left_ph.fixed_position.x / SIMULATION_SCALE
	
	# 邊界限制
	for player in players:
		var ph = player.get_node_or_null("PhysicsHandler")
		if not ph:
			continue
			
		var arena_left_fixed = round(arena_left * SIMULATION_SCALE)
		var arena_right_fixed = round(arena_right * SIMULATION_SCALE)
		var half_fixed = round(ph.colbox_half_width * SIMULATION_SCALE)
		
		ph.fixed_position.x = clampi(ph.fixed_position.x, arena_left_fixed + half_fixed, arena_right_fixed - half_fixed)
		player.global_position.x = ph.fixed_position.x / SIMULATION_SCALE
		
		player.skip_pushbox = false

func is_at_corner(player: Node) -> bool:
	var ph = player.get_node_or_null("PhysicsHandler")
	if not ph:
		return false
		
	var epsilon_fixed = round(collision_epsilon * SIMULATION_SCALE)
	var fixed_pos_x = ph.fixed_position.x
	var half_fixed = round(ph.colbox_half_width * SIMULATION_SCALE)
	var arena_left_fixed = round(arena_left * SIMULATION_SCALE)
	var arena_right_fixed = round(arena_right * SIMULATION_SCALE)
	
	var left_target = arena_left_fixed + half_fixed
	var right_target = arena_right_fixed - half_fixed
	
	var diff_left = abs(fixed_pos_x - left_target)
	var diff_right = abs(fixed_pos_x - right_target)
	
	var self_at_left = diff_left < epsilon_fixed
	var self_at_right = diff_right < epsilon_fixed
	
	return self_at_left or self_at_right
