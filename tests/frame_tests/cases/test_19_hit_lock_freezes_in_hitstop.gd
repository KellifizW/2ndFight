extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1：hit_lock_frames 必須與 hitstun_frames 對齊，並在 hitstop 期間凍結。
##
## 舊的 hit_timer 用 `-= delta`，PushManager 不受 fighter 的 hitstop 早退保護，
## 會被 Engine.time_scale=0.02 拉長。改幀後兩者應同步、每物理幀 -1。

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
	check(p2.hit_lock_frames == 48,
		"hit_lock_frames should seed to the same 48 physics frames, got %d" % p2.hit_lock_frames)

	var previous_lock: int = p2.hit_lock_frames
	var previous_stun: int = p2.hitstun_frames
	var decrement_count: int = 0
	for frame in 120:
		await await_frames(1)
		var current_lock: int = p2.hit_lock_frames
		var current_stun: int = p2.hitstun_frames
		if slowmo.is_hit_slowmo:
			check(current_lock == previous_lock,
				"hit_lock_frames should remain frozen during hitstop, got %d after %d"
				% [current_lock, previous_lock])
			check(current_stun == previous_stun,
				"hitstun_frames should remain frozen during hitstop, got %d after %d"
				% [current_stun, previous_stun])
		elif current_lock < previous_lock:
			check(current_lock == previous_lock - 1,
				"hit_lock_frames should decrement by one, got %d after %d"
				% [current_lock, previous_lock])
			decrement_count += 1
		check(current_lock == current_stun,
			"hit_lock_frames (%d) should stay aligned with hitstun_frames (%d)"
			% [current_lock, current_stun])
		previous_lock = current_lock
		previous_stun = current_stun
		if current_lock == 0 and current_stun == 0:
			break

	check(decrement_count == 48,
		"hit_lock_frames should have exactly 48 decrement steps, got %d" % decrement_count)
	check(p2.hit_lock_frames == 0, "hit_lock_frames should reach zero")
	check(p2.hitstun_frames == 0, "hitstun_frames should reach zero")
	return not has_failures()
