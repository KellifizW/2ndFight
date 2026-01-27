extends Node

class_name SlowMoController

signal time_scale_changed(new_time_scale: float)

# 時間縮放參數
var normal_time_scale: float = 1
var slowmo_time_scale: float = 0.2
var hit_slowmo_time_scale: float = 0.02  
var slowmo_enter_time: float = 0.4   
var slowmo_exit_time: float = 0.4   
var slowmo_active: bool = false      
var hit_slowmo_time: float = 0.1333    # 擊中慢動作的持續時間（秒，真實時間）
var hit_slowmo_exit_time: float = 0  # 擊中慢動作的退出過渡時間（秒，真實時間）
var is_hit_slowmo: bool = false     # 標記是否處於擊中慢動作狀態

# Tween 用於平滑過渡
var tween: Tween

# 除錯：記錄擊中慢動作開始的真實時間（毫秒）
var hit_start_time: int = 0

func _ready():
	# 設置 process_mode 為始終運行
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 確保初始時間縮放為正常
	Engine.time_scale = normal_time_scale
	emit_signal("time_scale_changed", normal_time_scale)
	print("Debug: SlowMoController initialized, time_scale set to %s, process_mode set to ALWAYS" % normal_time_scale)

func _process(_delta):
	pass

# 請求切換慢動作狀態（手動切換）
func request_slowmo_change():
	if slowmo_active:
		exit_slowmo_animation()
	else:
		enter_slowmo_animation()

# 請求擊中慢動作效果
func request_hit_freeze():
	if slowmo_active or is_hit_slowmo:
		print("Debug: Hit slowmo request ignored (slowmo_active=%s, is_hit_slowmo=%s)" % [slowmo_active, is_hit_slowmo])
		return  # 避免重複觸發
	is_hit_slowmo = true
	if tween and tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_ignore_time_scale(true)  # 使用真實時間計時
	# 立即進入擊中慢動作
	Engine.time_scale = hit_slowmo_time_scale
	emit_signal("time_scale_changed", hit_slowmo_time_scale)
	# 除錯：記錄開始真實時間
	hit_start_time = Time.get_ticks_msec()
	# 持續慢動作 0.09 秒（真實時間）
	tween.tween_interval(hit_slowmo_time)
	# 退出慢動作（0.01秒，真實時間）
	tween.tween_property(Engine, "time_scale", normal_time_scale, hit_slowmo_exit_time)
	tween.tween_callback(_on_hit_slowmo_finished)
	print("Debug: Hit slowmo triggered, set time_scale=%s instantly, sustaining for %s seconds, then transitioning to %s over %s seconds (real time)" % [hit_slowmo_time_scale, hit_slowmo_time, normal_time_scale, hit_slowmo_exit_time])

# 進入慢動作的動畫（手動切換）
func enter_slowmo_animation():
	if tween and tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(Engine, "time_scale", slowmo_time_scale, slowmo_enter_time)
	tween.tween_callback(_on_enter_slowmo_finished)
	emit_signal("time_scale_changed", slowmo_time_scale)
	print("Debug: Entering slow motion, transitioning to time_scale=%s over %s seconds" % [slowmo_time_scale, slowmo_enter_time])

# 退出慢動作的動畫（手動切換）
func exit_slowmo_animation():
	if tween and tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(Engine, "time_scale", normal_time_scale, slowmo_exit_time)
	tween.tween_callback(_on_exit_slowmo_finished)
	emit_signal("time_scale_changed", normal_time_scale)
	print("Debug: Exiting slow motion, transitioning to time_scale=%s over %s seconds" % [normal_time_scale, slowmo_exit_time])

# 進入慢動作完成
func _on_enter_slowmo_finished():
	slowmo_active = true
	print("Debug: Slow motion activated, slowmo_active=%s" % slowmo_active)

# 退出慢動作完成
func _on_exit_slowmo_finished():
	slowmo_active = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)
	print("Debug: Slow motion deactivated, slowmo_active=%s, time_scale=%s" % [slowmo_active, Engine.time_scale])

# 擊中慢動作完成
func _on_hit_slowmo_finished():
	is_hit_slowmo = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)
	# 除錯：計算並打印真實持續時間（秒）
	var duration_sec = (Time.get_ticks_msec() - hit_start_time) / 1000.0
	print("Debug: Hit slowmo duration: %s seconds" % duration_sec)
	print("Debug: Hit slowmo finished, is_hit_slowmo=%s, time_scale=%s" % [is_hit_slowmo, Engine.time_scale])
