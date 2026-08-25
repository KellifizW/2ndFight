class_name InputManager extends Node

# ============================================================
# INPUT SYSTEM INTEGRATION
# Manages motion input detection with buffer support for special moves
# ============================================================

enum DirectionalInputs { NEUTRAL = 0, DOWN = 1, DOWN_FORWARD = 2, FORWARD = 3, DOWN_BACK = 4, BACK = 5, UP = 6, UP_FORWARD = 7, UP_BACK = 8 }
# 改為位元遮罩以支援多按鈕同時按下
enum ButtonInputs { 
	NONE = 0, 
	ST_LP = 1,      # 1 << 0
	ST_MP = 2,      # 1 << 1
	ST_HP = 4,      # 1 << 2
	ST_LK = 8,      # 1 << 3
	ST_MK = 16,     # 1 << 4
	ST_HK = 32      # 1 << 5
}
enum ButtonMode { PRESS, HOLD }

const INPUT_HISTORY_SIZE: int = 240  # 歷史記錄大小，約 2 秒 (120 FPS)
const INPUT_BUFFER: int = 30  # 輸入緩衝區，約 0.25 秒 (120 FPS)
const MAX_TOTAL_FRAMES: int = 120  # 總匹配時間限制，約 1.0 秒 (120 FPS)

# Special move detection result cache (prevents double-detection in same frame)
var detected_special_this_frame: String = ""
var last_detection_frame: int = 0

const DEBUG_DP: bool = false  # 設為 true 可開啟 DP 輸入除錯

const SPECIAL_INPUT_RESOURCES: Array[String] = [
	"res://data/specials/inputs/fireball_input.tres",
	"res://data/specials/inputs/powerkk_input.tres",
	"res://data/specials/inputs/spnk_input.tres",
	"res://data/specials/inputs/dp_input.tres",
	"res://data/specials/inputs/hdk_input.tres",
	"res://data/specials/inputs/100p_input.tres"
]

var special_input_registry: Dictionary = {}

var input_history: Array[InputRegistry] = []
var current_history: int = 0
var input_side: int = 1  # 1 = 面對右, -1 = 面對左

# ============================================================
# ENHANCED INPUT REGISTRY (inspired by Sakuga-Engine)
# ============================================================
class InputRegistry:
	var raw_input: int = 0        # Bit-masked input
	var duration: int = 0         # How many frames this input has been held
	var h_charge: int = 0         # Horizontal charge (negative = left, positive = right)
	var v_charge: int = 0         # Vertical charge (negative = down, positive = up)
	var b_charge: int = 0         # Button charge (any button held)
	
	func is_null() -> bool:
		return raw_input == 0
	
	func reset() -> void:
		raw_input = 0
		duration = 0
		# Don't reset charges - they carry over

func _ready():
	_load_special_input_sequences()
	input_history.resize(INPUT_HISTORY_SIZE)
	for i in INPUT_HISTORY_SIZE:
		input_history[i] = InputRegistry.new()

func _physics_process(_delta: float) -> void:
	pass

func update_input():
	var raw_input = get_current_raw_input()
	insert_to_history(raw_input)
	var parent = get_parent()
	
	# 改用 seat 判斷輸入後綴與特殊招式可用性
	var suffix = "_p2" if parent.seat == "player_b" else ""
	# var _is_dav = parent.character_id == "DAV"   # DAV 擁有 powerkk、dp、fireball
	# var _is_den = parent.character_id == "DEN"   # DEN 擁有 spnk、hdk、fireball
	
	# 初始化輸入數據
	var input_data = {}
	
	# super 招式檢查（只在 InputMap 有定義時才檢查）
	var super_action = "super" + suffix
	if InputMap.has_action(super_action) and Input.is_action_just_pressed(super_action):
		input_data["super_pressed"] = true
	
	# 普通按鈕輸入 - MP (Power Punch)
	if Input.is_action_just_pressed("st_mp" + suffix):
		# 檢查特殊招式（只檢查該角色擁有的招式）
		# 【重要】不在這裡設置 input_data，由 PlayerController 從 buffer 處理
		pass
	
	# 普通按鈕輸入 - MK (Power Kick) 【新增】
	if Input.is_action_just_pressed("st_mk" + suffix):
		# 檢查特殊招式（只檢查該角色擁有的招式）
		# 【重要】不在這裡設置 input_data，由 PlayerController 從 buffer 處理
		pass
	
	# 傳給 Player
	parent.set_input_data(input_data)

