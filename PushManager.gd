class_name PushManager extends Node

const SIMULATION_SCALE: float = 1000.0  # 與 world.gd 一致，避免不匹配

@export var PUSH_FRICTION: float = 66.0          # 摩擦用於推開計算（但現在移除額外摩擦）
@export var collision_epsilon: float = 1.0            # 碰撞容差

var players: Array = []

class Collider:
	var center: Vector2i
	var size: Vector2i
	
	func _init(c: Vector2i, s: Vector2i):
		center = c
		size = s
	
	func is_overlapping(other: Collider, x_trigger: int, y_trigger: int) -> bool:
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

func get_depth(a: Collider, b: Collider) -> Vector2i:
	var length = a.center - b.center
	var depth = (a.size + b.size) / 2
	depth.x -= abs(length.x)
	depth.y -= abs(length.y)
	depth.x = max(0, depth.x)
	depth.y = max(0, depth.y)
	return depth

func _ready() -> void:
	players = get_tree().get_nodes_in_group("players")
	for player in players:
		if not ("colbox_half_width" in player and "colbox_half_height" in player):
			if OS.is_debug_build():
				print("Warning: Player %s missing colbox_half_width or colbox_half_height." % player.name)

func _physics_process(delta: float) -> void:
	players = get_tree().get_nodes_in_group("players")
	if players.size() < 2:
		return

	# 處理所有玩家的hit/block/push_back/knockfly計時器
	for player in players:
		if player.is_push_back:
			if player.push_back_timer > 0:
				player.velocity.x = -player.push_back_velocity * player.facing_direction
				player.push_back_timer -= delta
				if player.push_back_timer <= 0:
					player.is_push_back = false
					player.push_back_velocity = 0.0
					player.initial_push_back = 0.0
					player.velocity.x = 0
		if player.is_hit:
			if player.hit_timer > 0:
				player.hit_timer -= delta
				if player.hit_push_timer > 0:
					player.velocity.x = -player.hit_push_velocity * player.facing_direction * (player.hit_push_timer / player.initial_hitstun)
					player.hit_push_timer -= delta
				if player.hit_timer <= 0:
					player.is_hit = false
					player.hit_push_timer = 0.0
					player.hit_push_velocity = 0.0
					player.initial_hitstun = 0.0
					player.velocity.x = 0
		if player.block_timer > 0:
			player.block_timer -= delta
			if player.block_push_timer > 0:
				player.velocity.x = -player.block_push_velocity * player.facing_direction * (player.block_push_timer / player.initial_blockstun)
				player.block_push_timer -= delta
			if player.block_timer <= 0:
				player.is_blocking = false
				player.is_crouch_blocking = false
				player.block_type = "none"
				player.block_push_timer = 0.0
				player.block_push_velocity = 0.0
				player.initial_blockstun = 0.0
				player.velocity.x = 0
		if player.knockfly_timer > 0:
			player.knockfly_timer -= delta
			if player.is_air_hit_knockfly:
				player.velocity.x = player.knockfly_velocity_x * (player.knockfly_timer / player.knockfly_duration)
			else:
				player.velocity.x = player.knockfly_velocity_x * pow(player.knockfly_timer / player.knockfly_duration, 2)
			var delta_x = abs(player.global_position.x - player.prev_position.x)
			player.knockfly_accumulated_distance += delta_x
			if player.knockfly_accumulated_distance >= player.knockfly_max_distance:
				player.velocity.x = 0
				player.knockfly_velocity_x = 0.0
			if player.knockfly_timer <= 0 and player.is_knockfly:
				var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % player.name) if get_tree().get_first_node_in_group("ui") else null
				if healthbar and healthbar.current_health <= 0:
					pass
				else:
					player.velocity.x = 0
					player.knockfly_velocity_x = 0.0
					player.knockfly_accumulated_distance = 0.0
					if player.animation_player:
						player.animation_player.speed_scale = 1.0

	# 中心化推開處理：移植 Sakuga 的邏輯，移除 trigger/min_push/friction/multiplier，使用精準 depth 推開
	for i in range(players.size()):
		var parent = players[i]
		parent.is_being_pushed = false
		for j in range(i + 1, players.size()):
			var other = players[j]
			if parent.is_hit or other.is_hit or parent.is_knockfly or other.is_knockfly or parent.is_blocking or other.is_blocking:
				continue  # 跳過禁用狀態，但允許attacking

			# 計算fixed_position和offset
			var fixed_position_a = Vector2i(round(parent.global_position.x * SIMULATION_SCALE), round(parent.global_position.y * SIMULATION_SCALE))
			var fixed_position_b = Vector2i(round(other.global_position.x * SIMULATION_SCALE), round(other.global_position.y * SIMULATION_SCALE))
			
			var pushbox_offset_a = parent.get_node("Pushbox").position if parent.has_node("Pushbox") else Vector2.ZERO
			var fixed_offset_a = Vector2i(round(pushbox_offset_a.x * SIMULATION_SCALE), round(pushbox_offset_a.y * SIMULATION_SCALE))
			var pushbox_offset_b = other.get_node("Pushbox").position if other.has_node("Pushbox") else Vector2.ZERO
			var fixed_offset_b = Vector2i(round(pushbox_offset_b.x * SIMULATION_SCALE), round(pushbox_offset_b.y * SIMULATION_SCALE))
			
			var side_a = Vector2i(int(parent.facing_direction), 1)
			var side_b = Vector2i(int(other.facing_direction), 1)
			
			var center_a = fixed_position_a + fixed_offset_a * side_a
			var size_a = Vector2i(round(parent.colbox_half_width * 2 * SIMULATION_SCALE), round(parent.colbox_half_height * 2 * SIMULATION_SCALE))
			var collider_a = Collider.new(center_a, size_a)
			
			var center_b = fixed_position_b + fixed_offset_b * side_b
			var size_b = Vector2i(round(other.colbox_half_width * 2 * SIMULATION_SCALE), round(other.colbox_half_height * 2 * SIMULATION_SCALE))
			var collider_b = Collider.new(center_b, size_b)
			
			# 檢查是否重疊（無 trigger，移植 Sakuga 的精準檢測）
			if collider_a.is_overlapping(collider_b, 0, 0):
				# 計算實際 depth
				var depth = get_depth(collider_a, collider_b)
				var overlap_fixed_x = depth.x
				var overlap_fixed_y = depth.y
				
				if overlap_fixed_x <= 0:
					continue
				
				# 推開距離為 depth.x（精準分離，無額外添加）
				var push_distance_fixed = overlap_fixed_x
				
				# 計算 normal_x
				var normal_x: int
				if fixed_position_a.x > fixed_position_b.x:
					normal_x = -1
				elif fixed_position_a.x < fixed_position_b.x:
					normal_x = 1
				else:
					normal_x = 1 if is_at_corner(parent) else -1  # 罕見情況，使用角落或默認
				
				# 計算邊界
				var epsilon_fixed = round(collision_epsilon * SIMULATION_SCALE)
				var arena_left_fixed = round(parent.arena_left * SIMULATION_SCALE)
				var arena_right_fixed = round(parent.arena_right * SIMULATION_SCALE)
				
				var half_a_fixed = size_a.x / 2
				var half_b_fixed = size_b.x / 2
				
				var self_at_left = abs(fixed_position_a.x - (arena_left_fixed + half_a_fixed)) < epsilon_fixed
				var self_at_right = abs(fixed_position_a.x - (arena_right_fixed - half_a_fixed)) < epsilon_fixed
				var other_at_left = abs(fixed_position_b.x - (arena_left_fixed + half_b_fixed)) < epsilon_fixed
				var other_at_right = abs(fixed_position_b.x - (arena_right_fixed - half_b_fixed)) < epsilon_fixed
				
				# 計算 unpushable（移植 Sakuga）
				var unpush_self = (other_at_left and fixed_position_a.x >= fixed_position_b.x) or (other_at_right and fixed_position_a.x <= fixed_position_b.x)
				var unpush_other = (self_at_left and fixed_position_b.x >= fixed_position_a.x) or (self_at_right and fixed_position_b.x <= fixed_position_a.x)
				
				# 計算推開量（修正：確保最小推開量以防止微小重疊）
				var push_vec_self = normal_x * (push_distance_fixed / 2 + 1)  # 額外 +1 防止重疊
				var push_vec_other = -normal_x * (push_distance_fixed / 2 + 1)
				
				if unpush_self:
					push_vec_self = normal_x * (push_distance_fixed + 2)  # 額外 +2 確保分離
				if unpush_other:
					push_vec_other = -normal_x * (push_distance_fixed + 2)
				
				# 計算新位置
				var new_self_fixed_x = fixed_position_a.x - push_vec_self
				var new_other_fixed_x = fixed_position_b.x - push_vec_other
				
				# 直接更新 fixed_position 和 global_position（同步 fixed_position 防止 snap back）
				parent.fixed_position.x = new_self_fixed_x
				other.fixed_position.x = new_other_fixed_x
				parent.global_position.x = new_self_fixed_x / SIMULATION_SCALE
				other.global_position.x = new_other_fixed_x / SIMULATION_SCALE
				parent.is_being_pushed = true
				other.is_being_pushed = true

	# 最終夾住所有玩家的位置（使用 fixed_position 保持一致）
	for player in players:
		var arena_left_fixed = round(player.arena_left * SIMULATION_SCALE)
		var arena_right_fixed = round(player.arena_right * SIMULATION_SCALE)
		var half_fixed = round(player.colbox_half_width * SIMULATION_SCALE)
		player.fixed_position.x = clamp(player.fixed_position.x, arena_left_fixed + half_fixed, arena_right_fixed - half_fixed)
		player.global_position.x = player.fixed_position.x / SIMULATION_SCALE

func is_at_corner(player: Node) -> bool:
	var epsilon_fixed = round(collision_epsilon * SIMULATION_SCALE)
	var fixed_pos_x = round(player.global_position.x * SIMULATION_SCALE)
	var half_fixed = round(player.colbox_half_width * SIMULATION_SCALE)
	var arena_left_fixed = round(player.arena_left * SIMULATION_SCALE)
	var arena_right_fixed = round(player.arena_right * SIMULATION_SCALE)
	var self_at_left = abs(fixed_pos_x - (arena_left_fixed + half_fixed)) < epsilon_fixed
	var self_at_right = abs(fixed_pos_x - (arena_right_fixed - half_fixed)) < epsilon_fixed
	return self_at_left or self_at_right
