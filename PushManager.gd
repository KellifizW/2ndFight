class_name PushManager extends Node

const SIMULATION_SCALE: float = 1000.0

# 🟢 Knockback 減速模式 Enum
enum DecelMode {
	POWER,           # 幂函數減速
	EASE_OUT,        # 緩動出（開始快減速，後期平緩）
	EASE_IN_OUT,     # 緩動進出（S形曲線）
	LINEAR_THRESHOLD # 線性閾值（分段式）
}

# 🟢 【調試開關】可在 Inspector 中快速切換詳細輸出
@export_group("Debug Settings")
@export var debug_knockback_velocity_calc: bool = true  # 反推速度計算的詳細輸出
@export var debug_knockback_execution: bool = true      # Knockback 執行的每幀詳細輸出
@export var debug_position_tracking: bool = true        # 位置追蹤的詳細輸出

@export var PUSH_FRICTION: float = 66.0
@export var collision_epsilon: float = 5.0
@export var arena_left: float = 0.0
@export var arena_right: float = 1600.0
@export var ground_push_multiplier: float = 0.6  # 地面推開倍數
@export var jump_push_multiplier: float = 1.0   # 跳躍推開倍數 (降低此值可減少跳躍越過時的推開距離)

# 🟢 Knockback 減速曲線控制組（在 Inspector 中可自由調整）
@export_group("Knockback Deceleration Curve")
@export var knockback_deceleration_mode: DecelMode = DecelMode.POWER  # 下拉選單選擇減速模式
@export var knockback_deceleration_power: float = 2.0  # 用於 POWER 模式：1.0=線性, 2.0=二次方, 3.0+=越來越快減速
@export var knockback_ease_strength: float = 1.5  # 用於 EASE_OUT 模式：控制緩動強度 (1.0-3.0)
@export var knockback_linear_threshold: float = 0.3  # 用於 LINEAR_THRESHOLD 模式：何時開始減速 (0.0-1.0)
@export var knockback_minimum_velocity_ratio: float = 0.05  # 最小速度比例 (0.0-0.5)，防止完全停止

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
	@warning_ignore("integer_division")
	var depth = (a.size + b.size) / 2
	depth.x -= abs(length.x)
	depth.y -= abs(length.y)
	depth.x = max(0, depth.x)
	depth.y = max(0, depth.y)
	return depth

# 🟢 計算 Knockback 減速倍數 - 支援多種曲線模式
func calculate_knockback_speed_multiplier(remaining_ratio: float) -> float:
	"""
	remaining_ratio: 0.0 (完成) ~ 1.0 (開始)
	返回值：速度倍數 0.0 ~ 1.0
	"""
	match knockback_deceleration_mode:
		# 模式 1: 幂函數（Power）- 最簡單直接
		DecelMode.POWER:
			return pow(remaining_ratio, knockback_deceleration_power)
		
		# 模式 2: 緩動出（Ease Out）- 開始快減速，後期平緩
		DecelMode.EASE_OUT:
			# 1 - (1 - remaining_ratio)^strength
			var inverse = 1.0 - remaining_ratio
			return 1.0 - pow(inverse, knockback_ease_strength)
		
		# 模式 3: 緩動進出（Ease In Out）- 開始減速緩，中間快，後期緩
		DecelMode.EASE_IN_OUT:
			if remaining_ratio < 0.5:
				var t = remaining_ratio * 2.0
				return 0.5 * pow(t, knockback_ease_strength)
			else:
				var t = (remaining_ratio - 0.5) * 2.0
				return 0.5 + 0.5 * (1.0 - pow(1.0 - t, knockback_ease_strength))
		
		# 模式 4: 線性閾值（Linear Threshold）- 開始線性，超過閾值後快速減速
		DecelMode.LINEAR_THRESHOLD:
			if remaining_ratio >= knockback_linear_threshold:
				# 線性區間
				return remaining_ratio
			else:
				# 快速減速區間
				var normalized = remaining_ratio / knockback_linear_threshold
				return knockback_linear_threshold * pow(normalized, knockback_deceleration_power)
		
		_:  # 默認使用 Power 模式
			return pow(remaining_ratio, knockback_deceleration_power)

