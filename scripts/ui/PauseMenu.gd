extends CanvasLayer
## In-fight pause menu. It keeps processing while SceneTree is paused.

const CHARACTER_SELECT_SCENE := "res://scenes/ui/CharacterSelect.tscn"
const NORMAL_COLOR := Color(0.15, 0.16, 0.2, 0.96)
const SELECTED_COLOR := Color(0.86, 0.24, 0.16, 1.0)

@onready var menu_root: Control = $MenuRoot
@onready var resume_button: Button = $MenuRoot/Center/Panel/Margin/Content/ResumeButton
@onready var character_select_button: Button = $MenuRoot/Center/Panel/Margin/Content/CharacterSelectButton

var _buttons: Array[Button] = []
var _selected_index: int = 0
var _leaving_scene: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_root.visible = false
	_buttons = [resume_button, character_select_button]
	resume_button.pressed.connect(_resume_game)
	character_select_button.pressed.connect(_return_to_character_select)
	for index in _buttons.size():
		_buttons[index].mouse_entered.connect(_select_button.bind(index))
	_update_selection()

func _unhandled_input(event: InputEvent) -> void:
	if _leaving_scene:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()
		return

	if not get_tree().paused or not menu_root.visible:
		return

	if _is_navigation_event(event):
		_selected_index = (_selected_index + 1) % _buttons.size()
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("st_lk") or event.is_action_pressed("st_lk_p2"):
		_activate_selected()
		get_viewport().set_input_as_handled()

func _is_navigation_event(event: InputEvent) -> bool:
	return (
		event.is_action_pressed("move_left")
		or event.is_action_pressed("move_right")
		or event.is_action_pressed("jump")
		or event.is_action_pressed("crouch")
		or event.is_action_pressed("move_left_p2")
		or event.is_action_pressed("move_right_p2")
		or event.is_action_pressed("jump_p2")
		or event.is_action_pressed("crouch_p2")
	)

func _pause_game() -> void:
	_selected_index = 0
	menu_root.visible = true
	_update_selection()
	get_tree().paused = true

func _resume_game() -> void:
	if _leaving_scene:
		return
	menu_root.visible = false
	get_tree().paused = false

func _return_to_character_select() -> void:
	if _leaving_scene:
		return
	_leaving_scene = true
	# Keep the game frozen while the global overlay fades to black.
	SceneTransition.transition_to(CHARACTER_SELECT_SCENE)

func _activate_selected() -> void:
	if _selected_index == 0:
		_resume_game()
	else:
		_return_to_character_select()

func _select_button(index: int) -> void:
	if not menu_root.visible or _leaving_scene:
		return
	_selected_index = index
	_update_selection()

func _update_selection() -> void:
	for index in _buttons.size():
		var button := _buttons[index]
		button.modulate = SELECTED_COLOR if index == _selected_index else NORMAL_COLOR
		button.button_pressed = index == _selected_index
	if not _buttons.is_empty():
		_buttons[_selected_index].grab_focus()
