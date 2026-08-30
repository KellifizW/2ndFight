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
## 這個用例直接測 Movement 的 AI dash 分支：把 p1 設為 AI 控制，讓它走真實的
## AIBehavior 承諾路徑（敵人放極遠 → emergency-block / 威脅評估都不會中斷承諾），
## 並把承諾輸入強制成 backdash（蹲姿經 AI input dict 的 crouch_pressed 帶入 ——
## AI 的 is_crouching 來自那裡，不是人類的 InputMap）。每個物理幀觀察
## is_backdashing：
##   - 蹲下：後衝必須被 can_dash 擋下（is_backdashing 維持 false）
##   - 站立（對照組）：同樣的 backdash 輸入必須正常發動
## 若守衛退回舊的漏網展開，蹲下那段就會觀察到 is_backdashing=true，用例失敗。

const OBSERVE_FRAMES: int = 20

func run() -> bool:
	await await_frames(10)
	# p1 用 AI 路徑；p2 放到極遠並保持中性，確保 AI 的 emergency-block 與
	# 威脅評估（MEDIUM 以上會清掉 dash 承諾）都不會觸發，承諾輸入穩定生效。
	teleport_x(p1, 300.0)
	teleport_x(p2, 4000.0)
	await await_frames(5)

	var ai = p1.get_node_or_null("AIBehavior")
	check(ai != null, "p1 應有 AIBehavior 節點才能驅動 AI 輸入")
	p1.is_ai_controlled = true
	if ai != null:
		ai.ai_enabled = true
		# AIBehavior 在 ai_enabled 首次為 true 時才建立子系統；直接確保對手引用。
		if "opponent" in ai:
			ai.opponent = p2

	# ── 階段 A：蹲下時，AI backdash 不應發動後衝 ──
	_force_commitment(ai, true)
	await await_frames(3)  # 讓 is_crouching 穩定為 true
	check(bool(p1.is_crouching), "階段 A 前置：p1 應處於蹲下狀態（is_crouching=true）")

	var backdashed_while_crouching: bool = false
	for f in OBSERVE_FRAMES:
		_force_commitment(ai, true)
		await await_frames(1)
		if bool(p1.is_backdashing):
			backdashed_while_crouching = true
	check(not backdashed_while_crouching,
		"蹲下時 AI backdash 必須被 can_dash 擋下（舊守衛漏 is_crouching 會在這裡誤發後衝）")

	# ── 階段 B（對照組）：站立時，同樣的 backdash 輸入必須正常發動 ──
	p1.is_backdashing = false
	p1.is_dashing = false
	p1.dash_timer = 0
	p1.fixed_velocity = Vector2i.ZERO
	_force_commitment(ai, false)
	await await_frames(3)
	check(not bool(p1.is_crouching), "階段 B 前置：p1 應已站起（is_crouching=false）")

	var backdashed_while_standing: bool = false
	for f in OBSERVE_FRAMES:
		_force_commitment(ai, false)
		await await_frames(1)
		if bool(p1.is_backdashing):
			backdashed_while_standing = true
	check(backdashed_while_standing,
		"站立時 AI backdash 必須正常發動（證明承諾輸入有走到 Movement，守衛不是永遠 false）")

	# 收尾：還原為人類控制（world 會整個釋放，這裡保險起見）。
	p1.is_ai_controlled = false
	if ai != null:
		ai.ai_enabled = false
		ai.commitment_frames = 0
	return not has_failures()

## 把 AI 的承諾輸入強制為 backdash，crouch 決定是否同時帶蹲姿，並補滿承諾幀數、
## 清掉當幀快取，讓 get_ai_input() 在 Layer 1（ACTION COMMITMENT）穩定回傳這份輸入。
## backdash 在 AI 邏輯裡屬「持續方向型」動作（非 throw 單次、非 special），承諾期間
## 每幀原樣回傳 committed_input。
func _force_commitment(ai: Node, crouch: bool) -> void:
	if ai == null:
		return
	ai.current_committed_action = "backdash"
	ai.commitment_frames = 100000
	ai.commitment_one_time_sent = false
	ai.committed_input = {
		"input_dir": 0,
		"crouch_pressed": crouch,
		"jump_pressed": false,
		"st_lp_pressed": false, "st_mp_pressed": false, "st_hp_pressed": false,
		"st_lk_pressed": false, "st_mk_pressed": false, "st_hk_pressed": false,
		"spm1_pressed": false, "spm2_pressed": false, "dp_pressed": false,
		"super_pressed": false,
		"dash_pressed": false,
		"backdash_pressed": true,
		"throw_pressed": false,
		"attack_type": "none",
	}
	ai._cached_input_frame = -1
