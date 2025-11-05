class_name AIBehavior extends Node

@export var reaction_delay: float = 0.4  # AI狀態切換延遲（秒），0.4-0.6以穩定狀態
@export var attack_decision_delay: float = 0.3  # 攻擊指令選擇延遲（秒），0.3-0.5以減少指令閃爍
@export var defend_decision_delay: float = 0.3  # 防守指令選擇延遲（秒），0.3-0.5以減少蹲下切換
@export var global_jump_chance: float = 0.02  # 全局跳躍機率（大幅降低）
@export var p1_dp_chance: float = 0.15  # P1 使用 DP 的機率（Inspector 可調）

var ai_enabled: bool = false
var opponent: Node = null  # 對手引用
var decision_timer: float = 0.0  # 狀態決策計時器
var attack_decision_timer: float = 0.0  # 攻擊指令計時器
var defend_decision_timer: float = 0.0  # 防守指令計時器
var state_timer: float = 0.0 : set = _set_state_timer  # 兼容world.gd，指向decision_timer
var last_action_time: float = 0.0  # 占位符，兼容world.gd
var random_action_chance: float = 0.25  # 隨機動作機率，控制攻擊多樣性
var parent: Node  # 父節點（Player）
var opponent_search_timer: float = 0.0  # 對手查找重試計時器
var world: Node = null  # world 引用

# 用於懲罰反擊的變數
var punish_timer: float = 0.0  # 計時器，等 blockstun 結束後反擊
var last_blockstun_duration: float = 0.0  # 記錄最近的 blockstun 時間
var punish_opportunity: bool = false  # 是否有懲罰機會
var punish_attack: String = "st_mk"  # 動態選擇的最佳反擊招式（初始為 P2 最快）

# 簡單狀態機，讓AI行為更結構化
var current_state: String = "idle"  # 狀態：idle（初始）、approach（接近）、attack（攻擊）、defend（防守）
var previous_state: String = ""  # 用來偵測狀態改變，觸發除錯 print
var current_attack: String = "none"  # 當前選擇的攻擊類型，保持到下次更新
var current_crouch: bool = false  # 當前蹲下狀態，保持到下次更新

# frame data 字典，分開 P1 和 P2，新增 startup 以優化選擇
var frame_data: Dictionary = {
	"p1": {
		"st_mp": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.267},
		"st_mk": {"startup": 0.2, "recovery": 0.4003, "blockstun": 0.3},
		"jump_mp": {"startup": 0.1333, "recovery": 0.2, "blockstun": 0.267},
		"jump_mk": {"startup": 0.1, "recovery": 0.3, "blockstun": 0.267},
		"powerkk": {"startup": 0.3, "recovery": 0.5, "blockstun": 0.267},
		"fireball": {"startup": 0.3, "recovery": 0.4667, "blockstun": 0.267}
	},
	"p2": {
		"st_mp": {"startup": 0.2, "recovery": 0.3667, "blockstun": 0.267},
		"st_mk": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.3},
		"jump_mp": {"startup": 0.1, "recovery": 0.2333, "blockstun": 0.267},
		"jump_mk": {"startup": 0.1, "recovery": 0.267, "blockstun": 0.267},
		"spnk": {"startup": 0.2, "recovery": 0.4667, "blockstun": 0.267},
		"fireball": {"startup": 0.3, "recovery": 0.3667, "blockstun": 0.267}
	}
}

# 用於 P1 st_mp 連技取消的計時器（模擬 player.gd 的 cancel_window_duration = 0.3s）
var cancel_window_timer_ai: float = 0.0  # AI 專用取消窗口計時器

func _ready():
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

func _process(delta):
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

func _set_state_timer(value: float):
	decision_timer = value

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if ai_enabled:
		print("AI enabled for %s" % parent.name)
	else:
		print("AI disabled for %s" % parent.name)
		current_state = "idle"
		current_attack = "none"
		current_crouch = false

func find_opponent():
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != parent:
			opponent = player
			print("AI opponent found: %s for %s" % [opponent.name, parent.name])
			if opponent.has_signal("hit_detected"):
				opponent.hit_detected.connect(_on_hit_detected)
			return
	print("Warning: No opponent found for %s" % parent.name)

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	if ai_enabled and opponent and is_blocked and target == parent.name:
		var opponent_attack = opponent.attack_type if "attack_type" in opponent else "st_mp"
		var move_set = opponent.get_node("MoveSet") if opponent.has_node("MoveSet") else null
		if move_set:
			if move_set.is_powerkk:
				opponent_attack = "powerkk"
			elif move_set.is_spnk:
				opponent_attack = "spnk"
			elif move_set.is_fireball:
				opponent_attack = "fireball"
			elif move_set.is_super:
				opponent_attack = "super"
			elif move_set.is_dp:
				opponent_attack = "dp"
		
		var recovery = frame_data[opponent.player_id].get(opponent_attack, {}).get("recovery", 0.4)
		var blockstun = frame_data[opponent.player_id].get(opponent_attack, {}).get("blockstun", 0.267)
		var advantage = blockstun - recovery
		print("Debug: %s blocked %s's %s, advantage: %.2f" % [parent.name, opponent.name, opponent_attack, advantage])
		
		punish_timer = blockstun
		last_blockstun_duration = blockstun
		punish_attack = _select_punish_attack(advantage)

func _select_punish_attack(advantage: float) -> String:
	var available_attacks = frame_data[parent.player_id]
	var best_attack = ""
	var best_startup = INF
	for attack in available_attacks:
		var startup = available_attacks[attack]["startup"]
		if startup < best_startup and startup <= advantage:
			best_startup = startup
			best_attack = attack
	return best_attack if best_attack else "st_mp"

