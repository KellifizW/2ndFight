class_name WalkHandler extends Node

# Handles walking movement logic
var movement_node: Node
var debug_walk_blocked: bool = false  # 調試開關

func _init(movement: Node) -> void:
	movement_node = movement

func handle_walk(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	# 【關鍵保護】剛被摔投或在 knockfly 狀態，完全跳過 WalkHandler
	var is_just_thrown = "just_thrown" in movement_node and movement_node.just_thrown
	var seat = movement_node.seat if "seat" in movement_node else "?"
	
	if is_just_thrown or movement_node.is_knockfly:
		print("[WALK_HANDLER] %s: Skipping walk (is_just_thrown=%s is_knockfly=%s vel_x=%d)" % [
			seat, is_just_thrown, movement_node.is_knockfly, movement_node.fixed_velocity.x
		])
		return
	
	# 🟢 【修復】在條件中也要檢查 knockback 和 corner push 狀態
	var is_in_knockback = "knockback_frames" in movement_node and movement_node.knockback_frames > 0
	var is_in_corner_push = "corner_push_frames" in movement_node and movement_node.corner_push_frames > 0
	var is_in_block_knockback = "block_knockback_frames" in movement_node and movement_node.block_knockback_frames > 0
	
	var can_walk = movement_node.is_on_floor() and not movement_node.is_attacking and not movement_node.is_dashing and not movement_node.is_backdashing and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.is_layground or is_in_knockback or is_in_corner_push or is_in_block_knockback) and not movement_node.is_crouching
	
	if not can_walk and input_dir != 0:
		var reasons = []
		if not movement_node.is_on_floor(): reasons.append("not_on_floor")
		if movement_node.is_attacking: reasons.append("is_attacking")
		if movement_node.is_dashing: reasons.append("is_dashing")
		if movement_node.is_backdashing: reasons.append("is_backdashing")
		if is_special_moving: reasons.append("is_special_moving")
		if movement_node.is_hit: reasons.append("is_hit")
		if movement_node.is_knockfly: reasons.append("is_knockfly")
		if movement_node.is_blocking: reasons.append("is_blocking")
		if movement_node.is_push_back: reasons.append("is_push_back")
		if movement_node.is_layground: reasons.append("is_layground")
		if movement_node.is_crouching: reasons.append("is_crouching")
		if "has_air_attacked" in movement_node and movement_node.has_air_attacked: reasons.append("has_air_attacked")
		if "is_air_attacking" in movement_node and movement_node.is_air_attacking: reasons.append("is_air_attacking")
		if "is_landing" in movement_node and movement_node.is_landing: reasons.append("is_landing")
		if debug_walk_blocked:
			print("[WALK BLOCKED] Seat: ", movement_node.seat if "seat" in movement_node else "?", " | Reasons: ", reasons)
	
	if can_walk:
		if input_dir != 0:
			if movement_node.is_proximity_blocking and input_dir * movement_node.facing_direction < 0:
				movement_node.fixed_velocity.x = 0
			else:
				var move_speed: float = movement_node.walk_speed if input_dir * movement_node.facing_direction > 0 else movement_node.back_speed
				movement_node.fixed_velocity.x = int(move_speed * scale_factor * input_dir)
		else:
			movement_node.fixed_velocity.x = 0
	else:
		# 檢查是否有攻擊移動激活，如果有則不清零速度
		# CRITICAL FIX: movement_node IS Player (class inheritance, not parent-child)
		# Player extends Fighter extends Movement - so movement_node already has AttackMovementHandler
		var attack_movement_handler = movement_node.get_node_or_null("AttackMovementHandler") if movement_node.has_method("get_node_or_null") else null
		var has_attack_movement = attack_movement_handler and attack_movement_handler.is_active()
		
		if not has_attack_movement and not is_in_knockback and not is_in_corner_push and not is_in_block_knockback and not (movement_node.is_jumping or movement_node.is_dashing or movement_node.is_backdashing or movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.jump_delay_timer > 0 or is_special_moving or movement_node.is_layground):
			movement_node.fixed_velocity.x = 0
