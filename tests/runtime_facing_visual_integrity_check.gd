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
	dav._set_facing(1.0)
	opponent._set_facing(-1.0)

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
	var first_wrong_frame := -1
	var first_wrong_snapshot := ""
	for i in range(320):
		await physics_frame
		var current_anim = dav.animation_state.get_current_node() if dav.animation_state else "none"
		if _is_landing_active(dav, current_anim):
			saw_landing = true
		if dav.is_on_floor() and landed_frame == -1 and Engine.get_physics_frames() > 20:
			landed_frame = Engine.get_physics_frames()
		if landed_frame != -1:
			var expected_facing: float = -1.0 if dav.global_position.x > opponent.global_position.x else 1.0
			var root_sign: float = sign(dav.scale.x)
			var sprite_sign: float = _sprite_global_x_sign(dav)
			var logical_ok: bool = dav.facing_direction == expected_facing
			var root_ok: bool = root_sign == expected_facing
			var visual_ok: bool = sprite_sign == expected_facing
			if not (logical_ok and root_ok and visual_ok) and first_wrong_frame == -1:
				first_wrong_frame = Engine.get_physics_frames()
				first_wrong_snapshot = _snapshot(dav, opponent, expected_facing, current_anim, sprite_sign)
		if landed_frame != -1 and Engine.get_physics_frames() - landed_frame > 90:
			break
	Input.action_release("move_right")

	var expected_final := -1.0 if dav.global_position.x > opponent.global_position.x else 1.0
	var final_sprite_sign := _sprite_global_x_sign(dav)
	var passed = saw_landing and first_wrong_frame == -1 and dav.facing_direction == expected_final and sign(dav.scale.x) == expected_final and final_sprite_sign == expected_final
	print("[FACING_VISUAL_RESULT] passed=%s saw_landing=%s first_wrong_frame=%d final=%s wrong_snapshot=%s" % [
		passed,
		saw_landing,
		first_wrong_frame,
		_snapshot(dav, opponent, expected_final, dav.animation_state.get_current_node() if dav.animation_state else "none", final_sprite_sign),
		first_wrong_snapshot,
	])

	quit(0 if passed else 1)

func _sprite_global_x_sign(player: Node) -> float:
	var animated_sprite = player.get_node_or_null("AnimatedSprite2D")
	if not animated_sprite:
		return 0.0
	return sign(animated_sprite.global_transform.x.x)

func _is_landing_active(player: Node, current_anim: String) -> bool:
	var player_anim: String = player.animation_player.current_animation if player.animation_player else ""
	return current_anim == "landing" or player_anim == "landing" or player.is_landing

func _snapshot(player: Node, opponent: Node, expected_facing: float, anim: String, sprite_sign: float) -> String:
	var animated_sprite = player.get_node_or_null("AnimatedSprite2D")
	var local_sprite_scale = animated_sprite.scale if animated_sprite else Vector2.ZERO
	return "frame=%d anim=%s x=%.1f opp=%.1f expected=%.1f facing=%.1f root_scale=%.3f sprite_local=(%.3f,%.3f) sprite_global_x_sign=%.1f landing=%s timer=%.4f lock=%s attacking=%s" % [
		Engine.get_physics_frames(),
		anim,
		player.global_position.x,
		opponent.global_position.x,
		expected_facing,
		player.facing_direction,
		player.scale.x,
		local_sprite_scale.x,
		local_sprite_scale.y,
		sprite_sign,
		player.is_landing,
		player.landing_lock_timer,
		player.landing_facing_lock,
		player.is_attacking,
	]