class_name InputHandler extends Node

# Handles all input-related operations for the movement system
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func get_input() -> Dictionary:
	var input_dir: int = 0
	var crouch_pressed: bool = false
	var jump_pressed: bool = false
	
	if Input.is_action_pressed("ui_right"):
		input_dir += 1
	if Input.is_action_pressed("ui_left"):
		input_dir -= 1
	if Input.is_action_pressed("ui_down"):
		crouch_pressed = true
	if Input.is_action_just_pressed("ui_up"):
		jump_pressed = true
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed
	}
