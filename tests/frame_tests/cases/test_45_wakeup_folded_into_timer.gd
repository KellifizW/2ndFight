extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 8：WAKEUP 的唯一權威改為 `wakeup_timer > 0`，`is_wakeup` 旗標
## 已刪除（核心三檔 bool 旗標 31 → 30）。
##
## 這是用「旗標」表達狀態改成用「幀計數器」表達狀態的第一刀，所以要釘的
## 不只是「摺疊後還能動」，而是四件事：
##
##   1. 旗標真的不存在了 —— `is_wakeup` 不再是 Player 的屬性。少了這條，
##      之後任何人把旗標加回來（或被場景覆寫帶回來）都不會被發現。
##   2. 摺疊後的語意與舊旗標一致 —— 起身期間 `FighterState.is_wakeup_active()`
##      為真、狀態解析回 WAKEUP、輸入被吞、不能出招、動畫鏈回 "wakeup"；
##      計時器歸零那一幀全部解除。
##   3. 計時器仍是逐幀 -1 的整數幀語意（Stage 1 的財產不能在 Stage 2 弄丟）。
##   4. `world.reset_players()` 必須連 `wakeup_timer` 一起歸零 —— 這是本切片
##      唯一的「補償」：過去它只清旗標、留下過期計時器（那段倒數是純空操作，
##      因為收尾副作用受 `and is_wakeup` 保護）。摺疊後過期計時器會變成
##      「reset 完還在起身」，所以歸零是等價性的一部分，不是順手清理。
##
## 起身狀態用 `take_hit(..., force_knockfly=true)` 確定性逼出（與 test_18 /
## test_34 同一條路徑：knockfly → 落地 layground → layground_timer 歸零 →
## 起身）。隨機輸入不保證能走到 knockfly，這裡不能靠運氣。

const WAKEUP_WAIT_FRAMES: int = 1200
const INJECTED_TIMER: int = 45

var _wakeup_frames: int = 0

