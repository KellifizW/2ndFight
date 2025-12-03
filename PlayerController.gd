# PlayerController.gd
class_name PlayerController extends Node

@export var player_id: String = "p1"

func get_input_data() -> Dictionary:
	var suffix = "_p2" if player_id == "p2" else ""
	var move_right = Input.is_action_pressed("move_right" + suffix)
	var move_left  = Input.is_action_pressed("move_left" + suffix)
	var move_up    = Input.is_action_pressed("jump" + suffix)      # 持續跳躍輸入
	var move_down  = Input.is_action_pressed("crouch" + suffix)
	
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
	var jump_pressed: bool   = dir_y < 0
	
	var st_mp_pressed = Input.is_action_just_pressed("st_mp" + suffix)
	var st_mk_pressed = Input.is_action_just_pressed("st_mk" + suffix)
	var spm1_pressed  = Input.is_action_just_pressed("spmove1" + suffix)
	var spm2_pressed  = Input.is_action_just_pressed("spmove2" + suffix)
	var spm3_pressed  = Input.is_action_just_pressed("spmove3" + suffix)
	var super_pressed = Input.is_action_just_pressed("super" + suffix)
	var dp_pressed    = false
	
	# 輸入序列檢測（保留你原本的 InputManager 邏輯）
	var input_manager = get_parent().get_node("InputManager") if get_parent().has_node("InputManager") else null
	if input_manager:
		if player_id == "p1" and input_manager.check_powerkk_input():
			spm1_pressed = true
			st_mp_pressed = false
		if player_id == "p1" and input_manager.check_dp_input():
			dp_pressed = true
			st_mp_pressed = false
		if player_id == "p2" and input_manager.check_spnk_input():
			spm1_pressed = true
			st_mk_pressed = false
		if input_manager.check_fireball_input():
			spm2_pressed = true
			st_mp_pressed = false
	
	# === 新增：P2 的 spmove3 直接觸發 hdk ===
	if player_id == "p2" and spm3_pressed:
		# 這裡不需要額外變數，直接在後面的 attack_type 判斷即可
		pass
	
	# P1 的 spm3 快捷觸發 dp（你原本就有的）
	if player_id == "p1" and spm3_pressed:
		dp_pressed = true
	
	# 攻擊優先級（已加入 P2 的 hdk）
	var attack_type = (
		"super"    if super_pressed else
		"powerkk"  if spm1_pressed and player_id == "p1" else
		"dp"       if dp_pressed and player_id == "p1" else
		"spnk"     if spm1_pressed and player_id == "p2" else
		"hdk"      if spm3_pressed and player_id == "p2" else          # ← 這一行是新增的
		"fireball" if spm2_pressed else
		"st_mp"    if st_mp_pressed else
		"st_mk"    if st_mk_pressed else
		"none"
	)

	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"st_mp_pressed": st_mp_pressed,
		"st_mk_pressed": st_mk_pressed,
		"attack_type": attack_type,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed,
		"spm3_pressed": spm3_pressed,       # 建議也回傳，之後狀態機可能會用到
		"super_pressed": super_pressed,
		"dp_pressed": dp_pressed
	}
