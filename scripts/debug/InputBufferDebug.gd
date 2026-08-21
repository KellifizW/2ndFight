extends Label

@export var startup_logs: bool = false

# ============================================================
# INPUT BUFFER DEBUG DISPLAY (Optional)
# Shows buffered input statistics for debugging
# 支援雙玩家同時顯示，保留統計資料
# ============================================================

@export var enabled: bool = false  # Toggle debug display
@export var show_both_players: bool = true  # 同時顯示兩個玩家
@export var show_statistics: bool = true  # 顯示統計資料（不會消失）

var player1_controller: PlayerController = null
var player2_controller: PlayerController = null

# 統計資料：記錄每個按鈕被 buffer 的次數和最後一次時間
var p1_stats: Dictionary = {}  # {"st_mp": {"count": 5, "last_time": 123.4}}
var p2_stats: Dictionary = {}

# 記錄上一幀檢測到的 buffer（用來判斷是否是新的）
var p1_last_buffered: Array = []
var p2_last_buffered: Array = []

func _ready() -> void:
	if not enabled:
		visible = false
		return
	
	# 延遲一幀，確保玩家已生成
	await get_tree().process_frame
	
	# 自動尋找兩個玩家的 PlayerController
	var players = get_tree().get_nodes_in_group("players")
	if startup_logs:
		Debug.log("InputBufferDebug: 找到 %d 個玩家" % players.size())
	
	for player in players:
		var controller = player.get_node_or_null("PlayerController")
		if controller:
			var seat = player.seat if "seat" in player else "unknown"
			if startup_logs:
				Debug.log("InputBufferDebug: 找到玩家 %s 的 PlayerController" % seat)
			
			if seat == "player_a":
				player1_controller = controller
			elif seat == "player_b":
				player2_controller = controller
	
	if not player1_controller and not player2_controller:
		if startup_logs:
			Debug.log("InputBufferDebug: 警告 - 沒有找到任何 PlayerController！")

func _process(_delta: float) -> void:
	if not enabled or not visible:
		return
	
	# 更新統計資料
	if player1_controller:
		_update_stats(player1_controller, p1_stats, p1_last_buffered)
	if player2_controller:
		_update_stats(player2_controller, p2_stats, p2_last_buffered)
	
	# 顯示
	var display_text = ""
	
	if show_statistics:
		# 統計模式：顯示累積資料
		if player1_controller:
			display_text += _get_stats_text("Player A", p1_stats)
		else:
			display_text += "Player A: 未找到\n"
		
		if show_both_players:
			display_text += "\n"
			if player2_controller:
				display_text += _get_stats_text("Player B", p2_stats)
			else:
				display_text += "Player B: 未找到\n"
	else:
		# 即時模式：顯示當前 buffer（會消失）
		if player1_controller:
			display_text += _get_realtime_text("Player A", player1_controller)
		else:
			display_text += "Player A: 未找到\n"
		
		if show_both_players:
			display_text += "\n"
			if player2_controller:
				display_text += _get_realtime_text("Player B", player2_controller)
			else:
				display_text += "Player B: 未找到\n"
	
	text = display_text

func _update_stats(controller: PlayerController, stats: Dictionary, last_buffered: Array) -> void:
	if not controller or not controller.input_buffer:
		return
	
	var buffer = controller.input_buffer
	var active_inputs = buffer.get_active_buffers()
	
	# 檢查是否有新的 buffer 輸入
	for action in active_inputs:
		if action not in last_buffered:
			# 新的 buffer！更新統計
			if not stats.has(action):
				stats[action] = {"count": 0, "last_time": 0.0}
			stats[action].count += 1
			stats[action].last_time = Time.get_ticks_msec() / 1000.0
	
	# 更新上一幀的記錄
	last_buffered.clear()
	last_buffered.append_array(active_inputs)

func _get_stats_text(player_name: String, stats: Dictionary) -> String:
	if stats.is_empty():
		return "%s: 尚無輸入\n" % player_name
	
	var result = "%s 統計:\n" % player_name
	
	# 按照次數排序
	var sorted_actions = stats.keys()
	sorted_actions.sort_custom(func(a, b): return stats[a].count > stats[b].count)
	
	for action in sorted_actions:
		var count = stats[action].count
		var elapsed = Time.get_ticks_msec() / 1000.0 - stats[action].last_time
		result += "  • %s: %d次 (%.1fs前)\n" % [action, count, elapsed]
	
	return result

func _get_realtime_text(player_name: String, controller: PlayerController) -> String:
	if not controller or not controller.input_buffer:
		return "%s: No Buffer\n" % player_name
	
	var buffer = controller.input_buffer
	var active_inputs = buffer.get_active_buffers()
	
	if active_inputs.is_empty():
		return "%s: [空]\n" % player_name
	else:
		var result = "%s 即時:\n" % player_name
		for action in active_inputs:
			var age = buffer.get_buffer_age(action)
			result += "  • %s (%df)\n" % [action, age]
		return result
