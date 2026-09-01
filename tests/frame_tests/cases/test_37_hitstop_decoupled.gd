extends "res://tests/frame_tests/frame_test_case.gd"
## Hitstop 使用「角色動畫定格 + 視覺微震動」而非全域 Engine.time_scale。
##
## 目標：
## - hitstop 期間 Engine.time_scale 必須維持 1.0（特效用正常速度播放）。
## - 角色動畫由 AnimationTree 驅動 AnimationPlayer；此時 AnimationPlayer.speed_scale
##   不會生效（官方文件明載），必須讓 AnimationTree 節點停止處理
##   （process_mode = DISABLED）才真正定格；AnimationPlayer.speed_scale=0 只覆蓋
##   繞過 Tree 的直接播放（landing 等）。
##   【勿改回 callback_mode_process = MANUAL】那個 setter 會 set_active(false→true)，
##   使 mixer 的 started 旗標打開 → 下一次處理以「seek 到 0」進狀態機 → 狀態機
##   重啟回 Start 節點 → 攻擊者在打中瞬間掉回 idle、解凍後重播攻擊動畫。
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

	# 攻擊者與受擊者的「可見動畫」都應定格：AnimationTree 節點停止處理（保持 active
	# 與 callback_mode_process 不變，狀態機內部完全不動）；
	# AnimationPlayer.speed_scale=0 繼續覆蓋繞過 Tree 的直接播放。
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
			and fighter.animation_tree.process_mode == Node.PROCESS_MODE_DISABLED,
			"%s AnimationTree should be frozen via process_mode = DISABLED during hitstop, got %d"
			% [fighter.name, fighter.animation_tree.process_mode if fighter.animation_tree else -1])
		check(fighter.animation_tree != null
			and fighter.animation_tree.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
			"%s must not be frozen by switching callback_mode_process (it restarts the state machine)"
			% fighter.name)

	# ── 受擊者：hitstop 期間就必須「已進入並停在」受擊動畫第 0 格 ──
	# 【角色分工】p1 = player_a（DAV）按 st_mp 出招 → 攻擊者；
	#            p2 = player_b（DEN）被打中 → 受擊者。
	# （舊版這裡把兩者寫反，於是斷言一直拿攻擊者的 sprite 去比 "hit"。）
	# DEN 的受擊動畫有多個變體（hit / hitb / hitc / cr_hit），由 take_hit 依
	# 攻擊強度與姿勢挑選 —— 這裡只在意「已經切進某個受擊動畫」。
	var hit_anims := [&"hit", &"hitb", &"hitc", &"cr_hit"]
	var defender_sprite := p2.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var defender_hit_anim: StringName = defender_sprite.animation
	check(defender_hit_anim in hit_anims,
		"Defender sprite should already show a hit animation during hitstop, got '%s'"
		% defender_hit_anim)
	check(defender_sprite.frame == 0,
		"Defender should be frozen on hit animation frame 0, got %d" % defender_sprite.frame)

	# ── 攻擊者：定格在打中瞬間的姿勢 ──
	var attacker_sprite := p1.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var att_anim_at_hitstop_start: StringName = attacker_sprite.animation
	var att_frame_at_hitstop_start: int = attacker_sprite.frame
	var att_offset_at_hitstop_start: Vector2 = attacker_sprite.offset

	# hitstop 只有 8 物理幀：取樣兩次，雙方 sprite 的動畫名與格數都不得推進。
	for sample in 2:
		await await_frames(2)
		if not slowmo.is_hit_slowmo:
			break  # CI 偶發卡頓讓 hitstop 提前結束時，略過「期間取樣」（結束後另有斷言）
		check(attacker_sprite.animation == att_anim_at_hitstop_start
			and attacker_sprite.frame == att_frame_at_hitstop_start,
			"Attacker pose must be frozen during hitstop (%s/%d → %s/%d)" % [
				att_anim_at_hitstop_start, att_frame_at_hitstop_start,
				attacker_sprite.animation, attacker_sprite.frame])
		# 震抖只屬於受擊方：攻擊者的 sprite offset 不得被 jitter 動到。
		check(attacker_sprite.offset == att_offset_at_hitstop_start,
			"Attacker sprite must not jitter during hitstop (%s → %s)" % [
				att_offset_at_hitstop_start, attacker_sprite.offset])
		check(defender_sprite.animation == defender_hit_anim and defender_sprite.frame == 0,
			"Defender must stay on the hit animation frame 0 during hitstop, got %s/%d"
			% [defender_sprite.animation, defender_sprite.frame])

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

	# ── 結束後：AnimationTree 還原為自動處理（process_mode 放回場景預設）──
	for fighter in [p1, p2]:
		check(fighter.animation_tree.process_mode != Node.PROCESS_MODE_DISABLED,
			"%s AnimationTree process_mode should be restored after hitstop, got %d"
			% [fighter.name, fighter.animation_tree.process_mode])
		check(fighter.animation_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
			"%s AnimationTree should stay on auto (IDLE) callback mode, got %d"
			% [fighter.name, fighter.animation_tree.callback_mode_process])

	# ── 結束後：受擊動畫從凍結點開始播放（格數推進）──
	# hitstun 還有約 28 物理幀，動畫 0.05s 換一格：20 幀窗口內必然推進。
	var frozen_frame: int = defender_sprite.frame
	var advanced: bool = await wait_until(
		func(): return defender_sprite.frame > frozen_frame, 20)
	check(advanced,
		"Hit animation should start playing after hitstop ends (frame stuck at %d)"
		% frozen_frame)
	if advanced:
		check(defender_sprite.animation == defender_hit_anim,
			"Hit animation should keep playing after hitstop, got '%s'"
			% defender_sprite.animation)

	return not has_failures()
