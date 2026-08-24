extends "res://tests/frame_tests/frame_test_case.gd"
## A no-input landing keeps the current landing state for an exact frame span.

func run() -> bool:
	await tap("jump")

	var me = p1
	var reached_air: bool = await wait_until(
		func(): return not me.is_on_floor(), 120)
	check(reached_air, "P1 should leave the floor after jumping")
	if not reached_air:
		return not has_failures()

	var landed: bool = await wait_until(
		func(): return me.is_on_floor() and me.is_landing, 360)
	check(landed, "P1 should enter landing state")
	if not landed:
		return not has_failures()

	var landing_frames: int = 1
	while p1.is_landing and landing_frames <= 120:
		await await_frames(1)
		if p1.is_landing:
			landing_frames += 1

	check(landing_frames == 23,
		"No-input landing should last 23 physics frames, got %d" % landing_frames)
	check(not p1.is_landing, "Landing state should clear after its frame span")
	return not has_failures()