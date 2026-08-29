extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 2：攻擊狀態必須「成對」出現 —— `is_attacking` 為真時
## `attack_type` 必須是一個合法攻擊 id，不能停在 "none"。
##
## 為什麼需要這個用例：
## 切片 2 之前攻擊子系統有**兩個**入口。除了 AttackExecutor 這條設計路徑，
## `fighter.gd` 還留著一段重構前的舊檢查（`st_mp_pressed or st_mk_pressed`
## → `is_attacking = true`），它不設 attack_type、不走按鈕優先序、不消耗輸入
## buffer，守衛條件也跟 AttackExecutor 那份不一樣。於是它能在 AttackExecutor
## **沒有**出招的幀把 is_attacking 設成 true，留下「在出招但不知道出哪一招」
## 的孤兒狀態：動畫層把它當 "Walk" 播、MoveSet 拒絕開新招、跳躍與衝刺守衛
## 全部擋下，而 attack_duration_timer 仍是 0 —— 沒有任何計時器會收回來。
##
## 本用例分兩段：
##   1. **針對性重現**：無輸入著地 → 著地後第 1 個物理幀點一下 st_mp。
##      那正是舊入口唯一穩定可達的窗口（landing_lock_frames=5→4、
##      _landing_forced_frames=1 < 2，著地攻擊取消還不能觸發）。
##      斷言：整個過程中不出現孤兒狀態，且那一下輸入**仍然**要出招
##      （移除舊入口不能吃掉玩家的輸入）。
##   2. **隨機壓力**：固定種子 600 幀亂按，每幀檢查
##      `FighterState.check_invariants()`（含新增的「攻擊必須成對」）全綠，
##      並印出實際走過的攻擊分佈，證明這段不是在測「站著不動」。
##
## 隨機輸入用固定種子（seed=20260829），失敗可重現（守則第 6 條）。

const FRAMES: int = 600
const SEED: int = 20260829

