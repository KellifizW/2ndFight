class_name BlockingHandler extends Node

# Handles blocking logic and state
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_blocking(input_dir: int, is_special_moving: bool) -> void:
	if movement_node.is_on_floor() and not movement_node.is_attacking and not movement_node.is_dashing and not movement_node.is_backdashing and not is_special_moving and not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_layground):
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
		if not (movement_node.is_hit or movement_node.is_knockfly or movement_node.is_blocking or movement_node.is_layground):
			movement_node.is_holding_back = false
			movement_node.is_crouch_blocking = false
			movement_node.is_proximity_blocking = false
