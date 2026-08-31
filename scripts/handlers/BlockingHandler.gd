class_name BlockingHandler extends Node

# Handles blocking logic and state
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_blocking(input_dir: int, is_special_moving: bool) -> void:
	# Stage 2 切片 5：站姿進入 / 釋放兩份守衛收攏到 FighterState
	# （逐字值等價：256 / 16 組合 Python 窮舉 0 分岔，test_36 引擎內逐幀釘住）。
	# 兩份守衛刻意**不是**同一個條件 —— 進入不含 is_blocking（blockstun 期間
	# 持續重取樣 held 方向，切片 4 finding #1 的預期行為），釋放含 is_blocking
	# （硬直期間站姿旗標保留）。詳見 FighterState 格擋族段頭，不要合併成一份。
	if FighterState.can_enter_block_stance(movement_node, is_special_moving):
		movement_node.is_holding_back = input_dir * movement_node.facing_direction < 0
		movement_node.is_crouch_blocking = movement_node.is_crouching and movement_node.is_holding_back
		
		# Proximity Block: 當向後移動且對手在proximity range內時,播放block動畫
		# 但不影響其他操作(跳躍、攻擊等),只阻止向後移動
		if movement_node.is_opponent_proximity and movement_node.is_holding_back:
			if not movement_node.is_proximity_blocking:
				var player_seat = movement_node.player.seat if movement_node.player and "seat" in movement_node.player else "?"
				Debug.log("[PROXIMITY BLOCK] %s: 激活 proximity block (opponent_prox=%s, holding_back=%s)" % [
					player_seat,
					movement_node.is_opponent_proximity,
					movement_node.is_holding_back
				])
			movement_node.is_proximity_blocking = true
		else:
			if movement_node.is_proximity_blocking:
				var player_seat = movement_node.player.seat if movement_node.player and "seat" in movement_node.player else "?"
				Debug.log("[PROXIMITY BLOCK] %s: 取消 proximity block" % player_seat)
			movement_node.is_proximity_blocking = false
	else:
		if FighterState.can_release_block_stance(movement_node):
			movement_node.is_holding_back = false
			movement_node.is_crouch_blocking = false
			movement_node.is_proximity_blocking = false
