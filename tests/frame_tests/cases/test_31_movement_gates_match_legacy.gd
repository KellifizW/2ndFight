extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 3：移動子系統（Walk / Dash / Jump）守衛的唯一定義（FighterState）
## 必須與**它取代的舊旗標表達式**逐幀等價。
##
## 為什麼需要這個用例：
## 切片 3 把「現在能不能走 / 能不能 dash / 能不能跳」從各 handler 內聯的散落
## 抄本（WalkHandler 1 份 + Movement._physics_process 的 AI dash 2 份 +
## JumpHandler 1 份）收攏成 FighterState 的三個函式（can_walk / can_dash /
## can_jump）。和切片 2 同樣的道理：收攏的價值只在於「等價」—— 任何一份
## 抄漏或多抄都會讓某個狀態下意外地走 / dash / 跳起來，肉眼幾乎不可能看出來。
##
## 本用例把三組舊表達式**原樣重寫在這裡**當對照組，每幀比對兩者。對照組刻意
## 保留舊寫法（包含 AI 直接 backdash 那條略寬鬆的舊分支），不要「順手優化」成
## 呼叫 FighterState，否則這個用例會變成自己跟自己比。
##
## 與 test_30 的差別：test_30 守的是攻擊子系統（已收攏），test_31 守的是
## 移動子系統（剛收攏）。兩者模式完全相同，但旗標清單不同 —— 後者必須額外
## 處理 jump_delay_timer 與 knockback/corner_push 幀計數器。

const FRAMES: int = 600
const SEED: int = 20260831