func _on_self_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
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

func get_ai_input() -> Dictionary:
	if not ai_enabled or not opponent:
		return {}
	
	var input_dir: int = 0
	var crouch_pressed: bool = false
	var jump_pressed: bool = false
	var st_mp_pressed: bool = false
	var st_mk_pressed: bool = false
	var spm1_pressed: bool = false
	var spm2_pressed: bool = false
	var dp_pressed: bool = false
	var super_pressed: bool = false
	
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
	var is_at_corner = is_at_left_corner() or is_at_right_corner()
	var is_near_corner = is_near_left_corner() or is_near_right_corner()
	
	decision_timer -= get_process_delta_time()
	if decision_timer <= 0:
		decision_timer = reaction_delay + randf_range(0.0, 0.2)
		previous_state = current_state
		match randi() % 4:
			0: current_state = "approach"
			1: current_state = "attack"
			2: current_state = "defend"
			3: current_state = "idle"
		if previous_state != current_state:
			print("Debug: %s state changed to %s" % [parent.name, current_state])
	
	if punish_opportunity:
		current_state = "attack"
		if parent.player_id == "p1" and randf() < 0.5:
			current_attack = "dp"
			dp_pressed = true
		else:
			current_attack = punish_attack
		punish_opportunity = false
		print("Debug: Punish opportunity triggered, attacking with %s" % current_attack)
	
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
					current_attack = "st_mp" if parent.player_id == "p2" else "st_mk"
			else:
				if randf() < random_action_chance:
					match randi() % 4:
						0: current_attack = "st_mk"
						1: current_attack = "spm1"
						2: current_attack = "spm2"
						3:
							if parent.player_id == "p1":
								current_attack = "dp"
								dp_pressed = true
				else:
					current_attack = "spm1"
			print("Debug: %s in attack, selected: %s" % [parent.name, current_attack])
	
	if current_state == "defend":
		defend_decision_timer -= get_process_delta_time()
		if defend_decision_timer <= 0:
			defend_decision_timer = defend_decision_delay + randf_range(0.0, 0.2)
			current_crouch = randf() < 0.6
			if is_near_corner:
				current_crouch = randf() < 0.3
			print("Debug: %s in defend, crouch: %s" % [parent.name, "true" if current_crouch else "false"])
	
	if distance < 120 and randf() < global_jump_chance and parent.is_on_floor():
		jump_pressed = true
		input_dir = -int(relative_dir) if current_state == "defend" else int(relative_dir)
		print("Debug: AI jump triggered globally for escape/attack, dir=%d" % input_dir)
	
	match current_state:
		"approach":
			input_dir = int(relative_dir)
			if distance > 150 and randf() < 0.2 and parent.is_on_floor():
				jump_pressed = true
			print("Debug: %s in approach, input_dir: %d, opponent at x: %.1f, self at x: %.1f" % [parent.name, input_dir, opponent.global_position.x, parent.global_position.x])
		"attack":
			match current_attack:
				"st_mp": st_mp_pressed = true
				"st_mk": st_mk_pressed = true
				"spm1": spm1_pressed = true
				"spm2": spm2_pressed = true
				"dp": dp_pressed = true
		"defend":
			input_dir = -int(relative_dir)
			crouch_pressed = current_crouch
			if randf() < 0.15 and parent.is_on_floor():
				jump_pressed = true
				input_dir = -int(relative_dir)
		"idle": pass
	
	if is_at_corner and randf() < 0.9 and parent.is_on_floor():
		jump_pressed = true
		input_dir = int(relative_dir)
		st_mp_pressed = false
		st_mk_pressed = false
		spm1_pressed = false
		spm2_pressed = false
		dp_pressed = false
		crouch_pressed = false
		print("Debug: Corner jump triggered for %s" % parent.name)
	
	if not parent.is_on_floor() and parent.velocity.y > 0 and parent.global_position.y < 50:
		if distance < 50 and randf() < 0.3:
			if randf() < 0.5:
				st_mp_pressed = true
			else:
				st_mk_pressed = true
			var attack_name = "jump_mp" if st_mp_pressed else "jump_mk"
			print("Debug: AI aerial attack triggered near landing, attack=%s, y=%.1f" % [attack_name, parent.global_position.y])
	
	if cancel_window_timer_ai > 0:
		spm1_pressed = true
		st_mp_pressed = false
		st_mk_pressed = false
		spm2_pressed = false
		dp_pressed = false
		print("Debug: AI P1 triggering spm1 in cancel window for combo")
	
	if parent.player_id == "p1" and (current_state == "attack" or current_state == "defend") and distance < 50 and randf() < p1_dp_chance and parent.is_on_floor():
		dp_pressed = true
		current_attack = "dp"
		st_mp_pressed = false
		st_mk_pressed = false
		spm1_pressed = false
		spm2_pressed = false
		print("Debug: AI P1 triggering DP (spmove3) in %s state, distance=%.1f" % [current_state, distance])
	
	var attack_type = "st_mp" if st_mp_pressed else "st_mk" if st_mk_pressed else "dp" if dp_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var blockstun_duration = frame_data[parent.player_id][current_attack]["blockstun"] if move_set and current_attack in frame_data[parent.player_id] else 0.2
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball or move_set.is_dp) else (10.0 if (st_mp_pressed or st_mk_pressed) else 0.0)
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"st_mp_pressed": st_mp_pressed,
		"st_mk_pressed": st_mk_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed,
		"dp_pressed": dp_pressed,
		"super_pressed": super_pressed
	}
