# InputHistoryDisplay.gd
# Visual input history display inspired by Sakuga-Engine
# Shows the last N inputs with directional arrows and button presses

extends VBoxContainer

@export var max_history_elements: int = 10
@export var show_frame_count: bool = true
@export_enum("Player A", "Player B") var track_player: String = "Player A"

var history_elements: Array[InputHistoryElement] = []
var input_manager: InputManager = null
var player_to_track: Player = null

class InputHistoryElement:
	var container: HBoxContainer
	var direction_label: Label
	var buttons_label: Label
	var frames_label: Label
	
	func _init():
		container = HBoxContainer.new()
		container.add_theme_constant_override("separation", 4)  # 元素間距
		direction_label = Label.new()
		buttons_label = Label.new()
		frames_label = Label.new()
		
		frames_label.custom_minimum_size = Vector2(35, 20)  # 縮小寬度（兩位數 + 邊距）
		direction_label.custom_minimum_size = Vector2(40, 20)
		buttons_label.custom_minimum_size = Vector2(120, 20)  # 增加寬度以容納多按鈕 (如 "LP+LK+HP")
		
		# 增加字體大小以便可見
		frames_label.add_theme_font_size_override("font_size", 18)
		frames_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT  # 數字右對齊
		direction_label.add_theme_font_size_override("font_size", 20)
		buttons_label.add_theme_font_size_override("font_size", 20)
		
		# ⭐ 順序：幀數 → 方向 → 按鈕
		container.add_child(frames_label)
		container.add_child(direction_label)
		container.add_child(buttons_label)
	
	func set_input_data(raw_input: int, duration: int):
		# Parse direction
		var dir = raw_input >> 8
		var dir_text = ""
		match dir:
			1: dir_text = "↓"      # DOWN
			2: dir_text = "↘"      # DOWN_FORWARD
			3: dir_text = "→"      # FORWARD
			4: dir_text = "↙"      # DOWN_BACK
			5: dir_text = "←"      # BACK
			6: dir_text = "↑"      # UP
			7: dir_text = "↗"      # UP_FORWARD
			8: dir_text = "↖"      # UP_BACK
			_: dir_text = "○"      # NEUTRAL
		
		direction_label.text = dir_text
		
		# Parse buttons (支援多按鈕，使用位元遮罩)
		var buttons = raw_input & 0xFF
		var button_parts: Array[String] = []
		
		# 檢查每個按鈕位元（按優先級順序）
		if buttons & 1:    # ST_LP (1 << 0)
			button_parts.append("LP")
		if buttons & 2:    # ST_MP (1 << 1)
			button_parts.append("MP")
		if buttons & 4:    # ST_HP (1 << 2)
			button_parts.append("HP")
		if buttons & 8:    # ST_LK (1 << 3)
			button_parts.append("LK")
		if buttons & 16:   # ST_MK (1 << 4)
			button_parts.append("MK")
		if buttons & 32:   # ST_HK (1 << 5)
			button_parts.append("HK")
		
		# 組合按鈕文字（用 + 連接，例如 "LP+LK"）
		if button_parts.size() > 0:
			buttons_label.text = "+".join(button_parts)
		else:
			buttons_label.text = "-"
		
		# 設置幀數（⭐ 最多顯示 99，只顯示數字）
		var display_duration = min(duration, 99)
		frames_label.text = str(display_duration)
	
	func clear():
		direction_label.text = ""
		buttons_label.text = ""
		frames_label.text = ""

func _ready():
	# Create history elements
	for i in max_history_elements:
		var element = InputHistoryElement.new()
		add_child(element.container)
		history_elements.append(element)
	
	# 自動查找玩家（延遲到下一幀，確保玩家已生成）
	call_deferred("_find_player")

func _find_player():
	"""自動查找並連接玩家"""
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		Debug.log("[InputHistoryDisplay] 警告：找不到 world 節點")
		return
	
	# 根據設置的 track_player 屬性選擇玩家
	if track_player == "Player A":
		player_to_track = world.player_a
	else:
		player_to_track = world.player_b
	
	if player_to_track:
		input_manager = player_to_track.get_node_or_null("InputManager")
		if input_manager:
			Debug.log("[InputHistoryDisplay] 成功連接到 " + player_to_track.name + " 的 InputManager")
		else:
			Debug.log("[InputHistoryDisplay] 警告：玩家 " + player_to_track.name + " 沒有 InputManager")
	else:
		Debug.log("[InputHistoryDisplay] 警告：找不到玩家")

func _physics_process(_delta: float):
	if not input_manager or not player_to_track:
		return
	
	# Update display from input history
	update_history_display()

func update_history_display():
	if not input_manager:
		return
		
	var current = input_manager.current_history
	
	# Show most recent input first
	history_elements[0].set_input_data(
		input_manager.input_history[current].raw_input,
		input_manager.input_history[current].duration
	)
	
	# Show older inputs
	var displayed = 1
	for i in range(max_history_elements - 1):
		var history_index = (current - i - 1 + input_manager.INPUT_HISTORY_SIZE) % input_manager.INPUT_HISTORY_SIZE
		var registry = input_manager.input_history[history_index]
		
		# Only show if there's actual input data
		if registry.duration > 0:
			history_elements[displayed].container.visible = true
			history_elements[displayed].set_input_data(registry.raw_input, registry.duration)
			displayed += 1
			if displayed >= max_history_elements:
				break
		else:
			break
	
	# Hide unused elements
	for i in range(displayed, max_history_elements):
		history_elements[i].container.visible = false

func set_player(player: Player):
	"""手動設置要追蹤的玩家（可選）"""
	player_to_track = player
	if player:
		input_manager = player.get_node_or_null("InputManager")

func clear():
	pass  # 不清除輸入歷史