func run() -> bool:
	await await_frames(10)
	# 距離拉近一點，確保攻擊 / 受擊 / knockback / layground 等戰鬥狀態在樣本裡
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

	var walk_mismatch: Array = []
	var dash_mismatch: Array = []
	var jump_mismatch: Array = []
	var walk_true: int = 0
	var dash_true: int = 0
	var jump_true: int = 0

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
			var spmove: bool = bool(fighter.is_special_moving) if "is_special_moving" in fighter else false

			# ── 對照組 1：can_walk（WalkHandler.handle_walk 的舊 can_walk 展開）──
			var is_in_knockback: bool = int(fighter.knockback_frames) > 0
			var is_in_corner_push: bool = int(fighter.corner_push_frames) > 0
			var is_in_block_knockback: bool = int(fighter.block_knockback_frames) > 0
			var legacy_walk: bool = on_floor and not bool(fighter.is_attacking) \
					and not bool(fighter.is_dashing) and not bool(fighter.is_backdashing) \
					and not spmove \
					and not (bool(fighter.is_hit) or bool(fighter.is_knockfly) \
						or bool(fighter.is_blocking) or bool(fighter.is_layground) \
						or is_in_knockback or is_in_corner_push or is_in_block_knockback) \
					and not bool(fighter.is_crouching)
			var new_walk: bool = FighterState.can_walk(fighter, spmove)
			if legacy_walk:
				walk_true += 1
			if legacy_walk != new_walk and walk_mismatch.size() < 8:
				walk_mismatch.append("frame %d %s: legacy=%s new=%s (on_floor=%s spmove=%s landing=%s lock=%d is_attacking=%s is_dashing=%s is_hit=%s is_knockfly=%s is_blocking=%s is_layground=%s is_crouching=%s knockback=%d corner=%d block_kn=%d)" % [
					frame, fighter.name, legacy_walk, new_walk,
					on_floor, spmove,
					bool(fighter.is_landing), int(fighter.landing_lock_frames),
					bool(fighter.is_attacking), bool(fighter.is_dashing),
					bool(fighter.is_hit), bool(fighter.is_knockfly),
					bool(fighter.is_blocking), bool(fighter.is_layground),
					bool(fighter.is_crouching),
					int(fighter.knockback_frames), int(fighter.corner_push_frames),
					int(fighter.block_knockback_frames)])

			# ── 對照組 2：can_dash（DashHandler.handle_dash 的舊守衛展開）──
			var legacy_dash: bool = on_floor \
				and not (bool(fighter.is_landing) and int(fighter.landing_lock_frames) > 0) \
				and not bool(fighter.is_attacking) and not bool(fighter.is_dashing) \
				and not bool(fighter.is_backdashing) and not spmove \
				and not (bool(fighter.is_hit) or bool(fighter.is_knockfly) \
					or bool(fighter.is_blocking) or bool(fighter.is_layground)) \
				and not bool(fighter.is_crouching)
			var new_dash: bool = FighterState.can_dash(fighter, spmove)
			if legacy_dash:
				dash_true += 1
			if legacy_dash != new_dash and dash_mismatch.size() < 8:
				dash_mismatch.append("frame %d %s: legacy=%s new=%s (landing=%s lock=%d is_attacking=%s is_dashing=%s is_backdashing=%s is_hit=%s is_knockfly=%s is_blocking=%s is_layground=%s is_crouching=%s)" % [
					frame, fighter.name, legacy_dash, new_dash,
					bool(fighter.is_landing), int(fighter.landing_lock_frames),
					bool(fighter.is_attacking), bool(fighter.is_dashing),
					bool(fighter.is_backdashing),
					bool(fighter.is_hit), bool(fighter.is_knockfly),
					bool(fighter.is_blocking), bool(fighter.is_layground),
					bool(fighter.is_crouching)])

			# ── 對照組 3：can_jump（JumpHandler.handle_jump 的舊守衛展開）──
			var input_data: Dictionary = fighter.get_input()
			var jump_pressed: bool = bool(input_data.get("jump_pressed", false))
			var legacy_jump: bool = not bool(fighter.is_landing) \
				and not bool(fighter.is_being_thrown) \
				and jump_pressed and on_floor \
				and not bool(fighter.is_crouching) \
				and not bool(fighter.is_dashing) and not bool(fighter.is_backdashing) \
				and not bool(fighter.is_attacking) and not spmove \
				and not (bool(fighter.is_hit) or bool(fighter.is_knockfly) \
					or bool(fighter.is_blocking) or bool(fighter.is_layground)) \
				and int(fighter.jump_delay_timer) <= 0
			var new_jump: bool = FighterState.can_jump(fighter, jump_pressed, spmove)
			if legacy_jump:
				jump_true += 1
			if legacy_jump != new_jump and jump_mismatch.size() < 8:
				jump_mismatch.append("frame %d %s: legacy=%s new=%s (jump_pressed=%s on_floor=%s spmove=%s is_landing=%s is_being_thrown=%s is_crouching=%s is_dashing=%s is_backdashing=%s is_attacking=%s is_hit=%s is_knockfly=%s is_blocking=%s is_layground=%s jump_delay=%d)" % [
					frame, fighter.name, legacy_jump, new_jump,
					jump_pressed, on_floor, spmove,
					bool(fighter.is_landing), bool(fighter.is_being_thrown),
					bool(fighter.is_crouching),
					bool(fighter.is_dashing), bool(fighter.is_backdashing),
					bool(fighter.is_attacking),
					bool(fighter.is_hit), bool(fighter.is_knockfly),
					bool(fighter.is_blocking), bool(fighter.is_layground),
					int(fighter.jump_delay_timer)])

	for action in held.keys():
		Input.action_release(action)

	check(walk_mismatch.is_empty(),
		"走路守衛與舊表達式分岔：%s" % " | ".join(walk_mismatch))
	check(dash_mismatch.is_empty(),
		"衝刺守衛與舊表達式分岔：%s" % " | ".join(dash_mismatch))
	check(jump_mismatch.is_empty(),
		"跳躍守衛與舊表達式分岔：%s" % " | ".join(jump_mismatch))

	# 覆蓋度：樣本必須真的包含三種守衛各自為真的幀，否則「全部相等」只是
	# 因為兩邊永遠都是 false。
	print("      移動守衛覆蓋: walk=%d 幀, dash=%d 幀, jump=%d 幀（共 %d 幀 ×2 角色）"
		% [walk_true, dash_true, jump_true, FRAMES])
	check(walk_true > 0, "600 幀內走路守衛應至少為真一次（否則比對無意義）")
	check(dash_true > 0, "600 幀內衝刺守衛應至少為真一次（否則比對無意義）")
	check(jump_true > 0, "600 幀內跳躍守衛應至少為真一次（否則比對無意義）")

	return not has_failures()
