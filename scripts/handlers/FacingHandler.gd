class_name FacingHandler extends Node

# Handles facing direction updates and management
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func set_facing(new_facing: float) -> void:
	if movement_node.facing_direction != new_facing:
		var seat = movement_node.get_meta("player_seat") if movement_node.has_meta("player_seat") else "unknown"
		Debug.log("[FACING_CHANGE] %s: %.1f → %.1f" % [seat, movement_node.facing_direction, new_facing])
	movement_node.facing_direction = new_facing
	movement_node.scale.x = sign(new_facing)
	movement_node.scale.y = 1
	if movement_node.sprite:
		movement_node.sprite.scale.x = 1.0
	movement_node.rotation_degrees = 0
	movement_node.update_hitbox_position()

func update_facing_direction(ignore_locks: bool = false) -> void:
	var is_landing_state = ("is_landing" in movement_node and movement_node.is_landing and "landing_lock_frames" in movement_node and movement_node.landing_lock_frames > 0)
	
	# 【cross-up 不變式】正常跳躍在空中時**絕不**翻面。
	#
	# 跳過對手頭頂的那一刻左右關係就已經反轉，若這裡放行，角色會在半空中
	# 轉身。設計上的翻面時機是「著地 → 播完 landing 動畫 → 著地鎖歸零」，
	# 由 TimerHandler 收尾時執行。landing_facing_lock 本來就負責這件事，
	# 但它散落在多個 handler（dash 結束、特殊招式收尾、AI 取消 dash…）都會被清掉，
	# 少一處就漏一次。這條檢查把「空中不翻面」變成 FacingHandler 自己的不變式。
	#
	# 刻意排除的空中狀態（維持原行為，不在本次修正範圍）：
	#   受擊 / 擊飛 / 空中受擊後跳 / 被摔投 → 面向會影響擊退方向，由 Fighter.take_hit 決定；
	#   特殊招式（DP 等）→ 由 MoveSet 以 force_update_facing_direction() 明確控制。
	if not ignore_locks and _is_airborne_normal_jump():
		return
	
	if not ignore_locks and (movement_node.is_attacking or movement_node.landing_facing_lock or is_landing_state or movement_node.is_layground):
		return
	
	var players = movement_node.get_tree().get_nodes_in_group("players")
	var other_player = null
	for p in players:
		if p != movement_node:
			other_player = p
			break
	
	if not other_player:
		set_facing(1.0)
		return
	
	var self_left = movement_node.global_position.x - movement_node.colbox_half_width
	var self_right = movement_node.global_position.x + movement_node.colbox_half_width
	var other_left = other_player.global_position.x - other_player.colbox_half_width
	var other_right = other_player.global_position.x + other_player.colbox_half_width
	var epsilon = 1.0
	
	if self_left > other_right + epsilon:
		set_facing(-1.0)
	elif self_right < other_left - epsilon:
		set_facing(1.0)
	else:
		var push_manager = movement_node.get_tree().get_first_node_in_group("push_manager")
		var is_at_left_corner = push_manager.is_at_corner(movement_node) if push_manager else false
		if is_at_left_corner:
			set_facing(-1.0 if movement_node.global_position.x > other_player.global_position.x else 1.0)
		else:
			set_facing(movement_node.facing_direction)

## 「此刻正處於一次普通跳躍的空中段」= 不允許改變面向。
##
## 只認 is_jumping（普通跳躍與其著地前的落下段），並排除所有由外部系統
## 決定面向的空中狀態（受擊族、被摔、特殊招式）。
func _is_airborne_normal_jump() -> bool:
	if movement_node.has_method("is_on_floor") and movement_node.is_on_floor():
		return false
	if not _flag("is_jumping"):
		return false
	if _flag("is_hit") or _flag("is_knockfly") or _flag("is_layground") \
			or _flag("is_air_hit_backjump") or _flag("is_being_thrown"):
		return false
	var move_set: Node = movement_node.get_node_or_null("MoveSet")
	if move_set != null and "is_spmove" in move_set and move_set.is_spmove:
		return false
	return true

func _flag(prop: String) -> bool:
	return prop in movement_node and bool(movement_node.get(prop))
