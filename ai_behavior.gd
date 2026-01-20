class_name AIBehavior extends Node

# ============================================================
# AI BEHAVIOR - Layered Decision Architecture
# ============================================================
# 分層決策系統：SURVIVAL > PUNISH > TACTICAL > POSITIONING > IDLE
# 使用威脅評估、幀數據、連段系統和空間控制模組
#
# ACTION COMMITMENT SYSTEM (Industry Standard)
# Prevents jittery behavior by locking actions for minimum duration
# Based on Street Fighter/Tekken AI architecture

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

# ============================================================
# ACTION COMMITMENT SYSTEM
# ============================================================
var current_committed_action: String = ""
var commitment_timer: float = 0.0
var committed_input: Dictionary = {}

# Decision cooldown (simulates human thinking time)
var decision_cooldown: float = 0.0
const DECISION_INTERVAL: float = 0.15  # Re-evaluate every 9 frames at 60fps

# Action duration database (based on frame data)
const ACTION_DURATIONS = {
	# Movement - needs sustained execution to avoid twitching
	"walk_forward": {"min": 0.4, "max": 0.7},
	"walk_backward": {"min": 0.4, "max": 0.7},
	"dash_forward": {"min": 0.35, "max": 0.35},
	"backdash": {"min": 0.35, "max": 0.35},
	
	# Normal attacks - based on startup + active + recovery frames
	"st_mp": {"min": 0.35, "max": 0.35},
	"st_mk": {"min": 0.45, "max": 0.45},
	"cr_mp": {"min": 0.30, "max": 0.30},
	"cr_mk": {"min": 0.40, "max": 0.40},
	
	# Special moves - must complete full animation
	"fireball": {"min": 0.8, "max": 0.8},
	"spm2": {"min": 0.8, "max": 0.8},
	"powerkk": {"min": 0.9, "max": 0.9},
	"spnk": {"min": 0.9, "max": 0.9},
	"dp": {"min": 0.65, "max": 0.65},
	"hdk": {"min": 0.8, "max": 0.8},
	"super": {"min": 1.5, "max": 1.5},
	
	# Defensive actions
	"stand_block": {"min": 0.3, "max": 0.6},
	"crouch_block": {"min": 0.3, "max": 0.6},
	
	# Jumping
	"jump_forward": {"min": 0.5, "max": 0.5},
	"jump_backward": {"min": 0.5, "max": 0.5},
	"jump_neutral": {"min": 0.5, "max": 0.5},
}

# 對手搜尋計時器
var opponent_search_timer: float = 0.0

# Internal delta tracking for commitment system
var _last_delta: float = 1.0/60.0

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
	# Track delta for commitment system
	_last_delta = delta
	
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
	"""Main entry point - Industry standard implementation"""
	if not ai_enabled or not opponent or not parent:
		return _neutral_input()
	
	var delta = _last_delta  # Use tracked delta from _process
	
	# ============================================================
	# LAYER 1: ACTION COMMITMENT (Highest Priority)
	# ============================================================
	# If currently committed to an action, continue executing it
	# This prevents jittery behavior and ensures smooth action completion
	if commitment_timer > 0:
		commitment_timer -= delta
		if debug_mode and Engine.get_physics_frames() % 60 == 0:
			print("[AI] Committed: %s (%.2fs remaining)" % [current_committed_action, commitment_timer])
		return committed_input
	
	# ============================================================
	# LAYER 2: COMBO PROTECTION (Special State)
	# ============================================================
	# Combos have absolute protection - cannot be interrupted
	if combo_system.is_executing_combo():
		var next_move = combo_system.get_next_combo_move()
		if next_move:
			if debug_mode:
				print("[AI] Combo step: %s" % next_move)
			return _commit_action(next_move, 0.4)
		else:
			combo_system.reset_combo()
	
	# ============================================================
	# LAYER 3: DECISION COOLDOWN
	# ============================================================
	# Don't re-evaluate every frame - simulates human reaction time
	if decision_cooldown > 0:
		decision_cooldown -= delta
		return committed_input if committed_input.size() > 0 else _neutral_input()
	
	# ============================================================
	# LAYER 4: NEW DECISION
	# ============================================================
	# Only reached every DECISION_INTERVAL seconds
	var decision = decision_layers.get_best_decision(parent, opponent)
	decision_cooldown = DECISION_INTERVAL
	
	# Log decision (less frequently to avoid spam)
	if Engine.get_physics_frames() % 20 == 0 or decision.action in SPECIAL_MOVE_ACTIONS:
		print("[AI] %s decision: %s (priority: %.1f) - %s" % [parent.name, decision.action, decision.priority, decision.reason])
	
	# Handle combo start
	if decision.action.begins_with("combo_"):
		var combo_name = decision.action.substr(6)
		combo_system.start_combo(combo_name)
		var first_move = combo_system.get_next_combo_move()
		if first_move:
			return _commit_action(first_move, 0.4)
	
	# Commit to the decided action
	var duration = _get_action_duration(decision.action)
	return _commit_action(decision.action, duration)

func _commit_action(action: String, duration: float) -> Dictionary:
	"""
	Commit to executing an action for a minimum duration
	This is the core of preventing jittery behavior
	"""
	current_committed_action = action
	commitment_timer = duration
	committed_input = _action_to_input(action)
	
	if debug_mode:
		print("[AI] NEW DECISION: '%s' locked for %.2fs (priority-based)" % [action, duration])
	
	return committed_input

func _get_action_duration(action: String) -> float:
	"""
	Get minimum duration for an action based on frame data
	Uses variable duration for movement to add unpredictability
	"""
	if action.begins_with("combo_"):
		return 1.5  # Combos are always protected for full duration
	
	if action in ACTION_DURATIONS:
		var data = ACTION_DURATIONS[action]
		return randf_range(data["min"], data["max"])
	
	# Default fallback
	return 0.3

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
