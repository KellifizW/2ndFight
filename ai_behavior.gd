# ai_behavior.gd
class_name AIBehavior extends Node

@export var reaction_delay: float = 0.4
@export var attack_decision_delay: float = 0.3
@export var defend_decision_delay: float = 0.3
@export var global_jump_chance: float = 0.01
@export var p1_dp_chance: float = 0.15

# 格擋參數
@export var block_distance: float = 80.0
@export var block_chance: float = 0.85  # 提高格擋機率
@export var crouch_block_chance: float = 0.5  # 提高蹲防機率

var ai_enabled: bool = false
var opponent: Node = null
var decision_timer: float = 0.0
var attack_decision_timer: float = 0.0
var defend_decision_timer: float = 0.0
var state_timer: float = 0.0 : set = _set_state_timer
var last_action_time: float = 0.0
var random_action_chance: float = 0.25
var parent: Node
var opponent_search_timer: float = 0.0
var world: Node = null

# 懲罰反擊
var punish_timer: float = 0.0
var last_blockstun_duration: float = 0.0
var punish_opportunity: bool = false
var punish_attack: String = "st_mk"

# 狀態機
var current_state: String = "idle"
var previous_state: String = ""
var current_attack: String = "none"
var current_crouch: bool = false

# frame data
var frame_data: Dictionary = {
	"p1": {
		"st_mp": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.267},
		"st_mk": {"startup": 0.2, "recovery": 0.4003, "blockstun": 0.3},
		"cr_mp": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.267},
		"cr_mk": {"startup": 0.2, "recovery": 0.4003, "blockstun": 0.3},
		"jump_mp": {"startup": 0.1333, "recovery": 0.2, "blockstun": 0.267},
		"jump_mk": {"startup": 0.1, "recovery": 0.3, "blockstun": 0.267},
		"powerkk": {"startup": 0.3, "recovery": 0.5, "blockstun": 0.267},
		"fireball": {"startup": 0.3, "recovery": 0.4667, "blockstun": 0.267}
	},
	"p2": {
		"st_mp": {"startup": 0.2, "recovery": 0.3667, "blockstun": 0.267},
		"st_mk": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.3},
		"cr_mp": {"startup": 0.2, "recovery": 0.3667, "blockstun": 0.267},
		"cr_mk": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.3},
		"jump_mp": {"startup": 0.1, "recovery": 0.2333, "blockstun": 0.267},
		"jump_mk": {"startup": 0.1, "recovery": 0.267, "blockstun": 0.267},
		"spnk": {"startup": 0.2, "recovery": 0.4667, "blockstun": 0.267},
		"fireball": {"startup": 0.3, "recovery": 0.3667, "blockstun": 0.267}
	}
}

var cancel_window_timer_ai: float = 0.0

func _ready() -> void:
	parent = get_parent()
	world = get_tree().get_first_node_in_group("world")
	if parent:
		if parent.player_id == "p1":
			punish_attack = "st_mp"
		else:
			punish_attack = "st_mk"
		if parent.has_signal("hit_detected"):
			parent.hit_detected.connect(_on_self_hit_detected)
	else:
		print("Warning: AIBehavior parent not found")
	opponent_search_timer = 0.1

func _process(delta: float) -> void:
	if not opponent and opponent_search_timer > 0:
		opponent_search_timer -= delta
		if opponent_search_timer <= 0:
			find_opponent()
			opponent_search_timer = 0.5
	
	if punish_timer > 0:
		punish_timer -= delta
		if punish_timer <= 0:
			punish_timer = 0.0
			punish_opportunity = true
	
	if cancel_window_timer_ai > 0:
		cancel_window_timer_ai -= delta
		if cancel_window_timer_ai <= 0:
			cancel_window_timer_ai = 0.0

	# === 修正：血量為零時完全停用 AI ===
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		var parent_healthbar = ui.get_node_or_null("%sHealthbar" % parent.name)
		var opponent_healthbar = ui.get_node_or_null("%sHealthbar" % opponent.name) if opponent else null
		var parent_health = parent_healthbar.current_health if parent_healthbar else 100
		var opponent_health = opponent_healthbar.current_health if opponent_healthbar else 100
		if parent_health <= 0 or opponent_health <= 0:
			ai_enabled = false
			return  # 直接結束本幀處理，停止所有 AI 行為

func _set_state_timer(value: float) -> void:
	decision_timer = value

func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	if ai_enabled:
		print("AI enabled for %s" % parent.name)
	else:
		print("AI disabled for %s" % parent.name)
		current_state = "idle"
		current_attack = "none"
		current_crouch = false

