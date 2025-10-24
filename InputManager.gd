class_name InputManager extends Node

# 模仿 Sakuga 的枚舉
enum DirectionalInputs { NEUTRAL = 0, DOWN = 1, DOWN_FORWARD = 2, FORWARD = 3, DOWN_BACK = 4, BACK = 5 }
enum ButtonInputs { NONE = 0, ST_MP = 1 }
enum ButtonMode { PRESS, HOLD }

const INPUT_HISTORY_SIZE: int = 240  # 擴大到 240 (約 2 秒)，允許更長的總輸入時間
const INPUT_BUFFER: int = 30  # 增大到 30，兼容按鍵持續太久

const FIREBALL_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}  # 改為 HOLD，兼容 PRESS 或 HOLD
]

const FIREBALL_SEQUENCE2: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}  # 改為 HOLD
]

# 新增變體：允許方向後單獨按 ST_MP（不需同時按 FORWARD）
const FIREBALL_SEQUENCE3: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

# 新增變體：基於 SEQUENCE2 的單獨 ST_MP
const FIREBALL_SEQUENCE4: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN_FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.FORWARD, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

const POWERKK_SEQUENCE: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}  # 改為 HOLD
]

# 新增變體：powerkk 的單獨 ST_MP
const POWERKK_SEQUENCE2: Array[Dictionary] = [
	{"directional": DirectionalInputs.DOWN, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.DOWN_BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.BACK, "buttons": ButtonInputs.NONE, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.PRESS},
	{"directional": DirectionalInputs.NEUTRAL, "buttons": ButtonInputs.ST_MP, "dir_mode": ButtonMode.HOLD, "but_mode": ButtonMode.HOLD}
]

var fireball_motion: Dictionary = {  # 模仿 MotionInputs
	"ValidInputs": [FIREBALL_SEQUENCE, FIREBALL_SEQUENCE2, FIREBALL_SEQUENCE3, FIREBALL_SEQUENCE4],  # 新增變體
	"InputBuffer": INPUT_BUFFER,
	"AbsoluteDirection": false  # 如 Sakuga
}

