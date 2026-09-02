extends "res://tests/frame_tests/frame_test_case.gd"
## WOO fireball（一鍵 SPM2 / QCF+P）端到端驗證。
##
## WOO 的火球走與 DAV/DEN 相同的路徑：
##   start_fireball() → _start_special("fireball") → 動畫 Call Method _spawn_fireball
##   → execute_fireball_spawn() → ResourcePreloader.get_fireball_scene("WOO")
##   → 以 WOO_fireball.tscn 生成投射物。
##
## 本用例把 P1 換成 WOO（其餘角色維持 DEN），直接呼叫 MoveSet.start_fireball()
## （等同 TouchControls SPM2 按鈕的執行路徑），驗證資源、move library、
## Call Method 生成投射物與收招。

## 告訴 runner 本用例需要 WOO 上場（run_tests.gd 的 case_characters 支援）
func case_characters() -> Array:
	return ["res://characters/WOO.character.tres", "res://characters/DEN.character.tres"]

func run() -> bool:
	await await_frames(10)

	check(p1.character_id == "WOO", "P1 應為 WOO，實為 %s" % p1.character_id)

	var ms = p1.move_set
	check(ms != null, "P1 MoveSet 節點不存在")
	if ms == null:
		return false

	# ── 1. Move library 應註冊 WOO fireball（讀取 data/specials/woo_fireball.tres）──
	var move = ms.get_move_data_for_character("fireball", "WOO")
	check(move != null, "WOO fireball 應該存在於 move_library")
	if move == null:
		return false

	check(move.name == "fireball", "WOO fireball move id 應為 fireball")
	check(abs(move.damage - 10.0) < 0.001, "WOO fireball 傷害應為 10.0，實為 %s" % move.damage)
	check(abs(move.knockback - 80.0) < 0.001, "WOO fireball knockback 應為 80.0，實為 %s" % move.knockback)
	check(move.hitstun == 24, "WOO fireball hitstun 應為 24 邏輯幀，實為 %d" % move.hitstun)
	check(move.blockstun == 14, "WOO fireball blockstun 應為 14 邏輯幀，實為 %d" % move.blockstun)
	check(move.duration == 0.0, "WOO fireball duration=0 應保留動畫長度 fallback")
	check(move.is_projectile, "WOO fireball 應維持 projectile 行為")
	check(move.sound_type == "FireballCallPlayer", "WOO fireball 音效節點名稱不可改變")
	check(abs(move.projectile_speed - 800.0) < 0.001, "WOO fireball 投射物速度應為 800.0，實為 %s" % move.projectile_speed)

	var source = ms.get_special_move_resource("fireball")
	check(source != null, "WOO fireball 應保留其 SpecialMoveData source reference")
	if source != null:
		check(source.resource_path.ends_with("data/specials/woo_fireball.tres"),
			"WOO fireball source 應為 data/specials/woo_fireball.tres，實為 %s" % source.resource_path)

	# ── 2. ResourcePreloader 應提供 WOO_fireball.tscn ─────────────────────────
	var preloader = world.get_node_or_null("ResourcePreloader")
	check(preloader != null, "World 應建立 ResourcePreloader")
	if preloader != null:
		check(preloader.has_fireball("WOO"), "ResourcePreloader.has_fireball('WOO') 應為 true")
		var woo_scene = preloader.get_fireball_scene("WOO")
		check(woo_scene != null, "ResourcePreloader.get_fireball_scene('WOO') 不應為 null")
		if woo_scene != null:
			check(str(woo_scene.resource_path).ends_with("scenes/projectiles/WOO_fireball.tscn"),
				"WOO 投射物場景應為 WOO_fireball.tscn，實為 %s" % woo_scene.resource_path)

	# ── 3. 一鍵出招：start_fireball()（等同 TouchControls SPM2 按鈕路徑）──────
	ms.start_fireball()

	check(ms.is_spmove == true, "start_fireball 後 is_spmove 應為 true")

	# 等 fireball 節點生成（WOO fireball 動畫 Call Method 在 16 邏輯幀後觸發）
	var check_spawned := func():
		var pl = p1
		return pl.active_fireball != null and is_instance_valid(pl.active_fireball)
	var spawned: bool = await wait_until(check_spawned, 120)
	check(spawned, "WOO fireball 應該在動畫 Call Method 時間點生成")
	if spawned:
		var fb = p1.active_fireball
		check(fb.scene_file_path.ends_with("WOO_fireball.tscn"),
			"生成的投射物場景應為 WOO_fireball.tscn，實為 %s" % fb.scene_file_path)
		check(fb.owner_character_id == "WOO", "投射物 owner_character_id 應為 WOO，實為 %s" % fb.owner_character_id)
		check(fb.global_position.x > p1.global_position.x, "fireball 應在 P1 前方（朝右）")
		# 特殊招式動畫播完後 is_spmove 應恢復 false（WOO fireball 動畫 0.8s = 96 物理幀）
		var check_reset := func():
			var m = ms
			return m.is_spmove == false
		var reset: bool = await wait_until(check_reset, 300)
		check(reset, "WOO fireball 動畫結束後 is_spmove 應恢復 false")

	return not has_failures()
