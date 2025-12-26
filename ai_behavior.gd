# ai_behavior.gd
class_name AIBehavior extends Node

@export var reaction_delay: float = 0.4
@export var attack_decision_delay: float = 0.3
@export var defend_decision_delay: float = 0.3
@export var global_jump_chance: float = 0.01
@export var p1_dp_chance: float = 0.15

# 遠距離火球相關參數
@export var fireball_distance: float = 400.0
@export var fireball_chance: float = 0.4

# 格擋參數
@export var block_distance: float = 80.0
@export var block_chance: float = 0.85
@export var crouch_block_chance: float = 0.5

# Dash / Backdash 機率調整
@export var dash_chance_far: float = 0.75      # 距離 > 200 時前衝機率
@export var backdash_chance_close: float = 0.65 # 距離 < 70 時後退衝刺機率
@export var dash_intent_duration: float = 0.25 # 持續輸出方向時間（秒），確保雙擊成功

# 後備攻擊範圍
var fallback_attack_ranges: Dictionary = {
	"st_mp": 65.0,
	"st_mk": 85.0,
	"cr_mp": 60.0,
	"cr_mk": 80.0,
	"spm1": 100.0,
	"spm2": 450.0,
	"dp": 75.0,
	"super": 120.0
}

var ai_enabled: bool = false
var opponent: Node = null
var decision_timer: float = 0.0
var attack_decision_timer: float = 0.0
var defend_decision_timer: float = 0.0
var state_timer: float = 0.0 : set = _set_state_timer
var random_action_chance: float = 0.35
var parent: Node
var opponent_search_timer: float = 0.0
var world: Node = null

# 懲罰反擊
var punish_timer: float = 0.0
var punish_opportunity: bool = false
var punish_attack: String = "st_mk"

# 狀態機
var current_state: String = "idle"
var previous_state: String = ""
var current_attack: String = "none"
var current_crouch: bool = false
var cancel_window_timer_ai: float = 0.0

# 新增：dash 意圖管理（關鍵修正）
var dash_intent_timer: float = 0.0
var dash_intent_dir: int = 0  # 0=無, 1=前衝, -1=後退衝刺

# FrameBar 與 AttackData 引用
var opponent_framebar: Node = null
var my_framebar: Node = null
var opponent_attack_data: AttackData = null

# 防重複列印追蹤
var _last_logged_state: String = ""
var _last_logged_dir: int = 999
var _last_logged_jump_attack: bool = false
var _last_logged_corner_escape: bool = false
var _last_logged_aerial_attack: bool = false
var _last_logged_attack_choice: String = ""
var _last_logged_punish: bool = false
var _last_logged_dp: bool = false
var _last_logged_cancel: bool = false
var _last_logged_fireball: bool = false

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
	
	if parent.player_id == "p1":
		opponent_attack_data = load("res://p2_attack_data.tres") as AttackData
	else:
		opponent_attack_data = load("res://p1_attack_data.tres") as AttackData
	
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		if parent.player_id == "p1":
			opponent_framebar = ui.get_node("FrameBarP2")
			my_framebar = ui.get_node("FrameBarP1")
		else:
			opponent_framebar = ui.get_node("FrameBarP1")
			my_framebar = ui.get_node("FrameBarP2")
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
	
	# 更新 dash 意圖計時器
	if dash_intent_timer > 0:
		dash_intent_timer -= delta
		if dash_intent_timer <= 0:
			dash_intent_timer = 0.0
			dash_intent_dir = 0
	
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

func get_current_hitbox_range() -> float:
	var hitbox_node = parent.get_node_or_null("Hitbox/HitShape")
	if not hitbox_node or hitbox_node.disabled:
		return 0.0
	var shape = hitbox_node.shape
	if not shape:
		return 0.0
	var facing = 1 if parent.scale.x > 0 else -1
	var local_offset = hitbox_node.position.x * facing
	var extent: float = 0.0
	if shape is RectangleShape2D:
		extent = shape.size.x / 2.0
	elif shape is CapsuleShape2D or shape is CircleShape2D:
		extent = shape.radius if shape.has("radius") else shape.height / 2.0
	return abs(local_offset) + extent

func can_current_attack_hit_opponent() -> float:
	if not opponent:
		return -1.0
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var my_range = get_current_hitbox_range()
	if my_range <= 0.0:
		return -1.0
	return my_range - distance + 20.0

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
		elif move_set.is_spnk: attack = "spnk"
		elif move_set.is_dp: attack = "dp"
		elif move_set.is_fireball: attack = "fireball"
		elif move_set.is_super: attack = "super"
	var recovery = _get_opponent_recovery(attack)
	var blockstun = _get_opponent_blockstun(attack)
	var advantage = blockstun - recovery
	print("[AI] %s 被 %s 的 %s block → advantage %.3f" % [parent.name, opponent.name, attack, advantage])
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

func is_at_left_corner() -> bool:
	if not world: return false
	var distance_to_left = parent.global_position.x - (world.arena_left / world.SIMULATION_SCALE)
	return distance_to_left <= 10.0

