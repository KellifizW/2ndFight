# InputHistoryDisplayIcon.gd
# 使用圖標替代文字的輸入歷史顯示
# 使用 arrow.png, punch.png, kick.png 來視覺化輸入

extends VBoxContainer

@export var startup_logs: bool = true  # 改為 true 以開啟調試日誌
@export var debug_history_updates: bool = true  # 調試顯示更新

@export var max_history_elements: int = 15
@export var show_frame_count: bool = true
@export_enum("Player A", "Player B") var track_player: String = "Player A"

# 圖標資源路徑
const ARROW_PATH = "res://assets/ui/cmdbttn/arrow.png"
const CIRCLE_PATH = "res://assets/ui/cmdbttn/circle.png"
const PUNCH_PATH = "res://assets/ui/cmdbttn/punch.png"
const KICK_PATH = "res://assets/ui/cmdbttn/kick.png"

var history_elements: Array[InputHistoryElement] = []
var input_manager: InputManager = null
var player_to_track: Player = null
var node_identity: String = ""  # 用於識別這個實例

# 預加載圖標
var arrow_texture: Texture2D
var circle_texture: Texture2D
var punch_texture: Texture2D
var kick_texture: Texture2D

# 真實世界時間追蹤（每60幀=1秒）
var input_start_times: Array[float] = []     # 記錄每個輸入的開始時間
var input_durations: Array[int] = []         # 記錄每個輸入的固定持續幀數（60 FPS）
var real_time_accumulated: float = 0.0       # 累積的真實時間（不受 time_scale 影響）
var last_current_history: int = -1           # 追蹤上一幀的 current_history
var last_input_durations_count: int = -1     # 追蹤上一幀的輸入計數

# 顏色定義（基於用戶測試結果）
const COLOR_LIGHT = Color(30.0/255.0 * 3.0, 100.0/255.0 * 3.0, 1.0 * 3.0)    # 藍色 (LP, LK) - RGB(30,100,255) I:3.0
const COLOR_MEDIUM = Color(1.0, 1.0, 1.0)                                      # 黃色 (MP, MK) - 不 modulate (圖標本身是黃色)
const COLOR_HEAVY = Color(1.0, 80.0/255.0, 160.0/255.0)                        # 紅色 (HP, HK) - RGB(255,80,160) I:1.0

class InputHistoryElement:
	var container: HBoxContainer
	var direction_icon: TextureRect
	var button_container: HBoxContainer  # 容納多個按鈕圖標
	var frames_label: Label
	var arrow_tex: Texture2D  # 保存箭頭紋理引用
	
	func _init(arrow_texture: Texture2D, circle_tex: Texture2D, punch_tex: Texture2D, kick_tex: Texture2D):
		arrow_tex = arrow_texture  # 保存引用
		container = HBoxContainer.new()
		container.custom_minimum_size = Vector2(220, 32)
		container.alignment = BoxContainer.ALIGNMENT_BEGIN
		container.add_theme_constant_override("separation", 2)  # 緊湊排列，元素間距為 2px
		
		# 幀數標籤（⭐ 改為最前面顯示）
		frames_label = Label.new()
		frames_label.custom_minimum_size = Vector2(28, 20)  # 縮小寬度（兩位數 + 少量邊距）
		frames_label.add_theme_font_size_override("font_size", 16)
		frames_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frames_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT  # 右對齊數字
		
		# 方向圖標
		direction_icon = TextureRect.new()
		direction_icon.texture = arrow_texture
		direction_icon.custom_minimum_size = Vector2(32, 32)
		direction_icon.size = Vector2(32, 32)
		direction_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		direction_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# ⭐ 關鍵修復：設置旋轉中心點為圖標中心，防止旋轉時位移
		direction_icon.pivot_offset = Vector2(16, 16)  # 32x32 圖標的中心點
		
		# 按鈕容器（可容納多個按鈕圖標）
		button_container = HBoxContainer.new()
		button_container.custom_minimum_size = Vector2(140, 32)
		button_container.add_theme_constant_override("separation", 4)  # 按鈕間距
		
		# ⭐ 順序：幀數 → 方向 → 按鈕
		container.add_child(frames_label)
		container.add_child(direction_icon)
		container.add_child(button_container)
	
	func set_input_data(raw_input: int, duration: int, circle_tex: Texture2D, punch_tex: Texture2D, kick_tex: Texture2D):
		# 解析方向
		var dir = raw_input >> 8
		_set_direction(dir, circle_tex)
		
		# 解析按鈕（支援多按鈕）
		var buttons = raw_input & 0xFF
		_set_buttons(buttons, punch_tex, kick_tex)
		
		# 設置幀數（⭐ 最多顯示 99，只顯示數字）
		var display_duration = min(duration, 99)
		frames_label.text = str(display_duration)
	
	func _set_direction(dir: int, circle_tex: Texture2D):
		"""設置方向圖標的旋轉角度"""
		direction_icon.visible = true
		direction_icon.rotation_degrees = 0  # 先重置旋轉
		
		match dir:
			0:  # NEUTRAL - 顯示圓圈
				direction_icon.texture = circle_tex
			1:  # DOWN
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = 90
			2:  # DOWN_FORWARD
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = 45
			3:  # FORWARD
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = 0
			4:  # DOWN_BACK
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = 135
			5:  # BACK
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = 180
			6:  # UP (新增)
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = -90
			7:  # UP_FORWARD (新增)
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = -45
			8:  # UP_BACK (新增)
				direction_icon.texture = arrow_tex
				direction_icon.rotation_degrees = -135
	
	func _set_buttons(buttons: int, punch_tex: Texture2D, kick_tex: Texture2D):
		"""設置按鈕圖標（支援多按鈕同時顯示）"""
		# 清除舊的按鈕圖標
		for child in button_container.get_children():
			child.queue_free()
		
		# 按優先級順序添加按鈕圖標
		if buttons & 1:    # LP (輕拳)
			_add_button_icon(punch_tex, COLOR_LIGHT)
		if buttons & 2:    # MP (中拳)
			_add_button_icon(punch_tex, COLOR_MEDIUM)
		if buttons & 4:    # HP (重拳)
			_add_button_icon(punch_tex, COLOR_HEAVY)
		if buttons & 8:    # LK (輕腳)
			_add_button_icon(kick_tex, COLOR_LIGHT)
		if buttons & 16:   # MK (中腳)
			_add_button_icon(kick_tex, COLOR_MEDIUM)
		if buttons & 32:   # HK (重腳)
			_add_button_icon(kick_tex, COLOR_HEAVY)
	
	func _add_button_icon(texture: Texture2D, color: Color):
		"""添加單個按鈕圖標"""
		var icon = TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = color
		button_container.add_child(icon)
	
	func clear():
		direction_icon.visible = false
		for child in button_container.get_children():
			child.queue_free()
		frames_label.text = ""

