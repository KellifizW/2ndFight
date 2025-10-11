class_name Player extends Fighter

signal hit_detected(target: String, blockstun_duration: float, is_blocked: bool)

@export var player_id: String = "p1"
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 50.0
@export var cancel_window_duration: float = 0.3

@onready var move_set = $MoveSet if has_node("MoveSet") else null
@onready var player_controller = $PlayerController if has_node("PlayerController") else null

var current_mode: String = "ground_stand"
var attack_type: String = "none"
var is_landing: bool = false
var is_wakeup: bool = false
var is_wakeup_locked: bool = false
var is_air_attacking: bool = false
var is_special_moving: bool = false
var landing_lock_timer: float = 0.0
var has_air_attacked: bool = false
var skip_pushbox: bool = false
var cancel_window_timer: float = 0.0

func _ready():
	super._ready()
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	if animation_tree and not animation_tree.animation_finished.is_connected(_on_animation_tree_finished):
		animation_tree.animation_finished.connect(_on_animation_tree_finished)
		animation_tree.active = true
		animation_state.travel("Walk")
	add_to_group("players")
	if player_controller:
		player_controller.player_id = player_id
	else:
		print("Warning: PlayerController not found for %s" % name)
	hit_detected.connect(_on_hit_detected)

func get_input() -> Dictionary:
	if is_knockfly or is_wakeup or is_hit:
		return {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"st_mp_pressed": false,
			"st_mk_pressed": false,
			"attack_type": "none",
			"blockstun_duration": 0.2,
			"damage": 0.0,
			"spm1_pressed": false,
			"spm2_pressed": false
		}
	if is_ai_controlled:
		var ai_behavior = $AIBehavior if has_node("AIBehavior") else null
		if ai_behavior:
			return ai_behavior.get_ai_input()
	if player_controller:
		return player_controller.get_input_data()
	else:
		print("Warning: Falling back to default input due to missing PlayerController for %s" % name)
		return {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"st_mp_pressed": false,
			"st_mk_pressed": false,
			"attack_type": "none",
			"blockstun_duration": 0.2,
			"damage": 0.0,
			"spm1_pressed": false,
			"spm2_pressed": false
		}

