extends Node

enum AIState {
	IDLE,
	APPROACH,
	ATTACK,
	DEFEND,
	JUMP
}

@onready var parent: Node = get_parent()

var ai_enabled: bool = false
var current_state: AIState = AIState.IDLE

var state_timer := 0.0
var action_timer := 0.0
var block_timer := 0.0
var attack_timer := 0.0
var special_timer := 0.0
var jump_attack_timer := 0.0
var timers := {
	"input_dir": 0.0,
	"dash": 0.0,
	"recovery": 0.0,
	"block": 0.0,
	"crouch": 0.0
}

@export var normal_attack_cooldown: float = 1.8
@export var special_attack_cooldown: float = 3.0
@export var jump_attack_cooldown: float = 2.0

@export var attack_range: float = 45.0
@export var approach_range: float = 40.0
@export var danger_range: float = 30.0

var state_data: Dictionary = {}

var in_danger := false
var can_attack := false
var is_cornered := false
var opponent_attacking := false
var distance := 0.0
var input_dir := 0
var input_dir_timer := 0.0
var crouch_timer := 0.0
var recovery_timer := 0.0

var crouch_pressed := false
var jump_pressed := false
var attack_pressed := false
var spm1_pressed := false
var dash_pressed := false
var attack_type := "none"
var blockstun_duration := 0.2
var damage := 0.0

var opponent_recovery_time: float = 0.0
var opponent_stun_remaining: float = 0.0

func build_input_dict(dir: int, crouch: bool, jump: bool, attack: bool, atk_type: String, 
					blockstun: float, dmg: float, special: bool, dash: bool) -> Dictionary:
	return {
		"input_dir": dir,
		"crouch_pressed": crouch,
		"jump_pressed": jump,
		"attack_pressed": attack,
		"attack_type": atk_type,
		"blockstun_duration": blockstun,
		"damage": dmg,
		"spm1_pressed": special,
		"dash_pressed": dash
	}

func get_strategy() -> Dictionary:
	if not parent or not parent.healthbar:
		return {"aggressive": false, "defensive": false, "special": false, "cornered": false}
	
	var opponent = get_opponent()
	if not opponent or not opponent.healthbar:
		return {"aggressive": false, "defensive": false, "special": false, "cornered": false}
	
	var my_health = parent.healthbar.current_health / parent.healthbar.max_health
	var opp_health = opponent.healthbar.current_health / opponent.healthbar.max_health
	
	return {
		"aggressive": my_health > opp_health,
		"defensive": my_health < opp_health,
		"special": my_health < 0.5 and opp_health > 0.7,
		"cornered": is_cornered
	}

func check_hitbox_interaction(attacker: Node, target: Node, is_range_check := false) -> bool:
	if not target:
		return false
	
	var distance_val: float = abs(attacker.global_position.x - target.global_position.x)
	if is_range_check:
		return distance_val < attack_range
	
	if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
		return false
	
	var hitbox := attacker.get_node("Hitbox") as Area2D
	var hurtbox := target.get_node("Hurtbox") as Area2D
	
	for area in hitbox.get_overlapping_areas():
		if area == hurtbox and area.get_parent() != attacker:
			return true
	return false

func is_opponent_vulnerable_in_air(opponent: Node) -> bool:
	if not opponent:
		return false
	return not opponent.is_on_floor() and opponent.fixed_velocity.y > 0 and not opponent.is_air_attacking

func _ready():
	if parent:
		set_ai_enabled(true)
		state_timer = randf_range(0.8, 1.2)

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if enabled:
		current_state = AIState.APPROACH
		state_timer = randf_range(0.8, 1.2)

func _physics_process(delta):
	if not ai_enabled:
		return
	var opponent = get_opponent()
	if not opponent:
		return
	var parent_health = parent.healthbar.current_health if parent.healthbar else 100.0
	var opponent_health = opponent.healthbar.current_health if opponent.healthbar else 100.0
	if parent_health <= 0.0 or opponent_health <= 0.0:
		return
	
	update_timers(delta)
	update_ai_state(delta)

