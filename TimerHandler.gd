class_name TimerHandler extends Node

# Handles all timer management
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_timers(delta: float) -> void:
	var _seat = movement_node.seat if "seat" in movement_node else "?"
	
	if movement_node.neutral_timer > 0:
		movement_node.neutral_timer = max(0, movement_node.neutral_timer - delta)
		if movement_node.neutral_timer == 0:
			movement_node.pending_dash_dir = 0
	
	if movement_node.dash_timer > 0:
		# dash_timer is frame-based; decrement per physics frame
		movement_node.dash_timer = max(0, movement_node.dash_timer - 1)
		
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
	if "landing_lock_timer" in movement_node and movement_node.landing_lock_timer > 0:
		# 【計數幀數】每次handle_timers被調用時計數（相當於每frame）
		movement_node._landing_forced_frames += 1
		
		# 【檢查】必須等到至少2幀已過才能執行checkpoint（使用frame count，不使用time threshold）
		# 【重點】在遞減timer之前執行checkpoint，否則會被跳過
		if movement_node._landing_forced_frames >= 2 and not movement_node._landing_checkpoint_executed:
			# 強制2幀已結束，檢查是否有輸入
			# 【關鍵】著地2幀強制鎖定期間，檢查任何輸入（包括跳躍和攻擊）
			var input_data = movement_node.get_input() if movement_node.has_method("get_input") else {}
			var has_input = input_data.get("input_dir", 0) != 0 or input_data.get("crouch_pressed", false) or input_data.get("jump_pressed", false) \
					or input_data.get("st_lp_pressed", false) or input_data.get("st_mp_pressed", false) or input_data.get("st_hp_pressed", false) \
					or input_data.get("st_lk_pressed", false) or input_data.get("st_mk_pressed", false) or input_data.get("st_hk_pressed", false) \
					or input_data.get("spm1_pressed", false) or input_data.get("spm2_pressed", false) or input_data.get("dp_pressed", false)
			# 【改進】現在包括 jump_pressed 和攻擊檢查，這樣連續跳躍或攻擊時著地動畫會被立即中斷
			
			# 【重點】標記checkpoint已執行，防止重複執行
			movement_node._landing_checkpoint_executed = true
			
			var seat = movement_node.get_meta("player_seat") if movement_node.has_meta("player_seat") else "unknown"
			var timer_desc = "0.001s (interrupted)" if has_input else "0.2s (full animation)"
			print("[LANDING_CHECKPOINT] %s: input_detected=%s, landing_timer will be: %s" % [
				seat, has_input, timer_desc
			])
			
			# 【面向更新】在2幀強制鎖定完成時立即更新面向
			# 【關鍵】臨時禁用 is_landing 標記和 landing_facing_lock，使得 FacingHandler 能夠執行
			var saved_is_landing = movement_node.is_landing
			var saved_landing_facing_lock = movement_node.landing_facing_lock
			movement_node.is_landing = false
			movement_node.landing_facing_lock = false
			if movement_node.has_method("update_facing_direction"):
				movement_node.update_facing_direction()
			movement_node.is_landing = saved_is_landing
			movement_node.landing_facing_lock = saved_landing_facing_lock
			
			if has_input:
				# 【關鍵】設置極小的timer值，但不立即設為0
				# 這樣下一幀才會將 is_landing=false，JumpHandler 才會在下一幀處理跳躍延遲
				movement_node.landing_lock_timer = 0.001
				# 【新增】標記著地被輸入中斷，下一幀設置 is_landing=false
				movement_node._landing_interrupted_by_input = true
			else:
				var landing_duration = movement_node.landing_duration if "landing_duration" in movement_node else 0.2
				movement_node.landing_lock_timer = landing_duration
		
		# 【關鍵修正】移除早期return，讓timer正常遞減
		# 正常計時器遞減（每幀都要執行）
		movement_node.landing_lock_timer = max(0, movement_node.landing_lock_timer - delta)
		
		# 檢查著地是否完成
		if movement_node.landing_lock_timer <= 0:
			print("[%s] ✓ Landing COMPLETE, is_landing=false" % [_seat])
			movement_node.is_landing = false
			movement_node.is_jumping = false  # 【關鍵】著地完成時清除 is_jumping，完全解除著地狀態
			movement_node._landing_timer_initialized = false
			movement_node._landing_checkpoint_executed = false
			movement_node._landing_forced_frames = 0
			# 【新增】清除中斷標記
			if "landing_interrupted_by_input" in movement_node:
				movement_node._landing_interrupted_by_input = false
