class_name PushManager extends Node

@export var push_distance_multiplier: float = 0.5  # 地面推開力
@export var PUSH_FRICTION: float = 66.0          # 摩擦用於推開計算
@export var ground_push_trigger_distance: float = 2.0  # 地面推開觸發距離
@export var air_push_trigger_distance: float = 11.0    # 空中推開觸發距離
@export var corner_y_trigger_distance: float = 27.0    # 邊角空中y觸發距離
@export var collision_epsilon: float = 1.0            # 碰撞容差

var players: Array = []

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

	# 中心化推開處理：使用 Pushbox 作為碰撞計算基準
	for i in range(players.size()):
		var parent = players[i]
		parent.is_being_pushed = false
		for j in range(i + 1, players.size()):
			var other = players[j]
			if parent.is_hit or other.is_hit or parent.is_knockfly or other.is_knockfly or parent.is_blocking or other.is_blocking:
				continue  # 跳過禁用狀態，但允許attacking

			# 使用 Pushbox 的位置作為基準，移除 Sprite2D 影響
			var pushbox_offset = parent.get_node("Pushbox").position if parent.has_node("Pushbox") else Vector2.ZERO
			var other_pushbox_offset = other.get_node("Pushbox").position if other.has_node("Pushbox") else Vector2.ZERO
			var leftA = parent.global_position.x - parent.colbox_half_width + pushbox_offset.x
			var rightA = parent.global_position.x + parent.colbox_half_width + pushbox_offset.x
			var upA = parent.global_position.y - parent.colbox_half_height + pushbox_offset.y
			var downA = parent.global_position.y + parent.colbox_half_height + pushbox_offset.y
			var leftB = other.global_position.x - other.colbox_half_width + other_pushbox_offset.x
			var rightB = other.global_position.x + other.colbox_half_width + other_pushbox_offset.x
			var upB = other.global_position.y - other.colbox_half_height + other_pushbox_offset.y
			var downB = other.global_position.y + other.colbox_half_height + other_pushbox_offset.y

			# 修正重疊計算，確保非負
			var overlap_x = max(0.0, min(rightA, rightB) - max(leftA, leftB))
			var overlap_y = max(0.0, min(downA, downB) - max(upA, upB))
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

				# 使用 move_and_collide 進行平滑移動
				var self_velocity = Vector2(new_self_x - parent.global_position.x, 0.0)
				var other_velocity = Vector2(new_other_x - other.global_position.x, 0.0)
				var prev_velocity_y = parent.velocity.y
				parent.move_and_collide(self_velocity, false, 0.0, false)
				parent.velocity.y = prev_velocity_y
				var other_prev_velocity_y = other.velocity.y
				other.move_and_collide(other_velocity, false, 0.0, false)
				other.velocity.y = other_prev_velocity_y
				parent.is_being_pushed = true
				other.is_being_pushed = true

				if OS.is_debug_build():
					print("Debug: Push applied - %s x=%s, %s x=%s, overlap_x=%s, overlap_y=%s, is_air=%s, relative_pos_x=%s, parent_velocity_y=%.2f, other_velocity_y=%.2f" % 
						  [parent.name, new_self_x, other.name, new_other_x, overlap_x, overlap_y, (parent.is_jumping or other.is_jumping), relative_pos_x, prev_velocity_y, other_prev_velocity_y])

	# 最終夾住所有玩家的位置
	for player in players:
		player.global_position.x = clamp(player.global_position.x, player.arena_left + player.colbox_half_width, player.arena_right - player.colbox_half_width)

func is_at_corner(player: Node) -> bool:
	var self_at_left = abs(player.global_position.x - (player.arena_left + player.colbox_half_width)) < collision_epsilon
	var self_at_right = abs(player.global_position.x - (player.arena_right - player.colbox_half_width)) < collision_epsilon
	return self_at_left or self_at_right
