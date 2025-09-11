class_name Dennis extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

var current_damage: float = 0.0  # 新增：記錄當前攻擊的傷害值

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	else:
		print("Warning: Hitbox not found for %s" % name)
	$Sprite2D.flip_h = true
	facing_direction = -1.0
	add_to_group("players")
	update_hitbox_position()

func get_input() -> Dictionary:
	var input_dir = 0
	var crouch_pressed = Input.is_action_pressed("crouch_p2")
	var jump_pressed = Input.is_action_pressed("jump_p2")
	var attack_pressed = Input.is_action_just_pressed("attack_p2")
	var right_pressed = Input.is_action_pressed("move_right_p2")
	var left_pressed = Input.is_action_pressed("move_left_p2")
	var spmove1_pressed = Input.is_action_pressed("spmove1_p2")
	
	if right_pressed and left_pressed:
		input_dir = 0
	elif right_pressed:
		input_dir = 1
	elif left_pressed:
		input_dir = -1
	
	var attack_type = "light" if attack_pressed else "none"
	var blockstun_duration = 0.2 if attack_type == "light" else 0.4
	var damage = 10.0 if attack_type == "light" else 0.0
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"attack_pressed": attack_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage
	}

func _physics_process(delta):  # 新增：覆蓋父類，偵測攻擊輸入時記錄 damage
	super._physics_process(delta)
	var input_data = get_input()
	if input_data.attack_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping:
		current_damage = input_data.damage  # 記錄傷害值

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		target.take_hit(blockstun_duration, current_damage)  # 使用記錄的 current_damage，而不是重新算
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		hit_detected.emit(target.name, blockstun_duration, is_blocked)
		print("Debug: Hit detected on %s with blockstun duration %s, damage %s, is_blocked: %s" % [target.name, blockstun_duration, current_damage, is_blocked])
		current_damage = 0.0  # 碰撞後重置，避免重複使用

func get_facing_multiplier() -> float:
	return -1.0

func update_hitbox_position():
	if has_node("Hitbox/HitShape"):
		$Hitbox.scale.x = facing_direction
	if has_node("Proximitybox/ProxShape"):
		$Proximitybox.scale.x = facing_direction
