class_name ControlHistory extends Node

var control_history = [[], []]
const MAX_HISTORY = 10
const INPUT_WINDOW_MS = 300

enum MoveDirection {
	NONE,
	FORWARD,
	BACKWARD,
	DOWN,
	DOWN_FORWARD,
	DOWN_BACKWARD,
	UP_FORWARD,
	UP_BACKWARD,
	UP
}

enum SpecialMoveButton {
	NONE,
	ST_MP
}

func poll_control(time: float, player_id: int, direction: MoveDirection, buttons: Array):
	var snapshot = {
		"time": time,
		"move": direction,
		"buttons": buttons.duplicate()
	}
	if _is_snapshot_different(snapshot, player_id):
		if control_history[player_id].size() >= MAX_HISTORY:
			control_history[player_id].pop_front()
		control_history[player_id].append(snapshot)
		print("Debug: Snapshot recorded for player %d: %s" % [player_id, snapshot])

func _is_snapshot_different(snapshot: Dictionary, player_id: int) -> bool:
	if not control_history[player_id] is Array or control_history[player_id].size() == 0:
		return true
	var last = control_history[player_id][-1]
	if abs(snapshot.time - last.time) < 0.001:
		return false
	return snapshot.move != last.move or snapshot.buttons != last.buttons

func has_special_move_been_executed(special_move: Dictionary, player_id: int, current_time: float) -> bool:
	var sequence = special_move.sequence
	
	if control_history[player_id].size() == 0:
		special_move.cursor = 0
		print("Debug: No input history for player %d, special move not executed" % player_id)
		return false
	
	var history_size = control_history[player_id].size()
	var sequence_length = sequence.size()
	if history_size < sequence_length:
		return false
	
	var matched = true
	var last_snapshot_time = 0.0
	for i in range(sequence_length):
		var history_index = history_size - sequence_length + i
		if history_index < 0:
			matched = false
			break
		
		var snapshot = control_history[player_id][history_index]
		var expected = sequence[i]
		
		if expected in [MoveDirection.DOWN, MoveDirection.DOWN_FORWARD, MoveDirection.FORWARD]:
			if i == sequence_length - 1 and expected == MoveDirection.FORWARD:
				# 允許最後一步為 NONE 或 FORWARD
				if snapshot.move != expected and snapshot.move != MoveDirection.NONE:
					matched = false
					break
			else:
				if snapshot.move != expected:
					matched = false
					break
		elif expected == SpecialMoveButton.ST_MP:
			if not snapshot.buttons[0]:
				matched = false
				break
		
		if i > 0 and (snapshot.time - control_history[player_id][history_index - 1].time) > INPUT_WINDOW_MS / 1000.0:
			matched = false
			break
		last_snapshot_time = snapshot.time
	
	if matched and (current_time - last_snapshot_time) <= INPUT_WINDOW_MS / 1000.0:
		special_move.cursor = sequence_length
		control_history[player_id].clear()
		print("Debug: Special move sequence completed for player %d, input history cleared" % player_id)
		return true
	else:
		# 修改 cursor 重置邏輯，僅當明確錯誤輸入時重置
		if history_size > 0:
			var latest_snapshot = control_history[player_id][-1]
			var cursor = special_move.cursor
			var expected = sequence[cursor] if cursor < sequence_length else null
			if expected and latest_snapshot.move != MoveDirection.NONE and latest_snapshot.move != expected and not (expected == SpecialMoveButton.ST_MP and latest_snapshot.buttons[0]):
				# 僅當最新輸入明確與序列不符時重置
				if latest_snapshot.time - control_history[player_id][-2].time > INPUT_WINDOW_MS / 1000.0 if history_size > 1 else true:
					special_move.cursor = 0
					print("Debug: Input mismatch for player %d, snapshot=%s, expected=%s, cursor reset" % [player_id, latest_snapshot, expected])
		return false

func _ready():
	print("Debug: ControlHistory node initialized at %s" % get_path())
