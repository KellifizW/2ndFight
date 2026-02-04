class_name TimerHandler extends Node

# Handles all timer management
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_timers(delta: float) -> void:
	
	if movement_node.neutral_timer > 0:
		movement_node.neutral_timer = max(0, movement_node.neutral_timer - delta)
		if movement_node.neutral_timer == 0:
			movement_node.pending_dash_dir = 0
	
	if movement_node.dash_timer > 0:
		movement_node.dash_timer = max(0, movement_node.dash_timer - delta)
		
		# Apply deceleration curve (quadratic decay)
		if movement_node.dash_timer > 0 and movement_node.dash_total_time > 0:
			var remaining_ratio: float = movement_node.dash_timer / movement_node.dash_total_time
			var speed_multiplier: float = remaining_ratio * remaining_ratio  # Quadratic decay
			movement_node.fixed_velocity.x = int(movement_node.dash_initial_speed * speed_multiplier)
		
		if movement_node.dash_timer == 0:
			movement_node.is_dashing = false
			movement_node.is_backdashing = false
			movement_node.fixed_velocity.x = 0
			movement_node.neutral_timer = 0.0
			movement_node.pending_dash_dir = 0
			movement_node.last_input_dir = 0
			movement_node.landing_facing_lock = false
			movement_node.dash_initial_speed = 0.0
			movement_node.dash_total_time = 0.0
	
	if movement_node.jump_delay_timer > 0:
		movement_node.jump_delay_timer = max(0, movement_node.jump_delay_timer - delta)
		if movement_node.jump_delay_timer == 0:
			movement_node.fixed_velocity.y = int(movement_node.jump_vertical_speed * (movement_node.world.SIMULATION_SCALE if movement_node.world else 1000))
			movement_node.just_jumped = true
			movement_node.fixed_position.y = (movement_node.world.FLOOR_Y if movement_node.world else 200000) - 1
	
	if movement_node.air_hit_backjump_timer > 0:
		movement_node.air_hit_backjump_timer = max(0, movement_node.air_hit_backjump_timer - delta)
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
		print("[LANDING_FRAME] %s | frame=%d timer=%.6f (before decrement)" % [_seat, movement_node._landing_forced_frames, movement_node.landing_lock_timer])
		
		# 【檢查】必須等到至少2幀已過才能執行checkpoint（使用frame count，不使用time threshold）
		# 【重點】在遞減timer之前執行checkpoint，否則會被跳過
		if movement_node._landing_forced_frames >= 2 and not movement_node._landing_checkpoint_executed:
			print("[LANDING_CHECKPOINT_EXECUTE] %s | frame=%d" % [_seat, movement_node._landing_forced_frames])
			
			# 強制2幀已結束，檢查是否有輸入
			var input_data = movement_node.get_input() if movement_node.has_method("get_input") else {}
			var has_input = input_data.get("input_dir", 0) != 0 or input_data.get("crouch_pressed", false) or input_data.get("jump_pressed", false)
			print("[LANDING_CHECKPOINT_INPUT] %s | has_input=%s" % [_seat, has_input])
			
			# 【重點】標記checkpoint已執行，防止重複執行
			movement_node._landing_checkpoint_executed = true
			
			if has_input:
				print("[LANDING_INTERRUPT] %s | setting timer=0.001" % _seat)
				movement_node.landing_lock_timer = 0.001
				return
			else:
				var landing_duration = movement_node.landing_duration if "landing_duration" in movement_node else 0.2
				print("[LANDING_CONTINUE] %s | extending timer to %.3f" % [_seat, landing_duration])
				movement_node.landing_lock_timer = landing_duration
				return
		
		# 現在才遞減timer（在checkpoint之後）
		movement_node.landing_lock_timer = max(0, movement_node.landing_lock_timer - delta)
		
		# 正常計時器遞減
		if movement_node.landing_lock_timer == 0:
			movement_node.is_landing = false
			movement_node._landing_timer_initialized = false
			movement_node._landing_checkpoint_executed = false
			movement_node._landing_forced_frames = 0
