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
	
	var move_set = movement_node.get_node_or_null("MoveSet")
	
	if move_set and move_set.is_spmove:
		var active_move_name = move_set.get_active_move_name()
		if active_move_name in ["super", "hdk", "powerkk", "spnk", "dp", "fireball"]:
			return active_move_name
	
	if movement_node.is_proximity_blocking:
		return "cr_block" if movement_node.is_crouching else "block"
	if movement_node.is_blocking:
		return "cr_block" if movement_node.is_crouch_blocking and crouch_input else "block"
	
	if movement_node.is_attacking:
		var atype = movement_node.get("attack_type") if "attack_type" in movement_node else "none"
		if atype in ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk", "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk", "super", "dp", "powerkk", "spnk", "fireball", "hdk"]:
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
		if "is_air_attacking" in movement_node and (movement_node.is_air_attacking or ("has_air_attacked" in movement_node and movement_node.has_air_attacked)):
			return movement_node.get("attack_type") if "attack_type" in movement_node else "jump_mp"
		else:
			return "Jump_F" if anim_jump_dir > 0 else ("Jump_B" if anim_jump_dir < 0 else "Jump_V")
	
	return "Walk"

func update_animation_state(dir_x: float, crouch_input: bool) -> void:
	if not movement_node.animation_state:
		return
	
	var curr_state: String = movement_node.animation_state.get_current_node() if movement_node.animation_state else ""
	var on_floor: bool = movement_node.is_on_floor()
	var anim_dir: float = dir_x * movement_node.facing_direction
	var anim_jump_dir: float = movement_node.jump_dir * movement_node.facing_direction
	var target_state: String = movement_node._compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	# 🟢 【只在實際改變時打印】避免冗餘日誌（Start→Walk在啟動時會重複很多次）
	if curr_state != target_state:
		# 過濾掉遊戲啟動時的 Start→Walk 重複（只打印特殊招式和重要狀態轉換）
		var is_special_relevant = target_state in ["dp", "powerkk", "super", "hdk", "spnk", "knockfly", "layground"] or curr_state in ["dp", "powerkk", "super", "hdk", "spnk", "knockfly", "layground"]
		if is_special_relevant:
			# 🟢 去重：只打印新的狀態轉換（不是上一幀已經打過的相同轉換）
			var transition_key = "%s→%s" % [curr_state, target_state]
			if last_printed_transition != transition_key:
				var seat_str = movement_node.seat if "seat" in movement_node else "?"
				var is_special_moving = movement_node.is_special_moving if "is_special_moving" in movement_node else false
				print("[STATE_CHANGE] %s: '%s' → '%s' (spmove=%s)" % [seat_str, curr_state, target_state, is_special_moving])
				last_printed_transition = transition_key
	
	var ui_root = movement_node.get_tree().get_first_node_in_group("ui")
	var healthbar_name = "PlayerAHealthbar" if movement_node.seat == "player_a" else "PlayerBHealthbar"
	var healthbar = ui_root.get_node_or_null(healthbar_name) if ui_root else null
	if healthbar and healthbar.current_health <= 0 and movement_node.is_layground:
		target_state = "layground"
		movement_node.animation_state.travel("layground")
		return
	
	# 移除會覆寫 target_state 的邏輯，因為 compute_target_state 已經正確處理了所有狀態
	# 如果這裡再根據 jump_dir 覆寫，會導致空中受擊的 Jump_B 被改成 Jump_F/Jump_V
	
	set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		if not (target_state == "knockfly" and movement_node.is_knockfly_animation_finished and not movement_node.is_on_floor()):
			movement_node.animation_state.travel(target_state)
	
	if target_state == "Walk":
		movement_node.animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
	if movement_node.is_jumping and on_floor:
		movement_node.is_jumping = false
