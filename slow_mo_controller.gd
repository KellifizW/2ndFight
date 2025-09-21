extends Node

class_name SlowMoController

# 時間縮放參數
var normal_time_scale: float = 1.0
var slowmo_time_scale: float = 0.15  # 慢動作速度（30%正常速度）
var slowmo_enter_time: float = 0.3   # 進入慢動作的過渡時間（秒）
var slowmo_exit_time: float = 0.15   # 退出慢動作的過渡時間（秒）
var slowmo_active: bool = false      # 慢動作是否啟動

# Tween 用於平滑過渡
var tween: Tween

func _ready():
	# 初始化 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	# 確保初始時間縮放為正常
	Engine.time_scale = normal_time_scale
	print("Debug: SlowMoController initialized, time_scale set to %s" % normal_time_scale)

# 請求切換慢動作狀態
func request_slowmo_change():
	if slowmo_active:
		exit_slowmo_animation()
	else:
		enter_slowmo_animation()

# 進入慢動作的動畫
func enter_slowmo_animation():
	if tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(Engine, "time_scale", slowmo_time_scale, slowmo_enter_time)
	tween.tween_callback(_on_enter_slowmo_finished)
	print("Debug: Entering slow motion, transitioning to time_scale=%s over %s seconds" % [slowmo_time_scale, slowmo_enter_time])

# 退出慢動作的動畫
func exit_slowmo_animation():
	if tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(Engine, "time_scale", normal_time_scale, slowmo_exit_time)
	tween.tween_callback(_on_exit_slowmo_finished)
	print("Debug: Exiting slow motion, transitioning to time_scale=%s over %s seconds" % [normal_time_scale, slowmo_exit_time])

# 進入慢動作完成
func _on_enter_slowmo_finished():
	slowmo_active = true
	print("Debug: Slow motion activated, slowmo_active=%s" % slowmo_active)

# 退出慢動作完成
func _on_exit_slowmo_finished():
	slowmo_active = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	print("Debug: Slow motion deactivated, slowmo_active=%s, time_scale=%s" % [slowmo_active, Engine.time_scale])
