class_name Player extends Fighter

signal hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool)

@export var player_id: String = "p1"
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 50.0
@export var cancel_window_duration: float = 0.3
@export var st_mp_hitstun: float = 0.4
@export var st_mp_blockstun: float = 0.267
@export var st_mk_hitstun: float = 0.65
@export var st_mk_blockstun: float = 0.3
@export var st_mp_damage: float = 10.0
@export var st_mk_damage: float = 15.0
@export var jump_mp_damage: float = 8.0
@export var jump_mk_damage: float = 12.0
@export var powerkk_blockstun: float = 0.3833
@export var cr_mp_hitstun: float = 0.35
@export var cr_mp_blockstun: float = 0.233
@export var cr_mp_damage: float = 8.0
@export var cr_mk_hitstun: float = 0.5
@export var cr_mk_blockstun: float = 0.267
@export var cr_mk_damage: float = 9.0

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
var is_facing_locked: bool = false
var special_input_data: Dictionary = {
	"spm1_pressed": false,
	"spm2_pressed": false,
	"dp_pressed": false,
	"super_pressed": false
}

func reset_attack_state():
	is_attacking = false
	attack_type = "none"
	cancel_window_timer = 0.0
	update_facing_direction()
	_update_animation_state(0, false)

func reset_landing_state():
	is_landing = false
	landing_lock_timer = 0.0
	landing_facing_lock = false
	update_facing_direction()
	_update_animation_state(0, false)

func reset_air_state():
	if is_on_floor():
		is_air_attacking = false
		has_air_attacked = false
		var input_data = get_input()
		if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed:
			is_landing = false
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
		else:
			is_landing = true
			landing_lock_timer = landing_duration

func reset_special_state():
	if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_dp or move_set.is_fireball):
		move_set.stop_special_move()
	is_facing_locked = false
	force_update_facing_direction()
	_update_animation_state(0, false)

var player_anim_resets: Dictionary = {
	"wakeup": func():
		is_wakeup = false
		is_wakeup_locked = false
		is_landing = false
		_update_animation_state(0, false),
	"landing": func(): reset_landing_state(),
	"st_mp": func(): reset_attack_state(),
	"st_mk": func(): reset_attack_state(),
	"cr_mp": func(): reset_attack_state(),
	"cr_mk": func(): reset_attack_state(),
	"jump_mp": func(): reset_air_state(),
	"jump_mk": func(): reset_air_state(),
	"jump_v": func():
		if is_on_floor():
			is_jumping = false
			var input_data = get_input()
			if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed:
				is_landing = false
				landing_facing_lock = false
				update_facing_direction()
				_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
			else:
				is_landing = true
				landing_lock_timer = landing_duration,
	"Jump_V": func(): player_anim_resets["jump_v"].call(),
	"Jump_F": func(): player_anim_resets["jump_v"].call(),
	"Jump_B": func(): player_anim_resets["jump_v"].call(),
	"fireball": func(): reset_special_state(),
	"powerkk": func(): reset_special_state(),
	"spnk": func(): reset_special_state(),
	"dp": func(): reset_special_state(),
}

func _ready():
	super._ready()
	world = get_tree().get_first_node_in_group("world")
	if player_id == "p1":
		st_mp_hitstun = 0.4
		st_mk_hitstun = 0.65
	else:
		st_mp_hitstun = 0.35
		st_mk_hitstun = 0.45
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	if animation_tree:
		animation_tree.animation_finished.connect(_on_animation_tree_finished)
		animation_tree.active = true
		animation_state.travel("Walk")
	add_to_group("players")
	if player_controller:
		player_controller.player_id = player_id
	hit_detected.connect(_on_hit_detected)

func set_input_data(data: Dictionary):
	special_input_data = data

var default_input: Dictionary = {
	"input_dir": 0,
	"crouch_pressed": false,
	"jump_pressed": false,
	"st_mp_pressed": false,
	"st_mk_pressed": false,
	"attack_type": "none",
	"blockstun_duration": 0.2,
	"damage": 0.0,
	"spm1_pressed": false,
	"spm2_pressed": false,
	"super_pressed": false,
	"dp_pressed": false
}

func get_input() -> Dictionary:
	if is_knockfly or is_wakeup or is_hit or is_layground:
		return default_input.duplicate()
	if is_ai_controlled:
		var ai_behavior = $AIBehavior if has_node("AIBehavior") else null
		if ai_behavior:
			return ai_behavior.get_ai_input()
	if player_controller:
		var input_data = player_controller.get_input_data()
		input_data.super_pressed = Input.is_key_pressed(KEY_P)
		if input_data.st_mp_pressed:
			input_data.damage = st_mp_damage if is_on_floor() else jump_mp_damage
			input_data.attack_type = "st_mp" if is_on_floor() else "jump_mp"
		elif input_data.st_mk_pressed:
			input_data.damage = st_mk_damage if is_on_floor() else jump_mk_damage
			input_data.attack_type = "st_mk" if is_on_floor() else "jump_mk"
		return input_data
	return default_input.duplicate()

