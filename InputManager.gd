class_name InputManager extends Node

# ============================================================
# INPUT SYSTEM INTEGRATION
# Manages motion input detection with buffer support for special moves
# ============================================================

enum DirectionalInputs { NEUTRAL = 0, DOWN = 1, DOWN_FORWARD = 2, FORWARD = 3, DOWN_BACK = 4, BACK = 5 }
enum ButtonInputs { NONE = 0, ST_LP = 1, ST_MP = 2, ST_HP = 3, ST_LK = 4, ST_MK = 5, ST_HK = 6 }
enum ButtonMode { PRESS, HOLD }

const INPUT_HISTORY_SIZE: int = 240  # 歷史記錄大小，約 4 秒 (60 FPS)
const INPUT_BUFFER: int = 10  # 輸入緩衝區，約 0.167 秒
const MAX_TOTAL_FRAMES: int = 120  # 總匹配時間限制，約 2 秒

# Special move detection result cache (prevents double-detection in same frame)
var detected_special_this_frame: String = ""
var last_detection_frame: int = 0

const FIREBALL_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const FIREBALL_SEQUENCE2: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const POWERKK_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const SPNK_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.ST_MK, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const DP_SEQUENCE1: Array[Dictionary] = [
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const DP_SEQUENCE2: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const DP_SEQUENCE3: Array[Dictionary] = [
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const HDK_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.ST_MK, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

var fireball_motion: Dictionary = {
	"ValidInputs": [FIREBALL_SEQUENCE, FIREBALL_SEQUENCE2],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var powerkk_motion: Dictionary = {
	"ValidInputs": [POWERKK_SEQUENCE],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var spnk_motion: Dictionary = {
	"ValidInputs": [SPNK_SEQUENCE],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var dp_motion: Dictionary = {
	"ValidInputs": [DP_SEQUENCE1, DP_SEQUENCE2, DP_SEQUENCE3],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var hdk_motion: Dictionary = {
	"ValidInputs": [HDK_SEQUENCE],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

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
	input_history.resize(INPUT_HISTORY_SIZE)
	for i in INPUT_HISTORY_SIZE:
		input_history[i] = InputRegistry.new()

func _physics_process(_delta: float) -> void:
	# Reset detection cache each frame
	detected_special_this_frame = ""

func update_input():
	var raw_input = get_current_raw_input()
	insert_to_history(raw_input)
	var parent = get_parent()
	
	# 改用 seat 判斷輸入後綴與特殊招式可用性
	var suffix = "_p2" if parent.seat == "player_b" else ""
	var is_dav = parent.character_id == "DAV"   # DAV 擁有 powerkk、dp、fireball
	var is_den = parent.character_id == "DEN"   # DEN 擁有 spnk、hdk、fireball
	
	# 初始化輸入數據
	var input_data = {}
	
	# super 招式檢查（只在 InputMap 有定義時才檢查）
	var super_action = "super" + suffix
	if InputMap.has_action(super_action) and Input.is_action_just_pressed(super_action):
		input_data["super_pressed"] = true
	
	# 普通按鈕輸入
	if Input.is_action_just_pressed("st_mp" + suffix):
		# 檢查特殊招式（只檢查該角色擁有的招式）
		if is_dav:
			if check_powerkk_input():
				input_data["spm1_pressed"] = true
			if check_dp_input():
				input_data["dp_pressed"] = true
			if check_fireball_input():
				input_data["spm2_pressed"] = true
		elif is_den:
			if check_fireball_input():
				input_data["spm2_pressed"] = true
	
	# 傳給 Player
	parent.set_input_data(input_data)

func get_current_raw_input() -> int:
	var parent = get_parent()
	var facing = parent.facing_direction if parent and "facing_direction" in parent else 1.0
	input_side = sign(facing)
	var suffix = "_p2" if parent.seat == "player_b" else ""
	
	var dir = DirectionalInputs.NEUTRAL
	var down = Input.is_action_pressed("crouch" + suffix)
	var forward = Input.is_action_pressed(("move_right" if input_side > 0 else "move_left") + suffix)
	var back = Input.is_action_pressed(("move_left" if input_side > 0 else "move_right") + suffix)
	
	if down and forward and not back:
		dir = DirectionalInputs.DOWN_FORWARD
	elif down and back and not forward:
		dir = DirectionalInputs.DOWN_BACK
	elif down and not (forward or back):
		dir = DirectionalInputs.DOWN
	elif forward and not (down or back):
		dir = DirectionalInputs.FORWARD
	elif back and not (down or forward):
		dir = DirectionalInputs.BACK
	
	var buttons = ButtonInputs.NONE
	if Input.is_action_just_pressed("st_mp" + suffix):
		buttons = ButtonInputs.ST_MP
	elif Input.is_action_just_pressed("st_mk" + suffix):
		buttons = ButtonInputs.ST_MK
	
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
	else:
		# Same input - just increment duration
		input_history[current_history].duration += 1
	
	# Update charge buffers
	_update_charge_buffers()

# ============================================================
# CHARGE SYSTEM (inspired by Sakuga-Engine)
# Automatically tracks how long directional/button inputs are held
# ============================================================
func _update_charge_buffers() -> void:
	var curr = input_history[current_history]
	
	# Horizontal charge
	var left_pressed = (curr.raw_input >> 8) in [DirectionalInputs.BACK, DirectionalInputs.DOWN_BACK]
	var right_pressed = (curr.raw_input >> 8) in [DirectionalInputs.FORWARD, DirectionalInputs.DOWN_FORWARD]
	
	if left_pressed:
		if curr.h_charge > 0:
			curr.h_charge = 0  # Reset if direction changed
		curr.h_charge -= 1
	elif right_pressed:
		if curr.h_charge < 0:
			curr.h_charge = 0
		curr.h_charge += 1
	else:
		curr.h_charge = 0  # Reset when neutral
	
	# Vertical charge
	var down_pressed = (curr.raw_input >> 8) in [DirectionalInputs.DOWN, DirectionalInputs.DOWN_BACK, DirectionalInputs.DOWN_FORWARD]
	var up_pressed = false  # Add if you have up inputs
	
	if down_pressed:
		if curr.v_charge > 0:
			curr.v_charge = 0
		curr.v_charge -= 1
	elif up_pressed:
		if curr.v_charge < 0:
			curr.v_charge = 0
		curr.v_charge += 1
	else:
		curr.v_charge = 0
	
	# Button charge (any button held)
	var any_button = (curr.raw_input & 0xFF) != ButtonInputs.NONE
	if any_button:
		curr.b_charge += 1
	else:
		curr.b_charge = 0
		
func check_fireball_input() -> bool:
	return check_motion(fireball_motion)

func check_powerkk_input() -> bool:
	return check_motion(powerkk_motion)

func check_spnk_input() -> bool:
	return check_motion(spnk_motion)

func check_hdk_input() -> bool:
	return check_motion(hdk_motion)

func check_dp_input() -> bool:
	return check_motion(dp_motion)

func check_motion(motion: Dictionary) -> bool:
	var found = false
	for seq in motion.ValidInputs:
		var last_buttons = input_history[current_history].raw_input & 0xFF
		var target_button = seq.back().buttons
		if last_buttons != target_button:
			continue
		
		var seq_idx = seq.size() - 1
		var hist_pos = current_history
		var total_frames = 0
		var matched = true
		
		while seq_idx >= 0 and matched:
			var step = seq[seq_idx]
			var step_matched = false
			var step_frames = 0
			
			while hist_pos >= 0 and not step_matched and step_frames < INPUT_BUFFER:
				var hist = input_history[hist_pos]
				step_frames += hist.duration
				total_frames += hist.duration
				
				if total_frames > MAX_TOTAL_FRAMES:
					matched = false
					break
				
				if check_input(hist_pos, step.directional, step.buttons if "buttons" in step else 0, step.dir_mode, step.but_mode if "but_mode" in step else ButtonMode.PRESS):
					if hist.duration <= INPUT_BUFFER:
						step_matched = true
						seq_idx -= 1
				
				hist_pos = (hist_pos - 1 + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
			
			if not step_matched:
				matched = false
		
		if matched:
			found = true
			break
	
	return found

# ============================================================
# ENHANCED SPECIAL MOVE DETECTION (with buffer support)
# Returns the name of detected special move or empty string
# ============================================================

func detect_special_move() -> String:
	"""
	檢測所有可能的特殊招式，返回檢測到的招式名稱
	優先級：super > DP > powerkk/spnk > fireball/hdk
	"""
	# Prevent double-detection in same frame
	if last_detection_frame == Engine.get_physics_frames():
		return detected_special_this_frame
	
	last_detection_frame = Engine.get_physics_frames()
	
	var parent = get_parent()
	var character_id = parent.character_id if parent and "character_id" in parent else "UNKNOWN"
	
	# Check in priority order
	# Note: Only check moves available to this character
	
	# Super (DAV only for now)
	# TODO: Add super detection if needed
	
	# DP (DAV only)
	if character_id == "DAV" and check_dp_input():
		detected_special_this_frame = "dp"
		return "dp"
	
	# PowerKK (DAV only)
	if character_id == "DAV" and check_powerkk_input():
		detected_special_this_frame = "powerkk"
		return "powerkk"
	
	# SPNK (DEN only)
	if character_id == "DEN" and check_spnk_input():
		detected_special_this_frame = "spnk"
		return "spnk"
	
	# HDK (DEN only)
	if character_id == "DEN" and check_hdk_input():
		detected_special_this_frame = "hdk"
		return "hdk"
	
	# Fireball (universal)
	if check_fireball_input():
		detected_special_this_frame = "fireball"
		return "fireball"
	
	detected_special_this_frame = ""
	return ""

# check_motion is already defined above (line 276), so we continue with check_input

func check_input(index: int, directional: int, buttons: int, dir_mode: int, but_mode: int) -> bool:
	var parent = get_parent()
	var suffix = "_p2" if parent.seat == "player_b" else ""
	var forward_action = "move_right" + suffix if input_side > 0 else "move_left" + suffix
	var back_action = "move_left" + suffix if input_side > 0 else "move_right" + suffix
	var down_action = "crouch" + suffix
	var button_action = "st_mp" + suffix if buttons == ButtonInputs.ST_MP else "st_mk" + suffix if buttons == ButtonInputs.ST_MK else ""
	
	var down = false
	var forward = false
	var back = false
	var button = false
	
	match dir_mode:
		ButtonMode.PRESS:
			down = was_pressed(index, down_action)
			forward = was_pressed(index, forward_action)
			back = was_pressed(index, back_action)
		ButtonMode.HOLD:
			down = is_being_pressed(index, down_action)
			forward = is_being_pressed(index, forward_action)
			back = is_being_pressed(index, back_action)
	
	match but_mode:
		ButtonMode.PRESS:
			button = was_pressed(index, button_action)
		ButtonMode.HOLD:
			button = is_being_pressed(index, button_action)
	
	var dir_match = false
	if directional == DirectionalInputs.NEUTRAL:
		dir_match = not (down or forward or back)
	else:
		dir_match = (directional == DirectionalInputs.DOWN and down and not (forward or back)) or \
			(directional == DirectionalInputs.DOWN_FORWARD and down and forward and not back) or \
			(directional == DirectionalInputs.FORWARD and forward and not (down or back)) or \
			(directional == DirectionalInputs.DOWN_BACK and down and back and not forward) or \
			(directional == DirectionalInputs.BACK and back and not (down or forward))
	
	var but_match = (buttons == 0) or button
	
	return dir_match and but_match

func is_being_pressed(index: int, action: String) -> bool:
	var raw = input_history[index].raw_input
	var dir = raw >> 8
	var buttons = raw & 0xFF
	
	if action.begins_with("crouch"):
		return dir == DirectionalInputs.DOWN or dir == DirectionalInputs.DOWN_FORWARD or dir == DirectionalInputs.DOWN_BACK
	elif action.begins_with("move_right"):
		return (dir == DirectionalInputs.FORWARD or dir == DirectionalInputs.DOWN_FORWARD) if input_side > 0 else (dir == DirectionalInputs.BACK or dir == DirectionalInputs.DOWN_BACK)
	elif action.begins_with("move_left"):
		return (dir == DirectionalInputs.BACK or dir == DirectionalInputs.DOWN_BACK) if input_side > 0 else (dir == DirectionalInputs.FORWARD or dir == DirectionalInputs.DOWN_FORWARD)
	elif action.begins_with("st_mp"):
		return buttons == ButtonInputs.ST_MP
	elif action.begins_with("st_mk"):
		return buttons == ButtonInputs.ST_MK
	return false

func was_pressed(index: int, action: String) -> bool:
	var prev_index = (index - 1 + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
	var curr_raw = input_history[index].raw_input
	var prev_raw = input_history[prev_index].raw_input
	var curr_dir = curr_raw >> 8
	var prev_dir = prev_raw >> 8
	var curr_buttons = curr_raw & 0xFF
	var prev_buttons = prev_raw & 0xFF
	
	if action.begins_with("crouch"):
		return (curr_dir == DirectionalInputs.DOWN or curr_dir == DirectionalInputs.DOWN_FORWARD or curr_dir == DirectionalInputs.DOWN_BACK) and \
			   (prev_dir != DirectionalInputs.DOWN and prev_dir != DirectionalInputs.DOWN_FORWARD and prev_dir != DirectionalInputs.DOWN_BACK) and \
			   input_history[index].duration <= 10
	elif action.begins_with("move_right"):
		if input_side > 0:
			return (curr_dir == DirectionalInputs.FORWARD or curr_dir == DirectionalInputs.DOWN_FORWARD) and \
				   (prev_dir != DirectionalInputs.FORWARD and prev_dir != DirectionalInputs.DOWN_FORWARD) and \
				   input_history[index].duration <= 10
		else:
			return (curr_dir == DirectionalInputs.BACK or curr_dir == DirectionalInputs.DOWN_BACK) and \
				   (prev_dir != DirectionalInputs.BACK and prev_dir != DirectionalInputs.DOWN_BACK) and \
				   input_history[index].duration <= 10
	elif action.begins_with("move_left"):
		if input_side > 0:
			return (curr_dir == DirectionalInputs.BACK or curr_dir == DirectionalInputs.DOWN_BACK) and \
				   (prev_dir != DirectionalInputs.BACK and prev_dir != DirectionalInputs.DOWN_BACK) and \
				   input_history[index].duration <= 10
		else:
			return (curr_dir == DirectionalInputs.FORWARD or curr_dir == DirectionalInputs.DOWN_FORWARD) and \
				   (prev_dir != DirectionalInputs.FORWARD and prev_dir != DirectionalInputs.DOWN_FORWARD) and \
				   input_history[index].duration <= 10
	elif action.begins_with("st_mp"):
		return curr_buttons == ButtonInputs.ST_MP and prev_buttons != ButtonInputs.ST_MP and \
			   input_history[index].duration <= 5
	elif action.begins_with("st_mk"):
		return curr_buttons == ButtonInputs.ST_MK and prev_buttons != ButtonInputs.ST_MK and \
			   input_history[index].duration <= 5
	return false

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
