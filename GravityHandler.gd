class_name GravityHandler extends Node

# Handles gravity application
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_gravity(delta: float, move_set) -> void:
	if movement_node.jump_delay_timer <= 0 and not movement_node.is_on_floor() and not movement_node.is_knockfly:
		var gravity: int = movement_node.world.GRAVITY if movement_node.world else 1800000
		if move_set and move_set.is_super:
			gravity = move_set.super_gravity
		movement_node.fixed_velocity.y += int(gravity * delta)
	else:
		if not movement_node.just_jumped and not movement_node.is_knockfly:
			movement_node.fixed_velocity.y = 0
			movement_node.fixed_position.y = movement_node.world.FLOOR_Y if movement_node.world else 200000
