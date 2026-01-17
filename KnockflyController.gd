class_name KnockflyController extends Node

# References
var movement_parent: Node
var world: Node

func _ready() -> void:
	movement_parent = owner
	world = get_tree().get_first_node_in_group("world")
	var retry_count: int = 0
	while not world and retry_count < 5:
		await get_tree().create_timer(0.1).timeout
		world = get_tree().get_first_node_in_group("world")
		retry_count += 1

func _apply_air_friction(friction_coeff: float, delta: float) -> void:
	var friction_amount = int(friction_coeff * (world.SIMULATION_SCALE if world else 1000.0) * delta)
	if movement_parent.fixed_velocity.x > 0:
		movement_parent.fixed_velocity.x = max(0, movement_parent.fixed_velocity.x - friction_amount)
	elif movement_parent.fixed_velocity.x < 0:
		movement_parent.fixed_velocity.x = min(0, movement_parent.fixed_velocity.x + friction_amount)

func _handle_knockfly_layground(delta: float, _floor_y: int) -> void:
	if "is_air_hit_backjump" in movement_parent and movement_parent.is_air_hit_backjump:
		movement_parent.air_hit_backjump_timer -= delta
		var gravity: int = world.GRAVITY if world else 6000000
		movement_parent.fixed_velocity.y += int(gravity * delta)
		_apply_air_friction(movement_parent.default_air_friction if "default_air_friction" in movement_parent else 200.0, delta)
		if movement_parent.air_hit_backjump_timer <= 0 or movement_parent.is_on_floor():
			movement_parent.is_air_hit_backjump = false
			movement_parent.is_hit = true
		return

	if "is_knockfly" in movement_parent and movement_parent.is_knockfly:
		movement_parent.knockfly_timer -= delta
		movement_parent.fixed_velocity.y += int(movement_parent.knockfly_gravity * delta)
		_apply_air_friction(movement_parent.air_friction if "air_friction" in movement_parent else 200.0, delta)

		if movement_parent.is_on_floor():
			movement_parent.fixed_velocity = Vector2i.ZERO
			movement_parent.is_knockfly = false
			if "is_layground" in movement_parent:
				movement_parent.is_layground = true
			if "layground_timer" in movement_parent:
				movement_parent.layground_timer = movement_parent.layground_duration
			if "is_knockfly_animation_finished" in movement_parent:
				movement_parent.is_knockfly_animation_finished = false
			
		var anim_controller = movement_parent.get_node_or_null("AnimationController")
		if anim_controller and "animation_state" in anim_controller and anim_controller.animation_state:
			anim_controller._update_animation_state(0, false)
			return

		if movement_parent.knockfly_timer <= 0 and not movement_parent.is_on_floor():
			if "is_knockfly_animation_finished" in movement_parent:
				movement_parent.is_knockfly_animation_finished = true
			movement_parent.fixed_velocity.x = 0
			return

	if "is_layground" in movement_parent and movement_parent.is_layground:
		movement_parent.layground_timer -= delta
		movement_parent.fixed_velocity = Vector2i.ZERO
		if movement_parent.layground_timer <= 0:
			_reset_layground_with_health_check()

func _reset_layground_with_health_check() -> void:
	var healthbar = movement_parent.healthbar if "healthbar" in movement_parent else null
	
	if healthbar and healthbar.current_health <= 0:
		if "is_layground" in movement_parent:
			movement_parent.is_layground = true
		if "is_knockfly" in movement_parent:
			movement_parent.is_knockfly = false
		if "is_knockfly_animation_finished" in movement_parent:
			movement_parent.is_knockfly_animation_finished = false
		return
	
	if "is_layground" in movement_parent:
		movement_parent.is_layground = false
	if "is_knockfly" in movement_parent:
		movement_parent.is_knockfly = false
	if "is_knockfly_animation_finished" in movement_parent:
		movement_parent.is_knockfly_animation_finished = false
	
	if "is_wakeup" in movement_parent:
		movement_parent.is_wakeup = true
		movement_parent.is_wakeup_locked = true
		var anim_ctrl_wakeup = movement_parent.get_node_or_null("AnimationController")
		if anim_ctrl_wakeup and "animation_state" in anim_ctrl_wakeup and anim_ctrl_wakeup.animation_state:
			anim_ctrl_wakeup.animation_state.travel("wakeup")
	
	var anim_ctrl = movement_parent.get_node_or_null("AnimationController")
	if anim_ctrl:
		anim_ctrl._update_animation_state(0, false)
