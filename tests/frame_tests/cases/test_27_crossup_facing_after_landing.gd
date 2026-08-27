extends "res://tests/frame_tests/frame_test_case.gd"
## Cross-up 面向時機：跳過對手後，翻面只能發生在「著地 + landing 動畫播完」之後。
##
## 這條不變式過去被三處程式碼破壞（都已修掉，本用例是它們的安全網）：
##   1. LandingHandler._handle_normal_landing 觸地當幀 force_update_facing_direction()
##      —— 繞過所有鎖，人一碰地（甚至還在落下判定的同一幀）就轉身。
##   2. Player._enter_landing_state 同樣的 force 呼叫（空中攻擊著地路徑）。
##   3. TimerHandler 著地 checkpoint（第 2 幀）暫時清掉 is_landing/landing_facing_lock
##      再更新面向 —— 完整著地動畫要 25 幀，等於提早 23 幀翻面。
##
## 正確時機只有一個：TimerHandler 在 landing_lock_frames 歸零時收尾，
## 清掉 is_landing 後才 update_facing_direction()。
##
## 場景：P1 (x=850, 面向 +1) 向右前跳越過 P2 (x=1050)。
## 跳躍水平速度 470 px/s、滯空約 0.68s → 水平位移約 300px，足以越過 200px 的間距。
## 起跳後立刻放開方向鍵，確保著地時沒有輸入（landing 不被中斷，跑完整 25 幀動畫）。

func run() -> bool:
	var me = p1
	var foe = p2

	teleport_x(p1, 850.0)
	teleport_x(p2, 1050.0)
	await await_frames(4)

	check(p1.facing_direction == 1.0, "起跳前 P1 應面向右（+1），實為 %s" % p1.facing_direction)

	Input.action_press("move_right")
	await await_frames(2)
	Input.action_press("jump")
	await await_frames(2)
	Input.action_release("jump")

	var airborne: bool = await wait_until(func(): return not me.is_on_floor(), 120)
	check(airborne, "P1 按跳躍後應離開地面")
	# 空中放開方向鍵：水平速度在起跳當幀就固定了，放開不影響飛行軌跡，
	# 但可保證著地 checkpoint 讀到「無輸入」→ 播完整 landing 動畫。
	Input.action_release("move_right")
	if not airborne:
		return not has_failures()

	var crossed: bool = false
	var flipped_in_air: bool = false
	var flipped_during_landing: bool = false
	var saw_landing: bool = false
	var landing_finished: bool = false
	var landing_frames: int = 0

	for i in 480:
		await await_frames(1)

		if px(me) > px(foe) + 5.0:
			crossed = true

		# ① 空中絕不翻面
		if not me.is_on_floor() and me.facing_direction != 1.0:
			flipped_in_air = true

		# ② 著地鎖期間（= landing 動畫還沒播完）也不翻面
		if me.is_landing and me.landing_lock_frames > 0:
			saw_landing = true
			landing_frames += 1
			if me.facing_direction != 1.0:
				flipped_during_landing = true

		if saw_landing and me.is_on_floor() and not me.is_landing:
			landing_finished = true
			break

	check(crossed, "P1 應向前跳越過 P2（P1 x=%.1f, P2 x=%.1f）" % [px(p1), px(p2)])
	check(saw_landing, "P1 應進入 landing 狀態")
	check(landing_finished, "landing 狀態應在觀測窗口內自動完成")
	check(not flipped_in_air, "P1 不該在空中（尚未著地）就翻面")
	check(not flipped_during_landing,
		"P1 不該在 landing 動畫播完前翻面（landing 觀測了 %d 幀）" % landing_frames)

	await await_frames(2)
	check(p1.facing_direction == -1.0,
		"landing 結束後 P1 應面向左（-1，朝向身後的對手），實為 %s" % p1.facing_direction)
	check(sign(p1.scale.x) == -1.0,
		"翻面後根節點 scale.x 應為 -1，實為 %s" % p1.scale.x)

	return not has_failures()
