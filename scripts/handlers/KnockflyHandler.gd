class_name KnockflyHandler extends Node

# Handles knockfly and layground mechanics (FRAME-BASED)
# All timers now decrement by 1 per frame
var movement_node: Node
var health_check_done: bool = false  # Track if health check already failed

func _init(movement: Node) -> void:
	movement_node = movement

func handle_knockfly_layground(_delta: float, _floor_y: int) -> void:
	# 【注意】delta 參數保留以保持向後相容，但不在此函數中使用
	# 所有計時器現在在 TimerHandler 或此處以幀計數方式遞減
	# KO safety net: if HP is 0 and we're on the floor, ensure layground is entered
	if _should_force_ko_layground():
		_enter_layground("ko_force")
		return
	
	if movement_node.is_air_hit_backjump:
		# 【重要】air_hit_backjump_timer 由 KnockflyHandler 管理，避免 TimerHandler 重複遞減
		movement_node.air_hit_backjump_timer = max(0, movement_node.air_hit_backjump_timer - 1)
		# 【統一重力系統】直接應用重力（這個狀態獨立於 GravitySystem）
		var gravity: int = movement_node.world.GRAVITY if movement_node.world else 6000000
		# 重力應用改為 1/60 秒固定（相當於 120 FPS 的 delta = 1/120）
		var physics_timestep = 1.0 / 60.0  # Fixed 60 FPS reference
		movement_node.fixed_velocity.y += int(float(gravity) * physics_timestep)
		apply_air_friction(movement_node.default_air_friction)
		if movement_node.air_hit_backjump_timer <= 0 or movement_node.is_on_floor():
			movement_node.is_air_hit_backjump = false
			# 空中被打回到地面後不播放 hit 動畫，清除受擊狀態
			movement_node.is_hit = false
			movement_node.hitstun_frames = 0
			# 只在落地時清除跳躍狀態，如果還在空中就設置 jump_dir 為後跳方向
			if movement_node.is_on_floor():
				movement_node.is_jumping = false
				movement_node.just_jumped = false
			else:
				# 設置 jump_dir 為後跳方向（與 facing 相反），確保播放 Jump_B
				movement_node.jump_dir = -movement_node.facing_direction
		return

	if movement_node.is_knockfly:
		# 【重要】knockfly_frames 由 PushManager._physics_process() 管理（每物理幀 -1，hitstop 凍結）
		# 不在此處遞減以避免重複遞減
		# 【重要】重力現在由 GravityHandler 統一管理，在 Movement._handle_gravity() 中應用
		# 此處不再重複應用重力，避免計算重複
		# 只負責狀態轉換
		
		# 【關鍵修復】跳過被摔投角色第一幀的摩擦力，防止初速被清除
		if "just_thrown" in movement_node and movement_node.just_thrown:
			Debug.log("[KNOCKFLY_FRICTION_SKIP] %s: Skipping friction on just_thrown frame" % (
				movement_node.seat if "seat" in movement_node else "?"
			))
			movement_node.just_thrown = false  # 清除標記，下一幀恢復正常摩擦力
		else:
			apply_air_friction(movement_node.air_friction)

		# 【調試】打印每幀的 knockfly 狀態
		var on_floor = movement_node.is_on_floor()
		var vel_y = movement_node.fixed_velocity.y
		var vel_x = movement_node.fixed_velocity.x
		var timer = movement_node.knockfly_frames
		var seat = movement_node.seat if "seat" in movement_node else "?"
		Debug.log("[KNOCKFLY_CHECK] %s | frames=%d | vel_x=%d vel_y=%d | on_floor=%s | frames<=0=%s" % [
			seat, timer, vel_x, vel_y, on_floor, timer <= 0
		])

		# 【修正】只有向下移動時才進入 layground，向上移動時保持 knockfly 狀態
		# 这防止刚被摔投时立即进入 layground 的问题
		if on_floor and vel_y >= 0:
			Debug.log("[KNOCKFLY→LAYGROUND] %s triggered: on_floor=%s vel_y=%d >= 0" % [seat, on_floor, vel_y])
			_enter_layground("knockfly_landed")
			return

		# If timer ends but still in air, only mark animation complete
		if timer <= 0 and not on_floor:
			Debug.log("[KNOCKFLY_ANIM_FINISH] %s | timer expired, still in air" % seat)
			movement_node.is_knockfly_animation_finished = true
			movement_node.fixed_velocity.x = 0
			return

	if movement_node.is_layground:
		# 【重要】layground 期間維持位置和速度為零
		movement_node.layground_timer = max(0, movement_node.layground_timer - 1)
		movement_node.fixed_velocity = Vector2i.ZERO  # 🟢 每幀強制清除速度
		
		# 🟢 【防護】防止位置穿過地面
		var floor_y: int = movement_node.world.FLOOR_Y if movement_node.world else 570000
		if movement_node.fixed_position.y > floor_y:
			movement_node.fixed_position.y = floor_y
			Debug.log("[LAYGROUND SNAP] Position snapped to floor: y=%d" % floor_y)
		
		if movement_node.layground_timer <= 0:
			reset_layground_with_health_check()