func _physics_process(delta):
	if has_node("InputManager"):
		$InputManager.update_input()
	super._physics_process(delta)
	if not world:
		return
	
	if is_air_attacking and is_on_floor():
		is_air_attacking = false
		has_air_attacked = false
	
	if cancel_window_timer > 0:
		cancel_window_timer -= delta
		if cancel_window_timer <= 0:
			cancel_window_timer = 0.0
	
	var input_data = get_input()
	input_data.merge(special_input_data, true)
	if input_data.spm2_pressed or input_data.dp_pressed or input_data.spm1_pressed or input_data.super_pressed:
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	var is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup and not is_layground
	
	if move_set and move_set.is_spmove:
		is_attacking = false
		attack_type = "none"
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if is_attacking and animation_state.get_current_node() in ["st_mp", "st_mk", "cr_mp", "cr_mk"]:
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if player_id == "p1" and is_attacking and attack_type == "st_mp" and cancel_window_timer > 0 and input_data.spm1_pressed:
		stop_attack()
	
	if move_set and move_set.process_move(delta, input_data, is_valid_ground_state):
		return
	
	if cancel_window_timer > 0:
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_ground_state:
		force_update_facing_direction()
		if is_crouching:
			if input_data.st_mp_pressed:
				current_damage = cr_mp_damage
				is_attacking = true
				attack_type = "cr_mp"
			elif input_data.st_mk_pressed:
				current_damage = cr_mk_damage
				is_attacking = true
				attack_type = "cr_mk"
		else:
			if input_data.st_mp_pressed:
				current_damage = st_mp_damage
				is_attacking = true
				attack_type = "st_mp"
			elif input_data.st_mk_pressed:
				current_damage = st_mk_damage
				is_attacking = true
				attack_type = "st_mk"
		if not is_push_back:
			fixed_velocity.x = 0
	
	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup and not has_air_attacked and not is_layground
	if input_data.st_mp_pressed and is_valid_air_state:
		current_damage = jump_mp_damage
		is_air_attacking = true
		has_air_attacked = true
		attack_type = "jump_mp"
	elif input_data.st_mk_pressed and is_valid_air_state:
		current_damage = jump_mk_damage
		is_air_attacking = true
		has_air_attacked = true
		attack_type = "jump_mk"
	
	if landing_lock_timer > 0:
		landing_lock_timer -= delta
		if is_landing and (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed):
			is_landing = false
			landing_lock_timer = 0.0
			landing_facing_lock = false
			update_facing_direction()
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	if not (landing_lock_timer > 0):
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _physics_process_jump(delta: float):
	var input_data = get_input()
	if input_data.jump_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_attacking and not is_hit and not is_knockfly and not is_blocking and not is_layground:
		is_jumping = true
		landing_facing_lock = true
		if world:
			fixed_position.y = world.FLOOR_Y - 1
			fixed_velocity.y = 0
			if input_data.input_dir != 0:
				var jump_speed = jump_horizontal_speed if input_data.input_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
				fixed_velocity.x = int(jump_speed * world.SIMULATION_SCALE * input_data.input_dir)
			else:
				fixed_velocity.x = 0

