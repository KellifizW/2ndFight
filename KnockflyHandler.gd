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
		# 【重要】air_hit_backjump_timer 現在由 TimerHandler 管理
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
		# 【重要】knockfly_timer 由 PushManager._physics_process() 管理（delta 遞減）
		# 不在此處遞減以避免重複遞減
		# 【重要】重力現在由 GravityHandler 統一管理，在 Movement._handle_gravity() 中應用
		# 此處不再重複應用重力，避免計算重複
		# 只負責狀態轉換
		apply_air_friction(movement_node.air_friction)

		# Only transition to layground if on floor
		if movement_node.is_on_floor():
			_enter_layground("knockfly_landed")
			return

		# If timer ends but still in air, only mark animation complete
		if movement_node.knockfly_timer <= 0 and not movement_node.is_on_floor():
			movement_node.is_knockfly_animation_finished = true
			movement_node.fixed_velocity.x = 0
			return

	if movement_node.is_layground:
		# 【重要】layground_timer 現在由 TimerHandler 管理（或下方自行管理）
		movement_node.layground_timer = max(0, movement_node.layground_timer - 1)
		movement_node.fixed_velocity = Vector2i.ZERO
		print("[LAYGROUND TICK] timer: %d → %d" % [movement_node.layground_timer + 1, movement_node.layground_timer])
		if movement_node.layground_timer <= 0:
			print("[LAYGROUND END] timer reached 0, calling reset")
			reset_layground_with_health_check()

func apply_air_friction(friction_coeff: float) -> void:
	# 【改為 frame-based】每幀應用摩擦力程度
	# 摩擦力計算：friction_amount = friction_coeff（單位：pixels/frame）
	var friction_amount = int(friction_coeff)  # 簡化：直接以 friction_coeff 作為每幀減速量
	if movement_node.fixed_velocity.x > 0:
		movement_node.fixed_velocity.x = max(0, movement_node.fixed_velocity.x - friction_amount)
	elif movement_node.fixed_velocity.x < 0:
		movement_node.fixed_velocity.x = min(0, movement_node.fixed_velocity.x + friction_amount)

func _should_force_ko_layground() -> bool:
	var player_healthbar = movement_node.healthbar
	if not player_healthbar:
		return false
	return player_healthbar.current_health <= 0 and movement_node.is_on_floor() and not movement_node.is_layground
	
func _enter_layground(reason: String = "unknown") -> void:
	print("[LAYGROUND ENTER] %s | reason=%s" % [movement_node.name, reason])
	movement_node.fixed_velocity = Vector2i.ZERO
	movement_node.knockfly_velocity_x = 0.0  # 🟢 重置 knockfly_velocity_x，確保下次跳躍不會繼承
	movement_node.knockfly_timer = 0  # 🟢 完全清除 timer
	movement_node.is_layground = true
	# 轉換 layground_duration（秒）為幀數（@120 FPS 物理幀）
	# layground_frames 在 _physics_process 每幀遞減，所以應×120 而非×60
	var layground_frames = int(round(movement_node.layground_duration * 120.0)) if "layground_duration" in movement_node else 24
	movement_node.layground_timer = layground_frames
	print("[LAYGROUND INIT] duration: %.3fs → timer: %d frames" % [movement_node.layground_duration, layground_frames])
	movement_node.is_knockfly_animation_finished = false
	movement_node._update_animation_state(0, false)

func reset_layground_with_health_check() -> void:
	var player_healthbar = movement_node.healthbar
	
	print("[RESET_LAYGROUND] movement_node: %s, has_is_wakeup: %s" % [movement_node.name, "is_wakeup" in movement_node])
	
	if player_healthbar and player_healthbar.current_health <= 0:
		# Only print debug message once when health reaches zero
		if not health_check_done:
			print("Debug: %s 血量已歸零，保持躺地狀態，不觸發 wakeup。" % movement_node.name)
			health_check_done = true
		movement_node.is_layground = true
		movement_node.is_knockfly = false
		movement_node.knockfly_velocity_x = 0.0  # 🟢 確保完全清除
		movement_node.knockfly_timer = 0  # 🟢 確保 timer 清除
		movement_node.is_knockfly_animation_finished = false
		return
	
	# Reset health_check_done if waking up normally
	health_check_done = false
	movement_node.is_layground = false
	movement_node.is_knockfly = false
	movement_node.knockfly_velocity_x = 0.0  # 🟢 確保完全清除
	movement_node.knockfly_timer = 0  # 🟢 確保 timer 清除
	movement_node.is_knockfly_animation_finished = false
	
	if "is_wakeup" in movement_node and "is_wakeup_locked" in movement_node:
		movement_node.is_wakeup = true
		movement_node.is_wakeup_locked = true
		
		# 【關鍵】Initialize wakeup_timer based on animation duration (120 FPS physics frames)
		if "animation_player" in movement_node and movement_node.animation_player and movement_node.animation_player.has_animation("wakeup"):
			var wakeup_duration = movement_node.animation_player.get_animation("wakeup").length
			movement_node.wakeup_timer = int(round(wakeup_duration * 120.0))
			print("[WAKEUP TIMER] wakeup_duration: %.3fs -> wakeup_timer: %d frames @120 FPS physics" % [wakeup_duration, movement_node.wakeup_timer])
		else:
			# Fallback: 1.0 second = 120 frames @120 FPS physics
			movement_node.wakeup_timer = 120
			print("[WAKEUP TIMER] Using fallback: wakeup_timer = 120 frames")
		
		print("[WAKEUP TRIGGERED] is_wakeup: %s, is_wakeup_locked: %s, wakeup_timer: %d" % [movement_node.is_wakeup, movement_node.is_wakeup_locked, movement_node.wakeup_timer])
		movement_node.animation_state.travel("wakeup")
		print("[WAKEUP ANIM] animation_state.travel('wakeup') called")
	else:
		print("[WAKEUP FAILED] movement_node: %s, has_is_wakeup: %s, has_is_wakeup_locked: %s" % [
			movement_node.name,
			"is_wakeup" in movement_node,
			"is_wakeup_locked" in movement_node
		])
	
	movement_node._update_animation_state(0, false)
