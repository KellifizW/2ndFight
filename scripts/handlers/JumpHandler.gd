class_name JumpHandler extends Node

# Handles jump mechanics
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_jump(jump_pressed: bool, input_dir: int, scale_factor: float, floor_y: int, is_special_moving: bool) -> void:
	# Stage 2 切片 3：跳躍守衛收攏到 FighterState.can_jump（值等價，見 test_31）。
	# 收攏後 JumpHandler 開頭的兩個 if（is_landing / is_being_thrown）併入同一份表達式，
	# 任何「這一刻能不能跳」的判定都會得到一致答案 —— 不再有「兩個入口各擋一半」
	# 留下可以鑽的窗口。
	if not FighterState.can_jump(movement_node, jump_pressed, is_special_moving):
		return

	movement_node.jump_dir = input_dir
	movement_node.is_jumping = true
	movement_node.landing_facing_lock = true
	# 【跳起煙】離地那一瞬間在腳底生成一團跳起煙（vjumpsmoke，仿照著地煙）。
	# 掛在 world 底下不跟著身體跑，播完自行消失。
	movement_node.spawn_vjump_smoke()
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
