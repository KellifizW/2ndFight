extends SceneTree

const WORLD_SCENE := "res://scenes/gameplay/world.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world_scene := load(WORLD_SCENE)
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

	var scale: int = world.SIMULATION_SCALE
	dav.fixed_position = Vector2i(int((opponent.global_position.x + 170.0) * scale), world.FLOOR_Y - 1000)
	dav.global_position = world.to_scaled_vector2(dav.fixed_position)
	dav.fixed_velocity = Vector2i(0, 360000)
	dav.is_jumping = true
	dav.just_jumped = false
	dav.landing_facing_lock = true
	dav.is_air_attacking = false
	dav.has_air_attacked = true
	dav.is_attacking = false
	dav.attack_type = "none"
	dav._set_facing(1.0)
	opponent._set_facing(-1.0)

	await physics_frame
	var after_touchdown := _snapshot(dav, opponent)
	await physics_frame
	await process_frame
	var after_landing_handler := _snapshot(dav, opponent)

	var current_anim: String = dav.animation_state.get_current_node() if dav.animation_state else "none"
	var sprite = dav.get_node_or_null("AnimatedSprite2D")
	var sprite_anim: String = str(sprite.animation) if sprite else "none"
	var passed: bool = dav.is_landing and dav.landing_lock_frames > 0 and (current_anim == "landing" or sprite_anim == "jumpV") and dav.facing_direction == -1.0
	print("[LANDING_OWNERSHIP_RESULT] passed=%s touchdown=%s landing_frame=%s" % [
		passed,
		after_touchdown,
		after_landing_handler,
	])

	quit(0 if passed else 1)

func _snapshot(player: Node, opponent: Node) -> String:
	var anim: String = player.animation_state.get_current_node() if player.animation_state else "none"
	var sprite = player.get_node_or_null("AnimatedSprite2D")
	var sprite_anim: String = str(sprite.animation) if sprite else "none"
	var sprite_frame: int = sprite.frame if sprite else -1
	var player_anim: String = player.animation_player.current_animation if player.animation_player else "none"
	var tree_active: bool = player.animation_tree.active if player.animation_tree else false
	return "frame=%d state=%s player_anim=%s tree_active=%s sprite=%s:%d x=%.1f opp=%.1f on_floor=%s jumping=%s landing=%s lock=%df facelock=%s facing=%.1f scale=%.1f has_start=%s" % [
		Engine.get_physics_frames(),
		anim,
		player_anim,
		tree_active,
		sprite_anim,
		sprite_frame,
		player.global_position.x,
		opponent.global_position.x,
		player.is_on_floor(),
		player.is_jumping,
		player.is_landing,
		player.landing_lock_frames,
		player.landing_facing_lock,
		player.facing_direction,
		player.scale.x,
		player.animation_state.has_method("start") if player.animation_state else false,
	]