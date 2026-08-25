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

	print("[REAL_CROSSUP] spawn dav_x=%.1f opp_x=%.1f facing=%.1f root_scale=%.1f sprite_sign=%.1f" % [
		dav.global_position.x,
		opponent.global_position.x,
		dav.facing_direction,
		dav.scale.x,
		_sprite_global_x_sign(dav),
	])

	Input.action_press("move_right")
	for i in range(95):
		await physics_frame
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
	var wrong_frame := -1
	var wrong_snapshot := ""
	for i in range(360):
		await physics_frame
		var current_anim: String = dav.animation_state.get_current_node() if dav.animation_state else "none"
		var expected_facing: float = -1.0 if dav.global_position.x > opponent.global_position.x else 1.0
		if _is_landing_active(dav, current_anim):
			saw_landing = true
		if dav.global_position.x > opponent.global_position.x + 20.0:
			crossed = true
		if dav.is_on_floor() and landed_frame == -1 and Engine.get_physics_frames() > 40:
			landed_frame = Engine.get_physics_frames()
		if landed_frame != -1:
			var logical_ok: bool = dav.facing_direction == expected_facing
			var root_ok: bool = sign(dav.scale.x) == expected_facing
			var visual_ok: bool = _sprite_global_x_sign(dav) == expected_facing
			if not (logical_ok and root_ok and visual_ok) and wrong_frame == -1:
				wrong_frame = Engine.get_physics_frames()
				wrong_snapshot = _snapshot(dav, opponent, expected_facing, current_anim)
		if landed_frame != -1 and Engine.get_physics_frames() - landed_frame > 90:
			break
	Input.action_release("move_right")

	var final_expected: float = -1.0 if dav.global_position.x > opponent.global_position.x else 1.0
	var passed: bool = crossed and saw_landing and wrong_frame == -1 and dav.facing_direction == final_expected and sign(dav.scale.x) == final_expected and _sprite_global_x_sign(dav) == final_expected
	print("[REAL_CROSSUP_RESULT] passed=%s crossed=%s saw_landing=%s wrong_frame=%d final=%s wrong_snapshot=%s" % [
		passed,
		crossed,
		saw_landing,
		wrong_frame,
		_snapshot(dav, opponent, final_expected, dav.animation_state.get_current_node() if dav.animation_state else "none"),
		wrong_snapshot,
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

func _snapshot(player: Node, opponent: Node, expected_facing: float, anim: String) -> String:
	var player_anim: String = player.animation_player.current_animation if player.animation_player else ""
	return "frame=%d state=%s player_anim=%s x=%.1f opp=%.1f expected=%.1f facing=%.1f root_scale=%.3f sprite_sign=%.1f landing=%s lock=%df facelock=%s attacking=%s" % [
		Engine.get_physics_frames(),
		anim,
		player_anim,
		player.global_position.x,
		opponent.global_position.x,
		expected_facing,
		player.facing_direction,
		player.scale.x,
		_sprite_global_x_sign(player),
		player.is_landing,
		player.landing_lock_frames,
		player.landing_facing_lock,
		player.is_attacking,
	]