extends FrameTestCase
## 地面攻擊 st_mp（DAV）：
## - 按 st_mp → is_attacking + attack_type + 動畫狀態 st_mp
## - st_mp 動畫長 24 邏輯幀 = 48 物理幀 → 攻擊應在 ~48+15 物理幀內結束
## - 結束後 is_attacking=false, attack_type="none"

func run() -> bool:
	await await_frames(10)

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	# 攻擊應在 12 物理幀內開始（lambda 只能 capture 局部變數）
	var me = p1
	var started: bool = await wait_until(
		func(): return me.is_attacking and me.attack_type == "st_mp", 12)
	check(started, "st_mp 攻擊應開始（is_attacking + attack_type='st_mp'）")
	if not started:
		return not has_failures()

	var anim_state: String = p1.animation_state.get_current_node()
	check(anim_state == "st_mp", "動畫狀態應為 st_mp，實為 %s" % anim_state)

	# 48 物理幀（動畫長度）+ 15 容差後攻擊必須結束
	var finished: bool = await wait_until(
		func(): return me.is_attacking == false, 63)
	check(finished, "st_mp 應在動畫長度（48 物理幀）+ 15 容差內結束")
	check(p1.attack_type == "none", "攻擊結束後 attack_type 應為 none，實為 %s" % p1.attack_type)

	# 對面 P2 不應該受到任何影響（P2 在 500px 外）
	check(p2.healthbar != null and p2.healthbar.current_health == 100.0, "P2 不應受傷，血量 %s" % (p2.healthbar.current_health if p2.healthbar else "N/A"))
	check(p2.is_hit == false, "P2 不應進入 hitstun")

	return not has_failures()
