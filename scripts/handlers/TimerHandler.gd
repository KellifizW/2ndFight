class_name TimerHandler extends Node

# Handles all timer management
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

## 著地完整動畫的物理幀數（由 landing_duration 秒換算，唯一轉換點）
func _full_landing_frames() -> int:
	var landing_duration: float = movement_node.landing_duration \
			if "landing_duration" in movement_node else 0.2
	return Movement.seconds_to_lock_frames(landing_duration)

# 【Stage 1】handle_timers 現在完全是幀制，不再需要 delta。
# 保留參數是為了不動 Movement._physics_process 的呼叫端簽章。
func handle_timers(_delta: float) -> void:
	var _seat = movement_node.seat if "seat" in movement_node else "?"
	
	if movement_node.neutral_timer > 0:
		# neutral_timer is an integer physics-frame counter (120 Hz).
		# Do not subtract delta here: the timer was created from frame counts,
		# and mixing seconds back in makes dash windows last the wrong amount
		# of gameplay frames after the frame-system cleanup.
		movement_node.neutral_timer = max(0, int(movement_node.neutral_timer) - 1)
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
			movement_node.neutral_timer = 0
			movement_node.pending_dash_dir = 0
			movement_node.last_input_dir = 0
			movement_node.landing_facing_lock = false
			movement_node.dash_initial_speed = 0.0
			movement_node.dash_total_time = 0.0
	
	if movement_node.jump_delay_timer > 0:
		# jump_delay_timer is also frame-based. A 12-frame jump
		# pre-jump must remain 12 physics ticks regardless of time_scale.
		movement_node.jump_delay_timer = max(0, int(movement_node.jump_delay_timer) - 1)
		if movement_node.jump_delay_timer == 0:
			movement_node.fixed_velocity.y = int(movement_node.jump_vertical_speed * (movement_node.world.SIMULATION_SCALE if movement_node.world else 1000))
			movement_node.just_jumped = true
			movement_node.fixed_position.y = (movement_node.world.FLOOR_Y if movement_node.world else 200000) - 1
	
	# air_hit_backjump_timer is decremented by KnockflyHandler, which also
	# owns that state's gravity/friction and cleanup. Do not decrement it
	# here or the state expires twice as fast.
	
	# 【著地動畫計時器】Frame-based landing animation duration
	# 【新規則】2幀強制landing，之後檢查輸入中斷
	if "landing_lock_frames" in movement_node and movement_node.landing_lock_frames > 0:
		# 【計數幀數】每次handle_timers被調用時計數（相當於每frame）
		movement_node._landing_forced_frames += 1
		
		# 【檢查】必須等到至少2幀已過才能執行checkpoint（使用frame count，不使用time threshold）
		# 【重點】在遞減timer之前執行checkpoint，否則會被跳過
		if movement_node._landing_forced_frames >= 2 and not movement_node._landing_checkpoint_executed:
			# 強制2幀已結束，檢查是否有輸入
			# 【關鍵】著地2幀強制鎖定期間，檢查任何輸入（包括跳躍、攻擊、特殊、衝刺、摔投）
			var input_data = movement_node.get_input() if movement_node.has_method("get_input") else {}
			var has_input = input_data.get("input_dir", 0) != 0 \
					or input_data.get("crouch_pressed", false) \
					or input_data.get("jump_pressed", false) \
					or input_data.get("st_lp_pressed", false) or input_data.get("st_mp_pressed", false) or input_data.get("st_hp_pressed", false) \
					or input_data.get("st_lk_pressed", false) or input_data.get("st_mk_pressed", false) or input_data.get("st_hk_pressed", false) \
					or input_data.get("spm1_pressed", false) or input_data.get("spm2_pressed", false) or input_data.get("dp_pressed", false) \
					or input_data.get("super_pressed", false) \
					or input_data.get("dash_pressed", false) or input_data.get("backdash_pressed", false) \
					or input_data.get("throw_pressed", false) \
					or input_data.get("100p_pressed", false)
			# 【改進】包含所有可能的動作輸入，確保衝刺/摔投/超殺同樣能中斷landing鎖
			
			# 【重點】標記checkpoint已執行，防止重複執行
			movement_node._landing_checkpoint_executed = true
			
			var seat = movement_node.get_meta("player_seat") if movement_node.has_meta("player_seat") else "unknown"
			var timer_desc = "%df (interrupted)" % Movement.LANDING_INTERRUPT_FRAMES if has_input \
					else "%df (full animation)" % _full_landing_frames()
			Debug.log("[LANDING_CHECKPOINT] %s: input_detected=%s, landing_frames will be: %s" % [
				seat, has_input, timer_desc
			])
			
			# 【面向規則】著地 checkpoint **不**更新面向。
			#
			# 這裡原本會暫時把 is_landing / landing_facing_lock 清成 false，
			# 再呼叫 update_facing_direction() ——等於在著地第 2 幀就強制翻面，
			# 而完整著地動畫要 25 幀。cross-up 跳過對手後，玩家看到的就是
			# 「人幾乎還在落地的瞬間就轉身」。正確時機是下面的收尾段：
			# landing_lock_frames 歸零（著地動畫播完）時才更新面向。

			if has_input:
				# 【關鍵】留 1 幀而非立即歸零
				# 這樣下一幀才會將 is_landing=false，JumpHandler 才會在下一幀處理跳躍延遲
				movement_node.landing_lock_frames = Movement.LANDING_INTERRUPT_FRAMES
			else:
				movement_node.landing_lock_frames = _full_landing_frames()
		
		# 【關鍵修正】移除早期return，讓timer正常遞減
		# 【Stage 1】每個物理幀固定 -1，不再用 delta：
		# hitstop 期間 Engine.time_scale=0.02 會把 delta 縮小 50 倍，
		# 舊的秒制寫法會讓著地鎖定被拉長，幀制則完全不受影響。
		movement_node.landing_lock_frames = max(0, movement_node.landing_lock_frames - 1)
		
		# 檢查著地是否完成
		if movement_node.landing_lock_frames <= 0:
			Debug.log("[%s] ✓ Landing COMPLETE, is_landing=false" % [_seat])
			movement_node.is_landing = false
			movement_node.is_jumping = false  # 【關鍵】著地完成時清除 is_jumping，完全解除著地狀態
			movement_node.landing_facing_lock = false
			movement_node._landing_checkpoint_executed = false
			movement_node._landing_forced_frames = 0
			if movement_node.has_method("update_facing_direction"):
				movement_node.update_facing_direction()