func _ready():
	node_identity = "[" + name + "]"  # 記錄這個實例的名稱
	
	if startup_logs:
		print(node_identity + " _ready() 被調用 | track_player=" + track_player)
	
	# 加載圖標
	arrow_texture = load(ARROW_PATH)
	circle_texture = load(CIRCLE_PATH)
	punch_texture = load(PUNCH_PATH)
	kick_texture = load(KICK_PATH)
	
	if not arrow_texture or not circle_texture or not punch_texture or not kick_texture:
		push_error(node_identity + " 錯誤：無法加載圖標資源")
		push_error("  arrow: " + str(arrow_texture != null) + ", circle: " + str(circle_texture != null) + ", punch: " + str(punch_texture != null) + ", kick: " + str(kick_texture != null))
		return
	
	# 創建歷史元素
	for i in max_history_elements:
		var element = InputHistoryElement.new(arrow_texture, circle_texture, punch_texture, kick_texture)
		add_child(element.container)
		history_elements.append(element)
	
	# 初始化時間追蹤陣列
	input_start_times.resize(240)  # 與 INPUT_HISTORY_SIZE 一致
	input_durations.resize(240)
	for i in 240:
		input_start_times[i] = 0.0
		input_durations[i] = 0
	
	if startup_logs:
		print(node_identity + " 初始化完成 | input_durations.size()=" + str(input_durations.size()))
	
	last_input_durations_count = 0
	
	# 自動查找玩家
	call_deferred("_find_player")

func _find_player():
	"""自動查找並連接玩家"""
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print(node_identity + " 警告：找不到 world 節點")
		return
	
	# 根據設置的 track_player 屬性選擇玩家
	if track_player == "Player A":
		player_to_track = world.player_a
	else:
		player_to_track = world.player_b
	
	if player_to_track:
		input_manager = player_to_track.get_node_or_null("InputManager")
		if input_manager:
			if startup_logs:
				var im_id = "0x" + str(input_manager.get_instance_id()).to_lower() # 實例 ID
				print(node_identity + " 成功連接到 " + player_to_track.name + " 的 InputManager (ID:" + im_id + ")")
		else:
			print(node_identity + " 警告：玩家 " + player_to_track.name + " 沒有 InputManager")
	else:
		print(node_identity + " 警告：找不到玩家")

