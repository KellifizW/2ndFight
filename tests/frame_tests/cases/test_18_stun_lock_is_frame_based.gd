extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1 迴歸：PushManager 族（knockfly / hit / block lock）必須是整數物理幀。
##
## 保護兩個不變量：
##   1. 秒數種子走 seconds_to_lock_frames（0.4s→49），與 landing 同一公式。
##   2. knockfly_frames 每個物理幀剛好 -1，且不受 delta / time_scale 影響。

func run() -> bool:
	check(Movement.seconds_to_lock_frames(0.4) == 49,
		"0.4s should convert to 49 frames (legacy float countdown), got %d"
		% Movement.seconds_to_lock_frames(0.4))
	check(Movement.seconds_to_lock_frames(8.0 / 60.0) == 17,
		"8/60s (min_hitstun_duration) should convert to 17 frames, got %d"
		% Movement.seconds_to_lock_frames(8.0 / 60.0))

	check(typeof(p1.knockfly_frames) == TYPE_INT,
		"knockfly_frames must be an int, not a float")
	check(typeof(p1.hit_lock_frames) == TYPE_INT,
		"hit_lock_frames must be an int, not a float")
	check(typeof(p1.block_lock_frames) == TYPE_INT,
		"block_lock_frames must be an int, not a float")
	check(typeof(p1.block_push_frames) == TYPE_INT,
		"block_push_frames must be an int, not a float")

	# Direct take_hit avoids animation / hitbox timing. skip_push keeps velocity
	# from the knockfly seed; lift the defender so KnockflyHandler does not
	# immediately promote to layground and zero the timer.
	p2.take_hit(18, 10, 12.0, true, true, {}, -1.0)
	p2.fixed_position.y = int(FLOOR_Y_PX * float(SIM_SCALE)) - 200000
	p2.fixed_velocity.y = -1000000

	var expected_knockfly: int = Movement.seconds_to_lock_frames(p2.default_knockfly_duration)
	check(p2.is_knockfly, "force_knockfly take_hit should enter knockfly")
	check(p2.knockfly_frames == expected_knockfly,
		"knockfly_frames should start at %d, got %d" % [expected_knockfly, p2.knockfly_frames])
	check(p2.knockfly_duration_frames == expected_knockfly,
		"knockfly_duration_frames should match the seed, got %d" % p2.knockfly_duration_frames)

	var previous: int = p2.knockfly_frames
	var steps: int = 0
	var bad_step: int = -999
	while p2.knockfly_frames > 0 and steps < 80:
		await await_frames(1)
		steps += 1
		# Keep the defender airborne so landing cannot reset the timer mid-count.
		if p2.fixed_position.y >= int(FLOOR_Y_PX * float(SIM_SCALE)) - 1000:
			p2.fixed_position.y = int(FLOOR_Y_PX * float(SIM_SCALE)) - 200000
			p2.fixed_velocity.y = -1000000
		var current: int = p2.knockfly_frames
		if previous - current != 1 and bad_step == -999:
			bad_step = previous - current
		previous = current

	check(bad_step == -999,
		"knockfly_frames should decrease by exactly 1 per physics frame, saw a step of %d"
		% bad_step)
	check(p2.knockfly_frames == 0,
		"knockfly_frames should settle at 0, got %d" % p2.knockfly_frames)
	check(steps == expected_knockfly,
		"knockfly should take exactly %d decrement steps, got %d" % [expected_knockfly, steps])

	return not has_failures()
