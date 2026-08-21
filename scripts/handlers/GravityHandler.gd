class_name GravityHandler extends Node

## 【改進】統一重力處理
## 合併原 GravityHandler 邏輯，並統一應用所有重力

var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_gravity(delta: float, move_set) -> void:
	# 【統一重力系統】應用正確的重力計算
	# 【新增】被摔投時跳過重力（由 ThrowHandler 控制）
	if "is_being_thrown" in movement_node and movement_node.is_being_thrown:
		return
	
	apply_gravity_unified(delta, move_set)
	
	# 🟢 【修正】地面時清除垂直速度 - 但DP等特殊招式期間不清零
	if not movement_node.is_knockfly and movement_node.jump_delay_timer <= 0 and movement_node.is_on_floor():
		if not movement_node.just_jumped:
			# 檢查是否在特殊招式的跳躍階段
			var in_special_jump = false
			if move_set and move_set.is_spmove and move_set.current_move_state.active_move:
				var move_name = move_set.current_move_state.active_move.name
				if (move_name.begins_with("dp") or move_name in ["hdk", "powerkk", "super"]) and movement_node.is_jumping:
					in_special_jump = true
					Debug.log("[GRAVITY_SKIP] %s 在%s期間跳過速度清零 | velocity.y=%d" % [movement_node.name, move_name, movement_node.fixed_velocity.y])
			
			if not in_special_jump:
				movement_node.fixed_velocity.y = 0
				movement_node.fixed_position.y = movement_node.world.FLOOR_Y if movement_node.world else 200000

## 🟢 【統一重力應用函數】
## 根據當前狀態，決定使用的正確重力
func apply_gravity_unified(delta: float, move_set: Node = null) -> void:
	if not movement_node.world:
		return
	
	# 🟢 【防護】Layground 期間不應用重力
	if "is_layground" in movement_node and movement_node.is_layground:
		return
	
	# ── Step 1: 檢查是否需要應用重力 ──
	var should_apply_gravity = false
	var gravity_to_apply: int = 0
	var gravity_source: String = "none"
	
	# 空中受擊回跳 (is_air_hit_backjump) - 由 KnockflyHandler 獨立處理
	if movement_node.is_air_hit_backjump:
		return  # 這個狀態有自己的重力邏輯
	
	# 被擊飛狀態 (is_knockfly) - 使用 knockfly_gravity
	if movement_node.is_knockfly:
		should_apply_gravity = true
		gravity_to_apply = int(movement_node.knockfly_gravity)
		gravity_source = "knockfly"
	
	# 跳躍/空中狀態 - 檢查是否使用特殊招式重力
	elif movement_node.jump_delay_timer <= 0 and not movement_node.is_on_floor():
		should_apply_gravity = true
		
		# 優先使用特殊招式重力（如 DP 期間）
		if move_set and move_set.is_spmove and move_set.current_move_state.active_move and move_set.current_move_state.active_move.gravity > 0:
			gravity_to_apply = int(move_set.current_move_state.active_move.gravity)
			gravity_source = "spmove"
		else:
			# 使用世界預設重力
			gravity_to_apply = int(movement_node.world.GRAVITY)
			gravity_source = "world"
	
	# ── Step 2: 應用重力 ──
	if should_apply_gravity and gravity_to_apply != 0:
		var old_velocity_y = movement_node.fixed_velocity.y
		
		# 【固定點數學】重力應用
		movement_node.fixed_velocity.y += int(float(gravity_to_apply) * delta)
		
		# 🔴 調試日誌（默認禁用，需要調試時改為 true）
		if false:
			Debug.log("[GRAVITY_UNIFIED] %s | source=%s gravity=%d delta=%.4f old_vy=%d new_vy=%d" % [
				movement_node.name,
				gravity_source,
				gravity_to_apply,
				delta,
				old_velocity_y,
				movement_node.fixed_velocity.y
			])
