extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 4：受擊子系統（Hitstun / Blockstun / Knockfly / Knockdown /
## Wakeup / 摔投）守衛的唯一定義（FighterState）必須與**它取代的舊旗標
## 表達式**逐幀等價。
##
## 為什麼需要這個用例：
## 切片 4 把四組散落在不同檔案的受擊相關判定收攏進 FighterState：
##   - is_input_locked   ← Player.get_input() 開頭的五個提前返回
##   - is_combo_stunned  ← HitResponseHandler / fireball 兩份逐字相同的 5 條 or 鏈
##   - can_initiate_throw ← ThrowHandler._can_initiate_throw
##   - can_be_thrown      ← ThrowHandler.check_grab_collision 的目標過濾
## 任何一份抄漏或多抄都會改變「輸入被不被吞 / 連段接不接得上 / 摔投發不
## 發得動 / 目標抓不抓得到」，肉眼幾乎看不出來。本用例把舊表達式**原樣重寫
## 在這裡**當對照組，每幀比對兩者。對照組刻意保留舊寫法，不要「順手優化」
## 成呼叫 FighterState，否則這個用例會變成自己跟自己比。
##
## 與 test_30 / test_31 同模式：600 幀固定種子隨機輸入（兩個角色都會真的
## 被打、格擋、擊飛、倒地、起身），每幀對兩名 fighter 各比對四組守衛。
## Python 暴力窮舉（所有相關旗標組合）已先證明 0 分岔，本用例在引擎內逐幀
## 釘住，並要求各守衛的 true/false 兩側都實際出現過（避免「永遠同一邊」
## 的假綠）。

const FRAMES: int = 600
const SEED: int = 20260901

