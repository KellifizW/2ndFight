# ai_behavior.gd
class_name AIBehavior extends Node

@export var reaction_delay: float = 0.4
@export var attack_decision_delay: float = 0.3
@export var defend_decision_delay: float = 0.3
@export var global_jump_chance: float = 0.01
@export var p1_dp_chance: float = 0.15

# 新增：P2 使用 HDK 的機率（可自行調整）
@export var p2_hdk_chance: float = 0.25          
@export var p2_hdk_corner_chance: float = 0.40   

# 格擋參數
@export var block_distance: float = 80.0
@export var block_chance: float = 0.85
@export var crouch_block_chance: float = 0.5

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

var cancel_window_timer_ai: float = 0.0

# 新增：FrameBar 與 AttackData 引用
var opponent_framebar: Node = null      # 對手的 FrameBar (p1 → FrameBarP1, p2 → FrameBarP2)
var my_framebar: Node = null            # 自己的 FrameBar
var opponent_attack_data: AttackData = null

# 防重複列印用的追蹤變數
var _last_logged_state: String = ""
var _last_logged_dir: int = 999
var _last_logged_crouch: bool = false
var _last_logged_jump_attack: bool = false
var _last_logged_corner_escape: bool = false
var _last_logged_aerial_attack: bool = false
var _last_logged_attack_choice: String = ""
var _last_logged_punish: bool = false
var _last_logged_dp: bool = false
var _last_logged_cancel: bool = false
var _last_logged_hdk: bool = false        # 新增：防止 HDK 重複列印

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
	
	# 載入對手的 AttackData
	if parent.player_id == "p1":
		opponent_attack_data = load("res://p2_attack_data.tres") as AttackData
	else:
		opponent_attack_data = load("res://p1_attack_data.tres") as AttackData
	
	# 取得兩個 FrameBar
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		if parent.player_id == "p1":
			opponent_framebar = ui.get_node("FrameBarP2")
			my_framebar       = ui.get_node("FrameBarP1")
		else:
			opponent_framebar = ui.get_node("FrameBarP1")
			my_framebar       = ui.get_node("FrameBarP2")
	else:
		push_error("AIBehavior 找不到 UI 節點，FrameBar 無法連結")

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
	
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		var parent_healthbar = ui.get_node_or_null("%sHealthbar" % parent.name)
		var opponent_healthbar = ui.get_node_or_null("%sHealthbar" % opponent.name) if opponent else null
		var parent_health = parent_healthbar.current_health if parent_healthbar else 100
		var opponent_health = opponent_healthbar.current_health if opponent_healthbar else 100
		if parent_health <= 0 or opponent_health <= 0:
			ai_enabled = false
			return

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

# 從對手 FrameBar 取得 startup / recovery（秒）
func _get_opponent_startup(anim: String) -> float:
	if opponent_framebar and opponent_framebar.current_animation == anim and opponent_framebar.frame_data.size() > 0:
		var count = 0
		for s in opponent_framebar.frame_data:
			if s == 0: count += 1
		return count / 60.0
	return 0.2

func _get_opponent_recovery(anim: String) -> float:
	if opponent_framebar and opponent_framebar.current_animation == anim and opponent_framebar.frame_data.size() > 0:
		var count = 0
		for s in opponent_framebar.frame_data:
			if s == 2: count += 1
		return count / 60.0
	return 0.35

func _get_opponent_blockstun(anim: String) -> float:
	if opponent_attack_data and opponent_attack_data.has(anim):
		return opponent_attack_data[anim].get("blockstun", 0.267)
	return 0.267

func _on_hit_detected(_target: String, _stun_duration: float, is_blocked: bool, _was_in_stun: bool) -> void:
	if not ai_enabled or not is_blocked or _target != parent.name: return
	
	var attack = opponent.attack_type
	var move_set = opponent.get_node("MoveSet") if opponent.has_node("MoveSet") else null
	if move_set:
		if move_set.is_powerkk: attack = "powerkk"
		elif move_set.is_spnk:   attack = "spnk"
		elif move_set.is_dp:     attack = "dp"
		elif move_set.is_fireball: attack = "fireball"
		elif move_set.is_super:  attack = "super"
	
	var recovery  = _get_opponent_recovery(attack)
	var blockstun = _get_opponent_blockstun(attack)
	var advantage = blockstun - recovery
	
	print("[AI] %s 被 %s 的 %s block → advantage %.3f (blockstun %.3f - recovery %.3f)" % [
		parent.name, opponent.name, attack, advantage, blockstun, recovery
	])
	
	punish_timer = blockstun
	punish_opportunity = true
	
	if advantage >= 0.25:
		punish_attack = "dp" if parent.player_id == "p1" else "spnk"
	elif advantage >= 0.15:
		punish_attack = "st_mk"
	else:
		punish_attack = "st_mp"

