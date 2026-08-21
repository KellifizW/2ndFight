# InputHistoryDebugger.gd
# 用於診斷輸入歷史顯示異常清除的問題
extends Node

@export var enabled: bool = true
@export var check_interval_frames: int = 30

var last_check_frame: int = 0
var p1_display: Node = null
var p2_display: Node = null

func _ready():
	call_deferred("_find_displays")

func _find_displays():
	"""尋找輸入歷史顯示節點"""
	var root = get_tree().root
	p1_display = root.find_child("P1InputHistory", true, false)
	p2_display = root.find_child("P2InputHistory", true, false)
	
	if p1_display:
		Debug.log("[InputHistoryDebugger] ✅ Found P1InputHistory")
	else:
		Debug.log("[InputHistoryDebugger] ❌ P1InputHistory not found - may be named differently")
	
	if p2_display:
		Debug.log("[InputHistoryDebugger] ✅ Found P2InputHistory")

func _physics_process(_delta: float):
	if not enabled:
		return
	
	var frame = Engine.get_physics_frames()
	if frame - last_check_frame < check_interval_frames:
		return
	
	last_check_frame = frame
	_check_displays()

func _check_displays():
	"""檢查並報告輸入歷史顯示狀態"""
	var separator = "="
	for i in range(70):
		separator += "="
	
	Debug.log("\n" + separator)
	var frame = Engine.get_physics_frames()
	Debug.log("[InputHistoryDebugger] Status Check @ Frame " + str(frame))
	Debug.log(separator)
	
	_check_single_display("P1", p1_display)
	_check_single_display("P2", p2_display)
	
	Debug.log(separator + "\n")

func _check_single_display(label: String, display: Node):
	"""檢查單個顯示節點的狀態"""
	if not display:
		Debug.log("[" + label + "] ⚠️ Display node not found")
		return
	
	# 檢查history_elements陣列
	if not "history_elements" in display:
		Debug.log("[" + label + "] ⚠️ No history_elements array")
		return
	
	var history_elements = display.history_elements
	var visible_count = 0
	var total_elements = history_elements.size()
	
	for element in history_elements:
		if element and "container" in element and element.container.visible:
			visible_count += 1
	
	# 檢查input_manager
	var input_manager = display.input_manager
	var input_history_size = 0
	var non_zero_inputs = 0
	
	if input_manager and "input_history" in input_manager:
		input_history_size = input_manager.input_history.size()
		for registry in input_manager.input_history:
			if registry.duration > 0:
				non_zero_inputs += 1
	
	# 檢查input_durations（如果存在）
	var durations_set = 0
	if "input_durations" in display:
		var input_durations = display.input_durations
		for i in range(input_durations.size()):
			if input_durations[i] > 0:
				durations_set += 1
	
	Debug.log("[" + label + "] Display Elements: " + str(visible_count) + "/" + str(total_elements) + " visible")
	Debug.log("     InputManager history: " + str(non_zero_inputs) + "/" + str(input_history_size) + " non-zero")
	if durations_set > 0:
		Debug.log("     input_durations set: " + str(durations_set) + " entries")
	
	# 檢查player_to_track
	if "player_to_track" in display and display.player_to_track:
		Debug.log("     Tracking: " + display.player_to_track.name)
	
	# 如果顯示數量為0，這表示問題
	if visible_count == 0 and non_zero_inputs > 0:
		Debug.log("     🔴 [PROBLEM] No visible elements but input history has data!")
		if durations_set == 0:
			Debug.log("            → input_durations array likely cleared or not populated")
