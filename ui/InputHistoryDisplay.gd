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
		direction_label = Label.new()
		buttons_label = Label.new()
		frames_label = Label.new()
		
		direction_label.custom_minimum_size = Vector2(60, 20)
		buttons_label.custom_minimum_size = Vector2(80, 20)
		frames_label.custom_minimum_size = Vector2(40, 20)
		
		# 增加字體大小以便可見
		direction_label.add_theme_font_size_override("font_size", 16)
		buttons_label.add_theme_font_size_override("font_size", 16)
		frames_label.add_theme_font_size_override("font_size", 16)
		
		container.add_child(direction_label)
		container.add_child(buttons_label)
		container.add_child(frames_label)
	
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
			_: dir_text = "○"      # NEUTRAL
		
		direction_label.text = dir_text
		
		# Parse buttons
		var buttons = raw_input & 0xFF
		var button_text = ""
		if buttons == 1: button_text = "LP"
		elif buttons == 2: button_text = "MP"
		elif buttons == 3: button_text = "HP"
		elif buttons == 4: button_text = "LK"
		elif buttons == 5: button_text = "MK"
		elif buttons == 6: button_text = "HK"
		else: button_text = "-"
		
		buttons_label.text = button_text
		frames_label.text = str(duration) + "f"
	
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
		print("[InputHistoryDisplay] 警告：找不到 world 節點")
		return
	
	# 根據設置的 track_player 屬性選擇玩家
	if track_player == "Player A":
		player_to_track = world.player_a
	else:
		player_to_track = world.player_b
	
	if player_to_track:
		input_manager = player_to_track.get_node_or_null("InputManager")
		if input_manager:
			print("[InputHistoryDisplay] 成功連接到 %s 的 InputManager" % player_to_track.name)
		else:
			print("[InputHistoryDisplay] 警告：玩家 %s 沒有 InputManager" % player_to_track.name)
	else:
		print("[InputHistoryDisplay] 警告：找不到玩家")

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
	for element in history_elements:
		element.clear()
		element.container.visible = false
