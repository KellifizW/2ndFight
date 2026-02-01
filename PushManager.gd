class_name PushManager extends Node

const SIMULATION_SCALE: float = 1000.0

@export var PUSH_FRICTION: float = 66.0
@export var collision_epsilon: float = 5.0
@export var arena_left: float = 0.0
@export var arena_right: float = 1600.0
@export var ground_push_multiplier: float = 0.6  # 地面推開倍數
@export var jump_push_multiplier: float = 1.0   # 跳躍推開倍數 (降低此值可減少跳躍越過時的推開距離)
@export var knockback_deceleration_power: float = 3.0  # 🟢 Knockback 減速指數
													   # 1.0=線性, 2.0=二次方, 3.0+=越來越快減速

var players: Array = []

class Collider:
	var center: Vector2i
	var size: Vector2i
	
	func _init(c: Vector2i, s: Vector2i):
		center = c
		size = s
	
	func is_overlapping(other: Collider, x_trigger: int, y_trigger: int) -> bool:
		@warning_ignore("integer_division")
		var left_a = center.x - (size.x / 2)
		@warning_ignore("integer_division")
		var right_a = center.x + (size.x / 2)
		@warning_ignore("integer_division")
		var left_b = other.center.x - (other.size.x / 2)
		@warning_ignore("integer_division")
		var right_b = other.center.x + (other.size.x / 2)
		var has_x_overlap = left_a <= right_b + x_trigger and right_a >= left_b - x_trigger
		
		@warning_ignore("integer_division")
		var up_a = center.y - (size.y / 2)
		@warning_ignore("integer_division")
		var down_a = center.y + (size.y / 2)
		@warning_ignore("integer_division")
		var up_b = other.center.y - (other.size.y / 2)
		@warning_ignore("integer_division")
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
	add_to_group("push_manager")

