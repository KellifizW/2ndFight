# PlayerController.gd（完全修正版：支援新 seat 系統 + 移除 player_id 依賴）

class_name PlayerController extends Node

# 移除舊的 player_id，改用 seat 來決定輸入後綴
# seat 會由 Player.gd 在 _ready() 時設定（"player_a" 或 "player_b"）
var player_seat: String = "player_a"  # 預設值，Player 會覆蓋它

# Input Buffer System
var input_buffer: InputBuffer = null

# Dash / Backdash 雙擊偵測變數
var last_input_dir: int = 0
var double_tap_timer: float = 0.0
const DOUBLE_TAP_TIME: float = 0.3  # 雙擊時間窗口（秒），與 Movement 原設定一致
const THROW_LENIENCE_FRAMES: int = 6  # 6 frames at 120 FPS (~50ms) - 標準競技級容許窗口
const DEBUG_THROW_INPUT: bool = false  # 設為 false 可關閉除錯輸出

var last_st_lp_frame: int = -9999
var last_st_lk_frame: int = -9999

func _ready() -> void:
	# Initialize input buffer
	input_buffer = InputBuffer.new()
	add_child(input_buffer)

func _physics_process(_delta: float) -> void:
	# Skip input recording for AI-controlled players
	var player_node = get_parent()
	if player_node and player_node is Player and player_node.is_ai_controlled:
		return
	
	# Record button presses into buffer
	var suffix = "_p2" if player_seat == "player_b" else ""
	
	# Record all button presses
	var st_lp_just = Input.is_action_just_pressed("st_lp" + suffix)
	var st_mp_just = Input.is_action_just_pressed("st_mp" + suffix)
	var st_hp_just = Input.is_action_just_pressed("st_hp" + suffix)
	var st_lk_just = Input.is_action_just_pressed("st_lk" + suffix)
	var st_mk_just = Input.is_action_just_pressed("st_mk" + suffix)
	var st_hk_just = Input.is_action_just_pressed("st_hk" + suffix)

	if DEBUG_THROW_INPUT and input_buffer:
		var frame_tag = input_buffer.current_frame
		if st_lp_just:
			print("[THROW INPUT] st_lp just pressed | frame=%d | seat=%s" % [frame_tag, player_seat])
		if st_lk_just:
			print("[THROW INPUT] st_lk just pressed | frame=%d | seat=%s" % [frame_tag, player_seat])
	
	if st_lp_just and input_buffer:
		last_st_lp_frame = input_buffer.current_frame
	if st_lk_just and input_buffer:
		last_st_lk_frame = input_buffer.current_frame
	
	if DEBUG_THROW_INPUT and input_buffer and (st_lp_just or st_lk_just):
		var other_action = "st_lk" if st_lp_just else "st_lp"
		var info = input_buffer.get_input_debug_info(other_action)
		var frame_delta = abs(last_st_lp_frame - last_st_lk_frame)
		print("[THROW INPUT] counterpart=%s exists=%s consumed=%s age=%d ts=%d delta=%d window=%d" % [
			other_action,
			info["exists"],
			info["consumed"],
			info["age"],
			info["timestamp"],
			frame_delta,
			THROW_LENIENCE_FRAMES
		])
	
	var throw_detected: bool = false
	# 【重要】st_lp + st_lk 允許在指定幀窗口內視為摔投（不依賴 buffer 是否被消耗）
	var throw_candidate = st_lp_just or st_lk_just
	var frame_delta = abs(last_st_lp_frame - last_st_lk_frame)
	if throw_candidate and last_st_lp_frame > -9990 and last_st_lk_frame > -9990 and frame_delta <= THROW_LENIENCE_FRAMES:
		throw_detected = true

	if throw_detected:
		input_buffer.clear_input("st_lp")
		input_buffer.clear_input("st_lk")
		input_buffer.record_input("throw")
		print("[INPUT] Throw detected: st_lp + st_lk within lenience window | st_lp_frame=%d st_lk_frame=%d delta=%d" % [last_st_lp_frame, last_st_lk_frame, frame_delta])
	else:
		# 僅在沒有同時按下時才記錄單獨的按鈕
		if st_lp_just:
			input_buffer.record_input("st_lp")
		if st_mp_just:
			input_buffer.record_input("st_mp")
		if st_hp_just:
			input_buffer.record_input("st_hp")
		if st_lk_just:
			input_buffer.record_input("st_lk")
		if st_mk_just:
			input_buffer.record_input("st_mk")
		if st_hk_just:
			input_buffer.record_input("st_hk")
	if Input.is_action_just_pressed("jump" + suffix):
		input_buffer.record_input("jump")
	if Input.is_action_just_pressed("spmove1" + suffix):
		input_buffer.record_input("spmove1")
	if Input.is_action_just_pressed("spmove2" + suffix):
		input_buffer.record_input("spmove2")
	if Input.is_action_just_pressed("spmove3" + suffix):
		input_buffer.record_input("spmove3")
	var super_action = "super" + suffix
	if InputMap.has_action(super_action) and Input.is_action_just_pressed(super_action):
		input_buffer.record_input("super")
	
	# Check for special move inputs via InputManager
	var input_manager = player_node.get_node_or_null("InputManager")
	if input_manager and input_manager.has_method("detect_special_move"):
		var detected_special = input_manager.detect_special_move()
		if detected_special != "":
			# Record the detected special move into buffer
			input_buffer.record_input(detected_special)
			# print("[PlayerController] Detected and buffered special move: %s" % detected_special)

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
	
	# Also check buffered jump input
	var jump_buffered = input_buffer.is_input_buffered("jump")
	
	# 蹲下保持 pressed
	var crouch_action = Input.is_action_pressed("crouch" + suffix)
	
	var dir_x: int = 0
	if move_right and not move_left:  
		dir_x = 1
	elif move_left and not move_right:  
		dir_x = -1
	
	var input_dir: int = dir_x
	var crouch_pressed: bool = crouch_action
	var jump_pressed: bool = jump_action or jump_buffered  # Combine held + buffered jump
	
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
	
	# 攻擊按鍵 - Check buffered inputs (don't consume yet, let player.gd decide)
	var st_lp_pressed = input_buffer.is_input_buffered("st_lp")
	var st_mp_pressed = input_buffer.is_input_buffered("st_mp")
	var st_hp_pressed = input_buffer.is_input_buffered("st_hp")
	var st_lk_pressed = input_buffer.is_input_buffered("st_lk")
	var st_mk_pressed = input_buffer.is_input_buffered("st_mk")
	var st_hk_pressed = input_buffer.is_input_buffered("st_hk")
	var throw_pressed = input_buffer.is_input_buffered("throw")
	var spm1_pressed  = input_buffer.is_input_buffered("spmove1")
	var spm2_pressed  = input_buffer.is_input_buffered("spmove2")
	var spm3_pressed  = input_buffer.is_input_buffered("spmove3")
	var super_pressed = input_buffer.is_input_buffered("super")
	var dp_pressed    = false
	
	# === 檢查 buffer 中的特殊招式（優先級最高）===
	var fireball_buffered = input_buffer.is_input_buffered("fireball")
	var powerkk_buffered = input_buffer.is_input_buffered("powerkk")
	var spnk_buffered = input_buffer.is_input_buffered("spnk")
	var hdk_buffered = input_buffer.is_input_buffered("hdk")
	var dp_buffered = input_buffer.is_input_buffered("dp")
	
	# 如果 buffer 中有特殊招式，設置對應的標誌
	if fireball_buffered:
		spm2_pressed = true
		st_mp_pressed = false  # 防止同時觸發普通攻擊
	if powerkk_buffered:
		spm1_pressed = true
		st_mp_pressed = false
	if spnk_buffered:
		spm1_pressed = true
		st_mk_pressed = false
	if hdk_buffered:
		spm3_pressed = true
		st_mk_pressed = false
	if dp_buffered:
		dp_pressed = true
		st_mp_pressed = false
	
	
	# === 舊版輸入序列檢測（作為備用，但不應該再需要了）===
	# 已經被 InputManager.detect_special_move() 和 buffer 系統取代
	# 保留這些代碼以防萬一，但在正常情況下不會執行到
	var input_manager = get_parent().get_node("InputManager") if get_parent().has_node("InputManager") else null
	var character_id: String = "UNKNOWN"
	if get_parent() and "character_id" in get_parent():
		character_id = get_parent().character_id
	
	# 只有在 buffer 中沒有檢測到特殊招式時才執行舊邏輯（fallback）
	if input_manager and not (fireball_buffered or powerkk_buffered or spnk_buffered or hdk_buffered or dp_buffered):
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
		"throw"    if throw_pressed else  # 【摔投優先級最高】
		"super"    if super_pressed else
		"powerkk"  if spm1_pressed and character_id == "DAV" else
		"dp"       if dp_pressed and character_id == "DAV" else
		"spnk"     if spm1_pressed and character_id == "DEN" else
		"hdk"      if spm3_pressed and character_id == "DEN" else
		"fireball" if spm2_pressed else
		"st_hp"    if st_hp_pressed else
		"st_mp"    if st_mp_pressed else
		"st_lp"    if st_lp_pressed else
		"st_hk"    if st_hk_pressed else
		"st_mk"    if st_mk_pressed else
		"st_lk"    if st_lk_pressed else
		"none"
	)
	

	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"st_lp_pressed": st_lp_pressed,
		"st_mp_pressed": st_mp_pressed,
		"st_hp_pressed": st_hp_pressed,
		"st_lk_pressed": st_lk_pressed,
		"st_mk_pressed": st_mk_pressed,
		"st_hk_pressed": st_hk_pressed,
		"throw_pressed": throw_pressed,
		"attack_type": attack_type,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed,
		"spm3_pressed": spm3_pressed,
		"super_pressed": super_pressed,
		"dp_pressed": dp_pressed,
		"dash_pressed": dash_pressed,
		"backdash_pressed": backdash_pressed
	}

# Helper method for player to consume inputs
func consume_button_input(button_name: String) -> bool:
	if input_buffer:
		return input_buffer.consume_input(button_name)
	return false

# Clear buffer on certain states (getting hit, etc)
func clear_buffer() -> void:
	if input_buffer:
		input_buffer.clear_all()
