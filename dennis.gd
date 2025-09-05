class_name Dennis extends Fighter

signal hit_detected(target: String)

func _ready():
	super._ready()
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	$Sprite2D.flip_h = true
	facing_direction = -1.0
	update_hitbox_position()

func get_input() -> Dictionary:
	var input_dir = 0
	var crouch_pressed = Input.is_action_pressed("crouch_p2")
	var jump_pressed = Input.is_action_pressed("jump_p2")
	var attack_pressed = Input.is_action_just_pressed("attack_p2")
	var right_pressed = Input.is_action_pressed("move_right_p2")
	var left_pressed = Input.is_action_pressed("move_left_p2")
	
	if right_pressed and left_pressed:
		input_dir = 0
	elif right_pressed:
		input_dir = 1
	elif left_pressed:
		input_dir = -1
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"attack_pressed": attack_pressed
	}

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		hit_detected.emit(target.name)
		target.take_hit()
		print("Debug: Hit detected on %s" % target.name)

func get_facing_multiplier() -> float:
	return -1.0  # Dennis 反向
