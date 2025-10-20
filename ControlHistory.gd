class_name ControlHistory extends Node

# 輸入歷史（兩個玩家）
var control_history = [[], []] # 每個玩家一個陣列
const MAX_HISTORY = 10 # 最大快照數
const INPUT_WINDOW_MS = 150 # 時間窗口（毫秒）

# 方向列舉（基於 input_dir 和 facing_direction）
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

# 按鈕列舉（僅需 st_mp 作為觸發）
enum SpecialMoveButton {
	NONE,
	ST_MP
}

# 記錄輸入快照
func poll_control(time: float, player_id: int, direction: MoveDirection, buttons: Array):
	var snapshot = {
		"time": time,
		"move": direction,
		"buttons": buttons.duplicate()  # [st_mp_pressed]
	}
	if _is_snapshot_different(snapshot, player_id):
		if control_history[player_id].size() >= MAX_HISTORY:
			control_history[player_id].pop_front()
		control_history[player_id].append(snapshot)
		print("Debug: Snapshot recorded for player %d: %s" % [player_id, snapshot])

# 檢查快照是否與前一個不同
func _is_snapshot_different(snapshot: Dictionary, player_id: int) -> bool:
	if not control_history[player_id] is Array or control_history[player_id].size() == 0:
		return true
	var last = control_history[player_id][-1]
	return snapshot.move != last.move or snapshot.buttons != last.buttons

# 檢查序列是否完成，返回是否成功
func has_special_move_been_executed(special_move: Dictionary, player_id: int, current_time: float) -> bool:
	var cursor = special_move.cursor
	var sequence = special_move.sequence
	if cursor > 0 and (not control_history[player_id] is Array or control_history[player_id].size() == 0):
		var last_time = control_history[player_id][-1].time
		if current_time - last_time > INPUT_WINDOW_MS / 1000.0:
			special_move.cursor = 0
			return false
	if control_history[player_id] is Array and control_history[player_id].size() > 0:
		var snapshot = control_history[player_id][-1]
		var expected = sequence[cursor]
		match expected:
			MoveDirection.DOWN, MoveDirection.DOWN_FORWARD, MoveDirection.FORWARD:
				if snapshot.move == expected:
					special_move.cursor += 1
			SpecialMoveButton.ST_MP:
				if snapshot.buttons[0]: # 檢查 st_mp
					special_move.cursor += 1
		if special_move.cursor >= sequence.size():
			special_move.cursor = 0
			control_history[player_id].clear() # 清空輸入歷史
			print("Debug: Special move sequence completed for player %d, input history cleared" % player_id)
			return true
	return false

func _ready():
	print("Debug: ControlHistory node initialized at %s" % get_path())
