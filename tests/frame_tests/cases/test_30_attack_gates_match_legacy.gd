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

const FRAMES: int = 600
const SEED: int = 20260830

func run() -> bool:
	await await_frames(10)
	# 距離拉近，讓攻擊/受擊/格擋/摔投真的出現在樣本裡
	teleport_x(p1, 520.0)
	teleport_x(p2, 680.0)
	await await_frames(5)

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

	var ground_mismatch: Array = []
	var air_mismatch: Array = []
	var throw_mismatch: Array = []
	var ground_true: int = 0
	var air_true: int = 0
	var throw_true: int = 0

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

		for fighter in [p1, p2]:
			# ── 對照組 1：地面出招守衛（player.gd 舊 is_valid_ground_state）──
			var legacy_ground: bool = fighter.is_on_floor() \
					and not fighter.is_dashing and not fighter.is_backdashing \
					and not fighter.is_jumping and not fighter.is_blocking \
					and not fighter.is_knockfly and not fighter.is_wakeup \
					and not fighter.is_layground \
					and not (fighter.is_landing \
						and fighter.landing_lock_frames > Movement.LANDING_INTERRUPT_FRAMES)
			var new_ground: bool = FighterState.can_start_ground_attack(fighter)
			if legacy_ground:
				ground_true += 1
			if legacy_ground != new_ground and ground_mismatch.size() < 8:
				ground_mismatch.append("frame %d %s: legacy=%s new=%s (landing=%s lock=%d)" % [
					frame, fighter.name, legacy_ground, new_ground,
					fighter.is_landing, int(fighter.landing_lock_frames)])

			# ── 對照組 2：空中出招守衛（player.gd 舊 is_valid_air_state）──
			var legacy_air: bool = not fighter.is_on_floor() and fighter.is_jumping \
					and not fighter.is_air_attacking and not fighter.is_blocking \
					and not fighter.is_knockfly and not fighter.is_hit \
					and not fighter.is_wakeup and not fighter.has_air_attacked \
					and not fighter.is_layground
			var new_air: bool = FighterState.can_start_air_attack(fighter)
			if legacy_air:
				air_true += 1
			if legacy_air != new_air and air_mismatch.size() < 8:
				air_mismatch.append("frame %d %s: legacy=%s new=%s" % [
					frame, fighter.name, legacy_air, new_air])

			# ── 對照組 3：攻擊方是否正在摔投 ──
			var legacy_throw: bool = bool(fighter.is_attacking) \
					and (str(fighter.attack_type) == "throw_enter" \
						or str(fighter.attack_type) == "throw_seq")
			var new_throw: bool = FighterState.is_throw_in_progress(fighter)
			if legacy_throw:
				throw_true += 1
			if legacy_throw != new_throw and throw_mismatch.size() < 8:
				throw_mismatch.append("frame %d %s: legacy=%s new=%s (attack_type='%s')" % [
					frame, fighter.name, legacy_throw, new_throw, fighter.attack_type])

	for action in held.keys():
		Input.action_release(action)

	check(ground_mismatch.is_empty(),
		"地面出招守衛與舊表達式分岔：%s" % " | ".join(ground_mismatch))
	check(air_mismatch.is_empty(),
		"空中出招守衛與舊表達式分岔：%s" % " | ".join(air_mismatch))
	check(throw_mismatch.is_empty(),
		"摔投判定與舊表達式分岔：%s" % " | ".join(throw_mismatch))

	# 覆蓋度：比對樣本必須真的包含三種守衛各自為真的幀，
	# 否則「全部相等」可能只是因為兩邊永遠都是 false。
	print("      守衛覆蓋: ground=%d 幀, air=%d 幀, throw=%d 幀（共 %d 幀 ×2 角色）"
		% [ground_true, air_true, throw_true, FRAMES])
	check(ground_true > 0, "600 幀內地面出招守衛應至少為真一次（否則比對無意義）")
	check(air_true > 0, "600 幀內空中出招守衛應至少為真一次（否則比對無意義）")

	return not has_failures()
