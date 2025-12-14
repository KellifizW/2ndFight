extends Control

@export var total_time: int = 99  # 總倒數秒數（從99開始）
@onready var label: RichTextLabel = $CountdownLabel
@onready var timer: Timer = $CountdownTimer

signal countdown_finished  # 倒數結束訊號

var remaining_time: int = total_time

func _ready() -> void:
	update_display()
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

func _on_timer_timeout() -> void:
	remaining_time -= 1
	update_display()
	
	if remaining_time <= 0:
		timer.stop()
		label.text = "[center][shake rate=20 level=15][rainbow freq=1 sat=1 val=1]TIME UP![/rainbow][/shake][/center]"
		await get_tree().create_timer(2.0).timeout  # 顯示2秒結束訊息
		visible = false
		countdown_finished.emit()

func update_display() -> void:
	# BBCode特效：剩餘30秒內閃爍紅色警告，否則正常波浪
	var bbcode: String
	if remaining_time <= 30:
		bbcode = "[center][wave amp=30 freq=4][color=#ff4444][shake rate=15 level=10]%d[/shake][/color][/wave][/center]" % remaining_time
	else:
		bbcode = "[center][wave amp=50 freq=5][rainbow freq=0.5 sat=1 val=1]%d[/rainbow][/wave][/center]" % remaining_time
	
	label.text = bbcode