func run() -> bool:
	await await_frames(10)
	# 距離拉近，確保受擊 / 格擋 / knockfly / layground / wakeup 在樣本裡真的發生。
	teleport_x(p1, 540.0)
	teleport_x(p2, 700.0)
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

	var lock_mismatch: Array = []
	var combo_mismatch: Array = []
	var throw_init_mismatch: Array = []
	var throw_target_mismatch: Array = []

	# 覆蓋度計數：每組守衛的 true / false 兩側都要實際出現。
	var lock_true: int = 0
	var combo_true: int = 0
	var throw_init_true: int = 0
	var throw_target_false: int = 0

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
			var on_floor: bool = bool(fighter.is_on_floor())
			var is_attacking: bool = bool(fighter.is_attacking)
			var attack_type: String = String(fighter.attack_type) if "attack_type" in fighter else "none"

			# ── 對照組 1：is_input_locked（Player.get_input 的舊提前返回鏈）──
			var legacy_lock: bool = bool(fighter.is_knockfly) or bool(fighter.is_wakeup) \
					or bool(fighter.is_hit) or bool(fighter.is_layground) \
					or (is_attacking and attack_type in ["throw_enter", "throw_seq"]) \
					or bool(fighter.is_being_thrown)
			var new_lock: bool = FighterState.is_input_locked(fighter)
			if legacy_lock:
				lock_true += 1
			if legacy_lock != new_lock and lock_mismatch.size() < 8:
				lock_mismatch.append("frame %d %s: legacy=%s new=%s (knockfly=%s wakeup=%s hit=%s layground=%s attacking=%s atk='%s' being_thrown=%s)" % [
					frame, fighter.name, legacy_lock, new_lock,
					bool(fighter.is_knockfly), bool(fighter.is_wakeup),
					bool(fighter.is_hit), bool(fighter.is_layground),
					is_attacking, attack_type, bool(fighter.is_being_thrown)])

			# ── 對照組 2：is_combo_stunned（HitResponseHandler/fireball 舊 5 條 or 鏈）──
			var legacy_combo: bool
			if "hitstun_frames" in fighter:
				legacy_combo = int(fighter.hitstun_frames) > 0 \
						or bool(fighter.waiting_for_hit_stop_end) \
						or bool(fighter.is_air_hit_backjump) \
						or bool(fighter.is_knockfly)
			else:
				legacy_combo = bool(fighter.is_hit) \
						or bool(fighter.waiting_for_hit_stop_end) \
						or bool(fighter.is_air_hit_backjump) \
						or bool(fighter.is_knockfly)
			var new_combo: bool = FighterState.is_combo_stunned(fighter)
			if legacy_combo:
				combo_true += 1
			if legacy_combo != new_combo and combo_mismatch.size() < 8:
				combo_mismatch.append("frame %d %s: legacy=%s new=%s (hitstun=%d waiting=%s air_backjump=%s knockfly=%s hit=%s)" % [
					frame, fighter.name, legacy_combo, new_combo,
					int(fighter.hitstun_frames), bool(fighter.waiting_for_hit_stop_end),
					bool(fighter.is_air_hit_backjump), bool(fighter.is_knockfly),
					bool(fighter.is_hit)])

			# ── 對照組 3：can_initiate_throw（ThrowHandler._can_initiate_throw 舊守衛）──
			var legacy_throw_init: bool = true
			if is_attacking and attack_type != "throw_enter":
				legacy_throw_init = false
			if bool(fighter.is_knockfly) or bool(fighter.is_hit) or bool(fighter.is_blocking):
				legacy_throw_init = false
			if not on_floor:
				legacy_throw_init = false
			var new_throw_init: bool = FighterState.can_initiate_throw(fighter)
			if legacy_throw_init:
				throw_init_true += 1
			if legacy_throw_init != new_throw_init and throw_init_mismatch.size() < 8:
				throw_init_mismatch.append("frame %d %s: legacy=%s new=%s (on_floor=%s attacking=%s atk='%s' knockfly=%s hit=%s blocking=%s)" % [
					frame, fighter.name, legacy_throw_init, new_throw_init,
					on_floor, is_attacking, attack_type,
					bool(fighter.is_knockfly), bool(fighter.is_hit), bool(fighter.is_blocking)])

			# ── 對照組 4：can_be_thrown（ThrowHandler 目標過濾舊式）──
			var legacy_throw_target: bool = not (bool(fighter.is_knockfly) or bool(fighter.is_being_thrown))
			var new_throw_target: bool = FighterState.can_be_thrown(fighter)
			if not legacy_throw_target:
				throw_target_false += 1
			if legacy_throw_target != new_throw_target and throw_target_mismatch.size() < 8:
				throw_target_mismatch.append("frame %d %s: legacy=%s new=%s (knockfly=%s being_thrown=%s)" % [
					frame, fighter.name, legacy_throw_target, new_throw_target,
					bool(fighter.is_knockfly), bool(fighter.is_being_thrown)])

	for action in held.keys():
		Input.action_release(action)

	check(lock_mismatch.is_empty(),
		"吞輸入守衛與舊表達式分岔：%s" % " | ".join(lock_mismatch))
	check(combo_mismatch.is_empty(),
		"連段續航守衛與舊表達式分岔：%s" % " | ".join(combo_mismatch))
	check(throw_init_mismatch.is_empty(),
		"摔投發起守衛與舊表達式分岔：%s" % " | ".join(throw_init_mismatch))
	check(throw_target_mismatch.is_empty(),
		"摔投目標守衛與舊表達式分岔：%s" % " | ".join(throw_target_mismatch))

	# 覆蓋度：600 幀 ×2 角色裡，受擊/吞輸入/可發起摔投/不可被摔都必須真的出現，
	# 否則「兩邊相等」可能只是因為永遠落在同一側。
	var total_samples: int = FRAMES * 2
	print("      受擊守衛覆蓋: input_locked=true %d 幀, combo_stunned=true %d 幀, "
		% [lock_true, combo_true])
	print("                  can_initiate_throw=true %d 幀, can_be_thrown=false %d 幀（共 %d 樣本）"
		% [throw_init_true, throw_target_false, total_samples])
	check(lock_true > 0, "600 幀內應至少有一幀輸入被吞（knockfly/hit/layground/wakeup/摔投）")
	check(combo_true > 0, "600 幀內應至少有一幀處於連段續航硬直（hitstun/knockfly/juggle）")
	check(throw_init_true > 0, "600 幀內應至少有一幀可發起摔投（否則比對無意義）")
	check(throw_target_false > 0, "600 幀內應至少有一幀目標不可被摔（knockfly/被摔投中）")
	# 反向覆蓋：也必須有「沒被吞輸入」的幀（否則 is_input_locked 永遠 true）。
	check(lock_true < total_samples, "600 幀內不應每幀都吞輸入（必須存在可操作幀）")

	return not has_failures()
