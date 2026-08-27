class_name JumpHandler extends Node

# Handles jump mechanics
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_jump(jump_pressed: bool, input_dir: int, scale_factor: float, floor_y: int, is_special_moving: bool) -> void:
	# 【重要】著地期間禁止新跳躍：is_landing 狀態未完成時，不允許開始新跳躍
	var is_landing = movement_node.is_landing if "is_landing" in movement_node else false
	if is_landing:
		return  # ← 著地中，忽略跳躍輸入
	
	# 【新增】被摔投時禁止跳躍（位置由 ThrowHandler 控制）
	var is_being_thrown = "is_being_thrown" in movement_node and movement_node.is_being_thrown
	if is_being_thrown:
		return
	
	if jump_pressed and movement_node.is_on_floor() and not movement_node.is_crouching and not movement_node.is_dashing and not movement_node.is_backdashing and not movement_node.is_attacking and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.is_layground) and movement_node.jump_delay_timer <= 0:
		
		movement_node.jump_dir = input_dir
		movement_node.is_jumping = true
		movement_node.landing_facing_lock = true
		# 【跳躍延遲】設置延遲計時器，使垂直速度延遲應用
		# jump_delay_duration 預設 0.067s = ~6 幀 @90FPS 或 ~8 幀 @120 FPS
		movement_node.jump_delay_timer = Movement.seconds_to_frames_nearest(movement_node.jump_delay_duration)
		Debug.log("[JUMP DEBUG] Jump started | jump_delay_duration: %.3fs -> jump_delay_timer: %d frames @120 FPS" % [movement_node.jump_delay_duration, movement_node.jump_delay_timer])
		movement_node.fixed_position.y = floor_y - 1
		movement_node.fixed_velocity.y = 0
		
		if movement_node.jump_dir != 0:
			var jump_speed: float = movement_node.jump_horizontal_speed if movement_node.jump_dir * movement_node.facing_direction > 0 else movement_node.jump_horizontal_speed * 0.75
			movement_node.fixed_velocity.x = int(jump_speed * scale_factor * movement_node.jump_dir)
		else:
			movement_node.fixed_velocity.x = 0
