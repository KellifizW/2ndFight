extends "res://tests/frame_tests/frame_test_case.gd"
## 長 hitstop（hitstop_frames = 60）時，攻擊者必須定格在「打中那一格」。
##
## 使用者回報的症狀（編輯器把 hitstop_frames 調到 60 之後）：
##   攻擊者的動畫在擊中對方的瞬間不但沒有停在打擊中的動畫格，反而被重置成 idle
##   的動畫格；等 hitstop 時滯結束後，同一段打擊動畫又被重播（甚至播多次）。
##
## 根因（Godot 引擎行為，不是遊戲邏輯）：
##   舊版 HitStopController 用 `AnimationTree.callback_mode_process = MANUAL` 定格。
##   `AnimationMixer::set_callback_mode_process()` 內部是
##   `set_active(false)` → 換模式 → `set_active(true)`，而 `AnimationTree::_set_active()`
##   會把 mixer 的 `started` 旗標設為 true。下一次處理（＝定格時的 advance(0)）
##   `_blend_pre_process()` 便以 `seeked = true, time = 0, is_external_seeking = false`
##   進入狀態機，命中 AnimationNodeStateMachinePlayback 的
##   「Check seek to 0 (means reset) by parent AnimationNode」分支 → `_start()` →
##   **整台狀態機重啟回 Start 節點**。
##   受擊方有 take_hit() 排好的 travel，重啟後立刻被帶去受擊動畫，所以看不出來；
##   攻擊方沒有待處理的 travel，重啟後就掉回 Start → idle。解凍時還原
##   callback_mode_process 會再重啟一次，狀態機回到 idle 而 `is_attacking` 仍為 true，
##   動畫層於是又 travel 一次攻擊動畫 —— 就是「解凍後重播打擊動畫」。
##
## 修正：改用 `AnimationTree.process_mode = PROCESS_MODE_DISABLED` 定格
##（完全不碰 active / callback_mode_process，狀態機內部原封不動）。
##
## 本用例釘住三件事：
##   1. 打中的瞬間，攻擊者的 sprite 動畫名與格數 == 打中前一幀的值（不得跳回 idle）。
##   2. 整段 hitstop 期間，攻擊者的動畫名／格數／狀態機節點都不得改變。
##   3. 解凍後不得「重播」打擊動畫（動畫不得重新回到第 0 格再播一次）。

const HITSTOP_FRAMES: int = 60  # 物理幀 @120 FPS = 0.5 秒


func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	var hitstop_controller = world.get_node_or_null("HitStopController")
	check(hitstop_controller != null, "World should contain a HitStopController node")
	if hitstop_controller == null:
		return not has_failures()

	hitstop_controller.hitstop_unit = 0  # HitstopUnit.PHYSICS_FRAMES_120FPS
	hitstop_controller.hitstop_frames = HITSTOP_FRAMES

	var attacker: Node = p1  # player_a（DAV）＝ 按 st_mp 的一方
	var attacker_sprite := attacker.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var slowmo = attacker.slow_mo_controller
	check(slowmo != null, "Attacker should see the SlowMoController")
	if slowmo == null:
		return not has_failures()

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	# ── 逐幀取樣，記住「hitstop 開始前最後一幀」的攻擊者姿勢 ──
	var prev_anim: StringName = attacker_sprite.animation
	var prev_frame: int = attacker_sprite.frame
	var prev_node: StringName = attacker.animation_state.get_current_node()
	var hitstop_started: bool = false
	for i in 120:
		await await_frames(1)
		if slowmo.is_hit_slowmo:
			hitstop_started = true
			break
		prev_anim = attacker_sprite.animation
		prev_frame = attacker_sprite.frame
		prev_node = attacker.animation_state.get_current_node()

	check(hitstop_started, "st_mp 命中時應該進入 hitstop")
	if not hitstop_started:
		return not has_failures()

	# 取樣有效性：打中前一幀，攻擊者本來就該停在某個地面攻擊狀態上。
	check(prev_node in FighterState.GROUND_ATTACK_IDS,
		"打中前一幀攻擊者應該在攻擊狀態，實測狀態機節點 '%s'" % prev_node)

	# 1) 打中的瞬間：攻擊者停在「打中那一格」，不得被重置成 idle。
	#    （動畫格數允許比取樣點前進 —— AnimationTree 走 idle callback，最後一次
	#      取樣到真正凍結之間可能還過了一個 render frame；但動畫**名稱**與狀態機
	#      節點絕不能改變，格數也絕不能倒退回 0。）
	check(attacker_sprite.animation == prev_anim,
		"攻擊者在打中瞬間應停在打擊動畫 '%s'，實測被切成 '%s'（狀態機 '%s' → '%s'）"
		% [prev_anim, attacker_sprite.animation, prev_node,
			attacker.animation_state.get_current_node()])
	check(attacker.animation_state.get_current_node() == prev_node,
		"攻擊者的狀態機節點不得因為定格而改變（'%s' → '%s'）"
		% [prev_node, attacker.animation_state.get_current_node()])
	check(attacker_sprite.frame >= prev_frame,
		"攻擊者的動畫格不得倒退（打中前 %d → 定格 %d）"
		% [prev_frame, attacker_sprite.frame])

	# 2) 整段定格期間：動畫名／格數／狀態機節點都不得推進。
	var frozen_anim: StringName = attacker_sprite.animation
	var frozen_frame: int = attacker_sprite.frame
	var frames_in_hitstop: int = 0
	while slowmo.is_hit_slowmo and frames_in_hitstop < HITSTOP_FRAMES * 3:
		await await_frames(1)
		if not slowmo.is_hit_slowmo:
			break
		frames_in_hitstop += 1
		check(attacker_sprite.animation == frozen_anim
			and attacker_sprite.frame == frozen_frame,
			"定格期間攻擊者的姿勢不得改變（第 %d 幀：%s/%d → %s/%d）"
			% [frames_in_hitstop, frozen_anim, frozen_frame,
				attacker_sprite.animation, attacker_sprite.frame])
		check(attacker.animation_state.get_current_node() == prev_node,
			"定格期間攻擊者的狀態機節點不得改變（第 %d 幀：'%s' → '%s'）"
			% [frames_in_hitstop, prev_node, attacker.animation_state.get_current_node()])

	check(frames_in_hitstop >= HITSTOP_FRAMES - 3,
		"定格長度應約等於 %d 物理幀，實測 %d" % [HITSTOP_FRAMES, frames_in_hitstop])

	# 3) 解凍後：打擊動畫只能「從定格點繼續播完」，不得重新從第 0 格再播一次。
	var last_anim: StringName = attacker_sprite.animation
	var last_frame: int = attacker_sprite.frame
	var replays: int = 0
	var left_attack_anim: bool = false
	# 觀察窗與 test_38 一致（90 物理幀）：這段時間內攻擊者不會有第二次出招。
	for i in 90:
		await await_frames(1)
		var anim: StringName = attacker_sprite.animation
		var frame_idx: int = attacker_sprite.frame
		if anim == frozen_anim:
			# 同一段打擊動畫內倒帶 = 重播；離開後又回來也是重播。
			if left_attack_anim or (last_anim == frozen_anim and frame_idx < last_frame):
				replays += 1
				left_attack_anim = false
		elif last_anim == frozen_anim:
			left_attack_anim = true
		last_anim = anim
		last_frame = frame_idx

	check(replays == 0,
		"解凍後打擊動畫 '%s' 不得被重播，實測重播 %d 次" % [frozen_anim, replays])

	return not has_failures()
