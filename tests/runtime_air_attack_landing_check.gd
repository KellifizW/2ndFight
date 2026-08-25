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

	var player = world.player_a
	if not player:
		push_error("Player A not spawned")
		quit(1)
		return

	print("[AIR_TEST] start anim=%s on_floor=%s" % [player.animation_state.get_current_node(), player.is_on_floor()])
	Input.action_press("jump")
	for i in range(6):
		await physics_frame
	Input.action_release("jump")

	for i in range(18):
		await physics_frame

	Input.action_press("st_mp")
	for i in range(3):
		await physics_frame
	Input.action_release("st_mp")

	var landed_frame := -1
	for i in range(260):
		await physics_frame
		if player.is_on_floor() and landed_frame == -1:
			landed_frame = Engine.get_physics_frames()
		if landed_frame != -1 and Engine.get_physics_frames() - landed_frame > 80:
			break

	var anim = player.animation_state.get_current_node() if player.animation_state else "none"
	print("[AIR_TEST_RESULT] landed_frame=%d anim=%s is_landing=%s landing_lock=%df is_jumping=%s is_air_attacking=%s has_air_attacked=%s is_attacking=%s attack_type=%s" % [
		landed_frame,
		anim,
		player.is_landing,
		player.landing_lock_frames,
		player.is_jumping,
		player.is_air_attacking,
		player.has_air_attacked,
		player.is_attacking,
		player.attack_type,
	])

	var stuck = player.is_landing or anim == "landing" or player.is_air_attacking or player.is_attacking or player.attack_type != "none"

	Input.action_press("st_lp")
	for i in range(3):
		await physics_frame
	Input.action_release("st_lp")
	for i in range(3):
		await physics_frame

	var action_anim = player.animation_state.get_current_node() if player.animation_state else "none"
	var can_act = player.is_attacking and player.attack_type == "st_lp"
	print("[AIR_TEST_ACTION] anim=%s can_act=%s is_attacking=%s attack_type=%s" % [
		action_anim,
		can_act,
		player.is_attacking,
		player.attack_type,
	])

	quit(1 if stuck or not can_act else 0)