extends "res://tests/frame_tests/frame_test_case.gd"
## 全局機制：空中重置（Air Reset / Flip-out）
##
## 規則（scripts/combat/AirReset.gd）：非擊倒性攻擊擊中 Airborne 目標時
##   1. 目標進入 is_air_hit_backjump（不是 knockfly）
##   2. 原有跳躍動量被清除，改成固定的「向後 X + 向上微浮空 Y」向量
##   3. 目標的攻擊狀態被取消，且該次滯空不得再出招（has_air_attacked）
##   4. 滯空期間水平速度單調收斂（空氣阻力），不被 knockback 覆蓋
##   5. 落地後狀態解除、恢復可行動
##
## 這個用例把上述五條逐一釘住 —— 舊實作只滿足第 2 條的一半（速度有寫，
## 但下一幀就被 PushManager 的 knockback 覆蓋），其餘四條全都不成立。

func run() -> bool:
	await await_frames(10)
	teleport_x(p1, 560.0)
	teleport_x(p2, 690.0)
	await await_frames(5)

	# P2 起跳，等它離地
	Input.action_press("jump_p2")
	await await_frames(4)
	Input.action_release("jump_p2")
	var airborne: bool = await wait_until(func(): return not p2.is_on_floor(), 90)
	check(airborne, "P2 應該成功起跳（前置條件）")

	var vy_before_hit: int = p2.fixed_velocity.y

	# P1 出中拳（damage=6 → 非擊倒性攻擊）
	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var reset_seen: bool = await wait_until(func(): return bool(p2.is_air_hit_backjump), 240)
	check(reset_seen, "空中被輕/中攻擊命中應觸發空中重置（is_air_hit_backjump）")
	if not reset_seen:
		return not has_failures()

	# ── 1. 不是 knockfly ──
	check(not p2.is_knockfly, "空中重置不得升級成 knockfly（非擊倒性攻擊）")

	# ── 2. 動量被清除並改寫成固定向量 ──
	var vx: int = p2.fixed_velocity.x
	var vy: int = p2.fixed_velocity.y
	check(vy < 0, "空中重置應賦予向上微浮空的 Y 速度，實為 %d" % vy)
	check(vy != vy_before_hit, "原有跳躍動量應被清除後重寫")
	# X 推力方向 = 受擊者的背後（-facing）
	check(vx * int(p2.facing_direction) < 0,
		"X 推力應朝受擊者背後（facing=%d, vel_x=%d）" % [int(p2.facing_direction), vx])
	check(p2.air_hit_backjump_timer >= AirReset.MIN_FRAMES,
		"空中重置時長至少 %d 物理幀，實為 %d" % [AirReset.MIN_FRAMES, p2.air_hit_backjump_timer])

	# ── 3. 進攻狀態被強制取消 ──
	check(not p2.is_attacking, "空中重置應取消受擊方的攻擊狀態")
	check(not p2.is_air_attacking, "空中重置應取消受擊方的空中攻擊")
	check(p2.has_air_attacked, "空中重置後該次滯空不得再出招")

	# ── 4. 水平速度單調收斂，且不被 knockback 覆蓋 ──
	var prev_abs: int = abs(p2.fixed_velocity.x)
	var monotonic: bool = true
	var knockback_leak: bool = false
	for i in 12:
		await await_frames(1)
		if not p2.is_air_hit_backjump:
			break
		if p2.knockback_frames > 0:
			knockback_leak = true
		var cur_abs: int = abs(p2.fixed_velocity.x)
		if cur_abs > prev_abs:
			monotonic = false
		prev_abs = cur_abs
	check(monotonic, "空中重置期間水平速度應只減不增（空氣阻力）")
	check(not knockback_leak, "空中重置期間不得同時跑 knockback（會覆蓋重置向量）")

	# ── 5. 落地後解除 ──
	var recovered: bool = await wait_until(
		func(): return p2.is_on_floor() and not p2.is_air_hit_backjump and not p2.is_hit, 600)
	check(recovered, "空中重置結束後 P2 應落地並恢復可行動")

	return not has_failures()
