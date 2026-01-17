class_name TimerHandler extends Node

# Handles all timer management
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_timers(delta: float) -> void:
	if movement_node.neutral_timer > 0:
		movement_node.neutral_timer = max(0, movement_node.neutral_timer - delta)
		if movement_node.neutral_timer == 0:
			movement_node.pending_dash_dir = 0
	
	if movement_node.dash_timer > 0:
		movement_node.dash_timer = max(0, movement_node.dash_timer - delta)
		if movement_node.dash_timer == 0:
			movement_node.is_dashing = false
			movement_node.is_backdashing = false
			movement_node.fixed_velocity.x = 0
			movement_node.neutral_timer = 0.0
			movement_node.pending_dash_dir = 0
			movement_node.last_input_dir = 0
			movement_node.landing_facing_lock = false
	
	if movement_node.jump_delay_timer > 0:
		movement_node.jump_delay_timer = max(0, movement_node.jump_delay_timer - delta)
		if movement_node.jump_delay_timer == 0:
			movement_node.fixed_velocity.y = int(movement_node.jump_vertical_speed * (movement_node.world.SIMULATION_SCALE if movement_node.world else 1000))
			movement_node.just_jumped = true
			movement_node.fixed_position.y = (movement_node.world.FLOOR_Y if movement_node.world else 200000) - 1
	
	if movement_node.air_hit_backjump_timer > 0:
		movement_node.air_hit_backjump_timer = max(0, movement_node.air_hit_backjump_timer - delta)
		if movement_node.air_hit_backjump_timer == 0:
			movement_node.is_air_hit_backjump = false
			movement_node.fixed_velocity = Vector2i.ZERO
