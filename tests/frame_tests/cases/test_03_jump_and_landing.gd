extends FrameTestCase
## 跳躍與著地：tap jump → 離地 → 落地 → landing 狀態自動完成
## 驗證空中狀態、landing lock、以及著地後 is_jumping 清除

func run() -> bool:
	var x0: float = px(p1)

	tap("jump")

	# 跳躍有 0.1s（12 物理幀）delay，最多等 1 秒應該離地
	# 注意: GDScript lambda 只能 capture 局部變數，先綁定 p1
	var me = p1
	var reached_air: bool = await wait_until(
		func(): return not me.is_on_floor(), 120)
	check(reached_air, "P1 跳躍後應離開地面")
	if not reached_air:
		return not has_failures()

	var apex_y: float = float(p1.fixed_position.y)
	for i in 60:
		await_frames(1)
		apex_y = min(apex_y, float(p1.fixed_position.y))
	check(apex_y < FLOOR_Y_PX - 10.0, "跳躍應達到離地 >10px（apex 差 %.1f px）" % (FLOOR_Y_PX - apex_y))

	# 落地：最多 3 秒
	var landed: bool = await wait_until(
		func(): return me.is_on_floor() and me.is_landing, 360)
	check(landed, "P1 應進入 landing 狀態")
	if not landed:
		return not has_failures()

	# landing 狀態應在 ~1 秒內自動完成
	var completed: bool = await wait_until(
		func(): return me.is_on_floor() and not me.is_landing, 240)
	check(completed, "landing 狀態應自動完成")
	check(p1.is_jumping == false, "著地後 is_jumping 應為 false")
	check(p1.fixed_velocity.y == 0, "著地後垂直速度應為 0，實為 %s" % p1.fixed_velocity.y)

	# 無水平輸入：跳躍前後 x 位移應小（純直上直下跳躍）
	check(abs(px(p1) - x0) < 5.0, "無方向輸入時跳躍 x 位移應 <5px，實為 %.1f px" % (px(p1) - x0))

	return not has_failures()
