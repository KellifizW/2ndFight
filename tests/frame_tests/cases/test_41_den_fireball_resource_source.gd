extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 3 slice 1: DEN fireball reads its external SpecialMoveData resource.
##
## The scene used to embed a partial smd_fireball resource.  The embedded value
## won over data/specials/den_fireball.tres, so editing the .tres silently had no
## effect.  The slice preserves the effective embedded values while making the
## .tres resource the runtime source.

func run() -> bool:
	await await_frames(10)

	var ms = p2.move_set
	check(ms != null, "P2 MoveSet 節點不存在")
	if ms == null:
		return false

	var move = ms.get_move_data_for_character("fireball", "DEN")
	check(move != null, "DEN fireball 應該存在於 move_library")
	if move == null:
		return false

	check(move.name == "fireball", "DEN fireball move id 應為 fireball")
	check(abs(move.damage - 8.0) < 0.001, "DEN fireball 傷害應保持 8.0，實為 %s" % move.damage)
	check(abs(move.knockback - 30.0) < 0.001, "DEN fireball knockback 應保持 30.0，實為 %s" % move.knockback)
	check(move.hitstun == 18, "DEN fireball hitstun 應保持 18 邏輯幀，實為 %d" % move.hitstun)
	check(move.blockstun == 10, "DEN fireball blockstun 應保持 10 邏輯幀，實為 %d" % move.blockstun)
	check(move.duration == 0.0, "DEN fireball duration=0 應保留動畫長度 fallback")
	check(move.is_projectile, "DEN fireball 應維持 projectile 行為")
	check(move.sound_type == "FireballCallPlayer", "DEN fireball 音效節點名稱不可改變")

	var source = ms.get_special_move_resource("fireball")
	check(source != null, "DEN fireball 應保留其 SpecialMoveData source reference")
	if source != null:
		check(source.resource_path.ends_with("data/specials/den_fireball.tres"),
			"DEN fireball source 應為 data/specials/den_fireball.tres，實為 %s" % source.resource_path)

	return not has_failures()
