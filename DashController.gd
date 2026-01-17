class_name DashController extends Node

# References
var movement_parent: Node
var world: Node
var groundsmoke: GPUParticles2D

func _ready() -> void:
	movement_parent = owner
	world = get_tree().get_first_node_in_group("world")
	groundsmoke = movement_parent.groundsmoke if "groundsmoke" in movement_parent else null

func _handle_dash(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if not (movement_parent.is_on_floor() and not ("is_attacking" in movement_parent and movement_parent.is_attacking) and not ("is_dashing" in movement_parent and movement_parent.is_dashing) and 
		not ("is_backdashing" in movement_parent and movement_parent.is_backdashing) and not is_special_moving and 
		not (("is_hit" in movement_parent and movement_parent.is_hit) or ("is_knockfly" in movement_parent and movement_parent.is_knockfly) or ("is_blocking" in movement_parent and movement_parent.is_blocking) or 
			("is_push_back" in movement_parent and movement_parent.is_push_back) or ("is_layground" in movement_parent and movement_parent.is_layground)) and 
		not ("is_crouching" in movement_parent and movement_parent.is_crouching)):
		return
	
	var neutral_timer = movement_parent.neutral_timer if "neutral_timer" in movement_parent else 0.0
	var pending_dash_dir = movement_parent.pending_dash_dir if "pending_dash_dir" in movement_parent else 0
	var last_input_dir = movement_parent.last_input_dir if "last_input_dir" in movement_parent else 0
	var double_tap_timer = movement_parent.double_tap_timer if "double_tap_timer" in movement_parent else 0.3
	var facing_direction = movement_parent.facing_direction if "facing_direction" in movement_parent else 1.0
	
	if neutral_timer > 0 and input_dir != 0 and pending_dash_dir == input_dir:
		if input_dir * facing_direction > 0:
			movement_parent.is_dashing = true
			movement_parent.dash_timer = movement_parent.dash_time
			movement_parent.fixed_velocity.x = int(movement_parent.dash_speed * scale_factor * input_dir)
			if groundsmoke:
				groundsmoke.scale.x = facing_direction
				groundsmoke.restart()
		elif not (("is_blocking" in movement_parent and movement_parent.is_blocking) and 
				 ("is_opponent_proximity" in movement_parent and movement_parent.is_opponent_proximity) and 
				 ("block_type" in movement_parent and movement_parent.block_type == "proximity")):
			movement_parent.is_backdashing = true
			movement_parent.dash_timer = movement_parent.backdash_time
			movement_parent.fixed_velocity.x = int(movement_parent.backdash_speed * scale_factor * input_dir)
			if groundsmoke:
				groundsmoke.scale.x = facing_direction
				groundsmoke.restart()
		movement_parent.neutral_timer = 0.0
		movement_parent.pending_dash_dir = 0
		movement_parent.last_input_dir = 0
		movement_parent.landing_facing_lock = true
	elif input_dir != last_input_dir:
		if last_input_dir != 0 and input_dir == 0:
			movement_parent.neutral_timer = double_tap_timer
			movement_parent.pending_dash_dir = last_input_dir
		movement_parent.last_input_dir = input_dir

func _handle_dash_timer(delta: float) -> void:
	if movement_parent.dash_timer > 0:
		movement_parent.dash_timer = max(0, movement_parent.dash_timer - delta)
		if movement_parent.dash_timer == 0:
			movement_parent.is_dashing = false
			movement_parent.is_backdashing = false
			movement_parent.fixed_velocity.x = 0
			movement_parent.neutral_timer = 0.0
			movement_parent.pending_dash_dir = 0
			movement_parent.last_input_dir = 0
			movement_parent.landing_facing_lock = false

func _handle_walk(input_dir: int, scale_factor: float, is_special_moving: bool) -> void:
	if not (movement_parent.is_on_floor() and not ("is_attacking" in movement_parent and movement_parent.is_attacking) and 
		not ("is_dashing" in movement_parent and movement_parent.is_dashing) and not ("is_backdashing" in movement_parent and movement_parent.is_backdashing) and 
		not is_special_moving and 
		not (("is_hit" in movement_parent and movement_parent.is_hit) or ("is_knockfly" in movement_parent and movement_parent.is_knockfly) or ("is_blocking" in movement_parent and movement_parent.is_blocking) or 
			("is_push_back" in movement_parent and movement_parent.is_push_back) or ("is_layground" in movement_parent and movement_parent.is_layground)) and 
		not ("is_crouching" in movement_parent and movement_parent.is_crouching)):
		if not (("is_jumping" in movement_parent and movement_parent.is_jumping) or ("is_dashing" in movement_parent and movement_parent.is_dashing) or ("is_backdashing" in movement_parent and movement_parent.is_backdashing) or 
			("is_hit" in movement_parent and movement_parent.is_hit) or ("is_knockfly" in movement_parent and movement_parent.is_knockfly) or ("is_blocking" in movement_parent and movement_parent.is_blocking) or 
			("is_push_back" in movement_parent and movement_parent.is_push_back) or ("jump_delay_timer" in movement_parent and movement_parent.jump_delay_timer > 0) or 
			is_special_moving or ("is_layground" in movement_parent and movement_parent.is_layground)):
			movement_parent.fixed_velocity.x = 0
		return
	
	if input_dir != 0:
		var is_proximity_blocking = movement_parent.is_proximity_blocking if "is_proximity_blocking" in movement_parent else false
		var facing_direction = movement_parent.facing_direction if "facing_direction" in movement_parent else 1.0
		
		if is_proximity_blocking and input_dir * facing_direction < 0:
			movement_parent.fixed_velocity.x = 0
		else:
			var move_speed: float = movement_parent.walk_speed if input_dir * facing_direction > 0 else movement_parent.back_speed
			movement_parent.fixed_velocity.x = int(move_speed * scale_factor * input_dir)
	else:
		movement_parent.fixed_velocity.x = 0