func find_opponent() -> void:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != parent:
			opponent = player
			print("AI opponent found: %s for %s" % [opponent.name, parent.name])
			if opponent.has_signal("hit_detected"):
				opponent.hit_detected.connect(_on_hit_detected)
			return
	print("Warning: No opponent found for %s" % parent.name)

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool) -> void:
	if not ai_enabled: return
	if opponent and is_blocked and target == parent.name:
		var opponent_attack = opponent.attack_type if "attack_type" in opponent else "st_mp"
		var move_set = opponent.get_node("MoveSet") if opponent.has_node("MoveSet") else null
		if move_set:
			if move_set.is_powerkk: opponent_attack = "powerkk"
			elif move_set.is_spnk: opponent_attack = "spnk"
			elif move_set.is_fireball: opponent_attack = "fireball"
			elif move_set.is_super: opponent_attack = "super"
			elif move_set.is_dp: opponent_attack = "dp"
		var recovery = frame_data[opponent.player_id].get(opponent_attack, {}).get("recovery", 0.4)
		var blockstun = frame_data[opponent.player_id].get(opponent_attack, {}).get("blockstun", 0.267)
		var advantage = blockstun - recovery
		print("Debug: %s blocked %s's %s, advantage: %.2f" % [parent.name, opponent.name, opponent_attack, advantage])
		punish_timer = blockstun
		last_blockstun_duration = blockstun
		punish_attack = _select_punish_attack(advantage)

func _select_punish_attack(advantage: float) -> String:
	var available_attacks = frame_data[parent.player_id]
	var best_attack: String = ""
	var best_startup: float = INF
	for attack in available_attacks:
		var startup = available_attacks[attack]["startup"]
		if startup < best_startup and startup <= advantage:
			best_startup = startup
			best_attack = attack
	return best_attack if best_attack else "st_mp"

func _on_self_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool) -> void:
	if parent.player_id == "p1" and parent.attack_type == "st_mp" and not is_blocked:
		cancel_window_timer_ai = 0.3
		print("Debug: AI P1 st_mp hit detected, cancel window started")

func is_at_left_corner() -> bool:
	if not world: return false
	var distance_to_left = parent.global_position.x - (world.arena_left / world.SIMULATION_SCALE)
	return distance_to_left <= 10.0

func is_at_right_corner() -> bool:
	if not world: return false
	var distance_to_right = (world.arena_right / world.SIMULATION_SCALE) - parent.global_position.x
	return distance_to_right <= 10.0

func is_near_left_corner() -> bool:
	if not world: return false
	var distance_to_left = parent.global_position.x - (world.arena_left / world.SIMULATION_SCALE)
	return distance_to_left <= 50.0

func is_near_right_corner() -> bool:
	if not world: return false
	var distance_to_right = (world.arena_right / world.SIMULATION_SCALE) - parent.global_position.x
	return distance_to_right <= 50.0

func can_jump_attack_hit() -> bool:
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var opponent_on_ground = opponent.is_on_floor() if opponent.has_method("is_on_floor") else true
	return distance >= 40 and distance <= 70 and opponent_on_ground

