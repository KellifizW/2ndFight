extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1 迴歸測試：landing 鎖定必須是整數物理幀，且每幀剛好遞減 1。
##
## 這個用例保護的是「秒 → 幀」遷移的兩個不變量：
##   1. seconds_to_lock_frames 精確重現舊的浮點遞減格數
##      （0.2s→25、2/60s→5、0.001s→1）。用 round() 會得到 24/4/0，
##      讓著地少一幀 —— 正是重構不能發生的行為漂移。
##   2. 遞減與 delta 無關：每個物理幀固定 -1。
##
## test_11 只覆蓋「無輸入著地持續幾幀」，覆蓋不到轉換公式本身，
## 所以那條 off-by-one 可以悄悄溜過去。這裡直接把公式釘死。

func run() -> bool:
	# ── 不變量 1：轉換公式 ──────────────────────────
	check(Movement.seconds_to_lock_frames(0.2) == 25,
		"0.2s should convert to 25 frames (legacy float countdown), got %d"
			% Movement.seconds_to_lock_frames(0.2))
	check(Movement.seconds_to_lock_frames(2.0 / 60.0) == 5,
		"2/60s should convert to 5 frames, got %d"
			% Movement.seconds_to_lock_frames(2.0 / 60.0))
	check(Movement.seconds_to_lock_frames(0.001) == 1,
		"The interrupt magic value 0.001s should convert to 1 frame, got %d"
			% Movement.seconds_to_lock_frames(0.001))
	check(Movement.seconds_to_lock_frames(0.0) == 0,
		"Zero seconds should convert to 0 frames")

	check(Movement.LANDING_FORCED_LOCK_FRAMES == 5,
		"LANDING_FORCED_LOCK_FRAMES should match the legacy 2.0/60.0 seed")
	check(Movement.LANDING_INTERRUPT_FRAMES == 1,
		"LANDING_INTERRUPT_FRAMES should leave exactly one frame")

	# ── 不變量 2：整數型別 ──────────────────────────
	check(typeof(p1.landing_lock_frames) == TYPE_INT,
		"landing_lock_frames must be an int, not a float")

	# ── 不變量 3：每物理幀剛好 -1 ───────────────────
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

	# 追蹤鎖定計數，確認它單調遞減且步長恆為 1。
	var previous: int = p1.landing_lock_frames
	var steps: int = 0
	var bad_step: int = -999
	while p1.is_landing and steps < 120:
		await await_frames(1)
		steps += 1
		var current: int = p1.landing_lock_frames
		# checkpoint（第 2 幀）會把計數重設成完整著地幀數，屬預期跳升。
		if current > previous:
			previous = current
			continue
		if previous - current != 1 and bad_step == -999:
			bad_step = previous - current
		previous = current

	check(bad_step == -999,
		"landing_lock_frames should decrease by exactly 1 per physics frame, saw a step of %d"
			% bad_step)
	check(p1.landing_lock_frames == 0,
		"landing_lock_frames should settle at 0, got %d" % p1.landing_lock_frames)
	check(not p1.is_landing, "Landing state should clear once the lock expires")

	return not has_failures()
