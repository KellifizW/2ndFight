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

# 【NEW】Throw detection with lenient timing window
const THROW_DETECTION_WINDOW: int = 3  # 3 frames @ 120 FPS = 25ms window
var throw_lp_frame: int = -1  # Frame when LP was pressed (-1 = not pressed)
var throw_lk_frame: int = -1  # Frame when LK was pressed (-1 = not pressed)
var current_physics_frame: int = 0  # Track current frame for throw window

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
	current_physics_frame = Engine.get_physics_frames()
	
	# 【重要】LP+LK 同時/近似 → throw，否則逐個記錄
	var _atk_btns := ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk"]
	var _just := {}
	for btn in _atk_btns:
		_just[btn] = Input.is_action_just_pressed(btn + suffix)
	
	# 【NEW】Track LP/LK presses for throw window detection
	var lp_just = _just["st_lp"]
	var lk_just = _just["st_lk"]
	
	if lp_just:
		throw_lp_frame = current_physics_frame
		print("[THROW TRACKING] LP pressed at frame=%d" % throw_lp_frame)
	if lk_just:
		throw_lk_frame = current_physics_frame
		print("[THROW TRACKING] LK pressed at frame=%d" % throw_lk_frame)
	
	# 【NEW】Check if LP and LK are within throw window (both pressed within 3 frames)
	var throw_detected = false
	if throw_lp_frame >= 0 and throw_lk_frame >= 0:
		var frame_diff = abs(throw_lp_frame - throw_lk_frame)
		if frame_diff <= THROW_DETECTION_WINDOW:
			throw_detected = true
			print("[THROW DETECTED] 🎯 LP(frame=%d) + LK(frame=%d) | diff=%d frames (within window=%d)" % [
				throw_lp_frame, throw_lk_frame, frame_diff, THROW_DETECTION_WINDOW
			])
			# Reset tracking after throwing
			throw_lp_frame = -1
			throw_lk_frame = -1
	
	# 【DEBUG】Show tracking state
	if lp_just or lk_just:
		print("[INPUT DEBUG] Frame=%d Seat=%s | st_lp_just=%s(tracked_at=%d) st_lk_just=%s(tracked_at=%d) | throw_detected=%s" % [
			current_physics_frame, player_seat,
			lp_just, throw_lp_frame, lk_just, throw_lk_frame, throw_detected
		])
	
	if throw_detected:
		# 【NEW】立即中斷st_lp/st_lk動畫（1F內優先級最高）
		var player = player_node as Player
		if player and player.is_attacking and player.attack_type in ["st_lp", "st_lk"]:
			print("[THROW INTERRUPT IMMEDIATE] Frame=%d | 打斷 '%s' → 執行 throw (diff <= %dF)" % [
				current_physics_frame, player.attack_type, THROW_DETECTION_WINDOW
			])
			# 強制停止當前攻擊
			player.stop_attack_for_throw()
		
		input_buffer.record_input("throw")
		print("[INPUT THROW DETECTED] ✅ Frame=%d Seat=%s | LP + LK within %d-frame window → 'throw' buffered" % [
			current_physics_frame, player_seat, THROW_DETECTION_WINDOW
		])
	else:
		for btn in _atk_btns:
			if _just[btn]:
				input_buffer.record_input(btn)
				if lp_just or lk_just:  # 【DEBUG】Show individual button recorded
					print("[INPUT SEPARATE] Frame=%d Seat=%s | Individual '%s' recorded (throw not detected)" % [
						current_physics_frame, player_seat, btn
					])
	
	# 【NEW】Don't let old tracking data persist: reset if too old (10-frame window)
	if throw_lp_frame >= 0 and current_physics_frame - throw_lp_frame > 10:
		throw_lp_frame = -1
	if throw_lk_frame >= 0 and current_physics_frame - throw_lk_frame > 10:
		throw_lk_frame = -1
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
	
	# 【DEBUG】顯示當前 buffer 中的按鍵狀態
	if st_lp_pressed or st_lk_pressed or throw_pressed:
		print("[BUFFER STATUS] Frame=%d Seat=%s | LP_buffered=%s LK_buffered=%s THROW_buffered=%s" % [
			Engine.get_physics_frames(), player_seat, st_lp_pressed, st_lk_pressed, throw_pressed
		])
	var spm1_pressed  = input_buffer.is_input_buffered("spmove1")
	var spm2_pressed  = input_buffer.is_input_buffered("spmove2")
	var spm3_pressed  = input_buffer.is_input_buffered("spmove3")
	var super_pressed = input_buffer.is_input_buffered("super")
	var dp_pressed    = false
	
	# === 檢查 buffer 中的特殊招式（優先級最高）===
	var fireball_buffered = input_buffer.is_input_buffered("fireball")
	var fireballL_buffered = input_buffer.is_input_buffered("fireballL")
	var fireballM_buffered = input_buffer.is_input_buffered("fireballM")
	var fireballH_buffered = input_buffer.is_input_buffered("fireballH")
	var powerkk_buffered = input_buffer.is_input_buffered("powerkk")
	var spnk_buffered = input_buffer.is_input_buffered("spnk")
	var hdk_buffered = input_buffer.is_input_buffered("hdk")
	# 🔴 FIX: detect_special_move() buffers "dpM"/"dpH"/"dpL", not just "dp"
	var dp_buffered = (input_buffer.is_input_buffered("dp") or
		input_buffer.is_input_buffered("dpL") or
		input_buffer.is_input_buffered("dpM") or
		input_buffer.is_input_buffered("dpH"))
	
	# 🔴 【新增 100p 檢查】CRUCIAL: 100p must be checked and buffered
	var move_100p_buffered = input_buffer.is_input_buffered("100p")
	
	# DEBUG: 每幀顯示 100p buffer 狀態
	if move_100p_buffered:
		print("[PlayerController Buffer] ✅ 100p FOUND in buffer! Setting 100p_pressed")
	
	# 如果 buffer 中有特殊招式，設置對應的標誌
	if fireball_buffered:
		spm2_pressed = true
		st_mp_pressed = false  # 防止同時觸發普通攻擊
	if fireballL_buffered:
		st_lp_pressed = false
	if fireballM_buffered:
		st_mp_pressed = false
	if fireballH_buffered:
		st_hp_pressed = false
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
		st_lp_pressed = false
		st_hp_pressed = false
	
	# 🔴 【新增】Handle 100p buffered input (DAV only, multi-hit punch)
	if move_100p_buffered:
		print("[PlayerController] 100p moving to spm3_pressed (or creating new flag for MoveSet handling)")
		# Note: 100p needs special handling since it's not in spm1/spm2/spm3
		st_mk_pressed = false  # Clear MK to prevent normal attack
	
	
	var character_id: String = get_parent().character_id if get_parent() and "character_id" in get_parent() else "UNKNOWN"
	
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
		"fireballL" if fireballL_buffered else
		"fireballM" if fireballM_buffered else
		"fireballH" if fireballH_buffered else
		"fireball" if spm2_pressed else
		"st_hp"    if st_hp_pressed else
		"st_mp"    if st_mp_pressed else
		"st_lp"    if st_lp_pressed else
		"st_hk"    if st_hk_pressed else
		"st_mk"    if st_mk_pressed else
		"st_lk"    if st_lk_pressed else
		"none"
	)
	
	# 【DEBUG】詳細顯示攻擊優先級決策
	if attack_type != "none" and (throw_pressed or st_lp_pressed or st_lk_pressed):
		print("[ATTACK PRIORITY] Frame=%d Seat=%s | throw_pressed=%s st_lp=%s st_lk=%s | SELECTED: '%s'" % [
			Engine.get_physics_frames(), player_seat, throw_pressed, st_lp_pressed, st_lk_pressed, attack_type
		])
	

	
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
		"fireballL_pressed": fireballL_buffered,
		"fireballM_pressed": fireballM_buffered,
		"fireballH_pressed": fireballH_buffered,
		"spm3_pressed": spm3_pressed,
		"super_pressed": super_pressed,
		"dp_pressed": dp_pressed,
		"dash_pressed": dash_pressed,
		"backdash_pressed": backdash_pressed,
		"100p_pressed": move_100p_buffered  # 🔴 【新增】 Return 100p flag to MoveSet
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
