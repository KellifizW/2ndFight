extends "res://tests/frame_tests/frame_test_case.gd"
## Combo counter must only continue when the previous target was still in stun
## before the new hit was applied. A later neutral hit should restart at 1.

func run() -> bool:
	await await_frames(5)
	world.reset_combo()

	# First standalone hit starts a combo at 1 (label remains hidden for 1 hit).
	world._on_hit_detected(p2.name, 24, false, false)
	check(world.current_combo == 1, "第一下非連段命中應設定 current_combo=1，實為 %d" % world.current_combo)
	check(world.combo_target == p2.name, "combo_target 應記錄 P2")

	# Another hit after the defender recovered must restart, not increment.
	world._on_hit_detected(p2.name, 24, false, false)
	check(world.current_combo == 1, "非 hitstun 內的下一次命中不應增加 combo，實為 %d" % world.current_combo)

	# A hit while the defender is still in stun is the only case that increments.
	world._on_hit_detected(p2.name, 24, false, true)
	check(world.current_combo == 2, "hitstun 內命中才應增加 combo，實為 %d" % world.current_combo)

	# Stage 1：連段視窗是 int 物理幀倒數（舊秒制 `combo_reset_timer` 已淘汰）。
	# 種子 = 24 邏輯 hitstun ×2 + 0.2s 緩衝（lock 式 floor×120+1 = 25）= 73 物理幀。
	check(typeof(world.combo_reset_frames) == TYPE_INT,
		"combo_reset_frames 必須是 int，實為 %s" % type_string(typeof(world.combo_reset_frames)))
	check(world.combo_reset_frames == 73,
		"combo_reset_frames 應為 73（48 stun + 25 buffer），實為 %d" % world.combo_reset_frames)
	return not has_failures()