func get_current_raw_input() -> int:
	var parent = get_parent()
	var facing = parent.facing_direction if parent and "facing_direction" in parent else 1.0
	input_side = sign(facing)
	var suffix = "_p2" if parent.seat == "player_b" else ""
	
	var dir = DirectionalInputs.NEUTRAL
	var down = Input.is_action_pressed("crouch" + suffix)
	var up = Input.is_action_pressed("jump" + suffix)
	# ⭐ 改為使用絕對方向（實際按鍵），不根據角色面向反轉
	var right = Input.is_action_pressed("move_right" + suffix)
	var left = Input.is_action_pressed("move_left" + suffix)
	
	# 優先級: 上下互斥（下 > 上），左右互斥（右 > 左）
	# 使用絕對方向編碼：RIGHT=FORWARD(3), LEFT=BACK(5)
	if down and right and not left:
		dir = DirectionalInputs.DOWN_FORWARD  # 下+右
	elif down and left and not right:
		dir = DirectionalInputs.DOWN_BACK  # 下+左
	elif down and not (right or left):
		dir = DirectionalInputs.DOWN
	elif up and right and not left:
		dir = DirectionalInputs.UP_FORWARD  # 上+右
	elif up and left and not right:
		dir = DirectionalInputs.UP_BACK  # 上+左
	elif up and not (right or left):
		dir = DirectionalInputs.UP
	elif right and not (down or left or up):
		dir = DirectionalInputs.FORWARD  # 右
	elif left and not (down or right or up):
		dir = DirectionalInputs.BACK  # 左
	
	# 使用位元遮罩支援多按鈕同時按下
	var buttons = 0
	if Input.is_action_pressed("st_lp" + suffix):
		buttons |= ButtonInputs.ST_LP
	if Input.is_action_pressed("st_mp" + suffix):
		buttons |= ButtonInputs.ST_MP
	if Input.is_action_pressed("st_hp" + suffix):
		buttons |= ButtonInputs.ST_HP
	if Input.is_action_pressed("st_lk" + suffix):
		buttons |= ButtonInputs.ST_LK
	if Input.is_action_pressed("st_mk" + suffix):
		buttons |= ButtonInputs.ST_MK
	if Input.is_action_pressed("st_hk" + suffix):
		buttons |= ButtonInputs.ST_HK
	
	return (dir << 8) | buttons

func insert_to_history(raw_input: int):
	# ⭐ Optimization: Only create new entry if input changed (like Sakuga-Engine)
	if input_history[current_history].raw_input != raw_input:
		# Input changed - move to next slot
		var previous_index = current_history
		current_history = (current_history + 1) % INPUT_HISTORY_SIZE
		
		input_history[current_history] = InputRegistry.new()
		input_history[current_history].raw_input = raw_input
		input_history[current_history].duration = 1
		
		# Carry over charge values from previous input
		input_history[current_history].h_charge = input_history[previous_index].h_charge
		input_history[current_history].v_charge = input_history[previous_index].v_charge
		input_history[current_history].b_charge = input_history[previous_index].b_charge
		
		# 🔍 調試已禁用以避免格式化錯誤
	else:
		# Same input - just increment duration
		input_history[current_history].duration += 1
	
	# Update charge buffers
	_update_charge_buffers()

# 6 entry lookup replaces 8-case match block（面向左時鏡像方向）
# key = 絕對方向，value = 鏡像後方向；未列出的方向（DOWN/UP/NEUTRAL）不需轉換
const _MIRROR_DIR: Dictionary = {2: 4, 3: 5, 4: 2, 5: 3, 7: 8, 8: 7}

