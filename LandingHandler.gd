class_name LandingHandler extends Node

# Handles landing mechanics
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_landing(input_data: Dictionary, floor_y: int, delta: float) -> void:
	if not movement_node.just_jumped and movement_node.fixed_position.y >= floor_y and movement_node.jump_delay_timer <= 0 and movement_node.fixed_velocity.y >= 0 and movement_node.is_jumping:
		movement_node.fixed_position.y = floor_y
		movement_node.fixed_velocity.y = 0
		movement_node.is_jumping = false
		movement_node.just_jumped = false
		movement_node.fixed_velocity.x = 0
		movement_node.neutral_timer = 0.0
		movement_node.pending_dash_dir = 0
		movement_node.last_input_dir = 0
		movement_node.landing_facing_lock = false
		
		var move_set = movement_node.get_node_or_null("MoveSet")
		if move_set and move_set.is_spmove:
			# 🟢 【DP自帶著地修正】DP/HDK/POWERKK自帶著地動畫，跳過landing邏輯
			# 這些招式會獨立播放，不受著地鎖定影響
			var active_move_name = move_set.get_active_move_name() if move_set.has_method("get_active_move_name") else ""
			if active_move_name in ["dp", "hdk", "powerkk"]:
				# 完全跳過著地檢查，讓招式動畫自行播放
				if "is_landing" in movement_node:
					movement_node.is_landing = false
					movement_node.landing_lock_timer = 0.0
				return
			else:
				# 其他特殊招式在著地時立即停止
				if "is_landing" in movement_node:
					movement_node.is_landing = false
					movement_node.landing_lock_timer = 0.0
		else:
			if "is_landing" in movement_node and "landing_lock_timer" in movement_node:
				if not (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed):
					movement_node.is_landing = true
					movement_node.landing_lock_timer = movement_node.landing_duration
		
		if movement_node.groundsmoke:
			movement_node.groundsmoke.scale.x = movement_node.facing_direction
			movement_node.groundsmoke.restart()
		
		movement_node._update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	var push_manager = movement_node.get_tree().get_first_node_in_group("push_manager")
	if push_manager:
		push_manager._physics_process(delta)
