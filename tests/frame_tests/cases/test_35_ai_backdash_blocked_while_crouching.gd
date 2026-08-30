extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 4：修復切片 3 披露的 AI backdash 守衛 bug。
##
## 背景：Movement._physics_process 裡 AI 直接觸發的衝刺有兩條分支 —— 前衝
## 早已收攏到 FighterState.can_dash（含 `not is_crouching`），但**後衝**仍用
## 一條手寫展開 `_ai_backdash_can_dash`，而那條展開**漏掉了 is_crouching**。
## 結果：AI 蹲下時仍會後衝，與前衝分支 / 人類雙擊路徑（DashHandler 內部也
## 走 can_dash）都不一致。切片 4 讓兩條 AI 路徑共用同一條 can_dash，這是切片 3
## 刻意保留、記錄在案的行為修正（ground rule #2 的例外，已披露）。
##
## 本用例用「強制 AI 承諾 backdash」的方式確定性重現：把 AI 的 committed_input
## 直接設成 backdash 並維持承諾幀數，分別在「蹲下」與「站立」兩種姿態下觀察
## is_backdashing 是否被觸發。
##   - 蹲下：backdash 必須被 can_dash 擋下（is_backdashing 保持 false）
##   - 站立（對照組）：同樣的 backdash 輸入必須正常發動（is_backdashing 變 true）
## 若守衛退回舊的漏網展開，蹲下那段就會觀察到 is_backdashing=true，用例失敗。

const OBSERVE_FRAMES: int = 30

func run() -> bool:
	await await_frames(10)
	# 用 p1 當 AI（遠離 p2，避免 emergency-block 之類的決策干擾）。
	teleport_x(p1, 300.0)
	teleport_x(p2, 900.0)
	await await_frames(5)

	p1.is_ai_controlled = true
	var ai = p1.get_node_or_null("AIBehavior")
	check(ai != null, "p1 應有 AIBehavior 節點才能驅動 AI 輸入")
	if ai != null:
		ai.ai_enabled = true

	# ── 階段 A：蹲下時，AI 承諾 backdash 不應發動後衝 ──
	# p1 是 AI，is_crouching 來自 AI input dict 的 crouch_pressed（不是人類的
	# InputMap action），所以蹲姿要一起放進強制的 committed_input。
	_reset_dash_state(p1)
	_force_ai_backdash(ai, true)
	await await_frames(3)  # 讓 is_crouching 穩定為 true
	check(bool(p1.is_crouching), "階段 A 前置：p1 應處於蹲下狀態")

	var backdashed_while_crouching: bool = false
	for f in OBSERVE_FRAMES:
		# 每幀重新強制承諾，避免承諾幀數倒數 / 決策層覆寫掉 backdash。
		_force_ai_backdash(ai, true)
		await await_frames(1)
		if bool(p1.is_backdashing):
			backdashed_while_crouching = true
	check(not backdashed_while_crouching,
		"蹲下時 AI backdash 必須被 can_dash 擋下（舊守衛漏 is_crouching 會在這裡誤發後衝）")

	# ── 階段 B（對照組）：站立時，同樣的 backdash 輸入必須正常發動 ──
	_reset_dash_state(p1)
	_force_ai_backdash(ai, false)
	await await_frames(5)
	check(not bool(p1.is_crouching), "階段 B 前置：p1 應已站起")

	var backdashed_while_standing: bool = false
	for f in OBSERVE_FRAMES:
		_force_ai_backdash(ai, false)
		await await_frames(1)
		if bool(p1.is_backdashing):
			backdashed_while_standing = true
	check(backdashed_while_standing,
		"站立時 AI backdash 必須正常發動（證明輸入注入有效，守衛不是永遠 false）")

	# 收尾：把 AI 控制權還原，避免影響後續用例（world 會整個釋放，這裡保險起見）。
	p1.is_ai_controlled = false
	if ai != null:
		ai.ai_enabled = false
		ai.commitment_frames = 0

	return not has_failures()

## 直接把 AI 的承諾輸入設成「後衝」（並依 crouch 參數帶蹲姿），補滿承諾幀數，
## 讓 get_ai_input() 在 Layer 1（ACTION COMMITMENT）穩定回傳這份輸入。
func _force_ai_backdash(ai: Node, crouch: bool) -> void:
	if ai == null:
		return
	ai.current_committed_action = "backdash"
	ai.commitment_frames = 60
	ai.commitment_one_time_sent = false
	ai.committed_input = {
		"backdash_pressed": true,
		"dash_pressed": false,
		"input_dir": 0,
		"crouch_pressed": crouch,
		"jump_pressed": false,
	}
	# 清掉當幀快取，確保下一次 get_ai_input() 重算會看到我們強制的承諾。
	ai._cached_input_frame = -1

func _reset_dash_state(fighter: Node) -> void:
	fighter.is_backdashing = false
	fighter.is_dashing = false
	fighter.dash_timer = 0
	fighter.fixed_velocity = Vector2i.ZERO