func get_ai_input() -> Dictionary:
	if not ai_enabled or not opponent:
		var default_input: Dictionary = {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"st_mp_pressed": false,
			"st_mk_pressed": false,
			"spm1_pressed": false,
			"spm2_pressed": false,
			"dp_pressed": false,
			"super_pressed": false
		}
		return default_input
	
	var input: Dictionary = {
		"input_dir": 0,
		"crouch_pressed": false,
		"jump_pressed": false,
		"st_mp_pressed": false,
		"st_mk_pressed": false,
		"spm1_pressed": false,
		"spm2_pressed": false,
		"dp_pressed": false,
		"super_pressed": false,
		"block_pressed": false
	}
	
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
	var is_at_corner = is_at_left_corner() or is_at_right_corner()
	var is_near_corner = is_near_left_corner() or is_near_right_corner()
	
	# 格擋判定（最優先）
	var opponent_attacking: bool = (
		opponent.is_attacking or
		(opponent.move_set and opponent.move_set.is_spmove)
	)
	if (opponent_attacking and distance <= block_distance and
		current_state != "attack" and not input.spm1_pressed and not input.dp_pressed):
		if randf() < block_chance:
			input.block_pressed = true
			input.input_dir = -int(relative_dir)
			input.crouch_pressed = randf() < crouch_block_chance
	
	# 狀態切換（大幅提高防守機率）
	decision_timer -= get_process_delta_time()
	if decision_timer <= 0:
		decision_timer = reaction_delay + randf_range(0.0, 0.2)
		previous_state = current_state
		var rand_state = randf()
		if distance > 100:
			# 遠距離：防守 70%
			if rand_state < 0.7: current_state = "defend"
			elif rand_state < 0.85: current_state = "approach"
			elif rand_state < 0.95: current_state = "attack"
			else: current_state = "idle"
		else:
			# 近距離：防守 65%
			if rand_state < 0.65: current_state = "defend"
			elif rand_state < 0.8: current_state = "attack"
			elif rand_state < 0.95: current_state = "approach"
			else: current_state = "idle"
		if previous_state != current_state:
			print("Debug: %s state changed to %s" % [parent.name, current_state])
	
	# 懲罰反擊
	if punish_opportunity:
		current_state = "attack"
		if parent.player_id == "p1" and randf() < 0.5:
			current_attack = "dp"
			input.dp_pressed = true
		else:
			current_attack = punish_attack
		punish_opportunity = false
		print("Debug: Punish opportunity triggered, attacking with %s" % current_attack)
	
	# 攻擊選擇
	if current_state == "attack":
		attack_decision_timer -= get_process_delta_time()
		if attack_decision_timer <= 0:
			attack_decision_timer = attack_decision_delay + randf_range(0.0, 0.2)
			if is_at_corner:
				if randf() < 0.7:
					current_attack = "spm1"
				else:
					current_attack = punish_attack
			elif distance < 30:
				if randf() < 0.5:
					current_attack = punish_attack
				else:
					current_attack = "cr_mp" if parent.player_id == "p2" else "cr_mk"
			else:
				if randf() < random_action_chance:
					match randi() % 6:
						0: current_attack = "st_mk"
						1: current_attack = "spm1"
						2: current_attack = "spm2"
						3: current_attack = "cr_mp"
						4: current_attack = "cr_mk"
						5:
							if parent.player_id == "p1":
								current_attack = "dp"
								input.dp_pressed = true
				else:
					current_attack = "spm1"
			print("Debug: %s in attack, selected: %s" % [parent.name, current_attack])
	
	# 防守蹲下
	if current_state == "defend":
		defend_decision_timer -= get_process_delta_time()
		if defend_decision_timer <= 0:
			defend_decision_timer = defend_decision_delay + randf_range(0.0, 0.2)
			current_crouch = randf() < 0.7  # 防守時更常蹲下
			if is_near_corner:
				current_crouch = randf() < 0.4
			print("Debug: %s in defend, crouch: %s" % [parent.name, "true" if current_crouch else "false"])
	
	# === 嚴格控制跳躍：僅反擊 + 角落逃脫 ===
	var jump_for_attack = can_jump_attack_hit() and randf() < 0.4 and parent.is_on_floor()
	var corner_escape = is_at_corner and randf() < 0.15 and parent.is_on_floor()
	
	if jump_for_attack:
		input.jump_pressed = true
		input.input_dir = int(relative_dir)
		if randf() < 0.6:
			input.st_mp_pressed = true
		else:
			input.st_mk_pressed = true
		print("Debug: Jump attack triggered (can hit), distance=%.1f" % distance)
	elif corner_escape:
		input.jump_pressed = true
		input.input_dir = -int(relative_dir)
		print("Debug: Corner escape jump triggered")
	
	# 狀態動作
	match current_state:
		"approach":
			input.input_dir = int(relative_dir)
			print("Debug: %s in approach, input_dir: %d" % [parent.name, input.input_dir])
		"attack":
			match current_attack:
				"st_mp": input.st_mp_pressed = true
				"st_mk": input.st_mk_pressed = true
				"cr_mp":
					input.crouch_pressed = true
					input.st_mp_pressed = true
				"cr_mk":
					input.crouch_pressed = true
					input.st_mk_pressed = true
				"spm1": input.spm1_pressed = true
				"spm2": input.spm2_pressed = true
				"dp": input.dp_pressed = true
		"defend":
			input.input_dir = -int(relative_dir)
			input.block_pressed = true  # 防守時持續格擋
			input.crouch_pressed = current_crouch
		"idle": pass
	
	# 空中攻擊（僅落地前）
	if not parent.is_on_floor() and parent.velocity.y > 0 and parent.global_position.y < 50:
		if distance < 50 and randf() < 0.3:
			if randf() < 0.5:
				input.st_mp_pressed = true
			else:
				input.st_mk_pressed = true
			print("Debug: Aerial attack near landing")
	
	# 取消窗口連招
	if cancel_window_timer_ai > 0:
		input.spm1_pressed = true
		input.st_mp_pressed = false
		input.st_mk_pressed = false
		input.spm2_pressed = false
		input.dp_pressed = false
		print("Debug: AI P1 cancel combo")
	
	# P1 近距離 DP
	if parent.player_id == "p1" and (current_state == "attack" or current_state == "defend") and distance < 50 and randf() < p1_dp_chance and parent.is_on_floor():
		input.dp_pressed = true
		current_attack = "dp"
		input.st_mp_pressed = false
		input.st_mk_pressed = false
		input.spm1_pressed = false
		input.spm2_pressed = false
		print("Debug: AI P1 DP close range")
	
	# 輸出
	var attack_type = "st_mp" if input.st_mp_pressed else "st_mk" if input.st_mk_pressed else "dp" if input.dp_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var blockstun_duration = frame_data[parent.player_id].get(current_attack, {}).get("blockstun", 0.2)
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball or move_set.is_dp) else (10.0 if (input.st_mp_pressed or input.st_mk_pressed) else 0.0)
	
	input["attack_type"] = attack_type
	input["blockstun_duration"] = blockstun_duration
	input["damage"] = damage
	return input
