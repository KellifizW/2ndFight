class_name AIBehavior extends Node

# ============================================================
# AI BEHAVIOR - Layered Decision Architecture
# ============================================================
# 分層決策系統：SURVIVAL > PUNISH > TACTICAL > POSITIONING > IDLE
# 使用威脅評估、幀數據、連段系統和空間控制模組

var threat_system: ThreatAssessment
var decision_layers: AIDecisionLayers
var frame_data: FrameDataManager
var combo_system: AIComboSystem
var space_control: SpaceControl

@export var ai_enabled: bool = false
@export var ai_difficulty: int = 5
@export var debug_mode: bool = false

var parent: Player
var opponent: Player
var world: Node

const SPECIAL_MOVE_ACTIONS = ["fireball", "spm2", "powerkk", "spnk", "hdk", "dp", "super"]

# 對手搜尋計時器
var opponent_search_timer: float = 0.0

func _ready() -> void:
	parent = get_parent()
	world = get_tree().get_first_node_in_group("world")
	
	if not parent:
		push_warning("Warning: AIBehavior parent not found")
		return
	
	_init_subsystems()
	opponent_search_timer = 0.1
	
	if debug_mode:
		print("[AI] AIBehavior initialized for %s" % parent.name)

func _init_subsystems() -> void:
	"""初始化所有子系統"""
	threat_system = ThreatAssessment.new()
	add_child(threat_system)
	
	decision_layers = AIDecisionLayers.new()
	add_child(decision_layers)
	
	frame_data = FrameDataManager.new()
	add_child(frame_data)
	
	combo_system = AIComboSystem.new()
	add_child(combo_system)
	
	space_control = SpaceControl.new()
	add_child(space_control)
	
	# 建立引用關係
	decision_layers.threat_system = threat_system
	decision_layers.frame_data = frame_data
	decision_layers.combo_system = combo_system
	decision_layers.space_control = space_control

func _process(delta: float) -> void:
	if not opponent and opponent_search_timer > 0:
		opponent_search_timer -= delta
		if opponent_search_timer <= 0:
			find_opponent()
			opponent_search_timer = 0.5

func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	if debug_mode:
		print("[AI] AI %s for %s" % ["enabled" if enabled else "disabled", parent.name if parent else "unknown"])

func find_opponent() -> void:
	"""尋找對手玩家"""
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != parent:
			opponent = player
			if debug_mode:
				print("[AI] Found opponent: %s" % opponent.name)
			return
	if debug_mode:
		push_warning("[AI] No opponent found for %s" % parent.name)

func get_ai_input() -> Dictionary:
	"""獲取AI輸入（主要入口點）"""
	if not ai_enabled or not opponent or not parent:
		return _neutral_input()
	
	# 執行中的連段繼續
	if combo_system.is_executing_combo():
		var next_move = combo_system.get_next_combo_move()
		if next_move:
			if debug_mode:
				print("[AI] Combo step: %s" % next_move)
			return _action_to_input(next_move)
		else:
			combo_system.reset_combo()
			return _neutral_input()
	
	# 獲取最佳決策
	var decision = decision_layers.get_best_decision(parent, opponent)
	
	# 每隔一段時間才輸出決策，避免刷屏
	if Engine.get_physics_frames() % 20 == 0 or decision.action in SPECIAL_MOVE_ACTIONS:
		print("[AI] %s decision: %s (priority: %.1f) - %s" % [parent.name, decision.action, decision.priority, decision.reason])
	
	# 開始新連段
	if decision.action.begins_with("combo_"):
		var combo_name = decision.action.substr(6)  # 移除 "combo_" 前綴
		combo_system.start_combo(combo_name)
		var first_move = combo_system.get_next_combo_move()
		if first_move:
			return _action_to_input(first_move)
	
	return _action_to_input(decision.action)

func _action_to_input(action: String) -> Dictionary:
	"""將動作轉換為輸入字典"""
	var input = _neutral_input()
	
	if not opponent:
		return input
	
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
	
	match action:
		"stand_block":
			input.block_pressed = true
			input.input_dir = -int(relative_dir)
		"crouch_block":
			input.block_pressed = true
			input.crouch_pressed = true
			input.input_dir = -int(relative_dir)
		"st_mp":
			input.st_mp_pressed = true
		"st_mk":
			input.st_mk_pressed = true
		"cr_mp":
			input.crouch_pressed = true
			input.st_mp_pressed = true
		"cr_mk":
			input.crouch_pressed = true
			input.st_mk_pressed = true
		"fireball", "spm2":
			input.spm2_pressed = true
			if debug_mode:
				print("[AI._action_to_input] %s: Setting spm2_pressed=true for action '%s'" % [parent.name, action])
		"powerkk", "spm1":
			input.spm1_pressed = true
		"spnk":
			input.spm1_pressed = true
		"hdk":
			input.spm3_pressed = true
		"dp":
			input.dp_pressed = true
		"super":
			input.super_pressed = true
		"dash_forward":
			input.dash_pressed = true
			input.input_dir = int(relative_dir)
		"backdash":
			input.backdash_pressed = true
			input.input_dir = -int(relative_dir)
		"jump_forward":
			input.jump_pressed = true
			input.input_dir = int(relative_dir)
		"jump_backward":
			input.jump_pressed = true
			input.input_dir = -int(relative_dir)
		"jump_neutral":
			input.jump_pressed = true
		"walk_forward":
			input.input_dir = int(relative_dir)
		"walk_backward":
			input.input_dir = -int(relative_dir)
	
	return input

func _neutral_input() -> Dictionary:
	"""返回中立輸入（無操作）"""
	return {
		"input_dir": 0,
		"crouch_pressed": false,
		"jump_pressed": false,
		"st_mp_pressed": false,
		"st_mk_pressed": false,
		"spm1_pressed": false,
		"spm2_pressed": false,
		"spm3_pressed": false,
		"dp_pressed": false,
		"super_pressed": false,
		"block_pressed": false,
		"dash_pressed": false,
		"backdash_pressed": false
	}
