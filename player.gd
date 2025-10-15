# Frame Data for Attacks and Moves (based on animation timings in player1.tscn and player2.tscn)
# These values are derived from animation lengths and hitbox enable/disable timings in Godot 4.5.
# Startup: Time from animation start to when hitbox becomes active (HitShape:shape set to non-null).
# Active: Duration hitbox is active (from non-null to null or disabled).
# Recovery: Time from hitbox deactivation to animation end.
# Note: Values for P2 st_mp, st_mk, and spnk are updated based on player2.tscn (AnimationLibrary_46qut).
# For moves with multiple active periods (e.g., spnk), active time is aggregated.

# For P1 (Davis):
# - st_mp: startup = 0.1s, active = 0.0333s, recovery = 0.2667s (total 0.4s)
# - st_mk: startup = 0.2s, active = 0.0667s, recovery = 0.4003s (total 0.667s)
# - jump_mp: startup = 0.1333s, active = 0.0667s, recovery = 0.2s (total 0.4s)
# - jump_mk: startup = 0.1s, active = 0.1s, recovery = 0.3s (total 0.5s)
# - powerkk: startup = 0.3s, active = 0.1333s, recovery = 0.5s (total 0.9333s)
# - fireball: startup = 0.3s, active = 0.0333s, recovery = 0.4667s (total 0.8s)

