class_name DashHandler extends Node

# Handles dash and backdash logic
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_dash(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if movement_node.is_on_floor() and not movement_node.is_attacking and not movement_node.is_dashing and not movement_node.is_backdashing and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_push_back or movement_node.is_layground) and not movement_node.is_crouching:
		
		if movement_node.neutral_timer > 0 and input_dir != 0 and movement_node.pending_dash_dir == input_dir:
			if input_dir * movement_node.facing_direction > 0:
				movement_node.is_dashing = true
				movement_node.dash_timer = movement_node.dash_time
				movement_node.dash_total_time = movement_node.dash_time
				movement_node.dash_initial_speed = movement_node.dash_speed * scale_factor * input_dir
				movement_node.fixed_velocity.x = int(movement_node.dash_initial_speed)
				if movement_node.groundsmoke:
					movement_node.groundsmoke.scale.x = movement_node.facing_direction
					movement_node.groundsmoke.restart()
			elif not (movement_node.is_blocking and movement_node.is_opponent_proximity and movement_node.block_type == "proximity"):
				movement_node.is_backdashing = true
				movement_node.dash_timer = movement_node.backdash_time
				movement_node.dash_total_time = movement_node.backdash_time
				movement_node.dash_initial_speed = movement_node.backdash_speed * scale_factor * input_dir
				movement_node.fixed_velocity.x = int(movement_node.dash_initial_speed)
				if movement_node.groundsmoke:
					movement_node.groundsmoke.scale.x = movement_node.facing_direction
					movement_node.groundsmoke.restart()
			movement_node.neutral_timer = 0.0
			movement_node.pending_dash_dir = 0
			movement_node.last_input_dir = 0
			movement_node.landing_facing_lock = true
		elif input_dir != movement_node.last_input_dir:
			if movement_node.last_input_dir != 0 and input_dir == 0:
				movement_node.neutral_timer = movement_node.double_tap_timer
				movement_node.pending_dash_dir = movement_node.last_input_dir
			movement_node.last_input_dir = input_dir
