extends "res://tests/frame_tests/frame_test_case.gd"
## 2026-08 HitStop 重構回歸：hitstop 必須是「角色層凍結」而非全域 time_scale。
##
## 舊實作把 Engine.time_scale 壓到 0.02 做全域凍結：VFX 粒子、打擊火花、
## UI 計時器、音效全部一起凍住（畫面死寂感、打擊感喪失）。
## 新實作（HitStopManager）只凍結角色動畫 + 角色物理，並疊加像素級 jitter。
##
## 本用例釘住三個不變式：
##   1. 定格期間 Engine.time_scale == 1.0（特效 / UI 維持正常速度）
##   2. 定格期間雙方角色 fixed_position 完全不動、AnimationPlayer/Tree
##      process_mode == DISABLED、sprite 有非零 jitter 偏移
##   3. 定格結束後 process_mode 還原、sprite 偏移歸零、hitstun 開始遞減
##
## 【診斷用】每個可能觸發 runtime error 的段落前先把進度標記 push 進
## _failures、成功後 pop 掉：若中途 runtime error 讓協程死掉（GDScript
## 沒有 try/catch，error 會讓本腳本靜默中斷、runner 拿到 falsy 回傳、
## annotation 顯示「failure without detail」），最後一個標記就會留在
## 失敗報告裡，直接指出死在哪一段。

func _mark(section: String) -> void:
	_failures.append("[progress] " + section)

func _unmark() -> void:
	if _failures.size() > 0 and _failures.back().begins_with("[progress] "):
		_failures.pop_back()

func run() -> bool:
	_mark("start: reading p1/p2")
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)
	_unmark()

	_mark("resolving AnimatedSprite2D / slow_mo_controller")
	var sprite = p2.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		check(false, "P2 缺少 AnimatedSprite2D 視覺節點（無法驗證 jitter）")
		return false
	var sprite_base: Vector2 = sprite.position
	var slowmo = p2.slow_mo_controller
	if slowmo == null:
		check(false, "P2 缺少 slow_mo_controller（無法驗證 hitstop 旗標）")
		return false
	_unmark()

	_mark("pressing st_mp, waiting for hitstop to start")
	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")
	var hitstop_started: bool = await wait_until(
		func(): return slowmo.is_hit_slowmo, 120)
	_unmark()
	if not hitstop_started:
		check(false, "Hitstop 未啟動：st_mp 命中 120 物理幀內 is_hit_slowmo 從未變 true")
		return false

	_mark("hitstop started; checking frozen invariants (up to 60 frames)")
	var pos_p1 = p1.fixed_position
	var pos_p2 = p2.fixed_position
	var frames_checked: int = 0
	var saw_jitter: bool = false
	var time_scale_violated: bool = false
	var movement_violated: bool = false
	var anim_violated: bool = false
	for frame in 60:
		if not slowmo.is_hit_slowmo:
			break
		await await_frames(1)
		frames_checked += 1
		if not slowmo.is_hit_slowmo:
			break
		if Engine.time_scale != 1.0:
			time_scale_violated = true
		if p1.fixed_position != pos_p1 or p2.fixed_position != pos_p2:
			movement_violated = true
		if p1.animation_player and p1.animation_player.get_process_mode() != Node.PROCESS_MODE_DISABLED:
			anim_violated = true
		if p2.animation_player and p2.animation_player.get_process_mode() != Node.PROCESS_MODE_DISABLED:
			anim_violated = true
		if p1.animation_tree and p1.animation_tree.get_process_mode() != Node.PROCESS_MODE_DISABLED:
			anim_violated = true
		if p2.animation_tree and p2.animation_tree.get_process_mode() != Node.PROCESS_MODE_DISABLED:
			anim_violated = true
		if sprite.position != sprite_base:
			saw_jitter = true
	_unmark()

	check(not time_scale_violated,
		"Engine.time_scale must stay 1.0 during hitstop (VFX/UI keep full speed), got %s" % Engine.time_scale)
	check(not movement_violated,
		"Both players' fixed_position must be completely frozen during hitstop (p1=%s p2=%s)" % [p1.fixed_position, p2.fixed_position])
	check(not anim_violated,
		"Both players' AnimationPlayer/AnimationTree process_mode must be DISABLED during hitstop")
	check(saw_jitter,
		"Sprite jitter offset should be visible during hitstop (AnimatedSprite2D.position moved)")
	check(frames_checked >= 12 and frames_checked <= 20,
		"Hitstop should last ~16 physics frames (8 logic frames), saw %d frames" % frames_checked)

	_mark("post-hitstop: verifying restoration")
	check(Engine.time_scale == 1.0, "Engine.time_scale should be 1.0 after hitstop, got %s" % Engine.time_scale)
	if p1.animation_player:
		check(p1.animation_player.get_process_mode() == Node.PROCESS_MODE_INHERIT,
			"P1 AnimationPlayer process_mode should be restored to INHERIT, got %s" % p1.animation_player.get_process_mode())
	else:
		check(false, "P1 animation_player is null after hitstop")
	if p2.animation_player:
		check(p2.animation_player.get_process_mode() == Node.PROCESS_MODE_INHERIT,
			"P2 AnimationPlayer process_mode should be restored to INHERIT, got %s" % p2.animation_player.get_process_mode())
	else:
		check(false, "P2 animation_player is null after hitstop")
	check(sprite.position == sprite_base,
		"Sprite position should be restored to base (%s), got %s" % [sprite_base, sprite.position])
	check(p2.hitstun_frames >= 46 and p2.hitstun_frames <= 48,
		"Hitstun (48 physics frames) should have just started after hitstop, got %d" % p2.hitstun_frames)
	_unmark()

	_mark("waiting for hitstun recovery (300 frames)")
	var check_recovered := func():
		var t = p2
		return t.hitstun_frames == 0 and not t.is_hit
	var recovered: bool = await wait_until(check_recovered, 300)
	_unmark()
	check(recovered, "P2 should recover from hitstun normally after hitstop (hitstun=%d is_hit=%s)" % [p2.hitstun_frames, p2.is_hit])

	return not has_failures()
