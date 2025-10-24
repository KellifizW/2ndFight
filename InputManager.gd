class_name InputManager extends Node

# 模仿 Sakuga 的枚舉
enum DirectionalInputs { NEUTRAL = 0, DOWN = 1, DOWN_FORWARD = 2, FORWARD = 3, DOWN_BACK = 4, BACK = 5 }
enum ButtonInputs { NONE = 0, ST_MP = 1, ST_MK = 2 }
enum ButtonMode { PRESS, HOLD }

const INPUT_HISTORY_SIZE: int = 240  # 擴大到 240 (約 2 秒)，允許更長的總輸入時間
const INPUT_BUFFER: int = 45  # 增大到 45，增加魯棒性，兼容按鍵持續太久或重複
const MAX_TOTAL_FRAMES: int = 120  # 總匹配時間限制，約 2 秒

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

const FIREBALL_SEQUENCE3: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const FIREBALL_SEQUENCE4: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const POWERKK_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const POWERKK_SEQUENCE2: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const SPNK_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.ST_MK, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const SPNK_SEQUENCE2: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MK, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

var fireball_motion: Dictionary = {
	"ValidInputs": [FIREBALL_SEQUENCE, FIREBALL_SEQUENCE2, FIREBALL_SEQUENCE3, FIREBALL_SEQUENCE4],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var powerkk_motion: Dictionary = {
	"ValidInputs": [POWERKK_SEQUENCE, POWERKK_SEQUENCE2],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var spnk_motion: Dictionary = {
	"ValidInputs": [SPNK_SEQUENCE, SPNK_SEQUENCE2],
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false
}

var input_history: Array[InputRegistry] = []
var current_history: int = 0
var input_side: int = 1  # 1 = 面對右, -1 = 面對左

func _ready():
	input_history.resize(INPUT_HISTORY_SIZE)
	for i in INPUT_HISTORY_SIZE:
		input_history[i] = InputRegistry.new()

func update_input():
	var raw_input = get_current_raw_input()
	insert_to_history(raw_input)
	# 僅在檢測到 st_mp 或 st_mk 輸入時檢查招式
	var parent = get_parent()
	var suffix = "_p2" if parent and parent.player_id == "p2" else ""
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	if Input.is_action_just_pressed("st_mp" + suffix):
		if player_id == "p1":
			check_powerkk_input()
		check_fireball_input()
	elif Input.is_action_just_pressed("st_mk" + suffix):
		if player_id == "p2":
			check_spnk_input()

func get_current_raw_input() -> int:
	var parent = get_parent()
	var facing = parent.facing_direction if parent and "facing_direction" in parent else 1.0
	input_side = sign(facing)
	var suffix = "_p2" if parent and parent.player_id == "p2" else ""
	
	var dir = DirectionalInputs.NEUTRAL
	var down = Input.is_action_pressed("crouch" + suffix)
	var forward = Input.is_action_pressed(("move_right" if input_side > 0 else "move_left") + suffix)
	var back = Input.is_action_pressed(("move_left" if input_side > 0 else "move_right") + suffix)
	
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	if player_id == "p1" and (down or forward or back):
		print("Debug: [%s] down = %s, forward = %s, back = %s, input_side = %d, suffix = %s" % [player_id, down, forward, back, input_side, suffix])
	
	if down and forward:
		dir = DirectionalInputs.DOWN_FORWARD
	elif down and back:
		dir = DirectionalInputs.DOWN_BACK
	elif down:
		dir = DirectionalInputs.DOWN
	elif forward:
		dir = DirectionalInputs.FORWARD
	elif back:
		dir = DirectionalInputs.BACK
	
	var buttons = ButtonInputs.NONE
	if Input.is_action_just_pressed("st_mp" + suffix):
		buttons = ButtonInputs.ST_MP
	elif Input.is_action_just_pressed("st_mk" + suffix):
		buttons = ButtonInputs.ST_MK
	
	if player_id == "p1" and buttons > 0:
		print("Debug: [%s] buttons = %d" % [player_id, buttons])
	
	return (dir << 8) | buttons

func insert_to_history(raw_input: int):
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	
	if input_history[current_history].raw_input != raw_input:
		current_history = (current_history + 1) % INPUT_HISTORY_SIZE
		input_history[current_history] = InputRegistry.new()
		input_history[current_history].raw_input = raw_input
		input_history[current_history].duration = 1
		if player_id == "p1" and raw_input != 0:
			print("Debug: [%s] New input inserted at history[%d]: %d (duration=1)" % [player_id, current_history, raw_input])
	else:
		input_history[current_history].duration += 1
		if player_id == "p1" and raw_input != 0 and input_history[current_history].duration % 10 == 0:
			print("Debug: [%s] Input unchanged, duration increased at history[%d] to %d" % [player_id, current_history, input_history[current_history].duration])

func check_fireball_input() -> bool:
	return check_motion(fireball_motion)

func check_powerkk_input() -> bool:
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	if player_id != "p1": return false
	return check_motion(powerkk_motion)

func check_spnk_input() -> bool:
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	if player_id != "p2": return false
	return check_motion(spnk_motion)

func check_motion(motion: Dictionary) -> bool:
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	
	var found = false
	for seq in motion.ValidInputs:
		# 檢查序列的最後輸入是否包含對應按鈕 (ST_MP 或 ST_MK)
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
			while hist_pos >= 0 and not step_matched:
				var hist = input_history[hist_pos]
				total_frames += hist.duration
				if total_frames > MAX_TOTAL_FRAMES:
					matched = false
					break
				
				if check_input(hist_pos, step.directional, step.buttons if "buttons" in step else 0, step.dir_mode, step.but_mode if "but_mode" in step else ButtonMode.PRESS):
					if hist.duration <= motion.InputBuffer:
						step_matched = true
						seq_idx -= 1
				
				hist_pos = (hist_pos - 1 + INPUT_HISTORY_SIZE) % INPUT_HISTORY_SIZE
			
			if not step_matched:
				matched = false
		
		if matched:
			found = true
			if player_id == "p1" or player_id == "p2":
				print("Debug: [%s] Sequence matched for %s!" % [player_id, "PowerKK" if "powerkk" in motion else "Spnk" if "spnk" in motion else "Fireball"])
			break
	
	return found

func check_input(index: int, directional: int, buttons: int, dir_mode: int, but_mode: int) -> bool:
	var parent = get_parent()
	var suffix = "_p2" if parent and parent.player_id == "p2" else ""
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
	
	var dir_match = (directional == DirectionalInputs.DOWN and down and not (forward or back)) or \
		(directional == DirectionalInputs.DOWN_FORWARD and down and forward) or \
		(directional == DirectionalInputs.FORWARD and forward and not down) or \
		(directional == DirectionalInputs.DOWN_BACK and down and back) or \
		(directional == DirectionalInputs.BACK and back and not down) or \
		(directional == DirectionalInputs.NEUTRAL and not (down or forward or back))
	
	var but_match = (buttons == 0) or button
	
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	var hist_buttons = input_history[index].raw_input & 0xFF
	if (player_id == "p1" or player_id == "p2") and not (dir_match and but_match) and buttons > 0 and hist_buttons > 0:
		print("Debug: [%s] Input check failed: dir_match=%s, but_match=%s, directional=%d, buttons=%d" % [player_id, dir_match, but_match, directional, buttons])
	
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

class InputRegistry:
	var raw_input: int = 0
	var duration: int = 0
