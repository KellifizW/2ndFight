extends Control

@export var total_time: int = 99  # 總倒數秒數（從99開始）
var last_tens: int = -1           # 用來偵測十位數變化

@onready var label: RichTextLabel = $CountdownLabel
@onready var timer: Timer = $CountdownTimer

signal countdown_finished  # 倒數結束訊號（供其他系統使用）

var remaining_time: int = total_time

func _ready() -> void:
	update_display()
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

func _on_timer_timeout() -> void:
	remaining_time -= 1
	
	if remaining_time < 0:
		remaining_time = 0
		timer.stop()
		countdown_finished.emit()  # 發送訊號給其他節點（如勝負判定）
	
	update_display()

func update_display() -> void:
	# 特殊處理：時間到底（00）時完全靜止顯示金黃色 00
	if remaining_time == 0:
		label.text = "[center][color=#ffd700]00[/color][/center]"
		return
	
	var tens_digit: int = remaining_time / 10
	var ones_digit: int = remaining_time % 10
	
	# 十位數變化偵測（第一次視為變化）
	var tens_changed: bool = (last_tens == -1) or (tens_digit != last_tens)
	last_tens = tens_digit
	
	var ones_part: String = ""
	var tens_part: String = ""
	
	if remaining_time <= 10:
		# 最後10秒（1~10）：金黃色強烈跳動
		ones_part = "[pulse color=#ffd700 freq=3.0 min=0.7 max=1.0][shake rate=25 level=15][wave amp=40 freq=10]%d[/wave][/shake][/pulse]" % ones_digit
		
		if tens_changed:
			tens_part = "[pulse color=#ffd700 freq=4.0 min=0.7 max=1.0][shake rate=30 level=18]%d[/shake][/pulse]" % tens_digit
		else:
			tens_part = "[color=#ffd700]%d[/color]" % tens_digit
			
	else:
		# 11秒以上：橙紅↔白色脈動
		ones_part = "[pulse color=#ff6200 freq=2.0 min=0.5 max=1.0][shake rate=15 level=8][wave amp=50 freq=5]%d[/wave][/shake][/pulse]" % ones_digit
		
		if tens_changed:
			tens_part = "[pulse color=#ff6200 freq=3.0 min=0.5 max=1.0][shake rate=20 level=12]%d[/shake][/pulse]" % tens_digit
		else:
			tens_part = "[color=#ff6200]%d[/color]" % tens_digit
	
	# 永遠顯示兩位數
	var bbcode: String = "[center]" + tens_part + ones_part + "[/center]"
	label.text = bbcode