# 🟢 反推初始速度：根據目標距離和衰減曲線，計算所需的初始速度
func calculate_required_knockback_velocity(target_distance_units: int, total_frames: int, debug_player_name: String = "") -> float:
	"""
	根據目標距離和 hitstun 幀數，反推初始速度
	
	原理：
	- 每幀的位移 = 初始速度 × 衰減倍數
	- 總距離 = 求和（每幀位移）= 初始速度 × 求和（衰減倍數）
	- 初始速度 = 目標距離 / 求和（衰減倍數）
	
	參數：
	- target_distance_units: 目標距離（固定點單位，已乘以 SIMULATION_SCALE）
	- total_frames: hitstun 或 blockstun 的總幀數
	- debug_player_name: 調試用的角色名稱（可選）
	
	返回：
	- 所需的初始速度（固定點單位）
	"""
	if total_frames <= 0:
		return 0.0
	
	# 計算衰減係數的總和（積分近似）
	var deceleration_sum: float = 0.0
	var frame_multipliers: Array = []  # 調試用：記錄每幀的衰減倍數
	
	for frame in range(total_frames):
		var remaining_ratio = float(total_frames - frame) / float(total_frames)
		var speed_multiplier = calculate_knockback_speed_multiplier(remaining_ratio)
		deceleration_sum += speed_multiplier
		frame_multipliers.append(speed_multiplier)
	
	# 反推初始速度
	if deceleration_sum <= 0:
		return 0.0
	
	# 🟢 【關鍵修復】考慮 delta 時間步長（Movement.gd 中 fixed_position += velocity * delta）
	# 總移動 = Σ(velocity * speed_multiplier * delta) = velocity * delta * deceleration_sum
	# 因此：velocity = total_distance / (delta * deceleration_sum)
	var physics_fps = Engine.physics_ticks_per_second  # 120 FPS
	var delta_factor = float(physics_fps)  # 補償 delta = 1/120
	var required_velocity = float(target_distance_units) * delta_factor / deceleration_sum
	
	return required_velocity

