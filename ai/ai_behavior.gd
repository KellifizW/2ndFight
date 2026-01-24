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
@export var ai_difficulty: int = 5  ## AI 難度 (1-10)，目前未使用，保留供未來實現反應時間/決策品質調整
@export var debug_mode: bool = false

# Move restrictions now managed by CPUController
var enable_move_restrictions: bool = false
var restricted_moves: Array[String] = []

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
const DECISION_INTERVAL: float = 0.25  # Re-evaluate every 15 frames at 60 FPS

@export var decision_interval_override: float = 0.0  # Allow tuning in Inspector; set to 0 to use DECISION_INTERVAL, >0 for custom, <0 for immediate updates

# ============================================================
# ADAPTIVE DECISION INTERVAL SYSTEM (Phase 2 Optimization)
# ============================================================
# 根據威脅等級動態調整決策速度，提高性能 5-8%
@export var enable_adaptive_interval: bool = true

const INTERVAL_CRITICAL: float = 0.1   # 反應快速以應對危險
const INTERVAL_HIGH: float = 0.15      # 正常反應
const INTERVAL_NORMAL: float = 0.25    # 放鬆的思考
const INTERVAL_SAFE: float = 0.3       # 非常放鬆

var current_adaptive_interval: float = INTERVAL_NORMAL

