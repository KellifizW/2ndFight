extends SceneTree

const WORLD_SCENE := "res://scenes/gameplay/world.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world_scene = load(WORLD_SCENE)
	if not world_scene:
		push_error("Failed to load world scene")
		quit(1)
		return

	var world = world_scene.instantiate()
	root.add_child(world)
	await process_frame
	await physics_frame

	var dav = world.player_a
	var opponent = world.player_b
	if not dav or not opponent:
		push_error("Players not spawned")
		quit(1)
		return

	dav.fixed_position = Vector2i(850 * world.SIMULATION_SCALE, world.FLOOR_Y)
	opponent.fixed_position = Vector2i(1050 * world.SIMULATION_SCALE, world.FLOOR_Y)
	dav.global_position = world.to_scaled_vector2(dav.fixed_position)
	opponent.global_position = world.to_scaled_vector2(opponent.fixed_position)
	dav.fixed_velocity = Vector2i.ZERO
	opponent.fixed_velocity = Vector2i.ZERO
	dav.facing_direction = 1.0
	dav.scale.x = 1.0
	opponent.facing_direction = -1.0
	opponent.scale.x = -1.0

	print("[CROSSUP_INPUT] start dav_x=%.1f opp_x=%.1f facing=%.1f" % [dav.global_position.x, opponent.global_position.x, dav.facing_direction])

	Input.action_press("move_right")
	Input.action_press("jump")
	for i in range(8):
		await physics_frame
	Input.action_release("jump")

	for i in range(20):
		await physics_frame
	Input.action_press("st_mp")
	for i in range(3):
		await physics_frame
	Input.action_release("st_mp")

	var landed_frame := -1
	var saw_landing := false
	var crossed := false
	for i in range(300):
		await physics_frame
		var current_anim = dav.animation_state.get_current_node() if dav.animation_state else "none"
		if _is_landing_active(dav, current_anim):
			saw_landing = true
		if dav.global_position.x > opponent.global_position.x + 20.0:
			crossed = true
		if dav.is_on_floor() and landed_frame == -1 and Engine.get_physics_frames() > 20:
			landed_frame = Engine.get_physics_frames()
		if landed_frame != -1 and Engine.get_physics_frames() - landed_frame > 70:
			break
	Input.action_release("move_right")

	var anim = dav.animation_state.get_current_node() if dav.animation_state else "none"
	var passed = crossed and saw_landing and dav.facing_direction == -1.0 and not dav.landing_facing_lock and not dav.is_landing and anim != "landing"
	print("[CROSSUP_INPUT_RESULT] landed_frame=%d crossed=%s saw_landing=%s anim=%s dav_x=%.1f opp_x=%.1f facing=%.1f lock=%s is_landing=%s passed=%s" % [
		landed_frame,
		crossed,
		saw_landing,
		anim,
		dav.global_position.x,
		opponent.global_position.x,
		dav.facing_direction,
		dav.landing_facing_lock,
		dav.is_landing,
		passed,
	])

	quit(0 if passed else 1)

func _is_landing_active(player: Node, current_anim: String) -> bool:
	var player_anim: String = player.animation_player.current_animation if player.animation_player else ""
	return current_anim == "landing" or player_anim == "landing" or player.is_landing