# 🟢 輔助函數：取得衰減模式的名稱
func _get_decel_mode_name() -> String:
	match knockback_deceleration_mode:
		DecelMode.POWER:
			return "POWER (power: %.1f)" % knockback_deceleration_power
		DecelMode.EASE_OUT:
			return "EASE_OUT (strength: %.1f)" % knockback_ease_strength
		DecelMode.EASE_IN_OUT:
			return "EASE_IN_OUT (strength: %.1f)" % knockback_ease_strength
		DecelMode.LINEAR_THRESHOLD:
			return "LINEAR_THRESHOLD (threshold: %.1f)" % knockback_linear_threshold
		_:
			return "UNKNOWN"

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
			if player.push_back_frames > 0:
				# Calculate progress (0.0 to 1.0) for smooth deceleration
				var progress = float(player.push_back_frames) / float(player.initial_push_back_frames)
				player.fixed_velocity.x = int(-player.push_back_velocity * player.facing_direction * progress)
				player.push_back_frames -= 1  # Decrement by 1 frame
			else:
				player.is_push_back = false
				player.fixed_velocity.x = 0
		
		# ────────────────────────────────────────────────────────────────────────
		# ── 【Knockback 執行 - 獨立於 hitstun，確保完整執行】──
		# ────────────────────────────────────────────────────────────────────────
		if player.knockback_frames > 0:
			# 🔴 DEBUG: 首次執行 knockback 時記錄時間和初始位置
			if player.knockback_start_time <= 0:
				player.knockback_start_time = Time.get_ticks_msec() / 1000.0
				
				# 🟢 【重要】保存 knockback 開始時的位置，用於計算實際移動距離
				player.knockback_start_x = player.position.x
				
		# 計算衰減倍數（二次方衰減曲線）
			# 使用 initial_knockback_frames（初始值，固定不變），而非 hitstun_frames（會變動）
			var total_knockback_frames = player.initial_knockback_frames
			if total_knockback_frames <= 0:
				total_knockback_frames = 1  # 避免除以 0
			
			var remaining_ratio: float = player.knockback_frames / float(total_knockback_frames)
			# 🟢 使用新的多模式減速曲線計算函數
			var speed_multiplier: float = calculate_knockback_speed_multiplier(remaining_ratio)
			player.fixed_velocity.x = int(-player.hit_push_velocity * speed_multiplier * player.facing_direction)
			
			# 🔴 重要：knockback_frames 的遞減現在在 Fighter._physics_process 中處理
			# 這裡只負責計算並應用速度，不負責遞減幀數
			var _old_frames = player.knockback_frames
			
			# Knockback結束檢查
			if player.knockback_frames <= 0:
				player.knockback_frames = 0
				player.hit_push_velocity = 0.0
				player.hit_push_initial_velocity = 0.0
				player.knockback_start_time = 0.0
				player.fixed_velocity.x = 0
		
		# ────────────────────────────────────────────────────────────────────────
		# ── 【Block Knockback 執行（幀計數系統）】──
		# ────────────────────────────────────────────────────────────────────────
		if player.block_knockback_frames > 0:
			# 計算衰減倍數（使用與 Hit Knockback 相同的曲線系統）
			var total_block_knockback_frames = player.initial_block_knockback_frames
			if total_block_knockback_frames <= 0:
				total_block_knockback_frames = 1  # 避免除以 0
			
			var remaining_ratio: float = player.block_knockback_frames / float(total_block_knockback_frames)
			var speed_multiplier: float = calculate_knockback_speed_multiplier(remaining_ratio)
			player.fixed_velocity.x = int(-player.block_push_initial_velocity * speed_multiplier * player.facing_direction)
			
			# Block Knockback 結束檢查
			if player.block_knockback_frames <= 0:
				player.block_knockback_frames = 0
				player.block_push_initial_velocity = 0.0
				player.fixed_velocity.x = 0
		
		# ────────────────────────────────────────────────────────────────────────
		# ── 【Corner Push 執行（使用與 Knockback 相同的機制）】──
		# ────────────────────────────────────────────────────────────────────────
		if player.corner_push_frames > 0:
			# 首次執行時記錄起始位置
			if player.corner_push_start_x <= 0 or player.corner_push_start_x == player.position.x:
				player.corner_push_start_x = player.position.x
			
			# 計算衰減倍數（使用與 Knockback 相同的曲線系統）
			var total_corner_push_frames = player.initial_corner_push_frames
			if total_corner_push_frames <= 0:
				total_corner_push_frames = 1  # 避免除以 0
			
			var remaining_ratio: float = player.corner_push_frames / float(total_corner_push_frames)
			var speed_multiplier: float = calculate_knockback_speed_multiplier(remaining_ratio)
			player.fixed_velocity.x = int(-player.corner_push_velocity * speed_multiplier * player.facing_direction)
			
			# Corner Push 結束檢查
			if player.corner_push_frames <= 0:
				var moved_distance = abs(player.position.x - player.corner_push_start_x)
				if debug_knockback_execution:
					print("[CORNER PUSH SUMMARY] %s - moved: %.2f px" % [player.name, moved_distance])
				player.corner_push_frames = 0
				player.corner_push_velocity = 0.0
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
					player.initial_hitstun = 0.0
					player.hit_timer = 0.0
		if player.block_timer > 0:
			player.block_timer -= delta
			# @deprecated 舊的 Delta-based block pushblock 邏輯（保留向後兼容）
			if player.block_push_timer > 0:
				player.block_push_timer -= delta
			if player.block_timer <= 0:
				player.is_blocking = false
				player.is_crouch_blocking = false
				player.block_type = "none"
				player.block_push_timer = 0.0  # @deprecated
				player.block_push_velocity = 0.0  # @deprecated
				player.initial_blockstun = 0.0  # @deprecated
				# 注意：block_knockback_frames 的遞減現在在 Fighter._physics_process 中處理
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
		
		# 🟢 【THROW SYSTEM FIX】Skip pushbox during throw
		var parent_in_throw = false
		if "is_being_thrown" in parent and parent.is_being_thrown:
			parent_in_throw = true  # Victim: being thrown
		if "attack_type" in parent and (parent.attack_type == "throw_enter" or parent.attack_type == "throw_seq"):
			parent_in_throw = true  # Attacker: executing throw
		
		if is_penetrable or parent.skip_pushbox or parent_in_throw:
			continue
		
		for j in range(i + 1, players.size()):
			var other = players[j]
			var other_move_set = other.get_node_or_null("MoveSet")
			var other_is_penetrable = false
			if other_move_set:
				# Check if the active move is penetrable
				other_is_penetrable = other_move_set.is_spmove and other_move_set.current_move_state.active_move and other_move_set.current_move_state.active_move.penetrable
			
			# 🟢 【THROW SYSTEM FIX】Skip pushbox during throw
			var other_in_throw = false
			if "is_being_thrown" in other and other.is_being_thrown:
				other_in_throw = true  # Victim: being thrown
			if "attack_type" in other and (other.attack_type == "throw_enter" or other.attack_type == "throw_seq"):
				other_in_throw = true  # Attacker: executing throw
			
			if other_is_penetrable or other.skip_pushbox or other_in_throw:
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
						# 🟢 【关键修正】只在两个角色都在地面时才进行地面吸附
						# 如果任一角色正在跳跃（is_jumping=true），则跳过速度清零
						var parent_needs_snap = not parent.is_immune_to_floor_snap and abs(parent.fixed_position.y - world.FLOOR_Y) < round(collision_epsilon * SIMULATION_SCALE)
						var other_needs_snap = not other.is_immune_to_floor_snap and abs(other.fixed_position.y - world.FLOOR_Y) < round(collision_epsilon * SIMULATION_SCALE)
						
						# 🟢 【调试】记录速度清零操作
						if parent_needs_snap and not parent.is_jumping:
							if parent.fixed_velocity.y != 0:
								print("[PUSH_SNAP] %s 地面吸附清零速度: velocity.y=%d → 0 | pos.y=%d | FLOOR_Y=%d" % [
									parent.name, parent.fixed_velocity.y, parent.fixed_position.y, world.FLOOR_Y
								])
							parent.fixed_position.y = world.FLOOR_Y
							parent.fixed_velocity.y = 0
						elif parent_needs_snap and parent.is_jumping:
							# 如果正在跳跃，只修正位置，不清零速度
							print("[PUSH_SNAP_SKIP] %s 正在跳躍，跳過速度清零 | velocity.y=%d | is_jumping=%s" % [
								parent.name, parent.fixed_velocity.y, parent.is_jumping
							])
							parent.fixed_position.y = world.FLOOR_Y
						
						if other_needs_snap and not other.is_jumping:
							if other.fixed_velocity.y != 0:
								print("[PUSH_SNAP] %s 地面吸附清零速度: velocity.y=%d → 0 | pos.y=%d | FLOOR_Y=%d" % [
									other.name, other.fixed_velocity.y, other.fixed_position.y, world.FLOOR_Y
								])
							other.fixed_position.y = world.FLOOR_Y
							other.fixed_velocity.y = 0
						elif other_needs_snap and other.is_jumping:
							# 如果正在跳跃，只修正位置，不清零速度
							print("[PUSH_SNAP_SKIP] %s 正在跳躍，跳過速度清零 | velocity.y=%d | is_jumping=%s" % [
								other.name, other.fixed_velocity.y, other.is_jumping
							])
							other.fixed_position.y = world.FLOOR_Y
				
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