# For P2 (Dennis):
# - st_mp: startup = 0.2s, active = 0.1333s, recovery = 0.3667s (total 0.7s)
# - st_mk: startup = 0.1s, active = 0.0333s, recovery = 0.2667s (total 0.4s)
# - jump_mp: startup = 0.1s, active = 0.0667s, recovery = 0.2333s (total 0.4s)
# - jump_mk: startup = 0.1s, active = 0.1s, recovery = 0.267s (total 0.467s)
# - spnk: startup = 0.2s, active = 0.1333s (0.0667s + 0.0666s), recovery = 0.4667s (total 1.0s)
# - fireball: startup = 0.3s, active = 0.0333s, recovery = 0.3667s (total 0.7s)

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
	if player_id == "p1":
		st_mp_hitstun = 0.4
		st_mk_hitstun = 0.65
	else:
		st_mp_hitstun = 0.35
		st_mk_hitstun = 0.45
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
	
	if is_air_attacking and is_on_floor():
		is_air_attacking = false
		has_air_attacked = false
	
	if cancel_window_timer > 0:
		cancel_window_timer -= delta
		if cancel_window_timer <= 0:
			cancel_window_timer = 0.0
	
	var input_data = get_input()
	var is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup
	
	# 修正：確保 spnk 結束後清除攻擊狀態
	if move_set and move_set.is_spmove:
		is_attacking = false
		attack_type = "none"
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if is_attacking and animation_state.get_current_node() in ["st_mp", "st_mk"]:
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if player_id == "p1" and is_attacking and attack_type == "st_mp" and cancel_window_timer > 0 and input_data.spm1_pressed:
		stop_attack()
	
	if move_set and (player_id == "p1" or player_id == "p2") and move_set.process_move(delta, input_data, is_valid_ground_state):
		return
	
	if cancel_window_timer > 0:
		input_data.st_mp_pressed = false
		input_data.st_mk_pressed = false
	
	if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_ground_state:
		force_update_facing_direction()
		current_damage = input_data.damage
		is_attacking = true
		# 修正：明確根據輸入設置 attack_type
		attack_type = "st_mp" if input_data.st_mp_pressed else "st_mk"
		if not is_push_back:
			fixed_velocity.x = 0
		# 加 debug：追蹤攻擊觸發時的 input 和 attack_type
		print("Debug: Attack triggered for %s, input_st_mp=%s, input_st_mk=%s, attack_type=%s, facing=%s, animation=%s" % [name, input_data.st_mp_pressed, input_data.st_mk_pressed, attack_type, facing_direction, animation_state.get_current_node() if animation_state else "none"])
	
	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup and not has_air_attacked
	if input_data.st_mp_pressed and is_valid_air_state:
		current_damage = input_data.damage
		is_air_attacking = true
		has_air_attacked = true
		attack_type = "jump_mp"
	elif input_data.st_mk_pressed and is_valid_air_state:
		current_damage = input_data.damage
		is_air_attacking = true
		has_air_attacked = true
		attack_type = "jump_mk"
	
	if landing_lock_timer > 0:
		landing_lock_timer -= delta
		if is_landing and (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed):
			is_landing = false
			landing_lock_timer = 0.0
			landing_facing_lock = false
			update_facing_direction()
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	if not (landing_lock_timer > 0):
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

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
			else:
				fixed_velocity.x = 0

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
		var damage = current_damage
		var world = get_tree().get_first_node_in_group("world")
		if not world:
			return
		var slowmo_controller = world.get_node_or_null("SlowMoController")
		if slowmo_controller:
			slowmo_controller.request_hit_freeze()
		
		var hitstun = st_mp_hitstun if attack_type == "st_mp" else st_mk_hitstun if attack_type == "st_mk" else 0.35
		var blockstun = st_mp_blockstun if attack_type == "st_mp" else st_mk_blockstun if attack_type == "st_mk" else 0.267
		
		var was_in_stun = target.is_hit or target.is_knockfly
		target.take_hit(hitstun, blockstun, damage, false)
		
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		var stun_duration = blockstun if is_blocked else hitstun
		hit_detected.emit(target.name, stun_duration, is_blocked, was_in_stun)
		
		var contact_point = get_contact_point($Hitbox, area)
		var vfx_scene_path = "res://vfx_blk.tscn" if is_blocked else "res://vfx_hit.tscn"
		var vfx = load(vfx_scene_path).instantiate()
		world.add_child(vfx)
		if contact_point == Vector2.ZERO:
			contact_point = (area.global_position + $Hitbox.global_position) / 2.0
			print("Warning: Using fallback midpoint position %s for VFX due to invalid contact point" % contact_point)
		vfx.global_position = contact_point
		if not target.is_on_floor():
			vfx.global_position.y += 10
		var particles_1 = vfx.get_node_or_null("exp") if is_blocked else vfx.get_node_or_null("explode")
		var particles_2 = vfx.get_node_or_null("wave") if is_blocked else vfx.get_node_or_null("ring")
		if particles_1:
			particles_1.emitting = true
		if particles_2:
			particles_2.emitting = true
		var vfx_position = vfx.global_position
		print("Debug: %s VFX spawned at %s for %s hitting %s (%s)" % ["Block" if is_blocked else "Hit", vfx.global_position, name, target.name, "blocked" if is_blocked else "unblocked"])
		
		var debug_text = "Hit on %s\nHitbox: %s (facing: %s)\nHurtbox: %s (facing: %s)\nVFX Contact: %s\nAir hit: %s\nBlocked: %s" % [
			target.name,
			$Hitbox.global_position,
			get_facing_multiplier(),
			area.global_position,
			target.get_facing_multiplier() if "get_facing_multiplier" in target else 1.0,
			vfx_position,
			"yes" if not target.is_on_floor() else "no",
			"yes" if is_blocked else "no"
		]
		var debug_label = world.get_node_or_null("UI/DebugLabel")
		if debug_label:
			debug_label.text = debug_text
		
		if move_set and (move_set.is_spnk or move_set.is_powerkk):
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
		else:
			pass

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	if player_id == "p1" and attack_type == "st_mp" and is_attacking:
		cancel_window_timer = cancel_window_duration

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
		# 加 debug：追蹤攻擊動畫結束
		print("Debug: Attack animation %s finished for %s, is_attacking=%s, attack_type=%s, facing=%s" % [anim_name, name, is_attacking, attack_type, facing_direction])
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
	elif anim_name in ["jump_v", "Jump_V", "Jump_F", "Jump_B"] and is_on_floor():
		is_jumping = false
		var input_data = get_input()
		if input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or input_data.st_mp_pressed or input_data.st_mk_pressed or input_data.spm1_pressed or input_data.spm2_pressed:
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
		# 加 debug：追蹤 spnk/powerkk 動畫結束
		print("Debug: Animation %s finished for %s, is_attacking=%s, attack_type=%s, facing=%s" % [anim_name, name, is_attacking, attack_type, facing_direction])

func stop_attack():
	is_attacking = false
	attack_type = "none"
	if animation_player:
		animation_player.stop()
	update_facing_direction()
	_update_animation_state(0, false)

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()

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
