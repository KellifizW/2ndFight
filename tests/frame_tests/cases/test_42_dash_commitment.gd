extends "res://tests/frame_tests/frame_test_case.gd"
## 【衝刺承諾（dash commitment）】dash / backdash 視同普通攻擊：發動後必須
## 跑完全程，期間不得執行任何其他動作 —— 移動、普通攻擊、特殊招式、摔投、
## 跳躍，也不能觸發格擋（含受擊瞬間的格擋判定）。
##
## 本用例釘住四件事：
##   1. 前衝期間所有行動守衛（attack / jump / walk / dash / block stance /
##      throw）一律回 false，普通攻擊輸入不會在衝刺中開招。
##   2. 前衝期間直呼 MoveSet.start_fireball()（TouchControls 同路徑）
##      不得開特殊招式（_start_special 的衝刺守衛）。
##   3. 後撤步期間格擋站姿旗標被清空（不能在衝刺中進入格擋）。
##   4. 後撤步期間即使站姿旗標殘留（發動幀的 stale is_holding_back），
##      take_hit 也不得判定為格擋 —— 必須吃 hitstun 而非 blockstun。

func run() -> bool:
	await await_frames(5)

	# ── 階段 1：雙擊前衝，衝刺期間全部行動守衛必須關閉 ──
	await tap("move_right")
	await await_frames(1)
	Input.action_press("move_right")

	var me = p1
	var dash_started: bool = await wait_until(
		func(): return me.is_dashing, 10)
	Input.action_release("move_right")
	check(dash_started, "雙擊前進應觸發前衝")
	if not dash_started:
		return not has_failures()

	# 衝刺中每一幀：守衛全關、不得開普通攻擊。
	# 同時按住攻擊鍵，確認輸入不會在衝刺中轉成招式。
	Input.action_press("st_lp")
	var sampled_frames: int = 0
	for i in 20:
		await await_frames(1)
		if not p1.is_dashing:
			break
		sampled_frames += 1
		check(not p1.is_attacking, "前衝第 %d 幀不得開普通攻擊" % i)
		check(not FighterState.can_start_ground_attack(p1), "前衝中 can_start_ground_attack 應為 false")
		check(not FighterState.can_jump(p1, true), "前衝中 can_jump 應為 false")
		check(not FighterState.can_walk(p1), "前衝中 can_walk 應為 false")
		check(not FighterState.can_dash(p1), "前衝中 can_dash 應為 false（不得再衝）")
		check(not FighterState.can_enter_block_stance(p1), "前衝中 can_enter_block_stance 應為 false")
		check(not FighterState.can_initiate_throw(p1), "前衝中 can_initiate_throw 應為 false")
	Input.action_release("st_lp")
	check(sampled_frames > 0, "應至少取樣到一幀衝刺狀態")

	# 衝刺中直呼特殊招式入口（TouchControls 直呼同路徑）必須被擋。
	if p1.is_dashing:
		var ms = p1.move_set
		check(ms != null, "P1 MoveSet 節點不存在")
		if ms != null:
			ms.start_fireball()
			check(not ms.is_spmove, "前衝中 start_fireball() 不得開特殊招式")

	# 等衝刺自然結束。衝刺中按住的 st_lp 會留在 InputBuffer（30 幀過期），
	# 衝刺結束後緩衝輸入**可以**合法開招 —— 承諾只覆蓋衝刺本身。
	var dash_ended: bool = await wait_until(
		func(): return not me.is_dashing, 60)
	check(dash_ended, "前衝應在計時器歸零後結束")

	# 先讓緩衝攻擊（若有）跑完，再驗證狀態已恢復可操作。
	var attack_cleared := func():
		var f = p1
		return not f.is_attacking
	await wait_until(attack_cleared, 300)
	await await_frames(5)
	check(FighterState.can_start_ground_attack(p1), "衝刺結束後應可再次出招")
	await await_frames(10)

	# ── 階段 2：雙擊後撤步，衝刺中不得進入 / 判定格擋 ──
	await tap("move_left")
	await await_frames(1)
	Input.action_press("move_left")

	var backdash_started: bool = await wait_until(
		func(): return me.is_backdashing, 10)
	check(backdash_started, "雙擊後退應觸發後撤步")
	if not backdash_started:
		Input.action_release("move_left")
		return not has_failures()

	# 後撤步期間持續按住後退：站姿旗標必須被清空（不能衝刺中進格擋站姿）。
	await await_frames(3)
	if p1.is_backdashing:
		check(not p1.is_holding_back, "後撤步中 is_holding_back 應被清空")
		check(not p1.is_crouch_blocking, "後撤步中 is_crouch_blocking 應被清空")
		check(not p1.is_proximity_blocking, "後撤步中 is_proximity_blocking 應被清空")

	# 後撤步期間受擊：即使站姿旗標殘留（模擬發動幀的 stale 值），
	# take_hit 也必須判定為受擊而不是格擋。
	if p1.is_backdashing:
		p1.is_holding_back = true
		p1.take_hit(18, 10, 10.0)
		check(not p1.is_blocking, "後撤步中受擊不得觸發格擋（is_blocking 應為 false）")
		check(int(p1.blockstun_frames) == 0, "後撤步中受擊 blockstun_frames 應為 0，實為 %d" % int(p1.blockstun_frames))
		check(bool(p1.is_hit), "後撤步中受擊應進入 hitstun（is_hit 應為 true）")
		check(int(p1.hitstun_frames) > 0, "後撤步中受擊 hitstun_frames 應 > 0")
	Input.action_release("move_left")

	return not has_failures()