func get_relative_direction(absolute_dir: int) -> int:
	var parent = get_parent()
	var facing = parent.facing_direction if parent and "facing_direction" in parent else 1.0
	if facing >= 0:
		return absolute_dir
	return _MIRROR_DIR.get(absolute_dir, absolute_dir)

# ============================================================
# CHARGE SYSTEM (inspired by Sakuga-Engine)
# Automatically tracks how long directional/button inputs are held
# ============================================================
# Returns updated charge value: accumulates in one direction, resets on reversal
func _update_single_charge(current: int, neg_flag: bool, pos_flag: bool) -> int:
	if neg_flag: return 0 if current > 0 else current - 1
	elif pos_flag: return 0 if current < 0 else current + 1
	return 0

func _update_charge_buffers() -> void:
	var curr = input_history[current_history]
	var dir: int = curr.raw_input >> 8
	curr.h_charge = _update_single_charge(curr.h_charge,
		dir in [DirectionalInputs.BACK, DirectionalInputs.DOWN_BACK],
		dir in [DirectionalInputs.FORWARD, DirectionalInputs.DOWN_FORWARD])
	curr.v_charge = _update_single_charge(curr.v_charge,
		dir in [DirectionalInputs.DOWN, DirectionalInputs.DOWN_BACK, DirectionalInputs.DOWN_FORWARD],
		dir in [DirectionalInputs.UP, DirectionalInputs.UP_BACK, DirectionalInputs.UP_FORWARD])
	curr.b_charge = curr.b_charge + 1 if (curr.raw_input & 0xFF) != ButtonInputs.NONE else 0

func _load_special_input_sequences() -> void:
	special_input_registry.clear()
	for path in SPECIAL_INPUT_RESOURCES:
		var resource = load(path)
		if resource == null:
			continue
		if not resource is SpecialInputSequence:
			continue
		var sequence_id = resource.sequence_id
		if sequence_id == "":
			continue
		special_input_registry[sequence_id] = _build_motion_from_sequence(resource)

func _build_motion_from_sequence(sequence: SpecialInputSequence) -> Dictionary:
	return {
		"ValidInputs": sequence.valid_inputs,
		"InputBuffer": sequence.input_buffer,
		"AbsoluteDirection": sequence.absolute_direction,
		"MaxTotalFrames": sequence.max_total_frames
	}

func _get_motion_for(move_id: String) -> Dictionary:
	return special_input_registry.get(move_id, {})
		
# Single entry point — replaces the 4 identical one-liner wrappers above
func check_motion_for(move_id: String) -> bool:
	return check_motion(_get_motion_for(move_id))

func check_fireball_input() -> bool: return check_motion_for("fireball")
func check_powerkk_input() -> bool:  return check_motion_for("powerkk")
func check_spnk_input()    -> bool:  return check_motion_for("spnk")
func check_hdk_input()     -> bool:  return check_motion_for("hdk")

func check_dp_input() -> bool:
	var motion = _get_motion_for("dp")
	if motion.is_empty():
		if DEBUG_DP: Debug.log("[DP_DEBUG] dp_input.tres not loaded!")
		return false
	if DEBUG_DP:
		_check_motion_debug(motion, "dp")
	return check_motion(motion)

