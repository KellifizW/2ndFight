# CharacterSelect.gd - SFIV 鍵盤游標版（P1/P2 獨立控制 + 自動跳轉）
extends Control

@export var dav_resource: CharacterData = preload("res://characters/DAV.character.tres")
@export var woo_resource: CharacterData = preload("res://characters/WOO.character.tres")
@export var den_resource: CharacterData = preload("res://characters/DEN.character.tres")

var characters: Array[CharacterData] = []
var p1_selected: int = 0
var p2_selected: int = 2
var p1_ready: bool = false
var p2_ready: bool = false

@onready var ready_label: Label = $MainMargin/MainHBox/CenterSection/ReadyLabel
@onready var p1_large: TextureRect = $MainMargin/MainHBox/P1Side/P1LargePreview
@onready var p1_name: Label = $MainMargin/MainHBox/P1Side/P1Name
@onready var p2_large: TextureRect = $MainMargin/MainHBox/P2Side/P2LargePreview
@onready var p2_name: Label = $MainMargin/MainHBox/P2Side/P2Name

var grid_buttons: Array[TextureButton] = []

func _ready() -> void:
	print("=== CharacterSelect _ready() 開始執行 ===")
	
	characters = [dav_resource, woo_resource, den_resource]
	
	# 抓取並設定格子
	var grid_container = $MainMargin/MainHBox/CenterSection/GridContainer
	grid_buttons = [
		grid_container.get_node("Btn0") as TextureButton,
		grid_container.get_node("Btn1") as TextureButton,
		grid_container.get_node("Btn2") as TextureButton
	]
	
	# 設定小頭像
	for i in characters.size():
		grid_buttons[i].texture_normal = characters[i].portrait
	
	# 連接滑鼠點擊（備用）
	for i in grid_buttons.size():
		grid_buttons[i].pressed.connect(func(): _on_grid_pressed(i))
	
	# 初始化 UI
	_update_ui()
	print("=== CharacterSelect 初始化完成 ===")

func _process(_delta: float) -> void:
	# P1 左右移動游標
	if Input.is_action_just_pressed("move_left"):
		p1_selected = (p1_selected - 1 + 3) % 3
		SelectedCharacters.p1_character = characters[p1_selected]
		_update_ui()
	if Input.is_action_just_pressed("move_right"):
		p1_selected = (p1_selected + 1) % 3
		SelectedCharacters.p1_character = characters[p1_selected]
		_update_ui()
	
	# P2 左右移動游標
	if Input.is_action_just_pressed("move_left_p2"):
		p2_selected = (p2_selected - 1 + 3) % 3
		SelectedCharacters.p2_character = characters[p2_selected]
		_update_ui()
	if Input.is_action_just_pressed("move_right_p2"):
		p2_selected = (p2_selected + 1) % 3
		SelectedCharacters.p2_character = characters[p2_selected]
		_update_ui()
	
	# P1 確認（踢攻擊）
	if Input.is_action_just_pressed("st_mk"):
		p1_ready = true
		_update_ui()
	
	# P2 確認（踢攻擊）
	if Input.is_action_just_pressed("st_mk_p2"):
		p2_ready = true
		_update_ui()

# 滑鼠點擊備用（點擊先算 P1，再算 P2）
func _on_grid_pressed(index: int) -> void:
	print("滑鼠點擊格子: ", index)
	if not p1_ready:
		p1_selected = index
		SelectedCharacters.p1_character = characters[p1_selected]
	elif not p2_ready:
		p2_selected = index
		SelectedCharacters.p2_character = characters[p2_selected]
	_update_ui()

func _update_ui() -> void:
	_update_previews()
	_update_highlights()
	_check_ready()

func _update_previews() -> void:
	# P1 預覽
	var p1_data = characters[p1_selected]
	if p1_large:
		p1_large.texture = p1_data.large_portrait
	if p1_name:
		p1_name.text = p1_data.display_name
	
	# P2 預覽
	var p2_data = characters[p2_selected]
	if p2_large:
		p2_large.texture = p2_data.large_portrait
	if p2_name:
		p2_name.text = p2_data.display_name

func _update_highlights() -> void:
	for i in grid_buttons.size():
		var btn = grid_buttons[i]
		btn.modulate = Color.WHITE
		
		if i == p1_selected:
			btn.modulate = Color.GREEN if p1_ready else Color(1, 1, 0.5)  # 綠=Ready, 黃=選擇中
		if i == p2_selected:
			btn.modulate = Color.PURPLE if p2_ready else Color(0.5, 0.8, 1)  # 紫=Ready, 藍=選擇中
		if i == p1_selected and i == p2_selected and p1_ready and p2_ready:
			btn.modulate = Color(1, 1, 0)  # 同選全Ready=金黃

func _check_ready() -> void:
	if ready_label:
		ready_label.text = ("P1 READY ∞" if p1_ready else "P1 ?") + "   " + ("P2 READY ∞" if p2_ready else "P2 ?")
	
	if p1_ready and p2_ready:
		print("兩人都確認完成，自動跳轉 world.tscn")
		get_tree().change_scene_to_file("res://scenes/gameplay/world.tscn")