func _compute_target_state(dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	if is_layground:
		return "layground"
	if is_knockfly:
		return "knockfly"
	if is_wakeup_locked:
		return "wakeup"
	if is_hit:
		return "hit"
	if move_set and move_set.is_spmove:
		if move_set.is_super:
			return "super"
		elif player_id == "p1" and move_set.is_powerkk:
			return "powerkk"
		elif player_id == "p1" and move_set.is_dp:
			return "dp"
		elif player_id == "p2" and move_set.is_spnk:
			return "spnk"
		elif move_set.is_fireball:
			return "fireball"
	if is_blocking:
		return "cr_block" if is_crouch_blocking and crouch_input else "block"
	if is_landing and landing_lock_timer > 0:
		return "landing"
	if not on_floor and (is_jumping or is_air_attacking):
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
	if area.name != "Hurtbox" or not area.get_parent().is_in_group("players") or area.get_parent() == self:
		return
	
	var target = area.get_parent()
	var target_name = target.name
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_blocked = target.is_blocking
	var was_in_stun = target.is_hit or target.is_knockfly
	
	var hitstun: float = 0.35
	var blockstun: float = 0.267
	var damage: float = current_damage
	var skip_push: bool = false
	var force_knockfly: bool = false
	var knockfly_params: Dictionary = {}
	
	if not world:
		return
	
	var slowmo_controller = world.get_node_or_null("SlowMoController")
	if slowmo_controller:
		slowmo_controller.request_hit_freeze()
	
	if attack_type == "st_mp":
		hitstun = st_mp_hitstun
		blockstun = st_mp_blockstun
		damage = st_mp_damage
	elif attack_type == "st_mk":
		hitstun = st_mk_hitstun
		blockstun = st_mk_blockstun
		damage = st_mk_damage
	elif attack_type == "cr_mp":
		hitstun = cr_mp_hitstun
		blockstun = cr_mp_blockstun
		damage = cr_mp_damage
	elif attack_type == "cr_mk":
		hitstun = cr_mk_hitstun
		blockstun = cr_mk_blockstun
		damage = cr_mk_damage
	elif attack_type == "jump_mp":
		hitstun = 0.4
		blockstun = 0.267
		damage = jump_mp_damage
	elif attack_type == "jump_mk":
		hitstun = 0.5
		blockstun = 0.3
		damage = jump_mk_damage
	elif move_set and move_set.is_powerkk:
		hitstun = 0.65
		blockstun = powerkk_blockstun
		damage = move_set.powerkk_damage
	elif move_set and move_set.is_spnk:
		hitstun = 0.45
		blockstun = powerkk_blockstun
		damage = move_set.spnk_damage
		var anim_pos = animation_player.current_animation_position if animation_player else 0.0
		if anim_pos < 0.2667:
			damage = 6.0
	elif move_set and move_set.is_fireball:
		hitstun = 0.35
		blockstun = 0.233
		damage = move_set.fireball_damage
		skip_push = true
	elif move_set and move_set.is_super:
		hitstun = 0.45
		blockstun = 0.3
		damage = move_set.super_damage
	elif move_set and move_set.is_dp:
		hitstun = 0.65
		blockstun = powerkk_blockstun
		damage = move_set.dp_damage
		force_knockfly = not is_blocked
		knockfly_params = {
			"gravity": move_set.dp_knockfly_gravity,
			"vertical_speed": move_set.dp_knockfly_vertical_speed,
			"duration": hitstun
		}
	
	target.take_hit(hitstun, blockstun, damage, skip_push, force_knockfly, knockfly_params)
	
	var stun_duration = blockstun if is_blocked else hitstun
	hit_detected.emit(target_name, stun_duration, is_blocked, was_in_stun)
	
	var hit_sound_player = $HitSoundPlayer if has_node("HitSoundPlayer") else null
	var block_sound_player = $BlockSoundPlayer if has_node("BlockSoundPlayer") else null
	if is_blocked and block_sound_player:
		block_sound_player.play()
	elif not is_blocked and hit_sound_player:
		hit_sound_player.play()
	
	var vfx_type = "block" if is_blocked else "hit"
	var contact_point = get_contact_point($Hitbox, area)
	if contact_point == Vector2.ZERO:
		contact_point = (area.global_position + $Hitbox.global_position) / 2.0
	if not target.is_on_floor():
		contact_point.y += 10
	VFXImpact.spawn_vfx(world, vfx_type, contact_point, facing_direction)
	
	var debug_text = "Hit on %s\nHitbox: %s (facing: %s)\nHurtbox: %s (facing: %s)\nVFX Contact: %s\nAir hit: %s\nBlocked: %s" % [
		target_name,
		$Hitbox.global_position,
		get_facing_multiplier(),
		area.global_position,
		target.get_facing_multiplier() if "get_facing_multiplier" in target else 1.0,
		contact_point,
		"yes" if not target.is_on_floor() else "no",
		"yes" if is_blocked else "no"
	]
	var debug_label = world.get_node_or_null("UI/DebugLabel")
	if debug_label:
		debug_label.text = debug_text
	
	if move_set and (move_set.is_spnk or move_set.is_powerkk or move_set.is_dp):
		return
	var push_manager = get_tree().get_first_node_in_group("push_manager")
	var is_target_at_corner = push_manager.is_at_corner(target) if push_manager else false
	if is_target_at_corner:
		var push_duration: float = stun_duration
		is_push_back = true
		push_back_timer = push_duration
		initial_push_back = push_duration
		push_back_velocity = 2.0 * corner_push_distance * world.SIMULATION_SCALE / push_duration
		var facing_mult = get_facing_multiplier()
		fixed_velocity.x = int(-push_back_velocity * facing_mult)

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	if player_id == "p1" and attack_type == "st_mp" and is_attacking:
		cancel_window_timer = cancel_window_duration

func _on_animation_tree_finished(anim_name: String):
	if anim_name == "layground" and is_layground:
		var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
		if healthbar and healthbar.current_health <= 0:
			return
		is_layground = false
		is_wakeup = true
		is_wakeup_locked = true
		fixed_velocity = Vector2i.ZERO
		animation_state.travel("wakeup")
	else:
		if anim_name in player_anim_resets:
			player_anim_resets[anim_name].call()

func stop_attack():
	is_attacking = false
	attack_type = "none"
	if animation_player:
		animation_player.stop()
	update_facing_direction()
	_update_animation_state(0, false)

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()

func update_facing_direction():
	if is_facing_locked:
		return
	super.update_facing_direction()

func force_update_facing_direction():
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for player in players:
		if player != self:
			other_player = player
			break
	
	if other_player:
		var self_left = global_position.x - colbox_half_width
		var self_right = global_position.x + colbox_half_width
		var other_left = other_player.global_position.x - other_player.colbox_half_width
		var other_right = other_player.global_position.x + other_player.colbox_half_width
		
		if self_left > other_right:
			facing_direction = -1.0
			scale.x = -1
		elif self_right < other_left:
			facing_direction = 1.0
			scale.x = 1
		update_hitbox_position()
	else:
		facing_direction = 1.0
		scale.x = 1
