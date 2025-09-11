class_name Davis extends Fighter

signal hit_detected(target: String, blockstun_duration: float)

func _ready():
	super._ready()
	$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	$Sprite2D.flip_h = false
	facing_direction = 1.0
	update_hitbox_position()

func get_input() -> Dictionary:
	var input_dir = 0
	var crouch_pressed = Input.is_action_pressed("crouch")
	var jump_pressed = Input.is_action_pressed("jump")
	var attack_pressed = Input.is_action_just_pressed("attack")
	var right_pressed = Input.is_action_pressed("move_right")
	var left_pressed = Input.is_action_pressed("move_left")
	
	if right_pressed and left_pressed:
		input_dir = 0
	elif right_pressed:
		input_dir = 1
	elif left_pressed:
		input_dir = -1
	
	var attack_type = "light" if attack_pressed else "none"
	var blockstun_duration = 0.2 if attack_type == "light" else 0.4
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"attack_pressed": attack_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration
	}

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var blockstun_duration = get_input().blockstun_duration
		hit_detected.emit(target.name, blockstun_duration)
		target.take_hit(blockstun_duration)
		print("Debug: Hit detected on %s with blockstun duration %s" % [target.name, blockstun_duration])

func get_facing_multiplier() -> float:
	return 1.0

func update_hitbox_position():
	if has_node("Hitbox/HitShape"):
		$Hitbox.scale.x = facing_direction
	if has_node("Proximitybox/ProxShape"):
		$Proximitybox.scale.x = facing_direction
