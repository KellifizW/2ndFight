extends FrameTestCase
## 格擋判定：P2 持續按「後」（move_right_p2，因為 P2 面向左）時被 P1 st_mp 命中
##
## 期望:
##   - P2 進入 blockstun（blockstun_frames = 16 邏輯幀 = 32 物理幀）
##   - P2 血量不減（格擋成功）
##   - blockstun 結束後恢復

func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	# P2 按住後 → BlockingHandler 設定 is_holding_back
	Input.action_press("move_right_p2")
	await await_frames(10)
	check(p2.is_holding_back == true, "P2 按住後應該 is_holding_back=true")

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var saw_blockstun_32: bool = false
	var saw_hit_damage: bool = false
	for i in 300:
		await await_frames(1)
		if p2.blockstun_frames == 32:
			saw_blockstun_32 = true
		if p2.healthbar and p2.healthbar.current_health < 100.0:
			saw_hit_damage = true
		if saw_blockstun_32 and p2.blockstun_frames < 32:
			break

	check(saw_blockstun_32, "P2 應進入 blockstun（blockstun_frames=32 = 16 邏輯幀 × 2）")
	check(saw_hit_damage == false, "格擋成功不應扣血")
	check(p2.healthbar != null and p2.healthbar.current_health == 100.0,
		"P2 血量應保持 100，實為 %s" % (p2.healthbar.current_health if p2.healthbar else "N/A"))
	check(p2.is_hit == false, "格擋時 P2 不應進入 hitstun 狀態")

	# 恢復
	var check_recovered := func():
		var t = p2
		return t.blockstun_frames == 0 and not t.is_blocking
	var recovered: bool = await wait_until(check_recovered, 900)
	Input.action_release("move_right_p2")
	check(recovered, "P2 應從 blockstun 恢復")

	return not has_failures()