# Action duration database (based on frame data)
const ACTION_DURATIONS = {
	# Movement - needs sustained execution to avoid twitching
	"walk_forward": {"min": 0.4, "max": 0.7},
	"walk_backward": {"min": 0.4, "max": 0.7},
	"dash_forward": {"min": 0.35, "max": 0.35},
	"backdash": {"min": 0.35, "max": 0.35},
	
	# Normal attacks - based on startup + active + recovery frames
	"st_lp": {"min": 0.25, "max": 0.25},
	"st_mp": {"min": 0.35, "max": 0.35},
	"st_hp": {"min": 0.55, "max": 0.55},
	"st_lk": {"min": 0.30, "max": 0.30},
	"st_mk": {"min": 0.45, "max": 0.45},
	"st_hk": {"min": 0.60, "max": 0.60},
	"cr_lp": {"min": 0.20, "max": 0.20},
	"cr_mp": {"min": 0.30, "max": 0.30},
	"cr_hp": {"min": 0.45, "max": 0.45},
	"cr_lk": {"min": 0.25, "max": 0.25},
	"cr_mk": {"min": 0.40, "max": 0.40},
	"cr_hk": {"min": 0.50, "max": 0.50},
	
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

func _adjust_decision_interval(threat_level: int, distance: float) -> void:
	"""根據威脅等級和距離動態調整決策速度"""
	if not enable_adaptive_interval:
		return
	
	match threat_level:
		4:  # CRITICAL (from ThreatAssessment.ThreatLevel)
			current_adaptive_interval = INTERVAL_CRITICAL
		3:  # HIGH
			current_adaptive_interval = INTERVAL_HIGH
		2:  # MEDIUM
			current_adaptive_interval = INTERVAL_NORMAL
		_:  # LOW/NONE
			# 根據距離調整：遠處更放鬆
			if distance > 300:
				current_adaptive_interval = INTERVAL_SAFE
			else:
				current_adaptive_interval = INTERVAL_NORMAL

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
	
	# Move restrictions initialized by CPUController

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
	
	# 檢查招式是否被限制，如果是則獲取替代決策
	if enable_move_restrictions and decision.action in restricted_moves:
		if debug_mode or Engine.get_physics_frames() % 60 == 0:
			print("[AI] Move '%s' (priority: %.1f) is restricted, finding alternative..." % [decision.action, decision.priority])
		decision = decision_layers.get_fallback_decision(parent, opponent)
		if debug_mode or Engine.get_physics_frames() % 60 == 0:
			print("[AI] Fallback decision: '%s' (priority: %.1f)" % [decision.action, decision.priority])
	
	# ============================================================
	# ADAPTIVE DECISION INTERVAL ADJUSTMENT (Phase 2)
	# ============================================================
	# 根據威脅等級調整決策間隔，在危急時刻反應迅速
	var active_interval: float
	if decision_interval_override > 0:
		active_interval = decision_interval_override
	elif decision_interval_override == 0:
		if enable_adaptive_interval:
			# 獲取威脅信息以調整間隔
			var threat = threat_system.evaluate_threats(parent, opponent) if threat_system else null
			var distance = abs(parent.global_position.x - opponent.global_position.x)
			if threat:
				_adjust_decision_interval(threat.level, distance)
				active_interval = current_adaptive_interval
			else:
				active_interval = DECISION_INTERVAL
		else:
			active_interval = DECISION_INTERVAL
	else:  # < 0, immediate updates
		active_interval = 0.0
	decision_cooldown = active_interval
	
	# ============================================================
	# 增強的調試輸出
	# ============================================================
	if debug_mode:
		# 獲取威脅信息
		var threat = threat_system.evaluate_threats(parent, opponent) if threat_system else null
		
		if threat:
			var threat_level_str = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"][threat.level]
			print("\n[AI DECISION] %s" % parent.name)
			print("  動作: %s" % decision.action)
			print("  優先級: %.1f" % decision.priority)
			print("  理由: %s" % decision.reason)
			if enable_adaptive_interval:
				print("  決策間隔: %.3f (自適應)" % active_interval)
			
			if threat.level > 0:  # 有威脅時顯示威脅信息
				print("  威脅等級: %s" % threat_level_str)
				if threat.source != "":
					print("  威脅來源: %s" % threat.source)
				if threat.frames_until_hit < 999:
					print("  撞擊幀數: %d" % threat.frames_until_hit)
	elif Engine.get_physics_frames() % 20 == 0 or decision.action in SPECIAL_MOVE_ACTIONS:
		# 簡化日誌（保持原有行為）
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
		"st_lp":
			input.st_lp_pressed = true
		"st_mp":
			input.st_mp_pressed = true
		"st_hp":
			input.st_hp_pressed = true
		"st_lk":
			input.st_lk_pressed = true
		"st_mk":
			input.st_mk_pressed = true
		"st_hk":
			input.st_hk_pressed = true
		"cr_lp":
			input.crouch_pressed = true
			input.st_lp_pressed = true
		"cr_mp":
			input.crouch_pressed = true
			input.st_mp_pressed = true
		"cr_hp":
			input.crouch_pressed = true
			input.st_hp_pressed = true
		"cr_lk":
			input.crouch_pressed = true
			input.st_lk_pressed = true
		"cr_mk":
			input.crouch_pressed = true
			input.st_mk_pressed = true
		"cr_hk":
			input.crouch_pressed = true
			input.st_hk_pressed = true
		"fireball", "spm2":
			# ⚠️ 檢查：不應該到達這裡（應該被決策層過濾）
			if enable_move_restrictions and "fireball" in restricted_moves:
				if debug_mode:
					print("[AI._action_to_input] WARNING: Fireball action reached input conversion despite being restricted!")
				# 返回中立輸入，不執行
				return _neutral_input()
			input.spm2_pressed = true
			if debug_mode:
				print("[AI._action_to_input] %s: Setting spm2_pressed=true for action '%s'" % [parent.name, action])
		"powerkk", "spm1":
			if enable_move_restrictions and "powerkk" in restricted_moves:
				if debug_mode:
					print("[AI._action_to_input] WARNING: Powerkk action reached input conversion despite being restricted!")
				return _neutral_input()
			input.spm1_pressed = true
		"spnk":
			if enable_move_restrictions and "spnk" in restricted_moves:
				return _neutral_input()
			input.spm1_pressed = true
		"hdk":
			if enable_move_restrictions and "hdk" in restricted_moves:
				return _neutral_input()
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
			input.input_dir = 0
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
		"st_lp_pressed": false,
		"st_mp_pressed": false,
		"st_hp_pressed": false,
		"st_lk_pressed": false,
		"st_mk_pressed": false,
		"st_hk_pressed": false,
		"spm1_pressed": false,
		"spm2_pressed": false,
		"spm3_pressed": false,
		"dp_pressed": false,
		"super_pressed": false,
		"block_pressed": false,
		"dash_pressed": false,
		"backdash_pressed": false
	}
