extends "res://tests/frame_tests/frame_test_case.gd"
## Hitstop（擊中凍結）迴歸測試：P1 st_mp 打中 P2 後
##
## 期望:
##   1. 命中後 SlowMoController.is_hit_slowmo 變為 true
##   2. hitstop 期間 Engine.time_scale 降至 hit_slowmo_time_scale
##   3. hitstop 在真實時間 hitstop_frames/60 秒後結束，
##      is_hit_slowmo 回到 false 且 Engine.time_scale 恢復 1.0
##
## 注意: hitstop 期間物理幀近乎停止（time_scale=0.02），
## 所以本測試用 process_frame（渲染幀）輪詢，不用 await_frames（物理幀）。

func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	var slowmo = world.get_node_or_null("SlowMoController")
	check(slowmo != null, "world 應有 SlowMoController 節點")
	if slowmo == null:
		return false

	check(slowmo.enable_hitstop, "enable_hitstop 預設應為 true")
	check(slowmo.hitstop_frames > 0, "hitstop_frames 預設應 > 0（實為 %d）" % slowmo.hitstop_frames)
	check(not slowmo.is_hit_slowmo, "攻擊前不應處於 hitstop")

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	# ── 階段 1：等待 hitstop 觸發（用渲染幀輪詢 + 真實時間上限）──
	var saw_freeze: bool = false
	var min_scale: float = 999.0
	var freeze_start_ms: int = 0
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await world.get_tree().process_frame
		if slowmo.is_hit_slowmo:
			saw_freeze = true
			freeze_start_ms = Time.get_ticks_msec()
			min_scale = minf(min_scale, Engine.time_scale)
			break

	check(saw_freeze, "命中後應觸發 hitstop（is_hit_slowmo 應變為 true）")
	if not saw_freeze:
		return not has_failures()

	# ── 階段 2：hitstop 期間持續取樣 time_scale，直到結束 ──
	var restored: bool = false
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if slowmo.is_hit_slowmo:
			min_scale = minf(min_scale, Engine.time_scale)
		elif absf(Engine.time_scale - 1.0) < 0.001:
			restored = true
			break
		await world.get_tree().process_frame

	check(min_scale <= slowmo.hit_slowmo_time_scale + 0.001,
		"hitstop 期間 Engine.time_scale 應降至 %.3f（實測最低 %.3f）" % [slowmo.hit_slowmo_time_scale, min_scale])
	check(restored, "hitstop 結束後 Engine.time_scale 應恢復 1.0（實為 %.3f，is_hit_slowmo=%s）" % [Engine.time_scale, slowmo.is_hit_slowmo])

	# ── 階段 3：真實持續時間 sanity check（放寬容差，headless 有排程抖動）──
	if restored:
		var duration_sec: float = float(Time.get_ticks_msec() - freeze_start_ms) / 1000.0
		var target_sec: float = float(slowmo.hitstop_frames) / 60.0
		check(duration_sec >= target_sec * 0.4,
			"hitstop 真實持續時間 %.3fs 不應遠短於目標 %.3fs（凍結被瞬間跳過 = 舊 bug 症狀）" % [duration_sec, target_sec])
		check(duration_sec <= target_sec * 5.0 + 0.5,
			"hitstop 真實持續時間 %.3fs 不應遠長於目標 %.3fs（凍結卡死）" % [duration_sec, target_sec])

	# ── 階段 4：hitstop 結束後 hitstun 應正常遞減、P2 恢復 ──
	var check_recovered := func():
		return p2.hitstun_frames == 0 and not p2.is_hit
	var recovered: bool = await wait_until(check_recovered, 900)
	check(recovered, "hitstop 結束後 P2 應能從 hitstun 正常恢復")

	return not has_failures()
