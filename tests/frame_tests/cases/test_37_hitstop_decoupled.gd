extends "res://tests/frame_tests/frame_test_case.gd"
## Hitstop 使用「角色動畫 + 視覺微震動」而非全域 Engine.time_scale。
##
## 目標：
## - hitstop 期間 Engine.time_scale 必須維持 1.0（特效用正常速度播放）。
## - 攻擊者與受擊者的 AnimationPlayer.speed_scale 被凍結為 0。
## - hitstop 結束後，角色動畫速度恢復為 1.0。

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

	# 攻擊者與受擊者的動畫都應定格（只有視覺，不改物理座標）。
	check(p1.animation_tree != null, "Attacker should have an AnimationTree")
	check(p2.animation_tree != null, "Defender should have an AnimationTree")
	var entries_count: int = hitstop_controller._entries.size() if hitstop_controller else -1
	check(p1.animation_tree != null and not p1.animation_tree.active,
		"Attacker AnimationTree should be frozen during hitstop, got active=%s entries=%d freeze_att=%s freeze_def=%s"
		% [p1.animation_tree.active if p1.animation_tree else "null",
			entries_count,
			hitstop_controller.freeze_attacker if hitstop_controller else "null",
			hitstop_controller.freeze_defender if hitstop_controller else "null"])
	check(p2.animation_tree != null and not p2.animation_tree.active,
		"Defender AnimationTree should be frozen during hitstop, got active=%s entries=%d"
		% [p2.animation_tree.active if p2.animation_tree else "null", entries_count])
	check(abs(p1.animation_player.speed_scale) < 0.01,
		"Attacker AnimationPlayer.speed_scale should also be 0 during hitstop, got %s entries=%d"
		% [p1.animation_player.speed_scale, entries_count])
	check(abs(p2.animation_player.speed_scale) < 0.01,
		"Defender AnimationPlayer.speed_scale should also be 0 during hitstop, got %s entries=%d"
		% [p2.animation_player.speed_scale, entries_count])

	var hitstop_ended: bool = await wait_until(
		func(): return not bool(slowmo.is_hit_slowmo), 120)
	check(hitstop_ended, "Hitstop should end")
	if not hitstop_ended:
		return not has_failures()

	check(p1.animation_tree != null and p1.animation_tree.active,
		"Attacker AnimationTree should be restored after hitstop")
	check(p2.animation_tree != null and p2.animation_tree.active,
		"Defender AnimationTree should be restored after hitstop")
	check(abs(p1.animation_player.speed_scale - 1.0) < 0.01,
		"Attacker AnimationPlayer should be restored after hitstop, got %s"
		% [p1.animation_player.speed_scale])
	check(abs(p2.animation_player.speed_scale - 1.0) < 0.01,
		"Defender AnimationPlayer should be restored after hitstop, got %s"
		% [p2.animation_player.speed_scale])

	return not has_failures()
