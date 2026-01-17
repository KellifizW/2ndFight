class_name BlockingHandler extends Node

# Handles blocking logic and state
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_blocking(input_dir: int, is_special_moving: bool) -> void:
	if movement_node.is_on_floor() and not movement_node.is_attacking and not movement_node.is_dashing and not movement_node.is_backdashing and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_layground):
		movement_node.is_holding_back = input_dir * movement_node.facing_direction < 0
		movement_node.is_crouch_blocking = movement_node.is_crouching and movement_node.is_holding_back
	else:
		if not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_layground):
			movement_node.is_holding_back = false
			movement_node.is_crouch_blocking = false
