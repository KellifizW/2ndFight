class_name PlayerController extends Node

@export var player_id: String = "p1"

func get_input_data() -> Dictionary:
	var suffix = "_p2" if player_id == "p2" else ""
	var move_right = Input.is_action_pressed("move_right" + suffix)
	var move_left = Input.is_action_pressed("move_left" + suffix)
	var move_up = Input.is_action_just_pressed("jump" + suffix)
	var move_down = Input.is_action_pressed("crouch" + suffix)
	
	var dir_x: int = 0
	if move_right and not move_left:
		dir_x = 1
	elif move_left and not move_right:
		dir_x = -1
	
	var dir_y: int = 0
	if move_up and not move_down:
		dir_y = -1
	elif move_down and not move_up:
		dir_y = 1
	
	var input_dir: int = dir_x
	var crouch_pressed: bool = dir_y > 0
	var jump_pressed: bool = dir_y < 0
	
	var st_mp_pressed = Input.is_action_just_pressed("st_mp" + suffix)
	var st_mk_pressed = Input.is_action_just_pressed("st_mk" + suffix)
	var spm1_pressed = Input.is_action_just_pressed("spmove1" + suffix)
	var spm2_pressed = Input.is_action_just_pressed("spmove2" + suffix)
	
	# 檢查 fireball 和 powerkk 序列
	var input_manager = get_parent().get_node("InputManager") if get_parent().has_node("InputManager") else null
	if input_manager:
		if player_id == "p1" and input_manager.check_powerkk_input():
			spm1_pressed = true
			st_mp_pressed = false  # 抑制正常 st_mp
		if input_manager.check_fireball_input():
			spm2_pressed = true
			st_mp_pressed = false  # 抑制正常 st_mp
	
	var move_set = get_parent().get_node("MoveSet") if get_parent().has_node("MoveSet") else null
	# 修正 attack_type 邏輯，優先處理 spm1_pressed 和 spm2_pressed
	var attack_type = "powerkk" if spm1_pressed and player_id == "p1" else "fireball" if spm2_pressed else "st_mp" if st_mp_pressed else "st_mk" if st_mk_pressed else "none"
	var blockstun_duration = 0.4 if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")) else 0.3 if move_set and move_set.is_fireball else 0.2
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball) else (10.0 if (st_mp_pressed or st_mk_pressed) else 0.0)
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"st_mp_pressed": st_mp_pressed,
		"st_mk_pressed": st_mk_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed
	}
