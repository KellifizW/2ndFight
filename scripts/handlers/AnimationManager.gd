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

func compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	# 優先處理空中受擊狀態，確保不會被 jump_dir 覆寫
	if "is_air_hit_backjump" in movement_node and movement_node.is_air_hit_backjump:
		return "Jump_B"
	
	if movement_node.is_hit:
		# 空中受擊永遠播放 Jump_B（後跳）動畫
		if not on_floor:
			return "Jump_B"
		# 地面受擊：根據受擊時的姿勢選擇動畫
		return "cr_hit" if movement_node.was_hit_while_crouching else "hit"
	
	if movement_node.is_layground:
		return "layground"
	if movement_node.is_knockfly:
		return "knockfly"
	if "is_wakeup_locked" in movement_node and movement_node.is_wakeup_locked:
		return "wakeup"
	
	# 【著地動畫優先】著地動畫應該優先於其他狀態，確保平滑過渡
	# 【業界標準】但在特殊招式期間，不播放landing動畫（由extended move animation包含）
	var seat = movement_node.seat if "seat" in movement_node else "?"
	
	if "is_landing" in movement_node and movement_node.is_landing and "landing_lock_frames" in movement_node and movement_node.landing_lock_frames > 0:
		var move_set_for_landing = movement_node.get_node_or_null("MoveSet")
		var is_spmove_active = move_set_for_landing and move_set_for_landing.is_spmove
		var active_move = move_set_for_landing.get_active_move_name() if move_set_for_landing and move_set_for_landing.has_method("get_active_move_name") else "none"
		
		if not is_spmove_active:  # 【重要】只在特殊招式結束後播放
			Debug.log("[LANDING_ANIMATION_PLAY] %s | move=%s | lock_frames=%d | spmove=%s" % [
				seat, active_move, movement_node.landing_lock_frames, is_spmove_active
			])
			return "landing"
		else:
			Debug.log("[LANDING_BLOCKED_BY_SPMOVE] %s | move=%s | lock_frames=%d" % [
				seat, active_move, movement_node.landing_lock_frames
			])
	elif "is_landing" in movement_node and movement_node.is_landing and "landing_lock_frames" in movement_node and movement_node.landing_lock_frames <= 0:
		# 【檢測】landing 被中斷
		Debug.log("[LANDING_INTERRUPTED] %s: is_landing=true but lock_frames=%d (should be false)" % [
			seat, movement_node.landing_lock_frames
		])
	elif "is_landing" in movement_node and movement_node.is_landing and ("landing_lock_frames" not in movement_node or movement_node.landing_lock_frames <= 0):
		# 【檢測】沒進入 landing 狀態的原因
		var lock_val = movement_node.landing_lock_frames if "landing_lock_frames" in movement_node else "N/A"
		Debug.log("[LANDING_NOT_PLAYING] %s: is_landing=true, lock_frames=%s, jumping=%s, knockfly=%s" % [
			seat, lock_val, movement_node.is_jumping, movement_node.is_knockfly
		])
	
	var move_set = movement_node.get_node_or_null("MoveSet")

	# 特殊招式進行中：一律鎖定招式動畫（不靠白名單）。
	# 升空類招式會設 is_jumping=true；若此處未攔截，下面空中分支會覆寫成 Jump_*。
	if move_set and move_set.is_spmove:
		var active_move_name = move_set.get_active_move_name()
		if active_move_name != "":
			return active_move_name
	
	if movement_node.is_proximity_blocking:
		return "cr_block" if movement_node.is_crouching else "block"
	if movement_node.is_blocking:
		return "cr_block" if movement_node.is_crouch_blocking and crouch_input else "block"
	
	if movement_node.is_attacking:
		var atype = movement_node.get("attack_type") if "attack_type" in movement_node else "none"
		# 普通攻擊 / 摔投：走固定 id 表。特殊招式 id 若誤入 is_attacking，也原樣回傳（不切 Walk）。
		if atype in ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk", "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk", "throw_enter", "throw_seq"]:
			return atype
		if atype != "" and atype != "none" and move_set and move_set.has_method("has_move_id") and move_set.has_move_id(atype):
			return atype
		return "Walk"
	
	if movement_node.is_dashing:
		return "Dash"
	if movement_node.is_backdashing:
		return "Backdash"
	
	if crouch_input and on_floor and not movement_node.is_blocking:
		if not movement_node.was_crouching_last_frame:
			if movement_node.animation_state:
				movement_node.animation_state.call_deferred("travel", "cr_down")
		return "cr_idle"
	
	if not on_floor and (movement_node.is_jumping or ("is_air_attacking" in movement_node and movement_node.is_air_attacking)):
		if "is_air_attacking" in movement_node and movement_node.is_air_attacking:
			var air_attack_type = movement_node.get("attack_type") if "attack_type" in movement_node else ""
			if air_attack_type in ["jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk"]:
				return air_attack_type
		return "Jump_F" if anim_jump_dir > 0 else ("Jump_B" if anim_jump_dir < 0 else "Jump_V")
	
	return "Walk"

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
	
