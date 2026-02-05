class_name TimerHandler extends Node

# Handles all timer management (FRAME-BASED)
# All timers decrement by 1 per frame (called once per _physics_process)
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_timers() -> void:
	# 【所有計時器現在為幀計數】每次多減1幀（相當於60FPS時減1/60秒）
	
	if movement_node.neutral_timer > 0:
		movement_node.neutral_timer -= 1
		if movement_node.neutral_timer == 0:
			movement_node.pending_dash_dir = 0
	
	if movement_node.dash_timer > 0:
		movement_node.dash_timer -= 1
		
		# Apply deceleration curve (quadratic decay)
		if movement_node.dash_timer > 0 and movement_node.dash_total_time > 0:
			var remaining_ratio: float = movement_node.dash_timer / float(movement_node.dash_total_time)
			var speed_multiplier: float = remaining_ratio * remaining_ratio  # Quadratic decay
			movement_node.fixed_velocity.x = int(movement_node.dash_initial_speed * speed_multiplier)
		
		if movement_node.dash_timer == 0:
			movement_node.is_dashing = false
			movement_node.is_backdashing = false
			movement_node.fixed_velocity.x = 0
			movement_node.neutral_timer = 0
			movement_node.pending_dash_dir = 0
			movement_node.last_input_dir = 0
			movement_node.landing_facing_lock = false
			movement_node.dash_initial_speed = 0.0
			movement_node.dash_total_time = 0
	
	if movement_node.jump_delay_timer > 0:
		movement_node.jump_delay_timer -= 1
		if movement_node.jump_delay_timer == 0:
			movement_node.fixed_velocity.y = int(movement_node.jump_vertical_speed * (movement_node.world.SIMULATION_SCALE if movement_node.world else 1000))
			movement_node.just_jumped = true
			movement_node.fixed_position.y = (movement_node.world.FLOOR_Y if movement_node.world else 200000) - 1
	
	if movement_node.air_hit_backjump_timer > 0:
		movement_node.air_hit_backjump_timer -= 1
		if movement_node.air_hit_backjump_timer == 0:
			movement_node.is_air_hit_backjump = false
			movement_node.fixed_velocity = Vector2i.ZERO
	
	# 【著地動畫計時器】Frame-based landing animation duration
	# 【新規則】2幀強制landing，之後檢查輸入中斷
	var _seat = movement_node.seat if "seat" in movement_node else "?"
	
	# 【著地動畫計時器】Frame-based landing animation duration
	# 【新規則】2幀強制landing，之後檢查輸入中斷
	if "landing_lock_timer" in movement_node and movement_node.landing_lock_timer > 0:
		# 【計數幀數】每次handle_timers被調用時計數（相當於每frame）
		movement_node._landing_forced_frames += 1
		
		# 【檢查】必須等到至少2幀已過才能執行checkpoint（使用frame count，不使用time threshold）
		# 【重點】在遞減timer之前執行checkpoint，否則會被跳過
		if movement_node._landing_forced_frames >= 2 and not movement_node._landing_checkpoint_executed:
			# 強制2幀已結束，檢查是否有輸入
			var input_data = movement_node.get_input() if movement_node.has_method("get_input") else {}
			var has_input = input_data.get("input_dir", 0) != 0 or input_data.get("crouch_pressed", false) or input_data.get("jump_pressed", false)
			
			# 【重點】標記checkpoint已執行，防止重複執行
			movement_node._landing_checkpoint_executed = true
			
			if has_input:
				movement_node.landing_lock_timer = 0
				return
			else:
				# 🔴 【關鍵修復】landing_duration 是秒數，轉換為 ×120 幀數（120 FPS 物理上下文）
				var landing_duration_frames = int(round(movement_node.landing_duration * 120.0)) if "landing_duration" in movement_node else 24
				movement_node.landing_lock_timer = landing_duration_frames
				return
		
		# 現在才遞減timer（在checkpoint之後）
		movement_node.landing_lock_timer -= 1
		
		# 正常計時器遞減
		if movement_node.landing_lock_timer == 0:
			movement_node.is_landing = false
			movement_node._landing_timer_initialized = false
			movement_node._landing_checkpoint_executed = false
			movement_node._landing_forced_frames = 0