func run() -> bool:
	await await_frames(10)
	teleport_x(p1, 540.0)
	teleport_x(p2, 700.0)
	await await_frames(5)

	# ── 階段 0：旗標必須真的消失 ──────────────────────────────────────
	check(not ("is_wakeup" in p2),
		"Stage 2 切片 8：Player 不應再有 `is_wakeup` 屬性（WAKEUP 改由 wakeup_timer > 0 表達）")
	check(int(p2.wakeup_timer) == 0,
		"開場 wakeup_timer 應為 0，實測 %d" % int(p2.wakeup_timer))
	check(not FighterState.is_wakeup_active(p2), "開場不應處於起身狀態")

	# ── 階段 1：確定性逼出起身（knockfly → layground → wakeup）──────────
	p2.take_hit(18, 10, 12.0, true, true, {}, -1.0)
	var saw_wakeup: bool = false
	for i in WAKEUP_WAIT_FRAMES:
		await await_frames(1)
		if int(p2.wakeup_timer) > 0:
			saw_wakeup = true
			break
	check(saw_wakeup,
		"take_hit(force_knockfly=true) 應讓 P2 走完 knockfly → layground → wakeup（%d 幀內 wakeup_timer 未 > 0）"
		% WAKEUP_WAIT_FRAMES)
	if not saw_wakeup:
		return not has_failures()

	var seed_frames: int = int(p2.wakeup_timer)
	check(seed_frames > 0, "起身種子必須為正（摺疊前提），實測 %d" % seed_frames)
	check(FighterState.is_wakeup_active(p2), "wakeup_timer > 0 時 is_wakeup_active() 應為真")
	check(FighterState.resolve(p2) == FighterState.State.WAKEUP,
		"起身期間狀態應解析為 WAKEUP，實測 %s"
		% FighterState.state_name(FighterState.resolve(p2)))
	check(FighterState.is_input_locked(p2), "起身期間輸入必須被完全吞沒")
	check(not FighterState.can_start_ground_attack(p2), "起身期間不得開地面招")
	var anim: String = FighterState.animation_for(
		p2, false, bool(p2.is_on_floor()), 0.0)
	check(anim == "wakeup", "起身期間動畫鏈應回 \"wakeup\"，實測 \"%s\"" % anim)

	# ── 階段 2：逐幀 -1，歸零那一幀解除 ────────────────────────────────
	var previous: int = seed_frames
	var steps: int = 0
	var bad_step: int = -999
	var released: bool = false
	var state_mismatch: String = ""
	while steps < seed_frames + 30:
		await await_frames(1)
		steps += 1
		var current: int = int(p2.wakeup_timer)
		if previous - current != 1 and bad_step == -999:
			bad_step = previous - current
		previous = current
		if current > 0:
			_wakeup_frames += 1
			if not FighterState.is_wakeup_active(p2) and state_mismatch == "":
				state_mismatch = "frame %d: wakeup_timer=%d 但 is_wakeup_active() 為假" % [steps, current]
		else:
			released = true
			break

	check(bad_step == -999,
		"wakeup_timer 應每物理幀恰好 -1，觀測到一次 %d" % bad_step)
	check(released, "wakeup_timer 應在 %d 幀內倒數到 0（實測跑了 %d 幀）" % [seed_frames + 30, steps])
	check(steps == seed_frames,
		"起身應恰好持續 %d 個物理幀，實測 %d" % [seed_frames, steps])
	check(state_mismatch == "", "起身狀態與計時器分岔：%s" % state_mismatch)
	check(_wakeup_frames >= 1, "至少要觀察到 1 幀起身狀態（否則本用例是假綠）")

	# 解除那一幀：不再是 WAKEUP、不再吞輸入（P2 此時無其他鎖）。
	check(not FighterState.is_wakeup_active(p2), "歸零那一幀 is_wakeup_active() 應為假")
	check(FighterState.resolve(p2) != FighterState.State.WAKEUP,
		"歸零那一幀不應再是 WAKEUP，實測 %s"
		% FighterState.state_name(FighterState.resolve(p2)))
	check(not FighterState.is_input_locked(p2), "起身結束後輸入必須恢復（此時無其他鎖）")
	check(FighterState.check_invariants(p2).is_empty(),
		"起身結束後不變式應為乾淨：%s" % " / ".join(FighterState.check_invariants(p2)))

	# ── 階段 3：reset 必須連計時器一起歸零（本切片唯一的補償）──────────
	# 直接種值模擬「reset 發生在起身途中」；真走一次 knockfly → wakeup 要
	# 數百幀，而這裡要釘的只是 reset 的契約。種值後先確認語意真的成立
	# （證明注入有效，不是永遠為假的斷言）。
	p2.wakeup_timer = INJECTED_TIMER
	check(FighterState.is_wakeup_active(p2),
		"注入 wakeup_timer=%d 後應處於起身狀態（否則本階段的斷言沒有意義）" % INJECTED_TIMER)

	world.reset_players()
	check(int(p2.wakeup_timer) == 0,
		"reset_players() 必須把 wakeup_timer 歸零，實測 %d" % int(p2.wakeup_timer))
	check(not FighterState.is_wakeup_active(p2), "reset 後不應仍處於起身狀態")
	check(FighterState.resolve(p2) != FighterState.State.WAKEUP, "reset 後不應是 WAKEUP")

	# 過期計時器若留下來，會在之後的某幀把角色「變回」起身狀態；跑 60 幀確認。
	for i in 60:
		await await_frames(1)
		if FighterState.is_wakeup_active(p2):
			check(false, "reset 後第 %d 幀又被判成起身狀態（wakeup_timer 殘留）" % i)
			break

	print("      起身幀數: %d（種子 %d 幀），reset 補償已釘住"
		% [_wakeup_frames, seed_frames])
	return not has_failures()
