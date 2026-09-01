extends "res://tests/frame_tests/frame_test_case.gd"
## 長 hitstop（hitstop_frames = 60）不得讓同一次揮拳被重複觸發／重複命中。
##
## 使用者回報的症狀：把編輯器的 hitstop_frames 調到 60 之後，攻擊方打中對手，
## 定格一結束同一招會再放一次（並再打中一次）。根因有兩條，本用例同時釘住：
##
##   1. 定格期間角色的「行動層」沒有被凍結 —— 攻擊移動、MoveSet、攻擊執行
##      每個物理幀照跑。定格中執行的 travel() 只會排隊（AnimationTree 是
##      MANUAL），等解凍才一次生效，看起來就是「解凍後又出了一次同樣的招」。
##   2. 單段攻擊沒有「一次揮拳只命中一次」的登記。定格期間 Hitbox 仍然開著，
##      而 PushManager / 攻擊前衝仍在移動角色，Hitbox 離開再進入 Hurtbox 就會
##      再觸發一次完整命中流程（第二次 take_hit / 音效 / 特效 / hitstop）。
##
## 定格長度越長，兩條路徑的時間窗越長 —— 所以問題在高 hitstop 值才穩定重現。

const HITSTOP_FRAMES: int = 60  # 物理幀 @120 FPS = 0.5 秒


func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	var hitstop_controller = world.get_node_or_null("HitStopController")
	check(hitstop_controller != null, "World should contain a HitStopController node")
	if hitstop_controller == null:
		return not has_failures()

	# 用「物理幀」單位把定格拉長到使用者回報的設定值。
	hitstop_controller.hitstop_unit = 0  # HitstopUnit.PHYSICS_FRAMES_120FPS
	hitstop_controller.hitstop_frames = HITSTOP_FRAMES
	check(hitstop_controller.get_hitstop_physics_frames() == HITSTOP_FRAMES,
		"hitstop_unit = physics frames 時，設定值就是物理幀數（got %d）"
		% hitstop_controller.get_hitstop_physics_frames())

	var attacker: Node = p1  # player_a（DAV）＝ 按 st_mp 的一方
	var defender: Node = p2
	var attacks_before: int = int(attacker.debug_attack_execution_count)
	var health_before: float = defender.healthbar.current_health if defender.healthbar else -1.0

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	var slowmo = attacker.slow_mo_controller
	var hitstop_started: bool = await wait_until(
		func(): return slowmo != null and slowmo.is_hit_slowmo, 120)
	check(hitstop_started, "st_mp 命中時應該進入 hitstop")
	if not hitstop_started:
		return not has_failures()

	var attacker_sprite := attacker.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var defender_sprite := defender.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var attacker_offset: Vector2 = attacker_sprite.offset
	var attacker_x_at_freeze: float = px(attacker)
	var defender_offsets: Dictionary = {}

	# ── 定格期間 ──
	var frames_in_hitstop: int = 0
	while slowmo.is_hit_slowmo and frames_in_hitstop < HITSTOP_FRAMES * 3:
		await await_frames(1)
		if not slowmo.is_hit_slowmo:
			break  # 這一幀已經解凍，之後的動作屬於正常恢復，不再套用定格斷言
		frames_in_hitstop += 1
		check(abs(px(attacker) - attacker_x_at_freeze) < 1.0,
			"定格期間攻擊方不應該繼續前衝（第 %d 幀，%.2f → %.2f）"
			% [frames_in_hitstop, attacker_x_at_freeze, px(attacker)])
		check(int(attacker.debug_attack_execution_count) == attacks_before + 1,
			"定格期間不得再出招（第 %d 幀，count=%d）"
			% [frames_in_hitstop, attacker.debug_attack_execution_count])
		check(attacker_sprite.offset == attacker_offset,
			"攻擊方 sprite 不應該震抖（第 %d 幀，%s → %s）"
			% [frames_in_hitstop, attacker_offset, attacker_sprite.offset])
		defender_offsets[defender_sprite.offset] = true

	# 定格長度應該等於設定值（±3 幀取樣誤差）。
	check(abs(frames_in_hitstop - HITSTOP_FRAMES) <= 3,
		"定格長度應約等於 %d 物理幀，實測 %d" % [HITSTOP_FRAMES, frames_in_hitstop])
	check(defender_offsets.size() > 1,
		"受擊方 sprite 應該有震抖（jitter_target = Defender only，實測 %d 種 offset）"
		% defender_offsets.size())

	# ── 定格結束後再觀察 90 幀：不得有第二次出招／第二次命中 ──
	for i in 90:
		await await_frames(1)
		check(int(attacker.debug_attack_execution_count) == attacks_before + 1,
			"一次按鍵只能出一招（解凍後第 %d 幀，count=%d）"
			% [i, attacker.debug_attack_execution_count])

	var hit_handler = attacker.hit_response_handler
	check(hit_handler != null and int(hit_handler.debug_hit_registered_count) == 1,
		"同一次揮拳只能登記一次命中，實測 %s"
		% [hit_handler.debug_hit_registered_count if hit_handler else "no handler"])

	if health_before > 0.0 and defender.healthbar:
		var damage: float = health_before - defender.healthbar.current_health
		check(damage > 0.0, "受擊方應該掉血（實測 %.1f）" % damage)
		check(damage <= 6.0 + 0.01,
			"一拳只能造成一次傷害（st_mp = 6.0，實測 %.1f）" % damage)

	return not has_failures()
