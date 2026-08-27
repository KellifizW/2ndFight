extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 安全網：顯式狀態層的「恰好一個活動狀態」與旗標互斥不變式。
##
## plan_game.md §6 要求的 `test_13_state_machine_invariants`（隨機輸入 600 幀，
## 每幀斷言恰好一個狀態活動 + 轉換合法性）。編號改為 25 是因為 13 已被
## Stage 1 的 combo 用例佔用。
##
## 這一刀的狀態層是**唯讀解析器**（FighterState.resolve），控制流仍讀旗標。
## 因此本用例真正的價值有兩個：
##   1. 釘住優先序表：resolve() 必須永遠回傳單一狀態（enum 天然保證），
##      且對每一組旗標組合都有定義（不會落到「沒有任何分支」的縫隙）。
##   2. 釘住**結構性互斥**：is_dashing/is_backdashing 不得同時為真、
##      knockfly/layground 不得同時為真、is_landing 必須伴隨 lock 幀…
##      這些以前只是註解裡的約定，現在每幀被檢查。
##
## 隨機輸入用固定種子（seed=20260827），失敗可重現 —— 這是守則第 6 條
## 「先確定性重現再修」的前提。

const FRAMES: int = 600
const SEED: int = 20260827

func run() -> bool:
	await await_frames(10)
	teleport_x(p1, 500.0)
	teleport_x(p2, 700.0)
	await await_frames(2)

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

	# 觀測到的狀態分布：用來證明這 600 幀真的走過多種狀態，
	# 而不是站著不動白跑一趟（否則不變式全綠也沒有意義）。
	var seen: Dictionary = {}
	var invariant_failures: Array = []
	var resolve_failures: Array = []

	for frame in FRAMES:
		# 每 6 幀換一次輸入組合（約 3 邏輯幀，接近人類連打上限）
		if frame % 6 == 0:
			for action in held.keys():
				Input.action_release(action)
			held.clear()
			var n: int = rng.randi_range(0, 2)
			for i in n:
				var a: String = actions[rng.randi_range(0, actions.size() - 1)]
				if not held.has(a):
					Input.action_press(a)
					held[a] = true
			# 讓 P2 也動起來，才能產生受擊/格擋/連段狀態
			if rng.randf() < 0.5:
				var b: String = p2_actions[rng.randi_range(0, p2_actions.size() - 1)]
				if not held.has(b):
					Input.action_press(b)
					held[b] = true

		await await_frames(1)

		for fighter in [p1, p2]:
			var state: int = fighter.get_fighter_state()
			seen[state] = int(seen.get(state, 0)) + 1

			# enum 保證單一值；這裡確認它落在已定義範圍內（沒有落入未定義縫隙）
			if state < 0 or state > FighterState.State.KO:
				resolve_failures.append("frame %d: resolve() 回傳未定義狀態 %d" % [frame, state])

			# 解析器必須是純函數：同一幀連呼兩次結果一致（不得有隱藏副作用）
			if fighter.get_fighter_state() != state:
				resolve_failures.append("frame %d: resolve() 非純函數（同幀兩次結果不同）" % frame)

			var broken: Array = FighterState.check_invariants(fighter)
			if not broken.is_empty() and invariant_failures.size() < 8:
				invariant_failures.append("frame %d %s: %s" % [
					frame, fighter.name, ", ".join(broken)])

	for action in held.keys():
		Input.action_release(action)

	check(resolve_failures.is_empty(),
		"狀態解析器不變式違反：%s" % ", ".join(resolve_failures))
	check(invariant_failures.is_empty(),
		"旗標互斥不變式違反：%s" % " | ".join(invariant_failures))

	# 覆蓋度：600 幀隨機輸入至少應該走過 4 種不同狀態，
	# 否則這個用例只是在測「站著不動」。
	var names: Array = []
	for state in seen.keys():
		names.append("%s×%d" % [FighterState.state_name(state), seen[state]])
	names.sort()
	print("      狀態分布: %s" % ", ".join(names))
	check(seen.size() >= 4,
		"600 幀隨機輸入應至少覆蓋 4 種狀態，實際只有 %d 種（%s）" % [
			seen.size(), ", ".join(names)])

	return not has_failures()
