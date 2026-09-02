class_name AnimationManager extends Node

# Handles animation state management and updates
var movement_node: Node
# 🟢 去重: 追蹤最後一次打印的狀態轉換，避免重複
var last_printed_transition: String = ""

func _init(movement: Node) -> void:
	movement_node = movement

func set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	if not movement_node.animation_tree:
		return
	
	for c in movement_node.animation_conditions:
		var condition_value: bool = (target_state == c)
		if c == "Walk":
			condition_value = condition_value and on_floor and not crouch_input
		elif c == "cr_block":
			condition_value = condition_value and movement_node.is_crouch_blocking and crouch_input
		movement_node.animation_tree.set("parameters/conditions/" + c, condition_value)

## Stage 2 切片 6 之前的舊判定鏈（已刪除）。保留這段說明是因為它解釋了
## 為什麼「刪掉一大段看起來在用的程式碼」是安全的：
## 所有角色場景掛的都是 player.gd，而 Player._compute_target_state() 會先
## 攔截 layground / knockfly / wakeup / hit / spmove / blocking / landing /
## 空中八段，所以本檔原本重寫的那八段**永遠跑不到**（順序甚至與 Player 不同，
## 正說明沒人同步過它們）。統一後的順序 = 兩份抄本合成後實際生效的順序，
## 由 ci/verify_animation_chain.py（18,874,368 組合）與 test_40 逐幀釘住。
func compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	# ── Stage 2 切片 6：判定鏈本身已搬到 FighterState.animation_for() ──
	# 這裡只剩「播放層」該做的兩件事：拿到目標動畫名，以及執行兩個
	# 與判定無關的副作用（蹲下轉場、著地診斷日誌）。
	# 判定鏈為什麼要搬走、以及舊的兩份抄本差在哪，見 FighterState.animation_for。
	var target_state: String = FighterState.animation_for(
		movement_node, crouch_input, on_floor, anim_jump_dir)

	# 副作用 1：第一次進入蹲姿時排一次 cr_down 轉場（舊鏈內聯在 crouch 分支裡）。
	# 「cr_idle」只會由那個分支產生，故此處條件與舊版逐值等價。
	if target_state == "cr_idle" and not movement_node.was_crouching_last_frame:
		if movement_node.animation_state:
			movement_node.animation_state.call_deferred("travel", "cr_down")

	# 副作用 2：著地診斷日誌（Debug 預設關閉，只在開啟時輸出）。
	_log_landing_diagnostics(target_state)

	return target_state

## 著地相關診斷日誌。舊鏈把它們夾在 landing 判定分支裡，其中
## 「landing 真的要播」與「被 spmove 擋下」兩條在實機上不可達
## （Player 的頭段先回傳了），統一後才第一次真的會輸出。
func _log_landing_diagnostics(target_state: String) -> void:
	if not ("is_landing" in movement_node) or not movement_node.is_landing:
		return
	var seat = movement_node.seat if "seat" in movement_node else "?"
	var lock_frames: int = int(movement_node.landing_lock_frames) if "landing_lock_frames" in movement_node else 0
	if target_state == "landing":
		var move_set_for_landing = movement_node.get_node_or_null("MoveSet")
		var active_move = move_set_for_landing.get_active_move_name() if move_set_for_landing and move_set_for_landing.has_method("get_active_move_name") else "none"
		Debug.log("[LANDING_ANIMATION_PLAY] %s | move=%s | lock_frames=%d" % [
			seat, active_move, lock_frames
		])
	elif lock_frames <= 0:
		# is_landing 為真卻沒有剩餘鎖幀 = 著地被中斷（Stage 1 不變式的破口，
		# test_25 的 check_invariants 也會抓）。
		Debug.log("[LANDING_INTERRUPTED] %s: is_landing=true but lock_frames=%d (should be false)" % [
			seat, lock_frames
		])