# デバッグ用：最後 N 個 history entry を相対方向で表示
func _dump_recent_history(count: int) -> String:
	var parts := []
	for i in count:
		var idx = (current_history - i + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
		var h = input_history[idx]
		var abs_dir = h.raw_input >> 8
		var rel_dir = get_relative_direction(abs_dir)
		var btns = h.raw_input & 0xFF
		parts.append("[abs=%d rel=%d btn=%d dur=%d]" % [abs_dir, rel_dir, btns, h.duration])
	return ", ".join(parts)

# DP 專用詳細 check_motion 除錯（只在 DEBUG_DP 時呼叫）
# 只在有按住拳腳按鈕時才輸出，避免每幀狂刷
func _check_motion_debug(motion: Dictionary, move_id: String) -> void:
	var valid_inputs = motion.get("ValidInputs", [])
	var input_buffer_size = motion.get("InputBuffer", INPUT_BUFFER)
	var max_total_frames = motion.get("MaxTotalFrames", MAX_TOTAL_FRAMES)
	var absolute_direction = motion.get("AbsoluteDirection", false)
	var last_buttons = input_history[current_history].raw_input & 0xFF
	# 只在有按下拳腳時才詳細輸出
	var punch_mask = ButtonInputs.ST_LP | ButtonInputs.ST_MP | ButtonInputs.ST_HP
	if (last_buttons & punch_mask) == 0:
		return
	Debug.log("[DP_DEBUG] check_motion(%s) | seat=%s | cur_history=%d | last_buttons=%d | input_side=%d | history(newest5): %s" % [
		move_id, get_parent().seat if get_parent() and "seat" in get_parent() else "?", current_history, last_buttons, input_side, _dump_recent_history(5)])
	for si in valid_inputs.size():
		var seq = valid_inputs[si]
		if seq.is_empty():
			continue
		var target_button = seq.back().buttons if "buttons" in seq.back() else ButtonInputs.NONE
		if target_button != ButtonInputs.NONE and (last_buttons & target_button) == 0:
			Debug.log("[DP_DEBUG]   seq[%d] SKIP early-exit: last_buttons=%d does not contain target_button=%d" % [si, last_buttons, target_button])
			continue
		Debug.log("[DP_DEBUG]   seq[%d] button match OK (btn=%d), checking %d steps..." % [si, target_button, seq.size()])
		var seq_idx = seq.size() - 1
		var hist_pos = current_history
		var total_frames = 0
		var matched = true
		while seq_idx >= 0 and matched:
			var step = seq[seq_idx]
			var step_matched = false
			var step_frames = 0
			while hist_pos >= 0 and not step_matched and step_frames < input_buffer_size:
				var h = input_history[hist_pos]
				step_frames += h.duration
				total_frames += h.duration
				if total_frames > max_total_frames:
					Debug.log("[DP_DEBUG]     step[%d] TIMEOUT total_frames=%d > max=%d" % [seq_idx, total_frames, max_total_frames])
					matched = false
					break
				var abs_dir = h.raw_input >> 8
				var rel_dir = get_relative_direction(abs_dir)
				var btn = h.raw_input & 0xFF
				var dir_ok = (step.directional == abs_dir) if absolute_direction else (step.directional == rel_dir)
				var btn_ok = (step.buttons == ButtonInputs.NONE) or ((btn & step.buttons) != 0)
				if dir_ok and btn_ok:
					Debug.log("[DP_DEBUG]     step[%d] MATCH: want(dir=%d,btn=%d) got(rel=%d,abs=%d,btn=%d) dur=%d" % [seq_idx, step.directional, step.buttons, rel_dir, abs_dir, btn, h.duration])
					var is_final_step = (seq_idx == seq.size() - 1)
					if not is_final_step or h.duration <= input_buffer_size:
						step_matched = true
						seq_idx -= 1
					else:
						Debug.log("[DP_DEBUG]     step[%d] MATCH but final-step duration %d > buffer %d" % [seq_idx, h.duration, input_buffer_size])
				else:
					Debug.log("[DP_DEBUG]     step[%d] no match: want(dir=%d,btn=%d) got(rel=%d,abs=%d,btn=%d) dir_ok=%s btn_ok=%s" % [seq_idx, step.directional, step.buttons, rel_dir, abs_dir, btn, dir_ok, btn_ok])
				hist_pos = (hist_pos - 1 + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
			if not step_matched:
				Debug.log("[DP_DEBUG]     step[%d] FAILED (no match within buffer)" % seq_idx)
				matched = false
		if matched:
			Debug.log("[DP_DEBUG]   seq[%d] ✅ FULL MATCH!" % si)
		else:
			Debug.log("[DP_DEBUG]   seq[%d] ❌ no match" % si)

func check_100p_input() -> bool: return check_motion_for("100p")

func check_motion(motion: Dictionary) -> bool:
	if motion.is_empty():
		return false
	var input_buffer = motion.get("InputBuffer", INPUT_BUFFER)
	var max_total_frames = motion.get("MaxTotalFrames", MAX_TOTAL_FRAMES)
	var absolute_direction = motion.get("AbsoluteDirection", false)
	var valid_inputs = motion.get("ValidInputs", [])
	
	var current_buttons = input_history[current_history].raw_input & 0xFF
	var current_duration = input_history[current_history].duration
	
	# Lenient input: only proceed if the button was freshly pressed
	# (current history entry duration within the buffer window)
	if current_duration > input_buffer:
		return false
	
	for seq in valid_inputs:
		if seq.is_empty():
			continue
		
		var target_button = seq.back().get("buttons", ButtonInputs.NONE)
		if target_button != ButtonInputs.NONE:
			if (current_buttons & target_button) == 0:
				continue
		
		var seq_idx = seq.size() - 1
		var hist_pos = current_history
		var total_frames = 0
		var matched = true
		
		while seq_idx >= 0 and matched:
			var step = seq[seq_idx]
			var is_final_step = (seq_idx == seq.size() - 1)
			var step_matched = false
			var step_frames = 0
			var required_dir = step.get("directional", DirectionalInputs.NEUTRAL)
			var required_btn = step.get("buttons", ButtonInputs.NONE) if not is_final_step else ButtonInputs.NONE
			
			# ── Lenient final-step logic ──────────────────────────────────────────
			# The button press is already confirmed by the current_buttons check above.
			# For the final step we only need to find the required direction somewhere
			# in the recent history (within input_buffer frames), so pressing the
			# button separately after completing the motion also triggers the move.
			if is_final_step:
				if required_dir == DirectionalInputs.NEUTRAL:
					# No direction requirement — button alone is sufficient.
					step_matched = true
					seq_idx -= 1
				else:
					# Search recent history for the required direction (ignore button).
					while hist_pos >= 0 and not step_matched and step_frames < input_buffer:
						var hist = input_history[hist_pos]
						step_frames += hist.duration
						total_frames += hist.duration
						if total_frames > max_total_frames:
							matched = false
							break
						# Direction-only check (button already confirmed above)
						if check_input(hist_pos, required_dir, ButtonInputs.NONE, step.get("dir_mode", 1), step.get("but_mode", ButtonMode.PRESS), absolute_direction):
							step_matched = true
							seq_idx -= 1
						hist_pos = (hist_pos - 1 + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
			else:
				# ── Standard matching for all non-final steps ─────────────────────
				while hist_pos >= 0 and not step_matched and step_frames < input_buffer:
					var hist = input_history[hist_pos]
					step_frames += hist.duration
					total_frames += hist.duration
					
					if total_frames > max_total_frames:
						matched = false
						break
					
					if check_input(hist_pos, required_dir, required_btn, step.get("dir_mode", 1), step.get("but_mode", ButtonMode.PRESS), absolute_direction):
						step_matched = true
						seq_idx -= 1
					hist_pos = (hist_pos - 1 + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
			
			if not step_matched:
				matched = false
		
		if matched:
			return true
	
	return false

# ============================================================
# ENHANCED SPECIAL MOVE DETECTION (with buffer support)
# Returns the name of detected special move or empty string
# ============================================================

func detect_special_move() -> String:
	"""
	檢測所有可能的特殊招式，返回檢測到的招式名稱
	優先級：super > DP > powerkk/100p > spnk > fireball/hdk
	"""
	# Prevent double-detection in same frame
	if last_detection_frame == Engine.get_physics_frames():
		return detected_special_this_frame
	
	last_detection_frame = Engine.get_physics_frames()
	
	var parent = get_parent()
	var character_id = parent.character_id if parent and "character_id" in parent else "UNKNOWN"
	var move_set = parent.move_set if parent and "move_set" in parent else null
	var can_use_special = func(move_id: String) -> bool:
		if move_set and move_set.has_method("has_move_for_character"):
			return move_set.has_move_for_character(move_id, character_id)
		return false

	# Avoid re-buffering while a special move is active
	if move_set and "is_spmove" in move_set and move_set.is_spmove:
		detected_special_this_frame = ""
		return ""
	
	# Check in priority order
	# Note: Only check moves available to this character
	
	# Super (DAV only for now)
	# TODO: Add super detection if needed
	
	# DP (check all possible variant keys: dp, dpL, dpM, dpH)
	var dp_can_use = (can_use_special.call("dp") or can_use_special.call("dpL")
		or can_use_special.call("dpM") or can_use_special.call("dpH"))
	var _dp_avail_debug = "dp=%s dpL=%s dpM=%s dpH=%s" % [
		can_use_special.call("dp"), can_use_special.call("dpL"),
		can_use_special.call("dpM"), can_use_special.call("dpH")]
	if not dp_can_use:
		# 只在按下拳按鈕時輸出，避免每幀狂刷（用來確認 DP 是否因 key mismatch 被跳過）
		var _cur_btns = input_history[current_history].raw_input & 0xFF
		var _punch_mask = ButtonInputs.ST_LP | ButtonInputs.ST_MP | ButtonInputs.ST_HP
		if (_cur_btns & _punch_mask) != 0 and input_history[current_history].duration <= INPUT_BUFFER:
			Debug.log("[DP_AVAIL] char=%s dp_can_use=false → DP 檢查被跳過 | %s" % [character_id, _dp_avail_debug])
	if dp_can_use and check_dp_input():
		var strength = _get_punch_strength()
		# 依優先順序選擇可用的 DP 變體：完全匹配 → 通用 → 任何可用
		var dp_variant = ""
		if can_use_special.call("dp" + strength):
			dp_variant = "dp" + strength
		elif can_use_special.call("dp"):
			dp_variant = "dp"
		elif can_use_special.call("dpM"):
			dp_variant = "dpM"
		elif can_use_special.call("dpH"):
			dp_variant = "dpH"
		elif can_use_special.call("dpL"):
			dp_variant = "dpL"
		if dp_variant == "":
			Debug.log("[DETECT_SPECIAL] DP input matched but NO dp variant found! char=%s %s" % [character_id, _dp_avail_debug])
		else:
			Debug.log("[DETECT_SPECIAL] DP detected → %s (strength=%s | %s)" % [dp_variant, strength, _dp_avail_debug])
			detected_special_this_frame = dp_variant
			return dp_variant
	
	# 【新增】100p 多段連打（236+MK）- DAV only
	if character_id == "DAV" and can_use_special.call("100p") and check_100p_input():
		Debug.log("[DETECT_SPECIAL] 💥 100p detected! | Seat: %s | Buffer Check: can_use_special('100p')=true" % character_id if character_id == "DAV" else "NOT_DAV")
		detected_special_this_frame = "100p"
		return "100p"
	
	# PowerKK
	if can_use_special.call("powerkk") and check_powerkk_input():
		Debug.log("[DETECT_SPECIAL] PowerKK detected")
		detected_special_this_frame = "powerkk"
		return "powerkk"
	
	# SPNK
	if can_use_special.call("spnk") and check_spnk_input():
		Debug.log("[DETECT_SPECIAL] SPNK detected")
		detected_special_this_frame = "spnk"
		return "spnk"
	
	# HDK
	if can_use_special.call("hdk") and check_hdk_input():
		Debug.log("[DETECT_SPECIAL] HDK detected")
		detected_special_this_frame = "hdk"
		return "hdk"
	
	# Fireball
	if (can_use_special.call("fireball") or can_use_special.call("fireballL")
		or can_use_special.call("fireballM") or can_use_special.call("fireballH")) and check_fireball_input():
		var strength = _get_punch_strength()
		# 依優先順序選擇可用的 Fireball 變體
		var fireball_variant = ""
		if can_use_special.call("fireball" + strength):
			fireball_variant = "fireball" + strength
		elif can_use_special.call("fireball"):
			fireball_variant = "fireball"
		elif can_use_special.call("fireballM"):
			fireball_variant = "fireballM"
		elif can_use_special.call("fireballL"):
			fireball_variant = "fireballL"
		elif can_use_special.call("fireballH"):
			fireball_variant = "fireballH"
		if fireball_variant != "":
			# 【除錯】如果 DP 可用但仍然到達 Fireball，表示 check_dp_input() 返回 false
			if dp_can_use:
				Debug.log("[DETECT_SPECIAL] ⚠ Fireball detected but dp_can_use=true → check_dp_input() may have failed! (char=%s strength=%s)" % [character_id, strength])
			Debug.log("[DETECT_SPECIAL] Fireball detected → %s (strength=%s)" % [fireball_variant, strength])
			detected_special_this_frame = fireball_variant
			return fireball_variant
	
	detected_special_this_frame = ""
	return ""

func _get_punch_strength() -> String:
	"""判斷輸入歷史中最新按下的拳按鈕強度（L/M/H）"""
	var buttons = input_history[current_history].raw_input & 0xFF
	if buttons & ButtonInputs.ST_HP:
		return "H"
	elif buttons & ButtonInputs.ST_MP:
		return "M"
	elif buttons & ButtonInputs.ST_LP:
		return "L"
	else:
		return "M"  # ST_MP or unknown defaults to Medium

# check_motion is already defined above (line 276), so we continue with check_input

func check_input(index: int, directional: int, buttons: int, dir_mode: int, but_mode: int, absolute_direction: bool = false) -> bool:
	"""
	檢查指定歷史索引的輸入是否匹配招式步驟
	注意：directional 參數是相對方向（FORWARD=前，BACK=後）
	"""
	var raw = input_history[index].raw_input
	var absolute_dir = raw >> 8
	var input_buttons = raw & 0xFF
	
	# ⭐ 將絕對方向轉換為相對方向（用於招式檢測）
	var relative_dir = get_relative_direction(absolute_dir)
	
	# 檢查方向是否匹配
	var dir_match = (directional == absolute_dir) if absolute_direction else (directional == relative_dir)
	
	# 檢查按鈕是否匹配
	var but_match = (buttons == ButtonInputs.NONE) or ((input_buttons & buttons) != 0)
	
	return dir_match and but_match

# ============================================================
# UTILITY METHODS
# ============================================================

func get_current_input() -> InputRegistry:
	"""Get the current input registry"""
	return input_history[current_history]

func get_button_charge() -> int:
	"""Get how long any button has been held"""
	return input_history[current_history].b_charge

func get_h_charge() -> int:
	"""Get horizontal charge (negative = left/back, positive = right/forward)"""
	return input_history[current_history].h_charge

func get_v_charge() -> int:
	"""Get vertical charge (negative = down, positive = up)"""
	return input_history[current_history].v_charge

func is_neutral() -> bool:
	"""Check if current input is neutral (no inputs)"""
	return input_history[current_history].is_null()

# ============================================================
# CHARGE-BASED SPECIAL MOVES (for future use)
# Example: Guile's Flash Kick requires holding down for 2 seconds
# ============================================================

func check_charge_special(direction: DirectionalInputs, required_frames: int) -> bool:
	"""
	Check if a charge requirement is met
	Example: check_charge_special(DirectionalInputs.BACK, 120) for 2 second back charge
	"""
	if direction == DirectionalInputs.BACK:
		return abs(input_history[current_history].h_charge) >= required_frames
	elif direction == DirectionalInputs.DOWN:
		return abs(input_history[current_history].v_charge) >= required_frames
	return false