func _on_self_hit_detected(_target: String, _stun_duration: float, is_blocked: bool, _was_in_stun: bool) -> void:
	if parent.player_id == "p1" and parent.attack_type == "st_mp" and not is_blocked:
		cancel_window_timer_ai = 0.3
		print("Debug: AI P1 st_mp hit detected, cancel window started")

# 其餘函式（角落判定、跳躍等）完全不變
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

func _log_state(state: String, dir: int) -> void:
	if state != _last_logged_state or dir != _last_logged_dir:
		print("Debug: %s state → %s, input_dir: %d" % [parent.name, state, dir])
		_last_logged_state = state
		_last_logged_dir = dir

func get_ai_input() -> Dictionary:
	if not ai_enabled or not opponent:
		return {
			"input_dir": 0, "crouch_pressed": false, "jump_pressed": false,
			"st_mp_pressed": false, "st_mk_pressed": false,
			"spm1_pressed": false, "spm2_pressed": false,
			"spm3_pressed": false,      # 新增 spm3 (HDK)
			"dp_pressed": false, "super_pressed": false
		}
	
	var input: Dictionary = {
		"input_dir": 0, "crouch_pressed": false, "jump_pressed": false,
		"st_mp_pressed": false, "st_mk_pressed": false,
		"spm1_pressed": false, "spm2_pressed": false, "spm3_pressed": false,
		"dp_pressed": false, "super_pressed": false, "block_pressed": false
	}
	
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
	
	# 格擋判定
	var opponent_attacking: bool = opponent.is_attacking or (opponent.move_set and opponent.move_set.is_spmove)
	if opponent_attacking and distance <= block_distance and current_state != "attack" and not input.spm1_pressed and not input.dp_pressed and not input.spm3_pressed:
		if randf() < block_chance:
			input.block_pressed = true
			input.input_dir = -int(relative_dir)
			input.crouch_pressed = randf() < crouch_block_chance
	
	# 狀態切換
	decision_timer -= get_process_delta_time()
	if decision_timer <= 0:
		decision_timer = reaction_delay + randf_range(0.0, 0.2)
		previous_state = current_state
		var r = randf()
		if distance > 100:
			current_state = "defend" if r < 0.7 else ("approach" if r < 0.85 else ("attack" if r < 0.95 else "idle"))
		else:
			current_state = "defend" if r < 0.65 else ("attack" if r < 0.8 else ("approach" if r < 0.95 else "idle"))
		if previous_state != current_state:
			_log_state(current_state, input.input_dir)
	
	# 懲罰反擊
	if punish_opportunity and not _last_logged_punish:
		current_state = "attack"
		current_attack = punish_attack
		match current_attack:
			"st_mp": input.st_mp_pressed = true
			"st_mk": input.st_mk_pressed = true
			"dp": input.dp_pressed = true
			"spnk": input.spm1_pressed = true
		print("Debug: %s 懲罰反擊！使用 %s" % [parent.name, current_attack])
		_last_logged_punish = true
		punish_opportunity = false
	elif not punish_opportunity:
		_last_logged_punish = false
	
	# 攻擊選擇（重點新增 P2 HDK 邏輯）
	if current_state == "attack":
		attack_decision_timer -= get_process_delta_time()
		if attack_decision_timer <= 0:
			attack_decision_timer = attack_decision_delay + randf_range(0.0, 0.2)
			
			# === P2 專屬 HDK 判定 ===
			if parent.player_id == "p2":
				if is_at_left_corner() or is_at_right_corner():
					# 被壓角時 HDK 機率大幅提高
					if randf() < p2_hdk_corner_chance:
						current_attack = "hdk"
					else:
						current_attack = "spm1" if randf() < 0.7 else punish_attack
				elif distance < 50:
					# 近距離普通情況
					var r = randf()
					if r < p2_hdk_chance:
						current_attack = "hdk"
					elif r < p2_hdk_chance + 0.3:
						current_attack = "spm1"      # spnk
					else:
						current_attack = "st_mk"
				else:
					# 遠距離沿用原本邏輯
					if randf() < random_action_chance:
						match randi() % 6:
							0: current_attack = "st_mk"
							1: current_attack = "spm1"
							2: current_attack = "spm2"
							3: current_attack = "cr_mp"
							4: current_attack = "cr_mk"
					else:
						current_attack = "spm1"
			else:
				# P1 保持原邏輯
				if is_at_left_corner() or is_at_right_corner():
					current_attack = "spm1" if randf() < 0.7 else punish_attack
				elif distance < 30:
					current_attack = punish_attack if randf() < 0.5 else ("cr_mp" if parent.player_id == "p2" else "cr_mk")
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
			
			if current_attack != _last_logged_attack_choice:
				print("Debug: %s 攻擊選擇 → %s" % [parent.name, current_attack])
				_last_logged_attack_choice = current_attack
	
	# 防守蹲下
	if current_state == "defend":
		defend_decision_timer -= get_process_delta_time()
		if defend_decision_timer <= 0:
			defend_decision_timer = defend_decision_delay + randf_range(0.0, 0.2)
			var new_crouch = randf() < (0.4 if (is_near_left_corner() or is_near_right_corner()) else 0.7)
			if new_crouch != _last_logged_crouch:
				current_crouch = new_crouch
				print("Debug: %s 防守蹲下: %s" % [parent.name, "true" if current_crouch else "false"])
				_last_logged_crouch = current_crouch
	
	# 跳躍、空中攻擊、取消連招、P1近距離DP 等其餘邏輯完全保留
	var jump_for_attack = can_jump_attack_hit() and randf() < 0.4 and parent.is_on_floor()
	var corner_escape = (is_at_left_corner() or is_at_right_corner()) and randf() < 0.15 and parent.is_on_floor()
	
	if jump_for_attack and not _last_logged_jump_attack:
		input.jump_pressed = true
		input.input_dir = int(relative_dir)
		input.st_mp_pressed = randf() < 0.6
		input.st_mk_pressed = not input.st_mp_pressed
		print("Debug: %s 跳躍攻擊觸發 (距離 %.1f)" % [parent.name, distance])
		_last_logged_jump_attack = true
	elif not jump_for_attack:
		_last_logged_jump_attack = false
	
	if corner_escape and not _last_logged_corner_escape:
		input.jump_pressed = true
		input.input_dir = -int(relative_dir)
		print("Debug: %s 角落逃脫跳躍" % parent.name)
		_last_logged_corner_escape = true
	elif not corner_escape:
		_last_logged_corner_escape = false
	
	match current_state:
		"approach":
			input.input_dir = int(relative_dir)
			_log_state(current_state, input.input_dir)
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
				"hdk":
					input.spm3_pressed = true
					if not _last_logged_hdk:
						print("Debug: %s 出 HDK！！！" % parent.name)
						_last_logged_hdk = true
		"defend":
			input.input_dir = -int(relative_dir)
			input.block_pressed = true
			input.crouch_pressed = current_crouch
			_log_state(current_state, input.input_dir)
		"idle":
			_log_state(current_state, input.input_dir)
	
	if not parent.is_on_floor() and parent.velocity.y > 0 and parent.global_position.y < 50:
		if distance < 50 and randf() < 0.3 and not _last_logged_aerial_attack:
			input.st_mp_pressed = randf() < 0.5
			input.st_mk_pressed = not input.st_mp_pressed
			print("Debug: %s 空中攻擊（落地前）" % parent.name)
			_last_logged_aerial_attack = true
	elif parent.is_on_floor():
		_last_logged_aerial_attack = false
		_last_logged_hdk = false   # 落地後重置 HDK 訊息旗標
	
	if cancel_window_timer_ai > 0 and not _last_logged_cancel:
		input.spm1_pressed = true
		input.st_mp_pressed = false
		input.st_mk_pressed = false
		input.spm2_pressed = false
		input.dp_pressed = false
		print("Debug: %s 取消連招" % parent.name)
		_last_logged_cancel = true
	elif cancel_window_timer_ai <= 0:
		_last_logged_cancel = false
	
	if parent.player_id == "p1" and (current_state == "attack" or current_state == "defend") and distance < 50 and randf() < p1_dp_chance and parent.is_on_floor() and not _last_logged_dp:
		input.dp_pressed = true
		current_attack = "dp"
		input.st_mp_pressed = false
		input.st_mk_pressed = false
		input.spm1_pressed = false
		input.spm2_pressed = false
		print("Debug: AI P1 近距離升龍拳！")
		_last_logged_dp = true
	elif not (distance < 50 and parent.is_on_floor()):
		_last_logged_dp = false
	
	# attack_type 與 damage 判斷也支援 hdk
	var attack_type = "hdk" if input.spm3_pressed else "st_mp" if input.st_mp_pressed else "st_mk" if input.st_mk_pressed else "dp" if input.dp_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball or move_set.is_dp or move_set.is_hdk) else (10.0 if (input.st_mp_pressed or input.st_mk_pressed) else 0.0)
	
	input["attack_type"] = attack_type
	input["damage"] = damage
	return input