var powerkk_motion: Dictionary = {  # 新增：powerkk 輸入配置
	"ValidInputs": [POWERKK_SEQUENCE, POWERKK_SEQUENCE2],  # 新增變體
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
	insert_to_history(raw_input)  # 每幀呼叫，無條件

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
		if player_id == "p1":
			# 確保在按下 st_mp 時保留方向輸入
			if forward:
				dir = DirectionalInputs.FORWARD
			elif back:
				dir = DirectionalInputs.BACK
			elif down and forward:
				dir = DirectionalInputs.DOWN_FORWARD
			elif down and back:
				dir = DirectionalInputs.DOWN_BACK
			elif down:
				dir = DirectionalInputs.DOWN
	
	if player_id == "p1" and buttons > 0:
		print("Debug: [%s] buttons = %d" % [player_id, buttons])
	
	return (dir << 8) | buttons

func insert_to_history(raw_input: int):
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	
	if input_history[current_history].raw_input != raw_input:
		current_history = (current_history + 1) % INPUT_HISTORY_SIZE
		input_history[current_history] = InputRegistry.new()  # 新條目
		input_history[current_history].raw_input = raw_input
		input_history[current_history].duration = 1  # 注意：從1開始
		if player_id == "p1" and raw_input != 0:
			print("Debug: [%s] New input inserted at history[%d]: %d (duration=1)" % [player_id, current_history, raw_input])
	else:
		input_history[current_history].duration += 1
		if player_id == "p1" and raw_input != 0 and input_history[current_history].duration % 10 == 0:  # 減少 print
			print("Debug: [%s] Input unchanged, duration increased at history[%d] to %d" % [player_id, current_history, input_history[current_history].duration])

func check_fireball_input() -> bool:
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	
	var motion = fireball_motion
	var found = false
	for seq in motion.ValidInputs:  # 支持多變體
		var length = seq.size()
		var starting_input = (current_history - length + 1)
		if starting_input < 0: starting_input += INPUT_HISTORY_SIZE
		var input_found = true
		for j in range(length):
			var hist_idx = (starting_input + j) % INPUT_HISTORY_SIZE
			var hist = input_history[hist_idx]
			var dir = seq[j].directional
			var buttons = seq[j].buttons if "buttons" in seq[j] else 0
			var dir_mode = seq[j].dir_mode
			var but_mode = seq[j].but_mode if "but_mode" in seq[j] else ButtonMode.PRESS
			
			var valid_buffer = motion.InputBuffer == 0 or hist.duration <= motion.InputBuffer
			var valid_input = check_input(hist_idx, dir, buttons, dir_mode, but_mode)
			
			if not (valid_buffer and valid_input):
				input_found = false
				if player_id == "p1" or player_id == "p2":
					print("Debug: [%s] Fireball mismatch at seq[%d], hist[%d]: raw=%d, duration=%d (valid_buffer=%s, valid_input=%s)" % [player_id, j, hist_idx, hist.raw_input, hist.duration, valid_buffer, valid_input])
				break
		if input_found:
			found = true
			if player_id == "p1" or player_id == "p2":
				print("Debug: [%s] Fireball sequence matched!" % player_id)
			break
	return found

func check_powerkk_input() -> bool:
	var parent = get_parent()
	var player_id = parent.player_id if parent and "player_id" in parent else "unknown"
	if player_id != "p1": return false  # 僅 P1 可使用 powerkk
	
	var motion = powerkk_motion
	var found = false
	for seq in motion.ValidInputs:
		var length = seq.size()
		var starting_input = (current_history - length + 1)
		if starting_input < 0: starting_input += INPUT_HISTORY_SIZE
		var input_found = true
		for j in range(length):
			var hist_idx = (starting_input + j) % INPUT_HISTORY_SIZE
			var hist = input_history[hist_idx]
			var dir = seq[j].directional
			var buttons = seq[j].buttons if "buttons" in seq[j] else 0
			var dir_mode = seq[j].dir_mode
			var but_mode = seq[j].but_mode if "but_mode" in seq[j] else ButtonMode.PRESS
			
			var valid_buffer = motion.InputBuffer == 0 or hist.duration <= motion.InputBuffer
			var valid_input = check_input(hist_idx, dir, buttons, dir_mode, but_mode)
			
			if not (valid_buffer and valid_input):
				input_found = false
				if player_id == "p1":
					print("Debug: [%s] PowerKK mismatch at seq[%d], hist[%d]: raw=%d, duration=%d (valid_buffer=%s, valid_input=%s)" % [player_id, j, hist_idx, hist.raw_input, hist.duration, valid_buffer, valid_input])
				break
		if input_found:
			found = true
			if player_id == "p1":
				print("Debug: [%s] PowerKK sequence matched!" % player_id)
			break
	return found

func check_input(index: int, directional: int, buttons: int, dir_mode: int, but_mode: int) -> bool:
	var parent = get_parent()
	var suffix = "_p2" if parent and parent.player_id == "p2" else ""
	var forward_action = "move_right" + suffix if input_side > 0 else "move_left" + suffix
	var back_action = "move_left" + suffix if input_side > 0 else "move_right" + suffix
	var down_action = "crouch" + suffix
	var button_action = "st_mp" + suffix if buttons == ButtonInputs.ST_MP else ""
	
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
	if (player_id == "p1" or player_id == "p2") and not (dir_match and but_match):
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
			   input_history[index].duration <= 10  # 增大到 10，兼容切換不夠快
	elif action.begins_with("move_right"):
		if input_side > 0:
			return (curr_dir == DirectionalInputs.FORWARD or curr_dir == DirectionalInputs.DOWN_FORWARD) and \
				   (prev_dir != DirectionalInputs.FORWARD and prev_dir != DirectionalInputs.DOWN_FORWARD) and \
				   input_history[index].duration <= 10  # 增大到 10
		else:
			return (curr_dir == DirectionalInputs.BACK or curr_dir == DirectionalInputs.DOWN_BACK) and \
				   (prev_dir != DirectionalInputs.BACK and prev_dir != DirectionalInputs.DOWN_BACK) and \
				   input_history[index].duration <= 10  # 增大到 10
	elif action.begins_with("move_left"):
		if input_side > 0:
			return (curr_dir == DirectionalInputs.BACK or curr_dir == DirectionalInputs.DOWN_BACK) and \
				   (prev_dir != DirectionalInputs.BACK and prev_dir != DirectionalInputs.DOWN_BACK) and \
				   input_history[index].duration <= 10  # 增大到 10
		else:
			return (curr_dir == DirectionalInputs.FORWARD or curr_dir == DirectionalInputs.DOWN_FORWARD) and \
				   (prev_dir != DirectionalInputs.FORWARD and prev_dir != DirectionalInputs.DOWN_FORWARD) and \
				   input_history[index].duration <= 10  # 增大到 10
	elif action.begins_with("st_mp"):
		return curr_buttons == ButtonInputs.ST_MP and prev_buttons != ButtonInputs.ST_MP and \
			   input_history[index].duration <= 5  # 增大到 5，兼容短暫 HOLD
	return false

# 輔助結構
class InputRegistry:
	var raw_input: int = 0
	var duration: int = 0