func apply_air_friction(friction_coeff: float) -> void:
	# 【改為 frame-based】每幀應用摩擦力程度
	# 摩擦力計算：friction_amount = friction_coeff（單位：pixels/frame）
	var friction_amount = int(friction_coeff)  # 簡化：直接以 friction_coeff 作為每幀減速量
	var seat = movement_node.seat if "seat" in movement_node else "?"
	var pre_friction_vel_x = movement_node.fixed_velocity.x
	
	if movement_node.fixed_velocity.x > 0:
		movement_node.fixed_velocity.x = max(0, movement_node.fixed_velocity.x - friction_amount)
	elif movement_node.fixed_velocity.x < 0:
		movement_node.fixed_velocity.x = min(0, movement_node.fixed_velocity.x + friction_amount)
	
	# 詳細日誌：記錄摩擦力應用
	if pre_friction_vel_x != movement_node.fixed_velocity.x:
		Debug.log("[AIR_FRICTION] %s: vel_x changed from %d to %d (friction_amount=%d)" % [
			seat, pre_friction_vel_x, movement_node.fixed_velocity.x, friction_amount
		])

func _should_force_ko_layground() -> bool:
	var player_healthbar = movement_node.healthbar
	if not player_healthbar:
		return false
	return player_healthbar.current_health <= 0 and movement_node.is_on_floor() and not movement_node.is_layground
	
func _enter_layground(reason: String = "unknown") -> void:
	Debug.log("[LAYGROUND ENTER] %s | reason=%s" % [movement_node.name, reason])
	movement_node.fixed_velocity = Vector2i.ZERO
	movement_node.knockfly_velocity_x = 0.0  # 🟢 重置 knockfly_velocity_x，確保下次跳躍不會繼承
	movement_node.knockfly_frames = 0  # 🟢 完全清除 timer
	movement_node.knockfly_duration_frames = 0
	movement_node.is_knockfly = false  # 🟢 【關鍵修復】清除 is_knockfly，停止重力累積
	movement_node.is_knockfly_animation_finished = false  # 🟢 先清除 flag，再進入 layground
	
	# 🟢 【關鍵修復】重置位置到地面，防止位置穿過地面
	var floor_y: int = movement_node.world.FLOOR_Y if movement_node.world else 570000
	movement_node.fixed_position.y = floor_y
	Debug.log("[LAYGROUND POSITION_RESET] fixed_position.y set to floor_y: %d" % floor_y)
	
	movement_node.is_layground = true
	# 轉換 layground_duration（秒）為物理幀（唯一秒→幀邊界 Movement.seconds_to_frames_nearest）
	var layground_frames = Movement.seconds_to_frames_nearest(movement_node.layground_duration) if "layground_duration" in movement_node else 24
	movement_node.layground_timer = layground_frames
	Debug.log("[LAYGROUND INIT] duration: %.3fs → timer: %d frames" % [movement_node.layground_duration, layground_frames])
	movement_node._update_animation_state(0, false)

func reset_layground_with_health_check() -> void:
	var player_healthbar = movement_node.healthbar
	
	if player_healthbar and player_healthbar.current_health <= 0:
		# Only print debug message once when health reaches zero
		if not health_check_done:
			Debug.log("Debug: %s 血量已歸零，保持躺地狀態，不觸發 wakeup。" % movement_node.name)
			health_check_done = true
		movement_node.is_layground = true
		movement_node.is_knockfly = false
		movement_node.knockfly_velocity_x = 0.0  # 🟢 確保完全清除
		movement_node.knockfly_frames = 0  # 🟢 確保 timer 清除
		movement_node.knockfly_duration_frames = 0
		movement_node.is_knockfly_animation_finished = false
		return
	
	# Reset health_check_done if waking up normally
	health_check_done = false
	movement_node.is_layground = false
	movement_node.is_knockfly = false
	movement_node.knockfly_velocity_x = 0.0  # 🟢 確保完全清除
	movement_node.knockfly_frames = 0  # 🟢 確保 timer 清除
	movement_node.knockfly_duration_frames = 0
	movement_node.is_knockfly_animation_finished = false
	
	if "is_wakeup" in movement_node:
		movement_node.is_wakeup = true
		
		# 【關鍵】Initialize wakeup_timer based on animation duration (120 FPS physics frames)
		if "animation_player" in movement_node and movement_node.animation_player and movement_node.animation_player.has_animation("wakeup"):
			var wakeup_duration = movement_node.animation_player.get_animation("wakeup").length
			movement_node.wakeup_timer = Movement.seconds_to_frames_nearest(wakeup_duration)
			Debug.log("[WAKEUP TIMER] wakeup_duration: %.3fs -> wakeup_timer: %d frames @120 FPS physics" % [wakeup_duration, movement_node.wakeup_timer])
		else:
			# Fallback: 1.0 second = 120 frames @120 FPS physics
			movement_node.wakeup_timer = 120
			Debug.log("[WAKEUP TIMER] Using fallback: wakeup_timer = 120 frames")
		
		Debug.log("[WAKEUP TRIGGERED] is_wakeup: %s, wakeup_timer: %d" % [movement_node.is_wakeup, movement_node.wakeup_timer])
		movement_node.animation_state.travel("wakeup")
		Debug.log("[WAKEUP ANIM] animation_state.travel('wakeup') called")
	else:
		Debug.log("[WAKEUP FAILED] movement_node: %s, has_is_wakeup: %s" % [
			movement_node.name,
			"is_wakeup" in movement_node
		])
	
	movement_node._update_animation_state(0, false)
