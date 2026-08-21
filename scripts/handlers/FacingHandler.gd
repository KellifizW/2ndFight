class_name FacingHandler extends Node

# Handles facing direction updates and management
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func set_facing(new_facing: float) -> void:
	if movement_node.facing_direction != new_facing:
		var seat = movement_node.get_meta("player_seat") if movement_node.has_meta("player_seat") else "unknown"
		Debug.log("[FACING_CHANGE] %s: %.1f → %.1f" % [seat, movement_node.facing_direction, new_facing])
	movement_node.facing_direction = new_facing
	movement_node.scale.x = sign(new_facing)
	movement_node.scale.y = 1
	if movement_node.sprite:
		movement_node.sprite.scale.x = 1.0
	movement_node.rotation_degrees = 0
	movement_node.update_hitbox_position()

func update_facing_direction(ignore_locks: bool = false) -> void:
	var is_landing_state = ("is_landing" in movement_node and movement_node.is_landing and "landing_lock_timer" in movement_node and movement_node.landing_lock_timer > 0)
	
	if not ignore_locks and (movement_node.is_attacking or movement_node.landing_facing_lock or is_landing_state or movement_node.is_layground):
		return
	
	var players = movement_node.get_tree().get_nodes_in_group("players")
	var other_player = null
	for p in players:
		if p != movement_node:
			other_player = p
			break
	
	if not other_player:
		set_facing(1.0)
		return
	
	var self_left = movement_node.global_position.x - movement_node.colbox_half_width
	var self_right = movement_node.global_position.x + movement_node.colbox_half_width
	var other_left = other_player.global_position.x - other_player.colbox_half_width
	var other_right = other_player.global_position.x + other_player.colbox_half_width
	var epsilon = 1.0
	
	if self_left > other_right + epsilon:
		set_facing(-1.0)
	elif self_right < other_left - epsilon:
		set_facing(1.0)
	else:
		var push_manager = movement_node.get_tree().get_first_node_in_group("push_manager")
		var is_at_left_corner = push_manager.is_at_corner(movement_node) if push_manager else false
		if is_at_left_corner:
			set_facing(-1.0 if movement_node.global_position.x > other_player.global_position.x else 1.0)
		else:
			set_facing(movement_node.facing_direction)
