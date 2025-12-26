# PlayerController.gd（修正版：加入 Dash/Backdash 支援 + 持續按上鍵可連續跳躍）

class_name PlayerController extends Node

@export var player_id: String = "p1"

# Dash / Backdash 雙擊偵測變數
var last_input_dir: int = 0
var double_tap_timer: float = 0.0
const DOUBLE_TAP_TIME: float = 0.3  # 雙擊時間窗口（秒），與 Movement 原設定一致

# 每幀更新雙擊計時器
func _process(delta: float) -> void:
	if double_tap_timer > 0:
		double_tap_timer -= delta
		if double_tap_timer <= 0:
			double_tap_timer = 0.0
			last_input_dir = 0

func get_input_data() -> Dictionary:
	var suffix = "_p2" if player_id == "p2" else ""
	
	# 基本移動輸入
	var move_right = Input.is_action_pressed("move_right" + suffix)
	var move_left  = Input.is_action_pressed("move_left" + suffix)
	
	# 跳躍改為持續按住即可觸發（落地後會立刻再跳）
	var jump_action = Input.is_action_pressed("jump" + suffix)
	
	# 蹲下保持 pressed
	var crouch_action = Input.is_action_pressed("crouch" + suffix)
	
	var dir_x: int = 0
	if move_right and not move_left:  
		dir_x = 1
	elif move_left and not move_right:  
		dir_x = -1
	
	var input_dir: int = dir_x
	var crouch_pressed: bool = crouch_action
	var jump_pressed: bool = jump_action  # 持續按住為 true，允許連續跳躍
	
	# Dash / Backdash 偵測
	var dash_pressed: bool = false
	var backdash_pressed: bool = false
	
	if input_dir != 0:
		# 判斷是否為雙擊（方向相同且在時間窗口內）
		if input_dir == last_input_dir and double_tap_timer > 0:
			# 取得角色目前面對方向（從父節點取得）
			var facing: float = get_parent().facing_direction if get_parent() and "facing_direction" in get_parent() else 1.0
			if input_dir * facing > 0:
				dash_pressed = true      # 前衝
			else:
				backdash_pressed = true  # 後衝
			# 觸發後立即重置，避免同一雙擊重複觸發
			double_tap_timer = 0.0
			last_input_dir = 0
		else:
			# 開始或更新雙擊計時
			last_input_dir = input_dir
			double_tap_timer = DOUBLE_TAP_TIME
	
	# 攻擊按鍵
	var st_mp_pressed = Input.is_action_just_pressed("st_mp" + suffix)
	var st_mk_pressed = Input.is_action_just_pressed("st_mk" + suffix)
	var spm1_pressed  = Input.is_action_just_pressed("spmove1" + suffix)
	var spm2_pressed  = Input.is_action_just_pressed("spmove2" + suffix)
	var spm3_pressed  = Input.is_action_just_pressed("spmove3" + suffix)
	var super_pressed = Input.is_action_just_pressed("super" + suffix)
	var dp_pressed    = false
	
	# === 輸入序列檢測（保持原邏輯不變）===
	var input_manager = get_parent().get_node("InputManager") if get_parent().has_node("InputManager") else null
	if input_manager:
		# P1 招式
		if player_id == "p1" and input_manager.check_powerkk_input():
			spm1_pressed = true
			st_mp_pressed = false
		if player_id == "p1" and input_manager.check_dp_input():
			dp_pressed = true
			st_mp_pressed = false
		
		# P2 招式（注意順序！hdk 優先於 spnk）
		if player_id == "p2" and input_manager.check_hdk_input():
			spm3_pressed = true
			st_mk_pressed = false
		if player_id == "p2" and input_manager.check_spnk_input():
			spm1_pressed = true
			st_mk_pressed = false
		
		# 通用招式
		if input_manager.check_fireball_input():
			spm2_pressed = true
			st_mp_pressed = false
	
	# P1 的 spmove3 快捷鍵觸發 DP
	if player_id == "p1" and spm3_pressed:
		dp_pressed = true
	
	# 攻擊優先級（保持原邏輯）
	var attack_type = (
		"super"    if super_pressed else
		"powerkk"  if spm1_pressed and player_id == "p1" else
		"dp"       if dp_pressed and player_id == "p1" else
		"spnk"     if spm1_pressed and player_id == "p2" else
		"hdk"      if spm3_pressed and player_id == "p2" else
		"fireball" if spm2_pressed else
		"st_mp"    if st_mp_pressed else
		"st_mk"    if st_mk_pressed else
		"none"
	)
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,      # 現在持續按住 jump 鍵即可連續跳躍
		"st_mp_pressed": st_mp_pressed,
		"st_mk_pressed": st_mk_pressed,
		"attack_type": attack_type,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed,
		"spm3_pressed": spm3_pressed,
		"super_pressed": super_pressed,
		"dp_pressed": dp_pressed,
		"dash_pressed": dash_pressed,      # 新增：前衝旗標
		"backdash_pressed": backdash_pressed  # 新增：後衝旗標
	}
