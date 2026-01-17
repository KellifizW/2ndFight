class_name JumpHandler extends Node

# Handles jump mechanics
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_jump(jump_pressed: bool, input_dir: int, scale_factor: float, floor_y: int, is_special_moving: bool) -> void:
	if jump_pressed and movement_node.is_on_floor() and not movement_node.is_crouching and not movement_node.is_dashing and not movement_node.is_backdashing and not movement_node.is_attacking and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.is_layground) and movement_node.jump_delay_timer <= 0:
		
		movement_node.jump_dir = input_dir
		movement_node.is_jumping = true
		movement_node.landing_facing_lock = true
		movement_node.jump_delay_timer = movement_node.jump_delay_duration
		movement_node.fixed_position.y = floor_y - 1
		movement_node.fixed_velocity.y = 0
		
		if movement_node.jump_dir != 0:
			var jump_speed: float = movement_node.jump_horizontal_speed if movement_node.jump_dir * movement_node.facing_direction > 0 else movement_node.jump_horizontal_speed * 0.75
			movement_node.fixed_velocity.x = int(jump_speed * scale_factor * movement_node.jump_dir)
		else:
			movement_node.fixed_velocity.x = 0