func update_ai_state(delta: float):
	var opponent = get_opponent()
	action_timer += delta
	state_timer -= delta
	if state_timer <= 0:
		choose_next_state(opponent)

	distance = abs(parent.global_position.x - opponent.global_position.x)
	can_attack = check_hitbox_interaction(parent, opponent, true)
	in_danger = check_hitbox_interaction(opponent, parent)
	opponent_attacking = opponent.is_attacking or opponent.is_dashing if opponent else false
	is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	
	if opponent:
		opponent_recovery_time = opponent.attack_timer if "attack_timer" in opponent else 0.0
		opponent_stun_remaining = max(opponent.hit_timer if "hit_timer" in opponent else 0.0, opponent.block_timer if "block_timer" in opponent else 0.0)
	
	if parent.is_hit or parent.is_knockfly:
		current_state = AIState.DEFEND
		set_timer("recovery", 0.5)
		set_timer("block", 0.5)
		set_timer("state", 0.5)
		state_data["forced_defense"] = true
		return
	
	var strategy = get_strategy()
	
	match current_state:
		AIState.IDLE:
			if action_timer > 0.3:
				var action_choice = randf_range(0.0, 1.0)
				if in_danger or (opponent_attacking and distance < 50.0):
					current_state = AIState.DEFEND
					set_timer("block", 0.5)
					set_timer("state", 0.5)
				elif can_attack and distance < attack_range and action_choice < 0.9:
					current_state = AIState.ATTACK
					state_data["normal_attack"] = true
				elif can_attack and distance < attack_range and should_use_special_move(opponent, distance):
					current_state = AIState.ATTACK
					state_data["use_special"] = true
				elif check_opponent_air_status(opponent):
					current_state = AIState.JUMP
					state_data["air_punish"] = true
				elif distance > attack_range:
					current_state = AIState.APPROACH
					state_timer = 0.8
				elif is_cornered and strategy.cornered:
					current_state = AIState.JUMP
					set_timer("state", 0.8)
					state_data["corner_escape"] = true
				else:
					state_timer = randf_range(0.4, 0.8)

		AIState.APPROACH:
			if action_timer > 0.3:
				if in_danger or (opponent_attacking and distance < danger_range):
					current_state = AIState.DEFEND
					block_timer = 0.5
					set_timer("state", 0.5)
				elif is_cornered and strategy.cornered:
					current_state = AIState.JUMP
					state_timer = 0.8
					state_data["corner_escape"] = true
				elif can_attack and get_timer("attack") <= 0:
					current_state = AIState.ATTACK
					set_timer("attack", normal_attack_cooldown)
				elif should_use_special_move(opponent, distance) and get_timer("special") <= 0:
					current_state = AIState.ATTACK
					set_timer("special", special_attack_cooldown)
				elif state_timer <= 0:
					if distance > attack_range:
						set_timer("state", randf_range(0.4, 0.8))
					else:
						current_state = AIState.ATTACK
						set_timer("state", 0.8)

		AIState.ATTACK:
			if in_danger or (opponent_attacking and distance < danger_range):
				current_state = AIState.DEFEND
				block_timer = 0.5
				set_timer("state", 0.5)
				return
			
			if distance > attack_range:
				current_state = AIState.APPROACH
				state_timer = randf_range(0.4, 0.8)
				return
			
			if opponent_stun_remaining > 0.15 and distance < 40.0 and attack_timer <= 0:
				attack_timer = normal_attack_cooldown
				state_timer = 0.8
				state_data["continue_combo"] = true
				return
			elif check_opponent_air_status(opponent) and randf_range(0.0, 1.0) < 0.7:
				current_state = AIState.JUMP
				state_timer = 0.8
				state_data["air_punish"] = true
			elif state_timer <= 0:
				if distance > attack_range:
					current_state = AIState.APPROACH
					state_timer = randf_range(0.4, 0.8)
				else:
					current_state = AIState.ATTACK
					state_timer = 0.8

		AIState.DEFEND:
			if recovery_timer <= 0 and block_timer <= 0:
				if not in_danger and (not opponent_attacking or distance > danger_range):
					if should_use_special_move(opponent, distance):
						current_state = AIState.ATTACK
						state_data["use_special"] = true
					elif can_attack:
						current_state = AIState.ATTACK
					else:
						current_state = AIState.APPROACH if distance > attack_range else AIState.ATTACK
						state_timer = randf_range(0.4, 0.8)
				elif opponent_stun_remaining > 0.1:
					current_state = AIState.ATTACK
					state_data["counter_hit"] = true

		AIState.JUMP:
			if state_timer <= 0 or opponent.is_jumping:
				current_state = AIState.APPROACH
				state_timer = randf_range(0.4, 0.8)
			elif in_danger or (opponent_attacking and distance < danger_range):
				current_state = AIState.DEFEND
				block_timer = 0.5
				set_timer("state", 0.5)
			elif is_cornered and strategy.cornered:
				state_timer = 0.8

	set_timer("action", action_timer + delta)