func _physics_process(delta):
	super._physics_process(delta)
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		return
	
	if is_jumping and not is_on_floor():
		print("Debug: In air, jump_dir = %.1f, facing_direction = %.1f" % [jump_dir, facing_direction])
	
	if is_air_attacking and is_on_floor():
		is_air_attacking = false
		has_air_attacked = false
	
	if cancel_window_timer > 0:
		cancel_window_timer -= delta
		if cancel_window_timer <= 0:
			cancel_window_timer = 0.0
			print("Debug: Cancel window closed for %s" % name)
	
	var input_data = get_input()
	var is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup
	
	print("Debug: Input check - is_attacking=%s, attack_type=%s, st_mp_pressed=%s, st_mk_pressed=%s, spm1_pressed=%s for %s" % [is_attacking, attack_type, input_data.st_mp_pressed, input_data.st_mk_pressed, input_data.spm1_pressed, name])
	
	if is_attacking and animation_state.get_current_node() in ["st_mp", "st_mk"]:
		if input_data.st_mp_pressed or input_data.st_mk_pressed:
			print("Debug: Ignoring st_mp_pressed=%s, st_mk_pressed=%s during attack animation %s for %s" % [input_data.st_mp_pressed, input_data.st_mk_pressed, animation_state.get_current_node(), name])
			input_data.st_mp_pressed = false
			input_data.st_mk_pressed = false
	
	if player_id == "p1" and is_attacking and attack_type == "st_mp" and cancel_window_timer > 0 and input_data.spm1_pressed:
		stop_attack()
		print("Debug: st_mp canceled to powerkk for %s, cancel_window_timer=%.2f" % [name, cancel_window_timer])
	
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_ground_state):
		return
	
	if cancel_window_timer > 0:
		print("Debug: Cancel window active (%.2f sec left), ignoring st_mp_pressed=%s, st_mk_pressed=%s for %s" % [cancel_window_timer, input_data.st_mp_pressed, input_data.st_mk_pressed, name])
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_ground_state:
		current_damage = input_data.damage
		is_attacking = true
		attack_type = input_data.attack_type
		if not is_push_back:
			fixed_velocity.x = 0
		print("Debug: Attack triggered, type=%s, st_mp_pressed=%s, st_mk_pressed=%s for %s" % [attack_type, input_data.st_mp_pressed, input_data.st_mk_pressed, name])
	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup and not has_air_attacked
	if input_data.st_mp_pressed and is_valid_air_state:
		current_damage = input_data.damage
		is_air_attacking = true
		has_air_attacked = true
		attack_type = "jump_mp"
		print("Debug: Air attack triggered, type=jump_mp for %s" % name)
	elif input_data.st_mk_pressed and is_valid_air_state:
		current_damage = input_data.damage
		is_air_attacking = true
		has_air_attacked = true
		attack_type = "jump_mk"
		print("Debug: Air attack triggered, type=jump_mk for %s" % name)
	
	if landing_lock_timer > 0:
		landing_lock_timer -= delta
		if is_landing and (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed):
			is_landing = false
			landing_lock_timer = 0.0
			landing_facing_lock = false
			update_facing_direction()
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	if not ("landing_lock_timer" in self and self.landing_lock_timer > 0):
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _compute_target_state(dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	if is_wakeup_locked:
		return "wakeup"
	elif move_set and move_set.is_spmove:
		if player_id == "p1" and move_set.is_powerkk:
			return "powerkk"
		elif player_id == "p2" and move_set.is_spnk:
			return "spnk"
		elif move_set.is_fireball:
			return "fireball"
	elif is_landing and landing_lock_timer > 0:
		return "landing"
	elif not on_floor and (is_jumping or is_air_attacking):
		if is_air_attacking or has_air_attacked:
			return attack_type
		else:
			if anim_jump_dir > 0:
				return "Jump_F"
			elif anim_jump_dir < 0:
				return "Jump_B"
			else:
				return "Jump_V"
	return super._compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	super._update_animation_state(dir_x, crouch_input)

func _on_hitbox_area_entered(area: Area2D):
	if area.name == "Hurtbox" and area.get_parent() != self:
		var target = area.get_parent()
		var input_data = get_input()
		var blockstun_duration = input_data.blockstun_duration
		var damage = current_damage
		if damage > 0:
			var world = get_tree().get_first_node_in_group("world")
			if not world:
				return
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze()
			target.take_hit(blockstun_duration, damage, false)
			var is_blocked = target.is_blocking and target.block_type == "ordinary"
			hit_detected.emit(target.name, blockstun_duration, is_blocked)
			if move_set and (move_set.is_spnk or move_set.is_powerkk):
				print("Debug: Special move hit detected, skipping push back for %s" % name)
				return
			var push_manager = get_tree().get_first_node_in_group("push_manager")
			var is_target_at_corner = push_manager.is_at_corner(target) if push_manager else false
			if is_target_at_corner:
				var push_duration: float
				if damage >= 20.0:
					push_duration = 0.4
				elif is_blocked:
					push_duration = 0.267
				else:
					push_duration = 0.35
				is_push_back = true
				push_back_timer = push_duration
				initial_push_back = push_duration
				push_back_velocity = 2.0 * corner_push_distance * world.SIMULATION_SCALE / push_duration
				var facing_mult = get_facing_multiplier()
				fixed_velocity.x = int(-push_back_velocity * facing_mult)
				print("Debug: Attacker pushed back due to defender at corner, push_duration=%.2f, velocity=%.2f" % [push_duration, push_back_velocity])
			else:
				print("Debug: No push back for attacker, defender not at corner for %s" % name)

func _on_hit_detected(target: String, blockstun_duration: float, is_blocked: bool):
	if player_id == "p1" and attack_type == "st_mp" and is_attacking:
		cancel_window_timer = cancel_window_duration
		print("Debug: Cancel window opened for powerkk (%.2f sec) for %s" % [cancel_window_duration, name])
	if has_node("Hitbox/HitShape"):
		print("Debug: Hitbox/HitShape disabled = %s after hit for %s" % [$Hitbox/HitShape.disabled, name])

func _on_animation_tree_finished(anim_name: String):
	var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
	if anim_name == "knockfly" and is_knockfly:
		if healthbar and healthbar.current_health <= 0:
			return
		is_knockfly = false
		is_wakeup = true
		is_wakeup_locked = true
		fixed_velocity = Vector2i.ZERO
		animation_state.travel("wakeup")
	elif anim_name == "wakeup" and is_wakeup:
		is_wakeup = false
		is_wakeup_locked = false
		is_landing = false
		_update_animation_state(0, false)
	elif anim_name == "landing" and is_landing:
		is_landing = false
		landing_lock_timer = 0.0
		landing_facing_lock = false
		update_facing_direction()
		_update_animation_state(0, false)
	elif anim_name in ["st_mp", "st_mk"] and is_attacking:
		is_attacking = false
		attack_type = "none"
		cancel_window_timer = 0.0
		update_facing_direction()
		_update_animation_state(0, false)
		if has_node("Hitbox/HitShape"):
			print("Debug: Hitbox/HitShape disabled = %s after %s anim finished for %s" % [$Hitbox/HitShape.disabled, anim_name, name])
	elif anim_name in ["jump_mp", "jump_mk"] and is_air_attacking:
		if is_on_floor():
			is_air_attacking = false
			has_air_attacked = false
			var input_data = get_input()
			if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed:
				is_landing = false
				_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
			else:
				is_landing = true
				landing_lock_timer = landing_duration
		else:
			pass
	elif anim_name in ["jump_v", "Jump_V", "Jump_F", "Jump_B"] and is_on_floor():
		is_jumping = false
		var input_data = get_input()
		if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed:
			is_landing = false
			landing_facing_lock = false
			update_facing_direction()
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
		else:
			is_landing = true
			landing_lock_timer = landing_duration
	elif anim_name in ["Dash", "Backdash"]:
		is_dashing = false
		is_backdashing = false
		_update_animation_state(0, false)
	elif anim_name == "fireball":
		if move_set and move_set.is_fireball:
			move_set.stop_special_move()
			_update_animation_state(0, false)
	elif anim_name in ["powerkk", "spnk"]:
		if move_set and (move_set.is_powerkk or move_set.is_spnk):
			move_set.stop_special_move()
			_update_animation_state(0, false)
		if has_node("Hitbox/HitShape"):
			print("Debug: Hitbox/HitShape disabled = %s after %s anim finished for %s" % [$Hitbox/HitShape.disabled, anim_name, name])

func stop_attack():
	is_attacking = false
	attack_type = "none"
	if animation_player:
		animation_player.stop()
	update_facing_direction()
	_update_animation_state(0, false)
	print("Debug: Attack stopped for %s" % name)
	if has_node("Hitbox/HitShape"):
		print("Debug: Hitbox/HitShape disabled = %s after stop_attack for %s" % [$Hitbox/HitShape.disabled, name])

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()

func _physics_process_jump(delta: float):
	var input_data = get_input()
	if input_data.jump_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_attacking and not is_hit and not is_knockfly and not is_blocking:
		is_jumping = true
		landing_facing_lock = true
		var world = get_tree().get_first_node_in_group("world")
		if world:
			fixed_position.y = world.FLOOR_Y - 1
			fixed_velocity.y = 0
			if input_data.input_dir != 0:
				var jump_speed = jump_horizontal_speed if input_data.input_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
				fixed_velocity.x = int(jump_speed * world.SIMULATION_SCALE * input_data.input_dir)
				print("Debug: Jump velocity set for %s, fixed_velocity.x = %d, input_dir = %.1f, jump_dir = %.1f" % [name, fixed_velocity.x, input_data.input_dir, jump_dir])
			else:
				fixed_velocity.x = 0
				print("Debug: Vertical jump initiated for %s, fixed_velocity.x = %d, jump_dir = %.1f" % [name, fixed_velocity.x, jump_dir])
