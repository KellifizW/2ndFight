extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1：block_lock_frames 必須與 blockstun_frames 對齊，並在 hitstop 期間凍結。

func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	Input.action_press("move_right_p2")
	await await_frames(10)
	check(p2.is_holding_back == true, "P2 按住後應該 is_holding_back=true")

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var slowmo = p2.slow_mo_controller
	var saw_block: bool = await wait_until(
		func(): return p2.blockstun_frames == 32, 300)
	check(saw_block, "P2 應進入 blockstun（blockstun_frames=32）")
	if not saw_block:
		Input.action_release("move_right_p2")
		return not has_failures()

	check(p2.block_lock_frames == 32,
		"block_lock_frames should seed to the same 32 physics frames, got %d"
		% p2.block_lock_frames)

	var previous_lock: int = p2.block_lock_frames
	var previous_stun: int = p2.blockstun_frames
	var decrement_count: int = 0
	for frame in 120:
		await await_frames(1)
		var current_lock: int = p2.block_lock_frames
		var current_stun: int = p2.blockstun_frames
		if slowmo != null and slowmo.is_hit_slowmo:
			check(current_lock == previous_lock,
				"block_lock_frames should remain frozen during hitstop, got %d after %d"
				% [current_lock, previous_lock])
		elif current_lock < previous_lock:
			check(current_lock == previous_lock - 1,
				"block_lock_frames should decrement by one, got %d after %d"
				% [current_lock, previous_lock])
			decrement_count += 1
		check(current_lock == current_stun,
			"block_lock_frames (%d) should stay aligned with blockstun_frames (%d)"
			% [current_lock, current_stun])
		previous_lock = current_lock
		previous_stun = current_stun
		if current_lock == 0 and current_stun == 0:
			break

	Input.action_release("move_right_p2")
	check(decrement_count == 32,
		"block_lock_frames should have exactly 32 decrement steps, got %d" % decrement_count)
	check(p2.block_lock_frames == 0, "block_lock_frames should reach zero")
	check(p2.blockstun_frames == 0, "blockstun_frames should reach zero")
	check(not p2.is_blocking, "Blocking state should clear when the lock expires")
	return not has_failures()
