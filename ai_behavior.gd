# ai_behavior.gd
class_name AIBehavior extends Node

@export var reaction_delay: float = 0.4  # 狀態思考冷卻（保留，防止瘋狂切換）
@export var attack_decision_delay: float = 0.15  # 加快攻擊選擇
@export var defend_decision_delay: float = 0.12  # 加快防守變化
@export var global_jump_chance: float = 0.01
@export var p1_dp_chance: float = 0.15

# 遠距離火球參數（完全無冷卻）
@export var fireball_distance: float = 350.0
@export var fireball_chance: float = 0.15

# 新增：火球格擋專用參數（超高機率+距離）
@export var fireball_block_distance: float = 400.0  # 遠距就開始後退
@export var fireball_block_chance: float = 0.98     # 幾乎必擋
@export var fireball_backdash_chance: float = 0.6   # 近火球機率後衝

# 格擋參數（降低過度防守）
@export var block_distance: float = 80.0
@export var block_chance: float = 0.7               # 降低格擋機率，避免過度退
@export var crouch_block_chance: float = 0.5

# Dash / Backdash 機率（適中）
@export var dash_chance_far: float = 0.35
@export var backdash_chance_close: float = 0.2
@export var dash_cooldown: float = 1.2

# 後備攻擊範圍（近距強攻）
var fallback_attack_ranges: Dictionary = {
	"st_mp": 75.0,
	"st_mk": 95.0,
	"cr_mp": 70.0,
	"cr_mk": 90.0,
	"spm1": 110.0,
	"spm2": 450.0,
	"dp": 85.0,
	"super": 130.0
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

# 待發招式
var pending_attack: String = ""

# 一次性 dash / backdash + 冷卻
var pending_dash: bool = false
var pending_backdash: bool = false
var dash_cooldown_timer: float = 0.0

# 狀態機
var current_state: String = "idle"
var previous_state: String = ""
var current_attack: String = "none"
var current_crouch: bool = false
var cancel_window_timer_ai: float = 0.0

# 角落逃脫冷卻
var corner_escape_cooldown: float = 0.0

# FrameBar 與 AttackData
var opponent_framebar: Node = null
var my_framebar: Node = null
var opponent_attack_data: AttackData = null
var parent_healthbar: Node = null
var opponent_healthbar: Node = null

# 防重複列印（統一使用字典）
var _last_logged: Dictionary = {
	"state": "",
	"dir": 999,
	"jump_attack": false,
	"aerial_attack": false,
	"attack_choice": "",
	"punish": false,
	"dp": false,
	"cancel": false,
	"fireball": false,
	"dash": false,
	"fireball_block": false
}

func _ready() -> void:
	parent = get_parent()
	world = get_tree().get_first_node_in_group("world")
	if parent:
		var char_id = parent.character_id if "character_id" in parent else "UNKNOWN"
		if char_id == "DAV":
			punish_attack = "st_mp"
		else:
			punish_attack = "st_mk"
		if parent.has_signal("hit_detected"):
			parent.hit_detected.connect(_on_self_hit_detected)
	else:
		push_warning("Warning: AIBehavior parent not found")
	opponent_search_timer = 0.1
	
	var char_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	if char_id == "DAV":
		opponent_attack_data = load("res://p2_attack_data.tres") as AttackData
	else:
		opponent_attack_data = load("res://p1_attack_data.tres") as AttackData
	
	var ui = get_tree().get_first_node_in_group("ui")
	if ui:
		var my_seat = parent.seat if "seat" in parent else "player_a"
		if my_seat == "player_a":
			opponent_framebar = ui.get_node("FrameBarP2")
			my_framebar = ui.get_node("FrameBarP1")
			parent_healthbar = ui.get_node_or_null("PlayerAHealthbar")
			opponent_healthbar = ui.get_node_or_null("PlayerBHealthbar")
		else:
			opponent_framebar = ui.get_node("FrameBarP1")
			my_framebar = ui.get_node("FrameBarP2")
			parent_healthbar = ui.get_node_or_null("PlayerBHealthbar")
			opponent_healthbar = ui.get_node_or_null("PlayerAHealthbar")
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
	
	if corner_escape_cooldown > 0:
		corner_escape_cooldown -= delta
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer <= 0:
			dash_cooldown_timer = 0.0
	
	var parent_health = parent_healthbar.current_health if parent_healthbar else 100
	var opponent_health = opponent_healthbar.current_health if opponent_healthbar else 100
	if parent_health <= 0 or opponent_health <= 0:
		ai_enabled = false
		return

func _set_state_timer(value: float) -> void:
	decision_timer = value

func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	current_state = "idle"
	current_attack = "none"
	current_crouch = false
	pending_attack = ""
	pending_dash = false
	pending_backdash = false
	dash_cooldown_timer = 0.0

func find_opponent() -> void:
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != parent:
			opponent = player
			if opponent.has_signal("hit_detected"):
				opponent.hit_detected.connect(_on_hit_detected)
			return
	push_warning("No opponent found for %s" % parent.name)

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
		var active_move_name = move_set.get_active_move_name()
		if not active_move_name.is_empty():
			attack = active_move_name
	var recovery = _get_opponent_recovery(attack)
	var blockstun = _get_opponent_blockstun(attack)
	var advantage = blockstun - recovery
	punish_timer = blockstun
	punish_opportunity = true
	var char_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	if advantage >= 0.25:
		punish_attack = "dp" if char_id == "DAV" else "spnk"
	elif advantage >= 0.15:
		punish_attack = "st_mk"
	else:
		punish_attack = "st_mp"

func _on_self_hit_detected(_target: String, _stun_duration: float, is_blocked: bool, _was_in_stun: bool) -> void:
	var char_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	if char_id == "DAV" and parent.attack_type == "st_mp" and not is_blocked:
		cancel_window_timer_ai = 0.3

func is_at_left_corner() -> bool:
	if not world: 
		return false
	var distance_to_left = parent.global_position.x - world.arena_left
	return distance_to_left <= 30.0

func is_at_right_corner() -> bool:
	if not world: 
		return false
	var distance_to_right = world.arena_right - parent.global_position.x
	return distance_to_right <= 30.0

func can_jump_attack_hit() -> bool:
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var opponent_on_ground = opponent.is_on_floor() if opponent.has_method("is_on_floor") else true
	return distance >= 40 and distance <= 70 and opponent_on_ground

func _log_state(state: String, dir: int) -> void:
	if state != _last_logged["state"] or dir != _last_logged["dir"]:
		_last_logged["state"] = state
		_last_logged["dir"] = dir

func get_ai_input() -> Dictionary:
	if not ai_enabled or not opponent:
		return {
			"input_dir": 0, "crouch_pressed": false, "jump_pressed": false,
			"st_mp_pressed": false, "st_mk_pressed": false,
			"spm1_pressed": false, "spm2_pressed": false,
			"dp_pressed": false, "super_pressed": false,
			"block_pressed": false,
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

	# ===== 火球偵測（最高優先級）=====
	var fireballs = get_tree().get_nodes_in_group("fireball")
	var incoming_fireball: bool = false
	for fireball in fireballs:
		if fireball.owner_character_id == parent.character_id or not fireball.is_active:
			continue
		var fb_dist = abs(fireball.global_position.x - parent.global_position.x)
		if fb_dist > fireball_block_distance:
			continue
		var fb_relative = sign(fireball.global_position.x - parent.global_position.x)
		if fb_relative == -fireball.direction:
			incoming_fireball = true
			if randf() < fireball_block_chance:
				input.block_pressed = true
				var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
				input.input_dir = -int(relative_dir)  # 強制後退格擋火球
				input.crouch_pressed = randf() < 0.3
				if fb_dist < 150 and randf() < fireball_backdash_chance and dash_cooldown_timer <= 0:
					pending_backdash = true
			if not _last_logged["fireball_block"]:
				_last_logged["fireball_block"] = true
		break

	if incoming_fireball:
		_last_logged["fireball_block"] = false
		input["attack_type"] = "none"
		input["damage"] = 0.0
		return input

	# ===== 處理待發招式 =====
	if pending_attack != "":
		match pending_attack:
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
			"super": input.super_pressed = true
		pending_attack = ""

	# ===== 處理 dash / backdash =====
	if pending_dash and dash_cooldown_timer <= 0:
		input.dash_pressed = true
		pending_dash = false
		dash_cooldown_timer = dash_cooldown
		_last_logged["dash"] = true
	elif pending_backdash and dash_cooldown_timer <= 0:
		input.backdash_pressed = true
		pending_backdash = false
		dash_cooldown_timer = dash_cooldown
		_last_logged["dash"] = true
	else:
		_last_logged["dash"] = false

	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)

	# ===== 一般格擋（修正：只在 defend 狀態且無火球時才後退格擋）=====
	var opponent_attacking: bool = opponent.is_attacking or (opponent.move_set and opponent.move_set.is_spmove)
	if current_state == "defend" and opponent_attacking and distance <= block_distance:
		if randf() < block_chance:
			input.block_pressed = true
			input.input_dir = -int(relative_dir)
			input.crouch_pressed = randf() < crouch_block_chance

	# ===== 狀態切換 =====
	decision_timer -= get_process_delta_time()
	if decision_timer <= 0:
		decision_timer = reaction_delay + randf_range(0.0, 0.2)
		previous_state = current_state
		var r = randf()
		if distance > 120:  # 遠距更傾向逼近
			current_state = "defend" if r < 0.4 else ("approach" if r < 0.85 else "attack")
		else:
			current_state = "defend" if r < 0.5 else ("attack" if r < 0.8 else "approach")
		if previous_state != current_state:
			_log_state(current_state, input.input_dir)

	# ===== 懲罰反擊 =====
	if punish_opportunity and not _last_logged["punish"]:
		current_state = "attack"
		current_attack = punish_attack
		pending_attack = punish_attack
		_last_logged["punish"] = true
		punish_opportunity = false
	elif not punish_opportunity:
		_last_logged["punish"] = false

	# ===== 攻擊選擇 =====
	if current_state == "attack":
		attack_decision_timer -= get_process_delta_time()
		if attack_decision_timer <= 0:
			attack_decision_timer = attack_decision_delay + randf_range(0.0, 0.1)
			
			if can_current_attack_hit_opponent() > 0:
				input["attack_type"] = current_attack if current_attack != "none" else "st_mp"
				input["damage"] = 10.0
				return input
			
			if distance > fireball_distance and randf() < fireball_chance and not _last_logged["fireball"]:
				pending_attack = "spm2"
				current_attack = "fireball"
				_last_logged["fireball"] = true
				input["attack_type"] = "spm2"
				input["damage"] = 15.0 if parent.character_id == "DAV" else 11.0
				return input
			elif _last_logged["fireball"]:
				_last_logged["fireball"] = false
			
			var possible_attacks: Array[String] = []
			var char_id = parent.character_id if "character_id" in parent else "UNKNOWN"
			for attack in fallback_attack_ranges.keys():
				if distance <= fallback_attack_ranges[attack]:
					if attack == "dp" and char_id != "DAV": continue
					if attack == "spm2" and distance < fireball_distance: continue
					possible_attacks.append(attack)
			
			if distance < 60:
				possible_attacks = ["st_mk", "cr_mk", "dp", "spm1"]
			
			current_attack = possible_attacks.pick_random() if possible_attacks.size() > 0 else "st_mp"
			pending_attack = current_attack
			if current_attack != _last_logged["attack_choice"]:
				_last_logged["attack_choice"] = current_attack
	if current_state == "defend":
		defend_decision_timer -= get_process_delta_time()
		if defend_decision_timer <= 0:
			defend_decision_timer = defend_decision_delay + randf_range(0.0, 0.1)
			current_crouch = randf() < 0.65

	# ===== Dash 觸發 =====
	if parent.is_on_floor() and dash_cooldown_timer <= 0:
		if distance > 200 and randf() < dash_chance_far and current_state == "approach":
			pending_dash = true
		elif distance < 70 and randf() < backdash_chance_close and current_state == "defend":
			pending_backdash = true

	# ===== 基本移動（關鍵修正：approach 時一定向前！）=====
	match current_state:
		"approach":
			input.input_dir = int(relative_dir)
			_log_state(current_state, input.input_dir)
		"defend":
			# defend 時才可能後退（已在上方格擋邏輯處理）
			if not input.block_pressed:  # 沒有格擋時可微調位置
				input.input_dir = -int(relative_dir) if distance < 60 else 0
			_log_state(current_state, input.input_dir)
		"idle":
			input.input_dir = 0
			_log_state(current_state, input.input_dir)

	# ===== 其他行為（跳躍、角落逃脫等保持不變）=====
	var jump_for_attack = can_jump_attack_hit() and randf() < 0.55 and parent.is_on_floor()
	if jump_for_attack and not _last_logged["jump_attack"]:
		input.jump_pressed = true
		input.input_dir = int(relative_dir)
		input.st_mp_pressed = randf() < 0.6
		input.st_mk_pressed = not input.st_mp_pressed
		_last_logged["jump_attack"] = true
	elif not jump_for_attack:
		_last_logged["jump_attack"] = false

	var in_corner = (is_at_left_corner() or is_at_right_corner()) and parent.is_on_floor()
	var try_escape = in_corner and corner_escape_cooldown <= 0 and randf() < 0.28
	if try_escape:
		input.jump_pressed = true
		input.input_dir = int(relative_dir)
		corner_escape_cooldown = 1.5

	if not parent.is_on_floor() and parent.velocity.y > 0 and distance < 80:
		if randf() < 0.7 and not _last_logged["aerial_attack"]:
			pending_attack = "st_mp" if randf() < 0.5 else "st_mk"
			_last_logged["aerial_attack"] = true
	elif parent.is_on_floor():
		_last_logged["aerial_attack"] = false

	if cancel_window_timer_ai > 0 and not _last_logged["cancel"]:
		pending_attack = "spm1"
		_last_logged["cancel"] = true
	elif cancel_window_timer_ai <= 0:
		_last_logged["cancel"] = false

	var char_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	if char_id == "DAV" and distance < 50 and randf() < p1_dp_chance and parent.is_on_floor() and not _last_logged["dp"]:
		pending_attack = "dp"
		current_attack = "dp"
		_last_logged["dp"] = true
	elif not (distance < 50 and parent.is_on_floor()):
		_last_logged["dp"] = false

	var attack_type = "st_mp" if input.st_mp_pressed else "st_mk" if input.st_mk_pressed else "dp" if input.dp_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var damage = 0.0
	if move_set and move_set.is_spmove and move_set.current_move_state.active_move:
		damage = move_set.get_special_damage()
	elif input.st_mp_pressed or input.st_mk_pressed:
		damage = 10.0
	input["attack_type"] = attack_type
	input["damage"] = damage

	return input
