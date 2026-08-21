extends Node

# 改用 players 群組抓取動態生成的兩個玩家（player_a 和 player_b）
@onready var players: Array = []

var ai_enabled_a: bool = false  # Player A（左邊/先手）的 AI 開關
var ai_enabled_b: bool = false  # Player B（右邊/後手）的 AI 開關

# ============================================================
# AI MOVE RESTRICTIONS - Inspector Configuration
# ============================================================
@export_category("Player A AI Settings")
@export var enable_restrictions_a: bool = false
@export var restricted_moves_a: Array[String] = []

@export_category("Player B AI Settings")
@export var enable_restrictions_b: bool = false
@export var restricted_moves_b: Array[String] = []
@export var startup_logs: bool = false

func _ready() -> void:
	# 延遲一幀抓取，確保 world 已生成玩家並加入群組
	await get_tree().process_frame
	players = get_tree().get_nodes_in_group("players")
	
	if players.size() < 2:
		push_warning("CPUController：找不到兩個玩家！目前找到 %d 個" % players.size())
	else:
		if startup_logs:
			Debug.log("Debug: CPUController ready! 找到 %d 個玩家" % players.size())
			Debug.log("Debug: 按 'C' 鍵切換 Player A AI，按 'V' 鍵切換 Player B AI")
		
		# 應用招式限制設定到動態生成的玩家
		_apply_move_restrictions()

func _input(event: InputEvent) -> void:
	# 切換 Player A（左邊玩家）的 AI
	if event.is_action_pressed("cpu_p1"):  # 預設綁定 C 鍵
		if players.is_empty():
			Debug.log("Warning: 還沒有玩家可控制 AI")
			return
			
		ai_enabled_a = !ai_enabled_a
		var player_a = players[0]
		player_a.is_ai_controlled = ai_enabled_a
		
		var ai_behavior = player_a.get_node_or_null("AIBehavior")
		if ai_behavior and ai_behavior.has_method("set_ai_enabled"):
			ai_behavior.set_ai_enabled(ai_enabled_a)
		
		Debug.log("Debug: Player A AI %s！（角色：%s）" % [
			"啟用" if ai_enabled_a else "停用",
			player_a.character_id if "character_id" in player_a else "UNKNOWN"
		])
	
	# 切換 Player B（右邊玩家）的 AI
	if event.is_action_pressed("cpu_p2"):  # 預設綁定 V 鍵
		if players.size() < 2:
			Debug.log("Warning: Player B 不存在，無法切換 AI")
			return
			
		ai_enabled_b = !ai_enabled_b
		var player_b = players[1]
		player_b.is_ai_controlled = ai_enabled_b
		
		var ai_behavior = player_b.get_node_or_null("AIBehavior")
		if ai_behavior and ai_behavior.has_method("set_ai_enabled"):
			ai_behavior.set_ai_enabled(ai_enabled_b)
		
		Debug.log("Debug: Player B AI %s！（角色：%s）" % [
			"啟用" if ai_enabled_b else "停用",
			player_b.character_id if "character_id" in player_b else "UNKNOWN"
		])

func _apply_move_restrictions() -> void:
	"""將 Inspector 設定的招式限制應用到動態生成的玩家"""
	if players.size() < 2:
		return
	
	# 應用 Player A 的限制
	var player_a = players[0]
	var ai_behavior_a = player_a.get_node_or_null("AIBehavior")
	if ai_behavior_a and ai_behavior_a.has_method("set_move_restrictions"):
		ai_behavior_a.set_move_restrictions(restricted_moves_a, enable_restrictions_a)
		if enable_restrictions_a and restricted_moves_a.size() > 0:
			if startup_logs:
				Debug.log("[CPU Controller] Player A move restrictions applied: %s" % str(restricted_moves_a))
	
	# 應用 Player B 的限制
	var player_b = players[1]
	var ai_behavior_b = player_b.get_node_or_null("AIBehavior")
	if ai_behavior_b and ai_behavior_b.has_method("set_move_restrictions"):
		ai_behavior_b.set_move_restrictions(restricted_moves_b, enable_restrictions_b)
		if enable_restrictions_b and restricted_moves_b.size() > 0:
			if startup_logs:
				Debug.log("[CPU Controller] Player B move restrictions applied: %s" % str(restricted_moves_b))
