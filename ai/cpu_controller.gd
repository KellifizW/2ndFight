extends Node

# 改為用 seat 抓取動態生成的兩個玩家（player_a / player_b），
# 不依賴群組內節點的順序，重複按鍵 / 重開對戰時都可靠。
signal ai_state_changed(seat: String, enabled: bool)

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
	add_to_group("cpu_controller")

	# 延遲一幀抓取，確保 world 已生成玩家並加入群組
	await get_tree().process_frame
	players = get_tree().get_nodes_in_group("players")

	if players.size() < 2:
		push_warning("CPUController：找不到兩個玩家！目前找到 %d 個" % players.size())
	else:
		if startup_logs:
			Debug.log("Debug: CPUController ready! 找到 %d 個玩家" % players.size())
			Debug.log("Debug: 按 'C' 鍵切換 Player A AI，按 'V' 鍵切換 Player B AI")
			Debug.log("Debug: 對戰畫面下方也有觸碰式 AI 開關按鈕")

		# 應用招式限制設定到動態生成的玩家
		_apply_move_restrictions()

# 同時支援 InputMap 與直接按鍵比對：
# Web 版（瀏覽器 / 不同鍵盤佈局）曾回報 action 匹配不到，
# 因此直接比對 keycode / physical_keycode / unicode 作為保險。
func _input(event: InputEvent) -> void:
	if _is_cpu_toggle_key(event, "cpu_p1", KEY_C):
		toggle_ai_a()
	elif _is_cpu_toggle_key(event, "cpu_p2", KEY_V):
		toggle_ai_b()

func _is_cpu_toggle_key(event: InputEvent, action: String, key: int) -> bool:
	if not (event is InputEventKey):
		return false
	if not event.pressed or event.echo:
		return false

	# 正常路徑：走 InputMap
	if event.is_action_pressed(action):
		return true

	# Web 保險路徑：直接比對按鍵代碼
	if event.keycode == key or event.physical_keycode == key:
		return true

	# 最後再比對 unicode（例如某些環境只提供 C/c、V/v 字元）
	var upper := int(key)
	var lower := int(key) + (ord("a") - ord("A"))
	if event.unicode == upper or event.unicode == lower:
		return true

	return false

# ============================================================
# 對外控制：供鍵盤（C / V）與對戰畫面觸碰按鈕共用
# ============================================================
func toggle_ai_a() -> void:
	_set_ai_enabled("player_a", not ai_enabled_a)

func toggle_ai_b() -> void:
	_set_ai_enabled("player_b", not ai_enabled_b)

func set_ai_enabled(seat: String, enabled: bool) -> void:
	_set_ai_enabled(seat, enabled)

func _set_ai_enabled(seat: String, enabled: bool) -> void:
	var player = _get_player(seat)
	if player == null:
		Debug.log("Warning: %s 不存在，無法切換 AI" % seat)
		return

	if seat == "player_a":
		ai_enabled_a = enabled
	else:
		ai_enabled_b = enabled

	player.is_ai_controlled = enabled

	var ai_behavior = player.get_node_or_null("AIBehavior")
	if ai_behavior and ai_behavior.has_method("set_ai_enabled"):
		ai_behavior.set_ai_enabled(enabled)

	ai_state_changed.emit(seat, enabled)

	Debug.log("Debug: %s AI %s！（角色：%s）" % [
		"Player A" if seat == "player_a" else "Player B",
		"啟用" if enabled else "停用",
		player.character_id if "character_id" in player else "UNKNOWN"
	])

func _get_player(seat: String) -> Node:
	var found: Array = get_tree().get_nodes_in_group("players")
	for p in found:
		if p is Player and p.seat == seat:
			return p

	# 備用：群組抓到的節點尚未設定 seat 時，依索引回退
	if seat == "player_a" and found.size() > 0:
		return found[0]
	if seat == "player_b" and found.size() > 1:
		return found[1]
	return null

func _apply_move_restrictions() -> void:
	"""將 Inspector 設定的招式限制應用到動態生成的玩家"""
	if players.size() < 2:
		return

	# 應用 Player A 的限制
	var player_a = _get_player("player_a")
	var ai_behavior_a = player_a.get_node_or_null("AIBehavior") if player_a else null
	if ai_behavior_a and ai_behavior_a.has_method("set_move_restrictions"):
		ai_behavior_a.set_move_restrictions(restricted_moves_a, enable_restrictions_a)
		if enable_restrictions_a and restricted_moves_a.size() > 0:
			if startup_logs:
				Debug.log("[CPU Controller] Player A move restrictions applied: %s" % str(restricted_moves_a))

	# 應用 Player B 的限制
	var player_b = _get_player("player_b")
	var ai_behavior_b = player_b.get_node_or_null("AIBehavior") if player_b else null
	if ai_behavior_b and ai_behavior_b.has_method("set_move_restrictions"):
		ai_behavior_b.set_move_restrictions(restricted_moves_b, enable_restrictions_b)
		if enable_restrictions_b and restricted_moves_b.size() > 0:
			if startup_logs:
				Debug.log("[CPU Controller] Player B move restrictions applied: %s" % str(restricted_moves_b))