func _process(delta: float):
	if not input_manager or not player_to_track:
		return
	
	# 累積真實世界時間（不受 Engine.time_scale 影響）
	real_time_accumulated += delta
	
	var current = input_manager.current_history
	
	# 檢測輸入是否改變（新輸入開始）
	if last_current_history != current:
		# 輸入改變了 - 固定上一個輸入的持續時間
		if last_current_history >= 0:
			var duration_seconds = real_time_accumulated - input_start_times[last_current_history]
			input_durations[last_current_history] = int(duration_seconds * 60.0)  # 轉為60 FPS幀數
			
			if debug_history_updates:
				print("[InputHistoryDisplayIcon] Input changed | last_idx=" + str(last_current_history) + " -> current=" + str(current) + " | last_duration=" + str(duration_seconds) + "s (" + str(input_durations[last_current_history]) + " frames)")
		
		# 記錄新輸入的開始時間
		input_start_times[current] = real_time_accumulated
		input_durations[current] = 0  # 重置當前輸入的持續時間
		last_current_history = current
	
	# 🔍 每隔60幀檢查input_durations陣列是否發生異常（已停用此陣列用於顯示，現在只用於調試）
	if debug_history_updates and Engine.get_physics_frames() % 60 == 0:
		var durations_sum = 0
		var durations_set = 0
		for i in range(input_manager.INPUT_HISTORY_SIZE):
			if input_durations[i] > 0:
				durations_set += 1
				durations_sum += input_durations[i]
		
		# 檢測異常清除
		if durations_set == 0 and last_input_durations_count > 3:
			print(node_identity + " ⚠️ 舊追蹤陣列異常：input_durations 從 " + str(last_input_durations_count) + " 降至 0（已不影響顯示）")
		
		last_input_durations_count = durations_set
		print(node_identity + " [調試] input_durations舊數組狀態: " + str(durations_set) + "/" + str(input_manager.INPUT_HISTORY_SIZE) + " entries (已棄用於顯示)")
	
	# 更新顯示
	update_history_display()

func update_history_display():
	if not input_manager:
		return
		
	var current = input_manager.current_history
	
	# 🔍 調試：檢查輸入歷史大小和內容
	var non_zero_count = 0
	for registry in input_manager.input_history:
		if registry.duration > 0:
			non_zero_count += 1
	
	if debug_history_updates and Engine.get_physics_frames() % 30 == 0:  # 每30幀打印一次
		var visible_count = 0
		for el in history_elements:
			if el and "container" in el and el.container.visible:
				visible_count += 1
		print(node_identity + " Update | current_idx=" + str(current) + " | non_zero_inputs=" + str(non_zero_count) + "/" + str(input_manager.INPUT_HISTORY_SIZE) + " | displayed=" + str(visible_count))
	
	# 顯示最新輸入在最上方（當前正在進行的輸入，實時計算）
	var current_duration_seconds = real_time_accumulated - input_start_times[current]
	var current_frames = int(current_duration_seconds * 60.0)  # 60 FPS
	history_elements[0].set_input_data(
		input_manager.input_history[current].raw_input,
		current_frames,
		circle_texture,
		punch_texture,
		kick_texture
	)
	# 【重要】第一個元素必須永遠可見
	history_elements[0].container.visible = true
	
	# 顯示舊輸入（使用 InputManager 的 duration 直接）
	var displayed = 1
	for i in range(max_history_elements - 1):
		var history_index = (current - i - 1 + input_manager.INPUT_HISTORY_SIZE) % input_manager.INPUT_HISTORY_SIZE
		var registry = input_manager.input_history[history_index]
		
		# 只檢查 InputManager 的 registry.duration - 這是權威的輸入記錄
		# 不再依賴 input_durations 數組（它會因為循環緩衝區而失效）
		if registry.duration > 0:
			history_elements[displayed].container.visible = true
			
			# 使用 InputManager 的 duration 直接（在 120 FPS 物理幀中）
			# 轉換為 60 FPS 顯示幀數以匹配動畫設計
			var display_duration = int(registry.duration / 2.0)  # 120 FPS → 60 FPS
			
			history_elements[displayed].set_input_data(
				registry.raw_input, 
				display_duration,
				circle_texture,
				punch_texture,
				kick_texture
			)
			displayed += 1
			if displayed >= max_history_elements:
				break
		else:
			break
	
	# 隱藏未使用的元素
	for i in range(displayed, max_history_elements):
		history_elements[i].container.visible = false

func clear():
	"""已禁用：不清除輸入歷史，確保歷史記錄永遠保留"""
	# 🔴 打印堆棧跟蹤，查看誰在調用此方法
	var separator = ""
	for i in range(60):
		separator += "="
	
	print("\n" + separator)
	print("[☠️ CLEAR() CALLED - BUG FOUND! ☠️]")
	print("=== 調用堆棧跟蹤 ===")
	print_stack()
	print("[track_player] " + track_player)
	var track_name: String = str(player_to_track.name) if player_to_track else "null"
	print("[player_to_track] " + track_name)
	var visible_count_clear = 0
	for el in history_elements:
		if el and "container" in el and el.container.visible:
			visible_count_clear += 1
	print("[current displayed elements] " + str(visible_count_clear))
	print(separator + "\n")
	pass  # 空操作 - 任何調用此方法的代碼都不會清除輸入歷史
