extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 2：出招守衛的唯一定義（FighterState）必須與**它取代的
## 舊旗標表達式**逐幀等價。
##
## 為什麼需要這個用例：
## 切片 2 把「現在能不能出招」從三份抄本收攏成 FighterState 的兩個函式
## （can_start_ground_attack / can_start_air_attack），並把
## 「攻擊方是否正在摔投」收攏成 is_throw_in_progress。收攏的價值只在於
## 「等價」—— 只要有一項旗標抄漏或多抄，某個狀態下的攻擊就會意外可用或
## 不可用，而這種偏差用肉眼看不出來。
##
## 所以本用例把舊表達式**原樣重寫在這裡**當對照組，每幀比對兩者。
## 這樣做同時釘住兩件事：
##   1. 收攏當下沒有抄錯（第一次跑就是驗收）。
##   2. 之後任何人改 FighterState 的守衛而沒改對照組（或反過來）會立刻失敗，
##      就像 test_26 釘住「狀態層 vs 動畫層」一樣。
##
## 對照組刻意保留舊寫法（一長串 and/not），不要「順手優化」成呼叫 FighterState，
## 否則這個用例會變成自己跟自己比。
##
## Stage 2 切片 8：`is_wakeup` 已刪除（WAKEUP 的唯一權威改為 `wakeup_timer > 0`），
## 所以對照組裡原本的 `not fighter.is_wakeup` 改寫成
## `not (int(fighter.wakeup_timer) > 0)` —— 同一語意的摺疊後寫法，
## **不是**呼叫 FighterState，對照組依然獨立。
##
## 覆蓋度的來源（2026-09-04）：空中守衛要求「在空中 + is_jumping + 尚未
## 空中出招」。隨機輸入曾經能滿足它，但 dash 承諾（PR #57）與空中重置
## （PR #59/#61）上線後，隨機按鍵幾乎總是在離地同一幀就帶著攻擊鍵，
## has_air_attacked 立刻為真，600 幀內 true 側一次都不出現 —— 用例因此
## 只掛在**覆蓋度**斷言、而不是等價性上（main 上觀察到的就是這種紅）。
## 處理方式與 test_34 / test_36 相同：加一段確定性樣本（只按跳躍鍵），
## 而不是放寬斷言。

const FRAMES: int = 600
const SEED: int = 20260830

# 覆蓋度與分岔記錄（階段 0 與隨機階段共用，_sample() 累積）
var _ground_mismatch: Array = []
var _air_mismatch: Array = []
var _throw_mismatch: Array = []
var _ground_true: int = 0
var _air_true: int = 0
var _throw_true: int = 0
var _samples: int = 0

func run() -> bool:
	await await_frames(10)
	# 距離拉近，讓攻擊/受擊/格擋/摔投真的出現在樣本裡
	teleport_x(p1, 520.0)
	teleport_x(p2, 680.0)
	await await_frames(5)

	# ── 階段 0（確定性）：只按跳躍鍵、不按任何攻擊鍵 ──────────────────
	# 空中出招守衛的 true 側需要「在空中 + is_jumping + 尚未空中出招」；
	# 隨機輸入現在給不出這個樣本（見檔頭說明），所以這裡用一次純跳躍
	# 確定性餵進去。等價性比對照跑，樣本照樣進 _sample()。
	Input.action_press("jump")
	Input.action_press("jump_p2")
	await await_frames(2)
	Input.action_release("jump")
	Input.action_release("jump_p2")
	var airborne_seen: bool = false
	for i in 150:
		await await_frames(1)
		_sample(p1, "phase0-%d" % i)
		_sample(p2, "phase0-%d" % i)
		if bool(p1.is_jumping) and not p1.is_on_floor():
			airborne_seen = true
		if airborne_seen and p1.is_on_floor() and p2.is_on_floor() \
				and not p1.is_landing and not p2.is_landing:
			break
	check(airborne_seen, "階段 0：只按跳躍鍵應讓 P1 真的離地（空中守衛樣本的來源）")

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var actions: Array = [
		"move_left", "move_right", "jump", "crouch",
		"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
		"spmove1", "spmove2", "spmove3",
	]
	var p2_actions: Array = [
		"move_left_p2", "move_right_p2", "jump_p2", "crouch_p2",
		"st_lp_p2", "st_mp_p2", "st_hp_p2", "st_lk_p2", "st_mk_p2", "st_hk_p2",
	]
	var held: Dictionary = {}

	for frame in FRAMES:
		if frame % 5 == 0:
			for action in held.keys():
				Input.action_release(action)
			held.clear()
			var n: int = rng.randi_range(0, 3)
			for i in n:
				var a: String = actions[rng.randi_range(0, actions.size() - 1)]
				if not held.has(a):
					Input.action_press(a)
					held[a] = true
			var b: String = p2_actions[rng.randi_range(0, p2_actions.size() - 1)]
			if not held.has(b):
				Input.action_press(b)
				held[b] = true

		await await_frames(1)

		_sample(p1, frame)
		_sample(p2, frame)

	for action in held.keys():
		Input.action_release(action)

	check(_ground_mismatch.is_empty(),
		"地面出招守衛與舊表達式分岔：%s" % " | ".join(_ground_mismatch))
	check(_air_mismatch.is_empty(),
		"空中出招守衛與舊表達式分岔：%s" % " | ".join(_air_mismatch))
	check(_throw_mismatch.is_empty(),
		"摔投判定與舊表達式分岔：%s" % " | ".join(_throw_mismatch))

	# 覆蓋度：比對樣本必須真的包含三種守衛各自為真的幀，
	# 否則「全部相等」可能只是因為兩邊永遠都是 false。
	print("      守衛覆蓋: ground=%d 幀, air=%d 幀, throw=%d 幀（共 %d 個樣本："
		% [_ground_true, _air_true, _throw_true, _samples])
	print("                階段 0 確定性跳躍 + 600 幀隨機輸入 ×2 角色）")
	check(_ground_true > 0, "樣本內地面出招守衛應至少為真一次（否則比對無意義）")
	check(_air_true > 0, "樣本內空中出招守衛應至少為真一次（階段 0 確定性跳躍提供）")

	return not has_failures()

