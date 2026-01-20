class_name SpaceControl extends Node

enum Zone { FAR, MID, CLOSE, CORNER }

func get_current_zone(ai_player: Player, opponent: Player) -> Zone:
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	
	if is_in_corner(ai_player, ai_player.world):
		return Zone.CORNER
	elif distance > 250:
		return Zone.FAR
	elif distance > 100:
		return Zone.MID
	else:
		return Zone.CLOSE

func is_in_corner(player: Player, world: Node) -> bool:
	if not world:
		return false
	var left_wall = world.arena_left if "arena_left" in world else 0.0
	var right_wall = world.arena_right if "arena_right" in world else 1152.0
	var x = player.global_position.x
	return (x - left_wall < 150) or (right_wall - x < 150)

func get_ideal_distance(ai_id: String, opp_id: String) -> float:
	"""獲取理想距離（基於角色特性）"""
	var ranges = {
		"DAV": 180.0,  # Davis 中距離角色
		"DEN": 95.0    # Dennis 近距離角色
	}
	return ranges.get(ai_id, 120.0)

func should_escape_corner(player: Player, world: Node) -> bool:
	"""判斷是否應該逃離角落"""
	if not is_in_corner(player, world):
		return false
	
	# 檢查是否在地面且沒有處於特殊狀態
	return player.is_on_floor() and not player.is_hit and not player.is_knockfly

func get_escape_action(player: Player, opponent: Player, world: Node) -> String:
	"""獲取逃離角落的最佳動作"""
	if not should_escape_corner(player, world):
		return ""
	
	var distance = abs(player.global_position.x - opponent.global_position.x)
	
	# 如果對手很近，跳躍是更好的選擇
	if distance < 100:
		return "jump_forward"
	# 如果對手較遠，衝刺通過
	elif distance < 200:
		return "dash_forward"
	else:
		return "walk_forward"
