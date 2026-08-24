extends "res://tests/frame_tests/frame_test_case.gd"
## Forward double-tap dash lasts exactly 42 physics frames (0.35s at 120 Hz).

func run() -> bool:
	await await_frames(5)
	await tap("move_right")
	await await_frames(1)
	Input.action_press("move_right")

	var me = p1
	var dash_started: bool = await wait_until(
		func(): return me.is_dashing, 10)
	Input.action_release("move_right")
	check(dash_started, "Forward double-tap should start a dash")
	if not dash_started:
		return not has_failures()

	check(p1.dash_timer == 42, "Dash should start at 42 frames, got %d" % p1.dash_timer)
	for expected in range(41, -1, -1):
		await await_frames(1)
		check(p1.dash_timer == expected,
			"Dash timer should decrement to %d, got %d" % [expected, p1.dash_timer])

	check(not p1.is_dashing, "Dash state should clear when the timer reaches zero")
	return not has_failures()