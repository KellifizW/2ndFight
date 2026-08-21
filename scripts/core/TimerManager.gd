# TimerManager.gd
class_name TimerManager extends Node

# 儲存所有計時器資料的結構
class TimerEntry:
	var timer_ref: RefCounted  # 使用 RefCounted 包裝 float，避免直接傳址問題
	var reset_callback: Callable
	var is_active: bool = false
	
	func _init(value: float, callback: Callable):
		timer_ref = RefCounted.new()
		timer_ref.value = value
		reset_callback = callback

# 內部字典：timer_name -> TimerEntry
var _timers: Dictionary = {}

# 註冊一個計時器
func register_timer(timer_name: String, initial_value: float, reset_callback: Callable) -> void:
	if _timers.has(timer_name):
		push_warning("TimerManager: Timer '%s' 已存在，將被覆蓋。" % timer_name)
	
	var entry = TimerEntry.new(initial_value, reset_callback)
	_timers[timer_name] = entry

# 開始計時（設定初始值並啟用）
func start_timer(timer_name: String, duration: float) -> void:
	if not _timers.has(timer_name):
		push_error("TimerManager: 嘗試啟動未註冊的計時器 '%s'" % timer_name)
		return
	var entry = _timers[timer_name]
	entry.timer_ref.value = duration
	entry.is_active = true

# 停止計時（歸零並禁用）
func stop_timer(timer_name: String) -> void:
	if not _timers.has(timer_name):
		return
	var entry = _timers[timer_name]
	entry.timer_ref.value = 0.0
	entry.is_active = false

# 取得目前計時值（只讀）
func get_time(timer_name: String) -> float:
	if not _timers.has(timer_name):
		return 0.0
	return _timers[timer_name].timer_ref.value

# 設定目前計時值（用於動態調整）
func set_time(timer_name: String, value: float) -> void:
	if not _timers.has(timer_name):
		return
	_timers[timer_name].timer_ref.value = max(0.0, value)
	_timers[timer_name].is_active = value > 0.0

# 檢查是否正在計時
func is_running(timer_name: String) -> bool:
	if not _timers.has(timer_name):
		return false
	return _timers[timer_name].is_active && _timers[timer_name].timer_ref.value > 0.0

# 每幀更新（必須在 _physics_process 中呼叫）
func process_timers(delta: float) -> void:
	for timer_name in _timers.keys():
		var entry = _timers[timer_name]
		if not entry.is_active:
			continue
		
		if entry.timer_ref.value > 0.0:
			entry.timer_ref.value -= delta
			if entry.timer_ref.value <= 0.0:
				entry.timer_ref.value = 0.0
				entry.is_active = false
				if entry.reset_callback.is_valid():
					entry.reset_callback.call()
				else:
					push_warning("TimerManager: Timer '%s' 的 reset_callback 無效" % timer_name)

# 清除所有計時器（用於重置玩家或場景）
func reset_all() -> void:
	for timer_name in _timers.keys():
		var entry = _timers[timer_name]
		entry.timer_ref.value = 0.0
		entry.is_active = false
	_timers.clear()

# 除錯：列印所有計時器狀態
func debug_print() -> void:
	Debug.log("=== TimerManager Debug ===")
	for timer_name in _timers.keys():
		var entry = _timers[timer_name]
		Debug.log("%s: %.3f (active: %s)" % [timer_name, entry.timer_ref.value, entry.is_active])
	Debug.log("==========================")
