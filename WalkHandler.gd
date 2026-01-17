class_name WalkHandler extends Node

# Handles walking movement logic
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_walk(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if movement_node.is_on_floor() and not movement_node.is_attacking and not movement_node.is_dashing and not movement_node.is_backdashing and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.is_layground) and not movement_node.is_crouching:
		if input_dir != 0:
			if movement_node.is_proximity_blocking and input_dir * movement_node.facing_direction < 0:
				movement_node.fixed_velocity.x = 0
			else:
				var move_speed: float = movement_node.walk_speed if input_dir * movement_node.facing_direction > 0 else movement_node.back_speed
				movement_node.fixed_velocity.x = int(move_speed * scale_factor * input_dir)
		else:
			movement_node.fixed_velocity.x = 0
	else:
		if not (movement_node.is_jumping or movement_node.is_dashing or movement_node.is_backdashing or movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.jump_delay_timer > 0 or is_special_moving or movement_node.is_layground):
			movement_node.fixed_velocity.x = 0
