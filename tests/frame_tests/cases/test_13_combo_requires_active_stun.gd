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

	# Timer is seconds, not raw frame count: 24 logic frames = 0.4s + 0.2 buffer.
	check(abs(world.combo_reset_timer - 0.6) < 0.001, "combo_reset_timer 應為 0.6 秒，實為 %.3f" % world.combo_reset_timer)
	return not has_failures()
