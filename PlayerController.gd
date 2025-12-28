# PlayerController.gd（完全修正版：支援新 seat 系統 + 移除 player_id 依賴）

class_name PlayerController extends Node

# 移除舊的 player_id，改用 seat 來決定輸入後綴
# seat 會由 Player.gd 在 _ready() 時設定（"player_a" 或 "player_b"）
var player_seat: String = "player_a"  # 預設值，Player 會覆蓋它

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
	# 根據 seat 決定輸入動作後綴
	# 建議你在 Project Settings → Input Map 中建立兩組動作：
	#   move_right, move_left, jump, crouch, st_mp, st_mk, spmove1, spmove2, spmove3, super
	#   move_right_p2, move_left_p2, jump_p2, crouch_p2, ...（第二玩家用）
	var suffix = "_p2" if player_seat == "player_b" else ""
	
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
	
	# === 輸入序列檢測（保持原邏輯，但改用 character_id 判斷角色）===
	var input_manager = get_parent().get_node("InputManager") if get_parent().has_node("InputManager") else null
	var character_id: String = "UNKNOWN"
	if get_parent() and "character_id" in get_parent():
		character_id = get_parent().character_id
	
	if input_manager:
		# DAV（原本 p1）的招式
		if character_id == "DAV" and input_manager.check_powerkk_input():
			spm1_pressed = true
			st_mp_pressed = false
		if character_id == "DAV" and input_manager.check_dp_input():
			dp_pressed = true
			st_mp_pressed = false
		
		# DEN（原本 p2）的招式
		if character_id == "DEN" and input_manager.check_hdk_input():
			spm3_pressed = true
			st_mk_pressed = false
		if character_id == "DEN" and input_manager.check_spnk_input():
			spm1_pressed = true
			st_mk_pressed = false
		
		# 通用招式
		if input_manager.check_fireball_input():
			spm2_pressed = true
			st_mp_pressed = false
	
	# DAV 的 spmove3 快捷鍵觸發 DP
	if character_id == "DAV" and spm3_pressed:
		dp_pressed = true
	
	# 攻擊優先級（已移除 player_id 判斷，改用 character_id）
	var attack_type = (
		"super"    if super_pressed else
		"powerkk"  if spm1_pressed and character_id == "DAV" else
		"dp"       if dp_pressed and character_id == "DAV" else
		"spnk"     if spm1_pressed and character_id == "DEN" else
		"hdk"      if spm3_pressed and character_id == "DEN" else
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
		"spm3_pressed": spm3_pressed,
		"super_pressed": super_pressed,
		"dp_pressed": dp_pressed,
		"dash_pressed": dash_pressed,
		"backdash_pressed": backdash_pressed
	}
