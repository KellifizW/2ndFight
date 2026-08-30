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
## 這個用例直接測 Movement 的 AI dash 分支：Player.get_input() 在
## is_ai_controlled=true 時會呼叫 AIBehavior 節點的 get_ai_input() 並 merge。
## 我們掛一個**測試替身** AIBehavior（腳本只回傳我們控制的 input dict），
## 繞過真實決策層的承諾/威脅評估干擾，確保 backdash_pressed 穩定送到 Movement。
## 每個物理幀觀察 is_backdashing：
##   - 蹲下（crouch_pressed=true → is_crouching=true）：後衝必須被 can_dash 擋下
##   - 站立（對照組）：同樣的 backdash 輸入必須正常發動
## 若守衛退回舊的漏網展開，蹲下那段就會觀察到 is_backdashing=true，用例失敗。

const OBSERVE_FRAMES: int = 20

class _StubAIBehavior extends Node:
	## 測試替身：只回傳一份固定 input dict，由測試每幀設定。
	var next_input: Dictionary = {}
	func get_ai_input() -> Dictionary:
		return next_input.duplicate(true)

var _stub: Node = null
var _real_ai: Node = null

func run() -> bool:
	await await_frames(10)
	# p1 用 AI 路徑；p2 放遠保持中性，避免任何互動干擾。
	teleport_x(p1, 300.0)
	teleport_x(p2, 4000.0)
	await await_frames(5)

	_install_stub(p1)
	p1.is_ai_controlled = true

	# ── 階段 A：蹲下時，AI backdash 不應發動後衝 ──
	_set_stub_input(true)
	await await_frames(3)  # 讓 is_crouching 穩定為 true
	check(bool(p1.is_crouching), "階段 A 前置：p1 應處於蹲下狀態（is_crouching=true）")

	var backdashed_while_crouching: bool = false
	for f in OBSERVE_FRAMES:
		_set_stub_input(true)
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
	_set_stub_input(false)
	await await_frames(3)
	check(not bool(p1.is_crouching), "階段 B 前置：p1 應已站起（is_crouching=false）")

	var backdashed_while_standing: bool = false
	for f in OBSERVE_FRAMES:
		_set_stub_input(false)
		await await_frames(1)
		if bool(p1.is_backdashing):
			backdashed_while_standing = true
	check(backdashed_while_standing,
		"站立時 AI backdash 必須正常發動（證明輸入有送到 Movement，守衛不是永遠 false）")

	# 收尾：還原為人類控制並移除替身（world 會整個釋放，這裡保險起見）。
	p1.is_ai_controlled = false
	if _stub != null and is_instance_valid(_stub):
		_stub.queue_free()
	return not has_failures()

## 把 p1 的 AIBehavior 換成測試替身（Player.get_input() 以 get_node_or_null
## ("AIBehavior") 找節點，名字必須是 AIBehavior）。
func _install_stub(fighter: Node) -> void:
	_real_ai = fighter.get_node_or_null("AIBehavior")
	if _real_ai != null:
		_real_ai.set_process(false)
		_real_ai.set_physics_process(false)
		# 暫時把真 AIBehavior 改名，讓替身佔用 "AIBehavior" 這個名字。
		_real_ai.name = "AIBehavior_real"
	_stub = _StubAIBehavior.new()
	_stub.name = "AIBehavior"
	fighter.add_child(_stub)

## 設定替身這一幀回傳的輸入：帶 backdash_pressed，crouch 決定是否蹲姿。
## AI 的 is_crouching 來自 input dict 的 crouch_pressed（不是人類 InputMap）。
func _set_stub_input(crouch: bool) -> void:
	if _stub == null:
		return
	_stub.next_input = {
		"input_dir": 0,
		"crouch_pressed": crouch,
		"jump_pressed": false,
		"st_lp_pressed": false, "st_mp_pressed": false, "st_hp_pressed": false,
		"st_lk_pressed": false, "st_mk_pressed": false, "st_hk_pressed": false,
		"spm1_pressed": false, "spm2_pressed": false, "spm3_pressed": false,
		"dp_pressed": false, "super_pressed": false,
		"block_pressed": false,
		"dash_pressed": false,
		"backdash_pressed": true,
		"throw_pressed": false,
	}
