class_name DashHandler extends Node

@export var debug_dash: bool = false

# Handles dash and backdash logic
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_dash(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	var seat = movement_node.seat if "seat" in movement_node else "?"
	if debug_dash and Engine.get_physics_frames() % 30 == 0 and input_dir != 0:  # 每 30 幀輸出一次（0.25秒）
		Debug.log("[DASH DEBUG] %s | input_dir=%d | neutral_timer=%.1f | pending_dir=%d | last_input=%d | conditions: on_floor=%s, attacking=%s, dashing=%s" % [
			seat, input_dir, movement_node.neutral_timer, movement_node.pending_dash_dir,
			movement_node.last_input_dir, movement_node.is_on_floor(), movement_node.is_attacking, movement_node.is_dashing
		])
	
	var is_landing_locked = "is_landing" in movement_node and movement_node.is_landing and "landing_lock_frames" in movement_node and movement_node.landing_lock_frames > 0
	if movement_node.is_on_floor() and not is_landing_locked and not movement_node.is_attacking and not movement_node.is_dashing and not movement_node.is_backdashing and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_layground) and not movement_node.is_crouching:
		
		if movement_node.neutral_timer > 0 and input_dir != 0 and movement_node.pending_dash_dir == input_dir:
			# 🟢 double-tap 被檢出！
			if debug_dash:
				Debug.log("[DASH DETECTED] %s | neutral_timer=%.1f | input_dir=%d | pending_dir=%d | facing=%.1f" % [
					seat, movement_node.neutral_timer, input_dir, movement_node.pending_dash_dir,
					movement_node.facing_direction
				])
			if input_dir * movement_node.facing_direction > 0:
				movement_node.is_dashing = true
				# 🔴 【關鍵修復】轉換秒數為幀計數（在 120 FPS 物理上下文中遞減）
				movement_node.dash_timer = Movement.seconds_to_frames_nearest(movement_node.dash_time)
				movement_node.dash_total_time = movement_node.dash_timer  # 保存初始幀數用於進度計算
				movement_node.dash_initial_speed = movement_node.dash_speed * scale_factor * input_dir
				movement_node.fixed_velocity.x = int(movement_node.dash_initial_speed)
				if debug_dash:
					Debug.log("[DASH STARTED] %s | timer_frames=%d | vel=%d | speed_value=%.0f" % [
						seat, movement_node.dash_timer, movement_node.fixed_velocity.x, movement_node.dash_initial_speed
					])
				if movement_node.groundsmoke:
					movement_node.groundsmoke.scale.x = movement_node.facing_direction
					movement_node.groundsmoke.restart()
			elif not (movement_node.is_blocking and movement_node.is_opponent_proximity and movement_node.block_type == "proximity"):
				movement_node.is_backdashing = true
				# 🔴 【關鍵修復】轉換秒數為幀計數（在 120 FPS 物理上下文中遞減）
				movement_node.dash_timer = Movement.seconds_to_frames_nearest(movement_node.backdash_time)
				movement_node.dash_total_time = movement_node.dash_timer  # 保存初始幀數用於進度計算
				movement_node.dash_initial_speed = movement_node.backdash_speed * scale_factor * input_dir
				movement_node.fixed_velocity.x = int(movement_node.dash_initial_speed)
				if debug_dash:
					Debug.log("[BACKDASH STARTED] %s | timer_frames=%d | vel=%d | speed_value=%.0f" % [
						seat, movement_node.dash_timer, movement_node.fixed_velocity.x, movement_node.dash_initial_speed
					])
				if movement_node.groundsmoke:
					movement_node.groundsmoke.scale.x = movement_node.facing_direction
					movement_node.groundsmoke.restart()
			movement_node.neutral_timer = 0
			movement_node.pending_dash_dir = 0
			movement_node.last_input_dir = 0
			movement_node.landing_facing_lock = true
		elif input_dir != movement_node.last_input_dir:
			if movement_node.last_input_dir != 0 and input_dir == 0:
				# 鍵盤被釋放，開始 double-tap 窗口
				movement_node.neutral_timer = Movement.seconds_to_frames_nearest(movement_node.double_tap_window_seconds)
				movement_node.pending_dash_dir = movement_node.last_input_dir
				if debug_dash:
					Debug.log("[DASH WINDOW START] %s | neutral_timer_frames=%d (%.2fs) | pending_dir=%d" % [
						seat, movement_node.neutral_timer, movement_node.neutral_timer / 120.0, movement_node.pending_dash_dir
					])
			movement_node.last_input_dir = input_dir
