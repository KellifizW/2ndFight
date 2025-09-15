class_name Player extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

@export var player_id: String = "p1" # 用於區分玩家1或玩家2的輸入
@onready var move_set = $MoveSet if has_node("MoveSet") else null

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	else:
		print("Warning: Hitbox not found for %s" % name)
	if move_set and player_id != "p1" and player_id != "p2":
		print("Warning: MoveSet node found for %s, but only P1 or P2 should have MoveSet" % name)
	add_to_group("players")

func get_input() -> Dictionary:
	var input_dir = 0
	var crouch_pressed = Input.is_action_pressed("crouch" + ("_p2" if player_id == "p2" else ""))
	var jump_pressed = Input.is_action_pressed("jump" + ("_p2" if player_id == "p2" else ""))
	var attack_pressed = Input.is_action_just_pressed("attack" + ("_p2" if player_id == "p2" else ""))
	var right_pressed = Input.is_action_pressed("move_right" + ("_p2" if player_id == "p2" else ""))
	var left_pressed = Input.is_action_pressed("move_left" + ("_p2" if player_id == "p2" else ""))
	var spm1_pressed = Input.is_action_just_pressed("spmove1" + ("_p2" if player_id == "p2" else "")) 
	
	if right_pressed and left_pressed:
		input_dir = 0
	elif right_pressed:
		input_dir = 1
	elif left_pressed:
		input_dir = -1
	
	var attack_type = "attack" if attack_pressed else "none"
	var blockstun_duration = 0.4 if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")) else 0.2
	var damage = move_set.get_special_damage() if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")) else (10.0 if attack_pressed else 0.0)
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"attack_pressed": attack_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed
	}

func _physics_process(delta):
	super._physics_process(delta)
	var input_data = get_input()
	
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping
	
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_state):
		return
	
	if input_data.attack_pressed and is_valid_state:
		current_damage = input_data.damage
		is_attacking = true
		attack_timer = attack_time
		velocity.x = 0
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = false
			print("Debug: Hitbox enabled during attack for %s" % name)
		if has_node("Proximitybox/ProxShape"):
			$Proximitybox/ProxShape.disabled = false
			print("Debug: ProximityBox enabled during attack for %s" % name)
	
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")):
		var curr_state = animation_state.get_current_node() if animation_state else ""
		var target_state = "powerkk" if player_id == "p1" else "spnk"
		animation_tree.set("parameters/conditions/powerkk", player_id == "p1")
		animation_tree.set("parameters/conditions/spnk", player_id == "p2")
		if curr_state != target_state:
			animation_state.travel(target_state)
			print("Debug: Animation switched to %s for %s" % [target_state, name])
	else:
		super._update_animation_state(dir_x, crouch_input)
		animation_tree.set("parameters/conditions/powerkk", false)
		animation_tree.set("parameters/conditions/spnk", false)

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		var damage = current_damage
		target.take_hit(blockstun_duration, damage)
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		hit_detected.emit(target.name, blockstun_duration, is_blocked)
		print("Debug: Hit detected on %s with blockstun duration %s, damage %s, is_blocked: %s" % [target.name, blockstun_duration, damage, is_blocked])
		current_damage = 0.0
		if has_node("Hitbox/HitShape"):
			$Hitbox/HitShape.disabled = true
			print("Debug: Hitbox disabled after hit for %s" % name)

func get_facing_multiplier() -> float:
	return facing_direction
