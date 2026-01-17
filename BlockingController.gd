class_name BlockingController extends Node

# References
var movement_parent: Node
var world: Node

func _ready() -> void:
	movement_parent = owner
	world = get_tree().get_first_node_in_group("world")

func _handle_blocking(input_dir: int, is_special_moving: bool) -> void:
	var is_attacking = "is_attacking" in movement_parent and movement_parent.is_attacking
	var is_dashing = "is_dashing" in movement_parent and movement_parent.is_dashing
	var is_backdashing = "is_backdashing" in movement_parent and movement_parent.is_backdashing
	var is_hit = "is_hit" in movement_parent and movement_parent.is_hit
	var is_knockfly = "is_knockfly" in movement_parent and movement_parent.is_knockfly
	var is_layground = "is_layground" in movement_parent and movement_parent.is_layground
	var is_blocking = "is_blocking" in movement_parent and movement_parent.is_blocking
	var is_crouching = "is_crouching" in movement_parent and movement_parent.is_crouching
	
	if movement_parent.is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not is_special_moving and not (is_hit or is_knockfly or is_layground):
		var facing_direction = movement_parent.facing_direction if "facing_direction" in movement_parent else 1.0
		movement_parent.is_holding_back = input_dir * facing_direction < 0
		movement_parent.is_crouch_blocking = is_crouching and movement_parent.is_holding_back
	else:
		if not (is_hit or is_knockfly or is_blocking or is_layground):
			movement_parent.is_holding_back = false
			movement_parent.is_crouch_blocking = false

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != movement_parent:
		movement_parent.is_opponent_proximity = true
		var input_dir: int = movement_parent.get_input().input_dir if "get_input" in movement_parent else 0
		var facing_direction = movement_parent.facing_direction if "facing_direction" in movement_parent else 1.0
		var is_hit = "is_hit" in movement_parent and movement_parent.is_hit
		var is_knockfly = "is_knockfly" in movement_parent and movement_parent.is_knockfly
		var is_layground = "is_layground" in movement_parent and movement_parent.is_layground
		
		if input_dir * facing_direction < 0 and movement_parent.is_on_floor() and not (is_hit or is_knockfly or is_layground):
			movement_parent.is_proximity_blocking = true
			movement_parent.fixed_velocity.x = 0

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != movement_parent:
		movement_parent.is_opponent_proximity = false
		movement_parent.is_proximity_blocking = false