func get_ai_input(delta: float = 0.0) -> Dictionary:
	if not ai_enabled or not parent or not parent.healthbar:
		return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false, false)
	
	var opponent = get_opponent()
	if not opponent or parent.healthbar.current_health <= 0 or opponent.healthbar.current_health <= 0:
		return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false, false)
	
	distance = abs(parent.global_position.x - opponent.global_position.x)
	var strategy = get_strategy()
	
	opponent_attacking = opponent.is_attacking or opponent.is_dashing
	can_attack = check_hitbox_interaction(parent, opponent, true)
	in_danger = check_hitbox_interaction(opponent, parent)
	is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	
	if opponent:
		opponent_recovery_time = opponent.attack_timer if "attack_timer" in opponent else 0.0
		opponent_stun_remaining = max(opponent.hit_timer if "hit_timer" in opponent else 0.0, opponent.block_timer if "block_timer" in opponent else 0.0)
	
	if parent.is_hit or parent.is_knockfly or block_timer > 0:
		input_dir = sign(opponent.global_position.x - parent.global_position.x) * -1
		crouch_pressed = (opponent.is_crouching and opponent_attacking) or (parent.is_hit and randf_range(0.0, 1.0) > 0.7)
		if crouch_pressed:
			crouch_timer = 0.2
		return build_input_dict(input_dir, crouch_pressed, false, false, "none", 0.2, 0.0, false, false)
	
	input_dir = 0
	if distance > attack_range:
		input_dir = sign(opponent.global_position.x - parent.global_position.x)
	elif distance < danger_range:
		input_dir = 0 if can_attack else sign(opponent.global_position.x - parent.global_position.x) * -1
	else:
		input_dir = 0
	
	if in_danger and distance < danger_range:
		input_dir = sign(opponent.global_position.x - parent.global_position.x) * -1
	
	if input_dir_timer <= 0:
		input_dir_timer = 0.4
	
	crouch_pressed = false
	jump_pressed = false
	attack_pressed = false
	spm1_pressed = false
	dash_pressed = false
	attack_type = "none"
	damage = 0.0
	
	match current_state:
		AIState.IDLE:
			if can_attack and get_timer("attack") <= 0:
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				set_timer("attack", normal_attack_cooldown)
			elif should_use_special_move(opponent, distance) and get_timer("special") <= 0:
				spm1_pressed = true
				damage = 20.0
				set_timer("special", special_attack_cooldown)
		
		AIState.DEFEND:
			crouch_pressed = opponent.is_crouching or randf_range(0.0, 1.0) > 0.7
			if strategy.cornered and randf_range(0.0, 1.0) > 0.6:
				jump_pressed = true
				crouch_pressed = false
	
		AIState.APPROACH:
			if distance > 80.0 and get_timer("dash") <= 0:
				dash_pressed = true
				set_timer("dash", 1.0)
			elif can_attack and get_timer("attack") <= 0:
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				set_timer("attack", normal_attack_cooldown)
			elif should_use_special_move(opponent, distance) and get_timer("special") <= 0:
				spm1_pressed = true
				damage = 20.0
				set_timer("special", special_attack_cooldown)
			if is_cornered and strategy.cornered:
				input_dir *= -1
				if randf_range(0.0, 1.0) > 0.5:
					jump_pressed = true
		
		AIState.ATTACK:
			if not check_combat_status(parent, opponent, "range"):
				current_state = AIState.APPROACH
				state_timer = 0.8
			else:
				if check_opponent_air_status(opponent) and randf_range(0.0, 1.0) > 0.5:
					jump_pressed = true
					attack_pressed = true
					damage = 10.0
					attack_type = "attack"
					set_timer("jump_attack", jump_attack_cooldown)
				elif get_timer("attack") <= 0:
					attack_pressed = true
					damage = 10.0
					attack_type = "attack"
					set_timer("attack", normal_attack_cooldown)
				elif get_timer("special") <= 0 and state_data.get("use_special", false):
					spm1_pressed = true
					damage = 20.0
					set_timer("special", special_attack_cooldown)
		
		AIState.JUMP:
			jump_pressed = true
			input_dir = -1 if state_data.get("corner_escape", false) else sign(opponent.global_position.x - parent.global_position.x)
			if is_opponent_vulnerable_in_air(opponent) and randf_range(0.0, 1.0) < 0.6:
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				set_timer("jump_attack", jump_attack_cooldown)
	
	if strategy.aggressive and can_attack and distance < attack_range and get_timer("attack") <= 0:
		attack_pressed = true
		damage = 10.0
		attack_type = "attack"
		set_timer("attack", normal_attack_cooldown)
	
	if check_opponent_air_status(opponent) and can_attack:
		jump_pressed = true
		attack_pressed = true
		damage = 10.0
		attack_type = "attack"
		crouch_pressed = false
		set_timer("jump_attack", jump_attack_cooldown)
	
	return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed, dash_pressed)

