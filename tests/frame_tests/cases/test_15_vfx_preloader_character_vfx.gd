extends "res://tests/frame_tests/frame_test_case.gd"
## Game load should preload and warm character VFX resources before first use.

func run() -> bool:
	await await_frames(5)
	var preloader = world.get_node_or_null("ResourcePreloader")
	check(preloader != null, "World 應建立 ResourcePreloader")
	if preloader == null:
		return not has_failures()

	check(preloader.has_method("warmup_character_vfx"), "ResourcePreloader 應支援角色 VFX 預熱")
	check(preloader.has_vfx("hit"), "hit VFX 應已預載")
	check(preloader.has_vfx("block"), "block VFX 應已預載")
	check(preloader.has_vfx("spawnfire"), "DAV spawnfire 角色 VFX 應已預載")
	check(preloader.preloaded_resources.has("vfx_spawnfire"), "preloaded_resources 應包含 vfx_spawnfire")
	check(preloader.has_fireball("DAV"), "DAV fireball 應已預載")
	check(preloader.has_fireball("DEN"), "DEN fireball 應已預載")
	check(preloader.has_fireball("WOO"), "WOO fireball 應已預載")
	check(preloader.preloaded_resources.has("fireball_WOO"), "preloaded_resources 應包含 fireball_WOO")
	return not has_failures()
