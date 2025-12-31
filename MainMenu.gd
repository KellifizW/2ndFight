# MainMenu.gd（修正版）
extends Control

@onready var start_button: Button = $VBoxContainer/Button
@onready var options_button: Button = $VBoxContainer/Button2
@onready var exit_button: Button = $VBoxContainer/Button3

# 目前選中的按鈕索引（0=Start, 1=Options, 2=Exit）
var current_selection: int = 0
const BUTTON_COUNT: int = 3

# 高亮顏色
const NORMAL_COLOR: Color = Color(1, 1, 1, 1)
const SELECTED_COLOR: Color = Color(1, 1, 0.5, 1)  # 淡黃色表示選中

func _ready() -> void:
	# 預設選中 Start 並更新高亮
	_update_highlight()

func _process(_delta: float) -> void:
	# 上／下移動（P1 或 P2 的跳躍/蹲下鍵皆可操作）
	var up_pressed: bool = Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("jump_p2")
	var down_pressed: bool = Input.is_action_just_pressed("crouch") or Input.is_action_just_pressed("crouch_p2")
	
	if up_pressed:
		current_selection = (current_selection - 1 + BUTTON_COUNT) % BUTTON_COUNT
		_update_highlight()
	
	if down_pressed:
		current_selection = (current_selection + 1) % BUTTON_COUNT
		_update_highlight()
	
	# 用「踢攻擊」作為確認鍵（P1 或 P2 任一按下都算）
	var confirm_pressed: bool = (
		Input.is_action_just_pressed("st_mk") or 
		Input.is_action_just_pressed("st_mk_p2")
	)
	
	if confirm_pressed:
		_on_button_confirmed(current_selection)

func _update_highlight() -> void:
	# 先恢復所有按鈕顏色
	start_button.modulate = NORMAL_COLOR
	options_button.modulate = NORMAL_COLOR
	exit_button.modulate = NORMAL_COLOR
	
	# 再把選中的變成淡黃色
	match current_selection:
		0: start_button.modulate = SELECTED_COLOR
		1: options_button.modulate = SELECTED_COLOR
		2: exit_button.modulate = SELECTED_COLOR

func _on_button_confirmed(index: int) -> void:
	match index:
		0:  # Start
			print("進入角色選擇畫面")
			get_tree().change_scene_to_file("res://ui/CharacterSelect.tscn")
		1:  # Options
			pass  # 暫時無功能
		2:  # Exit
			print("結束遊戲")
			get_tree().quit()
