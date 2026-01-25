class_name KnockflyHandler extends Node

# Handles knockfly and layground mechanics
var movement_node: Node
var health_check_done: bool = false  # Track if health check already failed

func _init(movement: Node) -> void:
	movement_node = movement

func handle_knockfly_layground(delta: float, _floor_y: int) -> void:
	if movement_node.is_air_hit_backjump:
		movement_node.air_hit_backjump_timer -= delta
		var gravity: int = movement_node.world.GRAVITY if movement_node.world else 6000000
		movement_node.fixed_velocity.y += int(gravity * delta)
		apply_air_friction(movement_node.default_air_friction, delta)
		if movement_node.air_hit_backjump_timer <= 0 or movement_node.is_on_floor():
			movement_node.is_air_hit_backjump = false
			movement_node.is_hit = true
		return

	if movement_node.is_knockfly:
		movement_node.knockfly_timer -= delta
		movement_node.fixed_velocity.y += int(movement_node.knockfly_gravity * delta)
		apply_air_friction(movement_node.air_friction, delta)

		# Only transition to layground if on floor
		if movement_node.is_on_floor():
			movement_node.fixed_velocity = Vector2i.ZERO
			movement_node.is_knockfly = false
			movement_node.is_layground = true
			movement_node.layground_timer = movement_node.layground_duration
			movement_node.is_knockfly_animation_finished = false
			movement_node._update_animation_state(0, false)
			return

		# If timer ends but still in air, only mark animation complete
		if movement_node.knockfly_timer <= 0 and not movement_node.is_on_floor():
			movement_node.is_knockfly_animation_finished = true
			movement_node.fixed_velocity.x = 0
			return

	if movement_node.is_layground:
		movement_node.layground_timer -= delta
		movement_node.fixed_velocity = Vector2i.ZERO
		if movement_node.layground_timer <= 0:
			reset_layground_with_health_check()

func apply_air_friction(friction_coeff: float, delta: float) -> void:
	var friction_amount = int(friction_coeff * (movement_node.world.SIMULATION_SCALE if movement_node.world else 1000.0) * delta)
	if movement_node.fixed_velocity.x > 0:
		movement_node.fixed_velocity.x = max(0, movement_node.fixed_velocity.x - friction_amount)
	elif movement_node.fixed_velocity.x < 0:
		movement_node.fixed_velocity.x = min(0, movement_node.fixed_velocity.x + friction_amount)

func reset_layground_with_health_check() -> void:
	var player_healthbar = movement_node.healthbar
	
	if player_healthbar and player_healthbar.current_health <= 0:
		# Only print debug message once when health reaches zero
		if not health_check_done:
			print("Debug: %s 血量已歸零，保持躺地狀態，不觸發 wakeup。" % movement_node.name)
			health_check_done = true
		movement_node.is_layground = true
		movement_node.is_knockfly = false
		movement_node.is_knockfly_animation_finished = false
		return
	
	# Reset health_check_done if waking up normally
	health_check_done = false
	movement_node.is_layground = false
	movement_node.is_knockfly = false
	movement_node.is_knockfly_animation_finished = false
	
	if "is_wakeup" in movement_node.get_parent() and "is_wakeup_locked" in movement_node.get_parent():
		movement_node.get_parent().is_wakeup = true
		movement_node.get_parent().is_wakeup_locked = true
		movement_node.animation_state.travel("wakeup")
	
	movement_node._update_animation_state(0, false)