func is_at_right_corner() -> bool:
	if not world: return false
	var distance_to_right = (world.arena_right / world.SIMULATION_SCALE) - parent.global_position.x
	return distance_to_right <= 10.0

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
			"dp_pressed": false, "super_pressed": false,
			"dash_pressed": false, "backdash_pressed": false
		}
	
	var input: Dictionary = {
		"input_dir": 0, "crouch_pressed": false, "jump_pressed": false,
		"st_mp_pressed": false, "st_mk_pressed": false,
		"spm1_pressed": false, "spm2_pressed": false,
		"dp_pressed": false, "super_pressed": false,
		"block_pressed": false,
		"dash_pressed": false, "backdash_pressed": false
	}
	
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
	
	# 格擋判定
	var opponent_attacking: bool = opponent.is_attacking or (opponent.move_set and opponent.move_set.is_spmove)
	if opponent_attacking and distance <= block_distance and current_state != "attack":
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
			current_state = "defend" if r < 0.6 else ("approach" if r < 0.8 else "attack")
		else:
			current_state = "defend" if r < 0.65 else ("attack" if r < 0.85 else "approach")
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
	
	# 攻擊選擇
	if current_state == "attack":
		attack_decision_timer -= get_process_delta_time()
		if attack_decision_timer <= 0:
			attack_decision_timer = attack_decision_delay + randf_range(0.0, 0.2)
			
			if distance > fireball_distance and randf() < fireball_chance and not _last_logged_fireball:
				current_attack = "fireball"
				print("Debug: %s 遠距離發射火球！距離 %.1f" % [parent.name, distance])
				_last_logged_fireball = true
			elif _last_logged_fireball:
				_last_logged_fireball = false
			
			elif can_current_attack_hit_opponent() > 0:
				print("Debug: %s 活躍 Hitbox 可打到對手，繼續壓制" % parent.name)
			
			else:
				var possible_attacks: Array[String] = []
				for attack in fallback_attack_ranges.keys():
					if distance <= fallback_attack_ranges[attack] + 30:
						if attack == "dp" and parent.player_id != "p1": continue
						if attack == "spm2" and distance < 200: continue
						possible_attacks.append(attack)
				
				if possible_attacks.size() > 0:
					current_attack = possible_attacks.pick_random()
				else:
					current_attack = "st_mp"
				
				if current_attack != _last_logged_attack_choice:
					print("Debug: %s 攻擊選擇 → %s (距離 %.1f)" % [parent.name, current_attack, distance])
					_last_logged_attack_choice = current_attack
	
	# 防守時蹲下
	if current_state == "defend":
		defend_decision_timer -= get_process_delta_time()
		if defend_decision_timer <= 0:
			defend_decision_timer = defend_decision_delay + randf_range(0.0, 0.2)
			current_crouch = randf() < 0.65
	
	# 決定是否要 dash / backdash（只在沒有意圖時重新決定）
	if parent.is_on_floor() and dash_intent_timer <= 0:
		if distance > 200 and randf() < dash_chance_far:
			dash_intent_dir = 1
			dash_intent_timer = dash_intent_duration
			print("Debug: %s 決定遠距離前衝 (dash)" % parent.name)
		elif distance < 70 and randf() < backdash_chance_close:
			dash_intent_dir = -1
			dash_intent_timer = dash_intent_duration
			print("Debug: %s 決定近距離後退衝刺 (backdash)" % parent.name)
	
	# 根據意圖持續輸出方向，讓 PlayerController 偵測到雙擊
	if dash_intent_timer > 0:
		if dash_intent_dir == 1:
			input.input_dir = int(relative_dir)
		elif dash_intent_dir == -1:
			input.input_dir = -int(relative_dir)
	
	# 跳躍攻擊與角落逃脫
	var jump_for_attack = can_jump_attack_hit() and randf() < 0.55 and parent.is_on_floor()
	var corner_escape = (is_at_left_corner() or is_at_right_corner()) and randf() < 0.2 and parent.is_on_floor()
	
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
	
	# 狀態對應基本移動（被 dash 意圖覆蓋優先）
	match current_state:
		"approach":
			if dash_intent_timer <= 0:
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
				"fireball": input.spm2_pressed = true
		"defend":
			if dash_intent_timer <= 0:
				input.input_dir = -int(relative_dir)
			input.block_pressed = true
			input.crouch_pressed = current_crouch
			_log_state(current_state, input.input_dir)
		"idle":
			_log_state(current_state, input.input_dir)
	
	# 空中攻擊
	if not parent.is_on_floor() and parent.velocity.y > 0 and distance < 80:
		if randf() < 0.7 and not _last_logged_aerial_attack:
			input.st_mp_pressed = randf() < 0.5
			input.st_mk_pressed = not input.st_mp_pressed
			print("Debug: %s 空中攻擊觸發" % parent.name)
			_last_logged_aerial_attack = true
	elif parent.is_on_floor():
		_last_logged_aerial_attack = false
	
	# 取消連招與 P1 近距離 DP
	if cancel_window_timer_ai > 0 and not _last_logged_cancel:
		input.spm1_pressed = true
		print("Debug: %s 取消連招" % parent.name)
		_last_logged_cancel = true
	elif cancel_window_timer_ai <= 0:
		_last_logged_cancel = false
	
	if parent.player_id == "p1" and distance < 50 and randf() < p1_dp_chance and parent.is_on_floor() and not _last_logged_dp:
		input.dp_pressed = true
		current_attack = "dp"
		print("Debug: AI P1 近距離升龍拳！")
		_last_logged_dp = true
	elif not (distance < 50 and parent.is_on_floor()):
		_last_logged_dp = false
	
	var attack_type = "st_mp" if input.st_mp_pressed else "st_mk" if input.st_mk_pressed else "dp" if input.dp_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball or move_set.is_dp) else (10.0 if (input.st_mp_pressed or input.st_mk_pressed) else 0.0)
	
	input["attack_type"] = attack_type
	input["damage"] = damage
	return input