func update_animation_state(dir_x: float, crouch_input: bool) -> void:
	if not movement_node.animation_state:
		return
	
	# 🟢 Hitstop 期間不要重新呼叫動畫更新：
	# HitStopController 凍結期間會把 AnimationTree 切到手動模式（MANUAL），此時
	# 就算排 travel 也不會被套用，反而會積壓到恢復後一次生效、跳過中間狀態。
	# 這裡直接跳過，讓 hitstop 結束後的第一次更新接手（凍結瞬間的姿勢切換
	# 由 HitStopController._apply_frozen_poses() 的 delta=0 沖洗完成）。
	var world = movement_node.get_tree().get_first_node_in_group("world") if movement_node.get_tree() else null
	var slowmo_controller = world.get_node_or_null("SlowMoController") if world else null
	if slowmo_controller and slowmo_controller.is_hit_slowmo:
		return

	var curr_state: String = movement_node.animation_state.get_current_node() if movement_node.animation_state else ""
	var on_floor: bool = movement_node.is_on_floor()
	var anim_dir: float = dir_x * movement_node.facing_direction
	var anim_jump_dir: float = movement_node.jump_dir * movement_node.facing_direction
	var target_state: String = movement_node._compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	var seat_str = movement_node.seat if "seat" in movement_node else "?"
	var is_landing = movement_node.is_landing if "is_landing" in movement_node else false
	var landing_lock = movement_node.landing_lock_frames if "landing_lock_frames" in movement_node else 0
	var move_set = movement_node.get_node_or_null("MoveSet")
	var is_spmove = move_set.is_spmove if move_set else false
	
	# 🟢 【只在實際改變時打印】避免冗餘日誌（Start→Walk在啟動時會重複很多次）
	if curr_state != target_state:
		# 過濾掉遊戲啟動時的 Start→Walk 重複（只打印特殊招式和重要狀態轉換）
		# 特殊招式狀態變更：以 is_spmove / move_library 判定，避免新招漏登白名單
		var is_special_relevant = is_spmove
		if not is_special_relevant and move_set and move_set.has_method("has_move_id"):
			is_special_relevant = move_set.has_move_id(target_state) or move_set.has_move_id(curr_state)
		if not is_special_relevant:
			var _sp_states = ["knockfly", "layground", "landing"]
			is_special_relevant = target_state in _sp_states or curr_state in _sp_states
		if is_special_relevant:
			# 🟢 去重：只打印新的狀態轉換（不是上一幀已經打過的相同轉換）
			var transition_key = "%s→%s" % [curr_state, target_state]
			if last_printed_transition != transition_key:
				Debug.log("[STATE_CHANGE] %s: '%s' → '%s' (spmove=%s is_landing=%s lock_frames=%d)" % [seat_str, curr_state, target_state, is_spmove, is_landing, landing_lock])
				last_printed_transition = transition_key
	
	var ui_root = movement_node.get_tree().get_first_node_in_group("ui")
	var healthbar_name = "PlayerAHealthbar" if movement_node.seat == "player_a" else "PlayerBHealthbar"
	var healthbar = ui_root.get_node_or_null(healthbar_name) if ui_root else null
	if healthbar and healthbar.current_health <= 0 and movement_node.is_layground:
		target_state = "layground"
		movement_node.animation_state.travel("layground")
		return

	if target_state == "landing":
		if movement_node.animation_tree:
			movement_node.animation_tree.active = false
		if movement_node.animation_player and movement_node.animation_player.current_animation != "landing":
			movement_node.animation_player.play("landing")
			movement_node.animation_player.seek(0.0, true)
		return
	elif movement_node.animation_tree and not movement_node.animation_tree.active:
		movement_node.animation_tree.active = true
	
	# 移除會覆寫 target_state 的邏輯，因為 compute_target_state 已經正確處理了所有狀態
	# 如果這裡再根據 jump_dir 覆寫，會導致空中受擊的 Jump_B 被改成 Jump_F/Jump_V
	
	set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		if not (target_state == "knockfly" and movement_node.is_knockfly_animation_finished and not movement_node.is_on_floor()):
			movement_node.animation_state.travel(target_state)
	
	if target_state == "Walk":
		movement_node.animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
