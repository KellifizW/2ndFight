extends SceneTree

const WORLD_SCENE := "res://scenes/gameplay/world.tscn"
const LANDING_CAPTURE := "res://tests/_crossup_landing_capture.png"
const FINAL_CAPTURE := "res://tests/_crossup_final_capture.png"

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

	var saved_landing := false
	var landed_frame := -1
	for i in range(360):
		await physics_frame
		await process_frame
		var current_anim: String = dav.animation_state.get_current_node() if dav.animation_state else "none"
		if _is_landing_active(dav, current_anim) and not saved_landing:
			saved_landing = true
			_save_viewport(LANDING_CAPTURE)
			print("[RENDER_CAPTURE_LANDING] %s" % _snapshot(dav, opponent, current_anim))
		if dav.is_on_floor() and landed_frame == -1 and Engine.get_physics_frames() > 40:
			landed_frame = Engine.get_physics_frames()
		if landed_frame != -1 and Engine.get_physics_frames() - landed_frame > 90:
			break
	Input.action_release("move_right")

	await process_frame
	_save_viewport(FINAL_CAPTURE)
	print("[RENDER_CAPTURE_FINAL] landing_saved=%s %s landing_path=%s final_path=%s" % [
		saved_landing,
		_snapshot(dav, opponent, dav.animation_state.get_current_node() if dav.animation_state else "none"),
		LANDING_CAPTURE,
		FINAL_CAPTURE,
	])
	quit(0 if saved_landing else 1)

func _save_viewport(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)

func _snapshot(player: Node, opponent: Node, anim: String) -> String:
	var animated_sprite = player.get_node_or_null("AnimatedSprite2D")
	var sprite_pos: Vector2 = animated_sprite.global_position if animated_sprite else Vector2.ZERO
	var sprite_offset: Vector2 = animated_sprite.offset if animated_sprite else Vector2.ZERO
	var sprite_anim: String = str(animated_sprite.animation) if animated_sprite else "none"
	var sprite_frame: int = animated_sprite.frame if animated_sprite else -1
	var player_anim: String = player.animation_player.current_animation if player.animation_player else ""
	var tree_active: bool = player.animation_tree.active if player.animation_tree else false
	var canvas_transform: Transform2D = player.get_viewport().get_canvas_transform()
	var player_screen: Vector2 = canvas_transform * player.global_position
	var opponent_screen: Vector2 = canvas_transform * opponent.global_position
	return "frame=%d state=%s player_anim=%s tree_active=%s sprite_anim=%s:%d root=(%.1f,%.1f) screen=(%.1f,%.1f) sprite=(%.1f,%.1f) sprite_offset=(%.1f,%.1f) opp=%.1f opp_screen_x=%.1f facing=%.1f root_scale=%.3f sprite_sign=%.1f landing=%s timer=%.4f" % [
		Engine.get_physics_frames(),
		anim,
		player_anim,
		tree_active,
		sprite_anim,
		sprite_frame,
		player.global_position.x,
		player.global_position.y,
		player_screen.x,
		player_screen.y,
		sprite_pos.x,
		sprite_pos.y,
		sprite_offset.x,
		sprite_offset.y,
		opponent.global_position.x,
		opponent_screen.x,
		player.facing_direction,
		player.scale.x,
		_sprite_global_x_sign(player),
		player.is_landing,
		player.landing_lock_timer,
	]

func _sprite_global_x_sign(player: Node) -> float:
	var animated_sprite = player.get_node_or_null("AnimatedSprite2D")
	if not animated_sprite:
		return 0.0
	return sign(animated_sprite.global_transform.x.x)

func _is_landing_active(player: Node, current_anim: String) -> bool:
	var player_anim: String = player.animation_player.current_animation if player.animation_player else ""
	return current_anim == "landing" or player_anim == "landing" or player.is_landing