extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 5：格擋子系統（站姿進入 / 站姿釋放）兩組守衛的唯一定義
## （FighterState）必須與**它取代的舊旗標表達式**逐幀等價。
##
## 為什麼需要這個用例：
## 切片 5 把 BlockingHandler.handle_blocking 裡兩份內聯展開的守衛收攏成
## FighterState 的兩個函式：
##   - can_enter_block_stance   ← 進入守衛（含 attacking/dashing/backdashing/
##     spmove，**不含** is_blocking —— blockstun 期間進入分支照跑並重取樣
##     held 方向，是切片 4 finding #1 披露的預期行為）
##   - can_release_block_stance ← else 分支守衛（**含** is_blocking —— 硬直
##     期間站姿旗標保留不釋放，供進入分支重取樣）
## 兩份守衛不是同一個條件；任何一份抄漏一項或多抄一項都會造成「blockstun
## 中 held 方向卡住 / 被提早釋放」，肉眼幾乎看不出來。本用例把兩組舊表達式
## **原樣重寫在這裡**當對照組，每幀比對新舊。對照組刻意保留舊寫法，不要
## 「順手優化」成呼叫 FighterState，否則這個用例會變成自己跟自己比。
##
## 結構：
##   階段 1 —— 確定性地逼 P2 進入 blockstun（P2 按後、P1 st_mp 命中，
##     與 test_06 同樣的布景）：保證「is_blocking 與進入守衛同時為真」的
##     幀（重取樣路徑）一定出現在樣本裡，不靠隨機種子走運。
##   階段 2 —— 600 幀固定種子隨機輸入（seed=20260902），兩個角色都會真的
##     攻擊 / 受擊 / 擊飛 / 衝刺 / 蹲下，逐幀比對兩組守衛。
##
## Python 暴力窮舉（256 / 16 組合，另加 is_blocking 靈敏度掃描 512 組合）
## 已先證明 0 分岔；本用例在引擎內逐幀釘住，並要求各守衛 true/false 兩側
## 都實際出現過（避免「永遠同一邊」的假綠）。

const RANDOM_FRAMES: int = 600
const SEED: int = 20260902

var _samples: int = 0
var _enter_true: int = 0
var _release_true: int = 0
var _blocking_resample: int = 0
var _mismatches: Array = []

func run() -> bool:
	# ── 階段 1：確定性逼 P2 進入 blockstun（重取樣路徑的覆蓋度來源）──
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	Input.action_press("move_right_p2")
	await await_frames(10)
	check(p2.is_holding_back == true,
		"階段 1 前置：P2 按住後應該 is_holding_back=true")

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var saw_blockstun: bool = false
	for i in 300:
		await await_frames(1)
		if int(p2.blockstun_frames) > 0:
			saw_blockstun = true
		_sample(p1, i)
		_sample(p2, i)
		if saw_blockstun and int(p2.blockstun_frames) == 0:
			break

	check(saw_blockstun, "階段 1：P2 應進入 blockstun（blockstun_frames > 0）")
	Input.action_release("move_right_p2")

	var check_recovered := func():
		var t = p2
		return int(t.blockstun_frames) == 0 and not bool(t.is_blocking)
	var recovered: bool = await wait_until(check_recovered, 900)
	check(recovered, "階段 1：P2 應從 blockstun 恢復")

	# ── 階段 2：600 幀固定種子隨機輸入 ──
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

	for frame in RANDOM_FRAMES:
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

		_sample(p1, 1000 + frame)
		_sample(p2, 1000 + frame)

	for action in held.keys():
		Input.action_release(action)

	check(_mismatches.is_empty(),
		"格擋守衛與舊表達式分岔：%s" % " | ".join(_mismatches))

	# 覆蓋度：每組守衛的 true / false 兩側都要實際出現；另外
	# 「blockstun 中進入守衛仍為真」的重取樣路徑必須被觀察到。
	print("      格擋守衛覆蓋: enter=true %d, release=true %d, "
		% [_enter_true, _release_true])
	print("                  blockstun 重取樣 %d（共 %d 樣本）"
		% [_blocking_resample, _samples])
	check(_enter_true > 0,
		"樣本內應至少有一幀站姿進入守衛為真（否則比對無意義）")
	check(_enter_true < _samples,
		"樣本內應至少有一幀站姿進入守衛為假（攻擊/硬直/空中幀），否則比對只測了一邊")
	check(_release_true > 0,
		"樣本內應至少有一幀站姿釋放守衛為真（否則比對無意義）")
	check(_release_true < _samples,
		"樣本內應至少有一幀站姿釋放守衛為假（受擊/擊飛/blockstun/倒地），否則比對只測了一邊")
	check(_blocking_resample > 0,
		"應至少有一幀 is_blocking 與進入守衛同時為真（blockstun 重取樣路徑活著；"
		+ "若有人把 is_blocking 加進進入守衛，這裡會變 0 而比對依然綠 —— 這正是它存在的理由）")

	return not has_failures()

## 逐幀比對：舊表達式（原樣搬運）vs FighterState。對照組直接讀旗標，
## **不**呼叫 FighterState —— 否則用例會變成自己跟自己比。
func _sample(fighter: Node, frame: int) -> void:
	_samples += 1
	var on_floor: bool = bool(fighter.is_on_floor())
	var spmove: bool = bool(fighter.is_special_moving) if "is_special_moving" in fighter else false

	# ── 對照組 1：can_enter_block_stance（BlockingHandler 舊進入守衛）──
	var legacy_enter: bool = on_floor \
		and not bool(fighter.is_attacking) and not bool(fighter.is_dashing) \
		and not bool(fighter.is_backdashing) and not spmove \
		and not (bool(fighter.is_hit) or bool(fighter.is_knockfly) \
			or bool(fighter.is_layground))
	var new_enter: bool = FighterState.can_enter_block_stance(fighter, spmove)
	if legacy_enter:
		_enter_true += 1
	if bool(fighter.is_blocking) and legacy_enter:
		_blocking_resample += 1
	if legacy_enter != new_enter and _mismatches.size() < 8:
		_mismatches.append("enter frame %d %s: legacy=%s new=%s (on_floor=%s spmove=%s attacking=%s dashing=%s backdashing=%s hit=%s knockfly=%s layground=%s blocking=%s)" % [
			frame, fighter.name, legacy_enter, new_enter,
			on_floor, spmove,
			bool(fighter.is_attacking), bool(fighter.is_dashing), bool(fighter.is_backdashing),
			bool(fighter.is_hit), bool(fighter.is_knockfly), bool(fighter.is_layground),
			bool(fighter.is_blocking)])

	# ── 對照組 2：can_release_block_stance（BlockingHandler 舊 else 分支守衛）──
	var legacy_release: bool = not (bool(fighter.is_hit) or bool(fighter.is_knockfly) \
		or bool(fighter.is_blocking) or bool(fighter.is_layground))
	var new_release: bool = FighterState.can_release_block_stance(fighter)
	if legacy_release:
		_release_true += 1
	if legacy_release != new_release and _mismatches.size() < 8:
		_mismatches.append("release frame %d %s: legacy=%s new=%s (hit=%s knockfly=%s blocking=%s layground=%s)" % [
			frame, fighter.name, legacy_release, new_release,
			bool(fighter.is_hit), bool(fighter.is_knockfly), bool(fighter.is_blocking),
			bool(fighter.is_layground)])
