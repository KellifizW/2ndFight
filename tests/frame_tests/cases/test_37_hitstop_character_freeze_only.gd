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
##      speed_scale == 0、sprite 有非零 jitter 偏移
##   3. 定格結束後 speed_scale 還原 1.0、sprite 偏移歸零、hitstun 開始遞減
##
## 每個可能失敗/早退的點都用 check() 記錄脈絡（避免「失敗但無訊息」）。

func run() -> bool:
	print("[TEST37] start | p1=%s p2=%s" % [p1.name if p1 else "?", p2.name if p2 else "?"])
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	# 記錄定格前的 sprite 基準點（場景預設 (0,0)；用實測值避免硬編碼）
	var sprite = p2.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		check(false, "P2 缺少 AnimatedSprite2D 視覺節點（無法驗證 jitter）")
		return false
	var sprite_base: Vector2 = sprite.position

	var slowmo = p2.slow_mo_controller
	if slowmo == null:
		check(false, "P2 缺少 slow_mo_controller（無法驗證 hitstop 旗標）")
		return false

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var hitstop_started: bool = await wait_until(
		func(): return slowmo.is_hit_slowmo, 120)
	if not hitstop_started:
		check(false, "Hitstop 未啟動：st_mp 命中 120 物理幀內 is_hit_slowmo 從未變 true")
		return false
	print("[TEST37] hitstop started | time_scale=%s | p1.speed=%s | p2.speed=%s" % [
		Engine.time_scale, p1.animation_player.speed_scale, p2.animation_player.speed_scale])

	# ── 定格期間：逐幀檢查三個不變式 ──
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
		if p1.animation_player and p1.animation_player.speed_scale != 0.0:
			anim_violated = true
		if p2.animation_player and p2.animation_player.speed_scale != 0.0:
			anim_violated = true
		if p1.animation_tree and p1.animation_tree.speed_scale != 0.0:
			anim_violated = true
		if p2.animation_tree and p2.animation_tree.speed_scale != 0.0:
			anim_violated = true
		if sprite.position != sprite_base:
			saw_jitter = true

	print("[TEST37] hitstop loop done | frames=%d | jitter=%s | ts_violation=%s" % [
		frames_checked, saw_jitter, time_scale_violated])

	check(not time_scale_violated,
		"Engine.time_scale must stay 1.0 during hitstop (VFX/UI keep full speed), got %s" % Engine.time_scale)
	check(not movement_violated,
		"Both players' fixed_position must be completely frozen during hitstop (p1=%s p2=%s)" % [p1.fixed_position, p2.fixed_position])
	check(not anim_violated,
		"Both players' AnimationPlayer/AnimationTree speed_scale must be 0 during hitstop")
	check(saw_jitter,
		"Sprite jitter offset should be visible during hitstop (AnimatedSprite2D.position moved)")
	check(frames_checked >= 12 and frames_checked <= 20,
		"Hitstop should last ~16 physics frames (8 logic frames), saw %d frames" % frames_checked)

	# ── 定格結束後：全部還原 + hitstun 開始遞減 ──
	check(Engine.time_scale == 1.0, "Engine.time_scale should be 1.0 after hitstop, got %s" % Engine.time_scale)
	check(p1.animation_player and p1.animation_player.speed_scale == 1.0,
		"P1 AnimationPlayer speed_scale should be restored to 1.0, got %s" % p1.animation_player.speed_scale)
	check(p2.animation_player and p2.animation_player.speed_scale == 1.0,
		"P2 AnimationPlayer speed_scale should be restored to 1.0, got %s" % p2.animation_player.speed_scale)
	check(sprite.position == sprite_base,
		"Sprite position should be restored to base (%s), got %s" % [sprite_base, sprite.position])
	check(p2.hitstun_frames >= 46 and p2.hitstun_frames <= 48,
		"Hitstun (48 physics frames) should have just started after hitstop, got %d" % p2.hitstun_frames)

	# hitstun 之後正常走完（恢復路徑未被 hitstop 破壞）
	var check_recovered := func():
		var t = p2
		return t.hitstun_frames == 0 and not t.is_hit
	var recovered: bool = await wait_until(check_recovered, 300)
	check(recovered, "P2 should recover from hitstun normally after hitstop (hitstun=%d is_hit=%s)" % [p2.hitstun_frames, p2.is_hit])

	return not has_failures()