func _physics_process(delta: float) -> void:
	players = get_tree().get_nodes_in_group("players")
	if players.size() < 2:
		return

	# 處理計時器
	for player in players:
		if player.is_push_back:
			if player.push_back_timer > 0:
				player.fixed_velocity.x = int(-player.push_back_velocity * player.facing_direction * (player.push_back_timer / player.initial_push_back))
				player.push_back_timer -= delta
				if player.push_back_timer <= 0:
					player.is_push_back = false
					player.push_back_velocity = 0.0
					player.initial_push_back = 0.0
					player.fixed_velocity.x = 0
		
		# ────────────────────────────────────────────────────────────────────────
		# ── 【Knockback 執行 - 獨立於 hitstun，確保完整執行】──
		# ────────────────────────────────────────────────────────────────────────
		if player.knockback_frames > 0:
			# 🔴 DEBUG: 首次執行 knockback 時記錄時間
			if player.knockback_start_time <= 0:
				player.knockback_start_time = Time.get_ticks_msec() / 1000.0
				print("[KNOCKBACK EXECUTION START] %s - Time: %.3f, knockback_frames: %d, initial_knockback_frames: %d, hitstun_frames: %d" % [
					player.name, player.knockback_start_time, player.knockback_frames, player.initial_knockback_frames, player.hitstun_frames
				])
			
			# 計算衰減倍數（二次方衰減曲線）
			# 使用 initial_knockback_frames（初始值，固定不變），而非 hitstun_frames（會變動）
			var total_knockback_frames = player.initial_knockback_frames
			if total_knockback_frames <= 0:
				total_knockback_frames = 1  # 避免除以 0
				print("[KNOCKBACK WARNING] %s - initial_knockback_frames 是 0！使用 1 避免除以 0" % player.name)
			
			var remaining_ratio: float = player.knockback_frames / float(total_knockback_frames)
			# 🟢 使用可配置的減速指數，支援提早減速效果
			# remaining_ratio^power：指數越高，減速越快、越早開始
			var speed_multiplier: float = pow(remaining_ratio, knockback_deceleration_power)
			player.fixed_velocity.x = int(-player.hit_push_velocity * speed_multiplier * player.facing_direction)
			
			# 🔴 重要：knockback_frames 的遞減現在在 Fighter._physics_process 中處理
			# 這裡只負責計算並應用速度，不負責遞減幀數
			var old_frames = player.knockback_frames
			
			# 每 6 幀顯示一次進度（約 0.1 秒）
			if int(old_frames) % 6 == 0 or player.knockback_frames <= 0:
				var elapsed_frames = total_knockback_frames - player.knockback_frames
				var progress_percent = elapsed_frames * 100.0 / total_knockback_frames
				
				if total_knockback_frames <= 0:
					progress_percent = 0.0
				
				print("[KNOCKBACK PROGRESS] %s - %.1f%% complete, remaining: %d frames, total_expected: %d, velocity: %d" % [
					player.name, progress_percent, player.knockback_frames, total_knockback_frames, player.fixed_velocity.x
				])
			
			# Knockback結束檢查
			if player.knockback_frames <= 0:
				var expected_frames = player.initial_knockback_frames  # ✅ 使用初始值
				var physics_fps = Engine.physics_ticks_per_second  # ✅ 使用動態 FPS
				var expected_duration = expected_frames / float(physics_fps)
				
				# knockback_frames 和 hitstun_frames 現在完全同步（都在 Fighter._physics_process 中遞減）
				# 所以實際執行的幀數應該等於初始值
				var actual_duration_by_frames = expected_duration
				
				# 牆上時鐘計時（用於參考，但可能因 time_scale 而不同）
				var actual_duration_by_clock = 0.0
				if player.knockback_start_time > 0:
					actual_duration_by_clock = (Time.get_ticks_msec() / 1000.0) - player.knockback_start_time
				
				print("\n[KNOCKBACK END] %s" % player.name)
				print("  - Expected Duration: %.3fs (%d frames @%d FPS)" % [expected_duration, expected_frames, physics_fps])
				print("  - Actual Duration (by frames): %.3fs" % actual_duration_by_frames)
				print("  - Actual Duration (by clock): %.3fs (可能因 time_scale 而異)" % actual_duration_by_clock)
				
				var sync_status = "✅ 同步" if abs(actual_duration_by_frames - expected_duration) < 0.05 else "❌ 不同步"
				print("  - Sync Status: %s\n" % sync_status)
				
				player.knockback_frames = 0
				player.hit_push_velocity = 0.0
				player.hit_push_initial_velocity = 0.0
				player.knockback_start_time = 0.0
				player.fixed_velocity.x = 0
		
		# ────────────────────────────────────────────────────────────────────────
		# ── 【Hitstun 和 Hit_timer（舊的Delta系統，保留用於兼容）】──
		# ────────────────────────────────────────────────────────────────────────
		if player.is_hit:
			if player.hit_timer > 0:
				player.hit_timer -= delta
				
				# ── Hitstun結束檢查 (與knockback獨立) ──
				if player.hit_timer <= 0:
					player.is_hit = false
					player.hit_push_delay_timer = 0.0
					player.initial_hitstun = 0.0
					player.hit_timer = 0.0
		if player.block_timer > 0:
			player.block_timer -= delta
			if player.block_push_timer > 0:
				player.fixed_velocity.x = int(-player.block_push_velocity * player.facing_direction * (player.block_push_timer / player.initial_blockstun))
				player.block_push_timer -= delta
			if player.block_timer <= 0:
				player.is_blocking = false
				player.is_crouch_blocking = false
				player.block_type = "none"
				player.block_push_timer = 0.0
				player.block_push_velocity = 0.0
				player.initial_blockstun = 0.0
				player.fixed_velocity.x = 0
		if player.knockfly_timer > 0:
			player.knockfly_timer -= delta
			if player.is_air_hit_knockfly:
				player.fixed_velocity.x = int(player.knockfly_velocity_x * (player.knockfly_timer / player.knockfly_duration))
			else:
				player.fixed_velocity.x = int(player.knockfly_velocity_x * pow(player.knockfly_timer / player.knockfly_duration, 2))
			var delta_x = abs(player.global_position.x - player.prev_position.x)
			player.knockfly_accumulated_distance += delta_x
			if player.knockfly_accumulated_distance >= player.knockfly_max_distance:
				player.fixed_velocity.x = 0
				player.knockfly_velocity_x = 0.0
			if player.knockfly_timer <= 0 and player.is_knockfly:
				var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % player.name) if get_tree().get_first_node_in_group("ui") else null
				if healthbar and healthbar.current_health <= 0:
					pass
				else:
					player.fixed_velocity.x = 0
					player.knockfly_velocity_x = 0.0
					player.knockfly_accumulated_distance = 0.0
					if player.animation_player:
						player.animation_player.speed_scale = 1.0

	# 推開處理
	for i in range(players.size()):
		var parent = players[i]
		var move_set = parent.get_node_or_null("MoveSet")
		var is_penetrable = false
		if move_set:
			# Check if the active move is penetrable
			is_penetrable = move_set.is_spmove and move_set.current_move_state.active_move and move_set.current_move_state.active_move.penetrable
		parent.is_being_pushed = false
		if is_penetrable or parent.skip_pushbox:
			continue
		for j in range(i + 1, players.size()):
			var other = players[j]
			var other_move_set = other.get_node_or_null("MoveSet")
			var other_is_penetrable = false
			if other_move_set:
				# Check if the active move is penetrable
				other_is_penetrable = other_move_set.is_spmove and other_move_set.current_move_state.active_move and other_move_set.current_move_state.active_move.penetrable
			if other_is_penetrable or other.skip_pushbox:
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
			var size_a = Vector2i(round(parent.colbox_half_width * 2 * SIMULATION_SCALE), round(parent.colbox_half_height * 2 * SIMULATION_SCALE))
			var collider_a = Collider.new(center_a, size_a)
			
			var center_b = fixed_position_b + fixed_offset_b * side_b
			var size_b = Vector2i(round(other.colbox_half_width * 2 * SIMULATION_SCALE), round(other.colbox_half_height * 2 * SIMULATION_SCALE))
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
					var push_amount = push_distance_fixed * ground_push_multiplier + 1
					push_vec_self = normal_x * push_amount
					push_vec_other = -normal_x * push_amount
				
				# 跳躍時應用不同的推開倍數
				if parent.just_jumped or other.just_jumped:
					push_vec_self = int(float(push_vec_self) * jump_push_multiplier)
					push_vec_other = int(float(push_vec_other) * jump_push_multiplier)
				elif parent.is_landing or other.is_landing:
					# 著陸時保持正常推開
					pass
				
				var new_self_fixed_x = fixed_position_a.x - push_vec_self
				var new_other_fixed_x = fixed_position_b.x - push_vec_other
				
				if overlap_fixed_y > 0:
					var world = get_tree().get_first_node_in_group("world")
					if world:
						if not parent.is_immune_to_floor_snap and abs(parent.fixed_position.y - world.FLOOR_Y) < round(collision_epsilon * SIMULATION_SCALE):
							parent.fixed_position.y = world.FLOOR_Y
							parent.fixed_velocity.y = 0
						if not other.is_immune_to_floor_snap and abs(other.fixed_position.y - world.FLOOR_Y) < round(collision_epsilon * SIMULATION_SCALE):
							other.fixed_position.y = world.FLOOR_Y
							other.fixed_velocity.y = 0
				
				parent.fixed_position.x = new_self_fixed_x
				other.fixed_position.x = new_other_fixed_x
				parent.global_position.x = new_self_fixed_x / SIMULATION_SCALE
				other.global_position.x = new_other_fixed_x / SIMULATION_SCALE
				parent.is_being_pushed = push_vec_self != 0
				other.is_being_pushed = push_vec_other != 0
			# 角色間最大距離限制 (1000 像素) - 只限後退 (允許前進 + 推擠)
		if players.size() == 2:
			var left_player = players[0] if players[0].fixed_position.x < players[1].fixed_position.x else players[1]
			var right_player = players[1] if players[0].fixed_position.x < players[1].fixed_position.x else players[0]
			
			var dist_pixels = abs(left_player.global_position.x - right_player.global_position.x)
			if dist_pixels > 1000.0 + collision_epsilon:  # 加 epsilon 防抖動
				var target_dist_fixed = round(1000.0 * SIMULATION_SCALE)
				
				# right_player 後退 = velocity.x > 0 → 鎖 velocity + 拉 position
				if right_player.fixed_velocity.x > 0:
					right_player.fixed_velocity.x = 0
					right_player.fixed_position.x = left_player.fixed_position.x + target_dist_fixed
					right_player.global_position.x = right_player.fixed_position.x / SIMULATION_SCALE
				
				# left_player 後退 = velocity.x < 0 → 鎖 velocity + 拉 position
				if left_player.fixed_velocity.x < 0:
					left_player.fixed_velocity.x = 0
					left_player.fixed_position.x = right_player.fixed_position.x - target_dist_fixed
					left_player.global_position.x = left_player.fixed_position.x / SIMULATION_SCALE

	# 邊界限制
	for player in players:
		var arena_left_fixed = round(arena_left * SIMULATION_SCALE)
		var arena_right_fixed = round(arena_right * SIMULATION_SCALE)
		var half_fixed = round(player.colbox_half_width * SIMULATION_SCALE)
		player.fixed_position.x = clampi(player.fixed_position.x, arena_left_fixed + half_fixed, arena_right_fixed - half_fixed)
		player.global_position.x = player.fixed_position.x / SIMULATION_SCALE
		player.skip_pushbox = false

func is_at_corner(player: Node) -> bool:
	var epsilon_fixed = round(collision_epsilon * SIMULATION_SCALE)
	var fixed_pos_x = player.fixed_position.x
	var half_fixed = round(player.colbox_half_width * SIMULATION_SCALE)
	var arena_left_fixed = round(arena_left * SIMULATION_SCALE)
	var arena_right_fixed = round(arena_right * SIMULATION_SCALE)
	var left_target = arena_left_fixed + half_fixed
	var right_target = arena_right_fixed - half_fixed
	var diff_left = abs(fixed_pos_x - left_target)
	var diff_right = abs(fixed_pos_x - right_target)
	var self_at_left = diff_left < epsilon_fixed
	var self_at_right = diff_right < epsilon_fixed
	return self_at_left or self_at_right