## 逐幀比對：舊表達式（原樣搬運）vs FighterState，並累積覆蓋度計數。
## 對照組直接讀旗標、**不**呼叫 FighterState —— 否則用例會變成自己跟自己比。
## 階段 0（確定性跳躍）與隨機階段共用這一份，避免同一條舊表達式有兩份抄本。
func _sample(fighter: Node, frame) -> void:
	_samples += 1

	# ── 對照組 1：地面出招守衛（player.gd 舊 is_valid_ground_state）──
	var legacy_ground: bool = fighter.is_on_floor() \
			and not fighter.is_dashing and not fighter.is_backdashing \
			and not fighter.is_jumping and not fighter.is_blocking \
			and not fighter.is_knockfly and not (int(fighter.wakeup_timer) > 0) \
			and not fighter.is_layground \
			and not (fighter.is_landing \
				and fighter.landing_lock_frames > Movement.LANDING_INTERRUPT_FRAMES)
	var new_ground: bool = FighterState.can_start_ground_attack(fighter)
	if legacy_ground:
		_ground_true += 1
	if legacy_ground != new_ground and _ground_mismatch.size() < 8:
		_ground_mismatch.append("frame %s %s: legacy=%s new=%s (landing=%s lock=%d)" % [
			frame, fighter.name, legacy_ground, new_ground,
			fighter.is_landing, int(fighter.landing_lock_frames)])

	# ── 對照組 2：空中出招守衛（player.gd 舊 is_valid_air_state）──
	var legacy_air: bool = not fighter.is_on_floor() and fighter.is_jumping \
			and not fighter.is_air_attacking and not fighter.is_blocking \
			and not fighter.is_knockfly and not fighter.is_hit \
			and not (int(fighter.wakeup_timer) > 0) and not fighter.has_air_attacked \
			and not fighter.is_layground
	var new_air: bool = FighterState.can_start_air_attack(fighter)
	if legacy_air:
		_air_true += 1
	if legacy_air != new_air and _air_mismatch.size() < 8:
		_air_mismatch.append("frame %s %s: legacy=%s new=%s (jumping=%s air_atk=%s has_air_attacked=%s)" % [
			frame, fighter.name, legacy_air, new_air,
			bool(fighter.is_jumping), bool(fighter.is_air_attacked),
			bool(fighter.has_air_attacked)])

	# ── 對照組 3：攻擊方是否正在摔投 ──
	var legacy_throw: bool = bool(fighter.is_attacking) \
			and (str(fighter.attack_type) == "throw_enter" \
				or str(fighter.attack_type) == "throw_seq")
	var new_throw: bool = FighterState.is_throw_in_progress(fighter)
	if legacy_throw:
		_throw_true += 1
	if legacy_throw != new_throw and _throw_mismatch.size() < 8:
		_throw_mismatch.append("frame %s %s: legacy=%s new=%s (attack_type='%s')" % [
			frame, fighter.name, legacy_throw, new_throw, str(fighter.attack_type)])