func run() -> bool:
	await await_frames(10)
	teleport_x(p1, 520.0)
	teleport_x(p2, 680.0)
	await await_frames(2)

	var orphan_frames: Array = []
	var invariant_failures: Array = []
	var seen_attacks: Dictionary = {}
	var attack_frames: int = 0

	# ── 1. 針對性重現：著地後第 1 幀的攻擊輸入 ────────────────────────
	await tap("jump")
	var me = p1
	var left_ground: bool = await wait_until(
		func(): return not me.is_on_floor(), 120)
	check(left_ground, "P1 應該起跳離地（否則測不到著地窗口）")

	# 著地瞬間刻意**不**給任何輸入 → 走完整 landing 鎖（5 幀強制 + checkpoint）。
	# 若著地當下就有輸入，LandingHandler 會直接跳過 landing 狀態，窗口就不存在。
	var landed: bool = await wait_until(
		func(): return me.is_on_floor(), 360)
	check(landed, "P1 應該著地")

	if landed:
		# 這一幀是著地幀 N：is_landing=true、landing_lock_frames=5、
		# _landing_forced_frames=0。下一幀（N+1）handle_timers 會把 forced 推到 1、
		# lock 推到 4 —— 那是唯一「lock>1 但著地攻擊取消還不能觸發（需 forced>=2）」
		# 的幀，也就是舊攻擊入口唯一穩定可達的窗口。
		#
		# 為什麼直接寫 buffer 而不是只按鍵：PlayerController 是 Player 的**子**節點，
		# 子節點的 _physics_process 在父節點之後跑，所以「這一幀按下的鍵」要到
		# 下一幀才進得了 buffer，會整整錯開一個物理幀、剛好錯過窗口。
		# 直接把按鍵塞進 buffer，才能讓 N+1 幀的 get_input() 讀得到它。
		Input.action_press("st_mp")
		var controller: Node = me.get_node_or_null("PlayerController")
		if controller != null and controller.input_buffer != null:
			controller.input_buffer.record_input("st_mp")

		# 接下來 30 幀逐幀取樣：舊入口會在 N+1 幀留下孤兒攻擊狀態。
		for i in 30:
			await await_frames(1)
			_scan(p1, i, orphan_frames, invariant_failures, seen_attacks)
		Input.action_release("st_mp")

		# 移除舊入口不能吃掉玩家輸入：那一下按鍵仍然要出招
		# （buffer 保留 30 物理幀，N+2 幀的 landing checkpoint 會中斷著地）。
		var mp_seen: bool = seen_attacks.has("st_mp")
		check(mp_seen,
			"著地後第 1 幀的 st_mp 仍須出招（移除舊入口不能吃掉輸入）；實際走過的攻擊: %s"
			% ", ".join(seen_attacks.keys()))
		await await_frames(20)

	# ── 2. 隨機壓力：600 幀亂按，每幀檢查不變式 ───────────────────────
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
		# 每 4 幀換一次輸入組合（比 test_25 的 6 幀更密，
		# 更容易撞到「動畫剛結束 + 按鍵還在 buffer」這類邊界）。
		if frame % 4 == 0:
			for action in held.keys():
				Input.action_release(action)
			held.clear()
			var n: int = rng.randi_range(0, 2)
			for i in n:
				var a: String = actions[rng.randi_range(0, actions.size() - 1)]
				if not held.has(a):
					Input.action_press(a)
					held[a] = true
			if rng.randf() < 0.5:
				var b: String = p2_actions[rng.randi_range(0, p2_actions.size() - 1)]
				if not held.has(b):
					Input.action_press(b)
					held[b] = true

		await await_frames(1)
		_scan(p1, frame, orphan_frames, invariant_failures, seen_attacks)
		_scan(p2, frame, orphan_frames, invariant_failures, seen_attacks)
		if bool(p1.is_attacking):
			attack_frames += 1
		if bool(p2.is_attacking):
			attack_frames += 1

	for action in held.keys():
		Input.action_release(action)

	check(orphan_frames.is_empty(),
		"出現孤兒攻擊狀態（is_attacking 為真但 attack_type 非法）：%s"
		% " | ".join(orphan_frames))
	check(invariant_failures.is_empty(),
		"FighterState.check_invariants 違反：%s" % " | ".join(invariant_failures))

	# 覆蓋度：600 幀亂按至少應該走過 3 種不同攻擊，
	# 否則「不變式全綠」只是因為根本沒出招。
	var names: Array = []
	for atype in seen_attacks.keys():
		names.append("%s×%d" % [atype, seen_attacks[atype]])
	names.sort()
	print("      攻擊分佈: %s（is_attacking 共 %d 幀）" % [", ".join(names), attack_frames])
	check(seen_attacks.size() >= 3,
		"600 幀隨機輸入應至少走過 3 種攻擊，實際 %d 種（%s）"
		% [seen_attacks.size(), ", ".join(names)])

	return not has_failures()

## 取樣一個 fighter：孤兒攻擊 + 全部結構性不變式 + 攻擊分佈統計。
func _scan(fighter: Node, frame: int, orphan_frames: Array,
		invariant_failures: Array, seen_attacks: Dictionary) -> void:
	var is_att: bool = bool(fighter.is_attacking)
	if not is_att:
		return
	var atype: String = str(fighter.attack_type)
	seen_attacks[atype] = int(seen_attacks.get(atype, 0)) + 1
	if not FighterState.is_attack_id(atype):
		if orphan_frames.size() < 8:
			orphan_frames.append("frame %d %s: attack_type='%s'"
				% [frame, fighter.name, atype])
	var broken: Array = FighterState.check_invariants(fighter)
	if not broken.is_empty() and invariant_failures.size() < 8:
		invariant_failures.append("frame %d %s: %s"
			% [frame, fighter.name, ", ".join(broken)])
