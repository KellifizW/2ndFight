extends "res://tests/frame_tests/frame_test_case.gd"
## Hitstun starts after hitstop, then decrements exactly once per physics frame.

func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var slowmo = p2.slow_mo_controller
	var hitstop_started: bool = await wait_until(
		func(): return slowmo != null and slowmo.is_hit_slowmo, 120)
	check(hitstop_started, "Hitstop should start when st_mp connects")
	if not hitstop_started:
		return not has_failures()

	check(p2.hitstun_frames == 48, "Hitstun should be 48 frames when hitstop starts")
	var previous: int = p2.hitstun_frames
	var decrement_count: int = 0
	for frame in 120:
		await await_frames(1)
		var current: int = p2.hitstun_frames
		if slowmo.is_hit_slowmo:
			check(current == previous,
				"Hitstun should remain frozen during hitstop, got %d after %d" % [current, previous])
		elif current < previous:
			check(current == previous - 1,
				"Hitstun should decrement by one, got %d after %d" % [current, previous])
			decrement_count += 1
		previous = current
		if current == 0:
			break

	check(decrement_count == 48,
		"Hitstun should have exactly 48 decrement steps, got %d" % decrement_count)
	check(p2.hitstun_frames == 0, "Hitstun should reach zero")
	check(not p2.is_hit, "Hit state should clear when hitstun reaches zero")
	return not has_failures()