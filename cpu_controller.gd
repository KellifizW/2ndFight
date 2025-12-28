extends Node

# 改用 players 群組抓取動態生成的兩個玩家（player_a 和 player_b）
@onready var players: Array = []

var ai_enabled_a: bool = false  # Player A（左邊/先手）的 AI 開關
var ai_enabled_b: bool = false  # Player B（右邊/後手）的 AI 開關

func _ready() -> void:
	# 延遲一幀抓取，確保 world 已生成玩家並加入群組
	await get_tree().process_frame
	players = get_tree().get_nodes_in_group("players")
	
	if players.size() < 2:
		push_warning("CPUController：找不到兩個玩家！目前找到 %d 個" % players.size())
	else:
		print("Debug: CPUController ready! 找到 %d 個玩家" % players.size())
		print("Debug: 按 'C' 鍵切換 Player A AI，按 'V' 鍵切換 Player B AI")

func _input(event: InputEvent) -> void:
	# 切換 Player A（左邊玩家）的 AI
	if event.is_action_pressed("cpu_p1"):  # 預設綁定 C 鍵
		if players.is_empty():
			print("Warning: 還沒有玩家可控制 AI")
			return
			
		ai_enabled_a = !ai_enabled_a
		var player_a = players[0]
		player_a.is_ai_controlled = ai_enabled_a
		
		var ai_behavior = player_a.get_node_or_null("AIBehavior")
		if ai_behavior and ai_behavior.has_method("set_ai_enabled"):
			ai_behavior.set_ai_enabled(ai_enabled_a)
		
		print("Debug: Player A AI %s！（角色：%s）" % [
			"啟用" if ai_enabled_a else "停用",
			player_a.character_id if "character_id" in player_a else "UNKNOWN"
		])
	
	# 切換 Player B（右邊玩家）的 AI
	if event.is_action_pressed("cpu_p2"):  # 預設綁定 V 鍵
		if players.size() < 2:
			print("Warning: Player B 不存在，無法切換 AI")
			return
			
		ai_enabled_b = !ai_enabled_b
		var player_b = players[1]
		player_b.is_ai_controlled = ai_enabled_b
		
		var ai_behavior = player_b.get_node_or_null("AIBehavior")
		if ai_behavior and ai_behavior.has_method("set_ai_enabled"):
			ai_behavior.set_ai_enabled(ai_enabled_b)
		
		print("Debug: Player B AI %s！（角色：%s）" % [
			"啟用" if ai_enabled_b else "停用",
			player_b.character_id if "character_id" in player_b else "UNKNOWN"
		])