func check_combat_status(attacker: Node, target: Node, check_type: String = "") -> bool:
	if not target:
		return false
	match check_type:
		"hitbox":
			if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
				return false
			var hitbox = attacker.get_node("Hitbox") as Area2D
			var hurtbox = target.get_node("Hurtbox") as Area2D
			for area in hitbox.get_overlapping_areas():
				if area == hurtbox and area.get_parent() != attacker:
					return true
			return false
		"range":
			return abs(attacker.global_position.x - target.global_position.x) < attack_range
		"air":
			return not target.is_on_floor() and not target.is_air_attacking and target.fixed_velocity.y > 0
		"landing":
			return target.is_landing and target.landing_lock_timer > 0
		_:
			return false

func should_use_special_move(opponent: Node, dist_to_target: float) -> bool:
	if get_timer("special") > 0:
		return false
		
	var strategy = get_strategy()
	var opponent_vulnerable = opponent.is_hit or opponent.is_knockfly or opponent.is_landing
	opponent_attacking = opponent.is_attacking or opponent.is_air_attacking
	
	return (
		(opponent_vulnerable and dist_to_target < 60.0) or
		(opponent_attacking and dist_to_target < 50.0 and strategy.aggressive) or
		(strategy.special and dist_to_target < 80.0 and randf_range(0.0, 1.0) > 0.6) or
		(dist_to_target < attack_range and randf_range(0.0, 1.0) > 0.7)
	)

func check_opponent_air_status(opponent: Node) -> bool:
	if not opponent:
		return false
	return not opponent.is_on_floor() and not opponent.is_air_attacking and opponent.fixed_velocity.y > 0

func choose_next_state(opponent: Node) -> void:
	distance = abs(parent.global_position.x - opponent.global_position.x)
	var strategy = get_strategy()
	
	if check_combat_status(opponent, parent, "hitbox"):
		current_state = AIState.DEFEND
		state_timer = 0.5
	elif distance > attack_range:
		current_state = AIState.APPROACH
		state_timer = 0.8
	elif can_attack and distance <= attack_range:
		current_state = AIState.ATTACK
		state_timer = 0.8
	elif check_combat_status(opponent, parent, "air"):
		current_state = AIState.JUMP
		state_timer = 0.8
	elif strategy.aggressive:
		current_state = AIState.ATTACK
		state_timer = 0.8
	else:
		current_state = AIState.IDLE
		state_timer = randf_range(0.4, 0.8)

func update_timers(delta: float) -> void:
	for key in timers.keys():
		timers[key] = max(0.0, timers[key] - delta)
	recovery_timer = max(0.0, recovery_timer - delta)
	block_timer = max(0.0, block_timer - delta)
	crouch_timer = max(0.0, crouch_timer - delta)
	attack_timer = max(0.0, attack_timer - delta)
	special_timer = max(0.0, special_timer - delta)
	jump_attack_timer = max(0.0, jump_attack_timer - delta)
	input_dir_timer = max(0.0, input_dir_timer - delta)

func set_timer(timer_name: String, duration: float) -> void:
	if timer_name == "state":
		state_timer = duration
	elif timer_name == "attack":
		attack_timer = duration
	elif timer_name == "special":
		special_timer = duration
	elif timer_name == "jump_attack":
		jump_attack_timer = duration
	elif timer_name in timers:
		timers[timer_name] = duration

func get_timer(timer_name: String) -> float:
	if timer_name == "state":
		return state_timer
	if timer_name == "attack":
		return attack_timer
	if timer_name == "special":
		return special_timer
	if timer_name == "jump_attack":
		return jump_attack_timer
	return timers.get(timer_name, 0.0)

func get_opponent() -> Node:
	var all_players = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != parent:
			return p
	return null
