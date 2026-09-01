extends "res://tests/frame_tests/frame_test_case.gd"
## Hitstop 使用「角色動畫定格 + 視覺微震動」而非全域 Engine.time_scale。
##
## 目標：
## - hitstop 期間 Engine.time_scale 必須維持 1.0（特效用正常速度播放）。
## - 角色動畫由 AnimationTree 驅動 AnimationPlayer；此時 AnimationPlayer.speed_scale
##   不會生效（官方文件明載），必須把 AnimationTree 切到手動模式（MANUAL）才真正定格，
##   AnimationPlayer.speed_scale=0 只覆蓋繞過 Tree 的直接播放（landing 等）。
## - hitstop 期間：受擊者必須「已進入並停在」受擊動畫第 0 格；攻擊者必須定格在
##   打中瞬間的姿勢（動畫名與格數都不推進）—— hitstop 的視覺本體。
## - hitstop 結束後：AnimationTree 還原為自動處理，受擊動畫從凍結點開始播放。

func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var slowmo = p2.slow_mo_controller
	var hitstop_started: bool = await wait_until(
		func(): return slowmo != null and slowmo.is_hit_slowmo, 120)
	check(hitstop_started, "Hitstop should start when st_mp connects")
	if not hitstop_started:
		return not has_failures()

	check(Engine.time_scale == 1.0,
		"Hitstop must not change Engine.time_scale (got %s)"
		% [Engine.time_scale])

	var hitstop_controller = world.get_node_or_null("HitStopController")
	check(hitstop_controller != null,
		"World should contain a HitStopController node")
	check(hitstop_controller != null and hitstop_controller.hitstop_frames > 0,
		"HitStopController should have a positive frame duration")

	# 攻擊者與受擊者的「可見動畫」都應定格：AnimationTree 切到手動模式（保持 active，
	# 不改狀態機內部）；AnimationPlayer.speed_scale=0 繼續覆蓋繞過 Tree 的直接播放。
	for fighter in [p1, p2]:
		check(fighter.animation_player != null,
			"%s should have an AnimationPlayer" % fighter.name)
		check(abs(fighter.animation_player.speed_scale) < 0.01,
			"%s AnimationPlayer.speed_scale should be 0 during hitstop, got %s"
			% [fighter.name, fighter.animation_player.speed_scale])
		check(fighter.animation_tree != null and fighter.animation_tree.active,
			"%s AnimationTree should stay active during hitstop (freeze must not use active=false)"
			% fighter.name)
		check(fighter.animation_tree != null
			and fighter.animation_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
			"%s AnimationTree should be frozen via MANUAL process mode during hitstop, got %d"
			% [fighter.name, fighter.animation_tree.callback_mode_process if fighter.animation_tree else -1])

	# ── 受擊者：hitstop 期間就必須「已進入並停在」受擊動畫第 0 格 ──
	# p1（WOO）被打中：hit 狀態的動畫會把 AnimatedSprite2D 切到 "hit" 第 0 格。
	# （被打前 sprite 停在 Walk/idle 的動畫上 —— 這正是舊版 hitstop 的症狀。）
	var p1_sprite := p1.get_node("AnimatedSprite2D") as AnimatedSprite2D
	check(p1_sprite.animation == &"hit",
		"Defender sprite should already show the hit animation during hitstop, got '%s'"
		% p1_sprite.animation)
	check(p1_sprite.frame == 0,
		"Defender should be frozen on hit animation frame 0, got %d" % p1_sprite.frame)

	# ── 攻擊者：定格在打中瞬間的姿勢 ──
	var p2_sprite := p2.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var att_anim_at_hitstop_start: StringName = p2_sprite.animation
	var att_frame_at_hitstop_start: int = p2_sprite.frame

	# hitstop 只有 8 物理幀：取樣兩次，雙方 sprite 的動畫名與格數都不得推進。
	for sample in 2:
		await await_frames(2)
		if not slowmo.is_hit_slowmo:
			break  # CI 偶發卡頓讓 hitstop 提前結束時，略過「期間取樣」（結束後另有斷言）
		check(p2_sprite.animation == att_anim_at_hitstop_start
			and p2_sprite.frame == att_frame_at_hitstop_start,
			"Attacker pose must be frozen during hitstop (%s/%d → %s/%d)" % [
				att_anim_at_hitstop_start, att_frame_at_hitstop_start,
				p2_sprite.animation, p2_sprite.frame])
		check(p1_sprite.animation == &"hit" and p1_sprite.frame == 0,
			"Defender must stay on hit animation frame 0 during hitstop, got %s/%d"
			% [p1_sprite.animation, p1_sprite.frame])

	var hitstop_ended: bool = await wait_until(
		func(): return not bool(slowmo.is_hit_slowmo), 120)
	check(hitstop_ended, "Hitstop should end")
	if not hitstop_ended:
		return not has_failures()

	check(abs(p1.animation_player.speed_scale - 1.0) < 0.01,
		"Attacker AnimationPlayer should be restored after hitstop, got %s"
		% [p1.animation_player.speed_scale])
	check(abs(p2.animation_player.speed_scale - 1.0) < 0.01,
		"Defender AnimationPlayer should be restored after hitstop, got %s begins=%d finishes=%d cancels=%d is_active=%s hit_slowmo=%s att=%s"
		% [p2.animation_player.speed_scale,
			hitstop_controller.debug_begin_count if hitstop_controller else -1,
			hitstop_controller.debug_finish_count if hitstop_controller else -1,
			hitstop_controller.debug_cancel_count if hitstop_controller else -1,
			hitstop_controller.is_active if hitstop_controller else "null",
			slowmo.is_hit_slowmo if slowmo else "null",
			p1.animation_player.speed_scale if p1.animation_player else "null"])

	# ── 結束後：AnimationTree 還原為自動處理（本專案場景用預設 IDLE）──
	for fighter in [p1, p2]:
		check(fighter.animation_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
			"%s AnimationTree should be restored to auto (IDLE) after hitstop, got %d"
			% [fighter.name, fighter.animation_tree.callback_mode_process])

	# ── 結束後：受擊動畫從凍結點開始播放（格數推進）──
	# hitstun 還有約 28 物理幀，動畫 0.05s 換一格：20 幀窗口內必然推進。
	var frozen_frame: int = p1_sprite.frame
	var advanced: bool = await wait_until(
		func(): return p1_sprite.frame > frozen_frame, 20)
	check(advanced,
		"Hit animation should start playing after hitstop ends (frame stuck at %d)"
		% frozen_frame)
	if advanced:
		check(p1_sprite.animation == &"hit",
			"Hit animation should keep playing after hitstop, got '%s'"
			% p1_sprite.animation)

	return not has_failures()
