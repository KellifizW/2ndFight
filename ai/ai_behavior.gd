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
@export var debug_block_trace: bool = false
@export var startup_logs: bool = false
@export var verbose_decision_logs: bool = false

# Move restrictions now managed by CPUController
var enable_move_restrictions: bool = false
var restricted_moves: Array[String] = []

var parent: Player
var opponent: Player
var world: Node

const SPECIAL_MOVE_ACTIONS = ["fireball", "fireballL", "fireballM", "fireballH", "spm2", "powerkk", "spnk", "hdk", "dp", "dpL", "dpM", "dpH", "100p", "super"]

# ============================================================
# ACTION COMMITMENT SYSTEM
# ============================================================
var current_committed_action: String = ""
# Stage 1：承諾視窗改為 int 物理幀（每個 get_ai_input tick -1）。
# 舊版以 _process 的真實秒 delta 倒數、每物理 tick 扣一次 —— 時間域混用，
# 行為隨渲染幀率漂移（60fps ≈ 2 tick/0.033s，headless 下更不可預測）。
var commitment_frames: int = 0
var committed_input: Dictionary = {}
var commitment_one_time_sent: bool = false  # 【FIX】追蹤是否已發送過單幀命令（throw/special moves）
var _cached_input_frame: int = -1
var _cached_input_result: Dictionary = {}

# Decision cooldown (simulates human thinking time)
# Stage 1：int 物理幀計數；設計者秒數（DECISION_INTERVAL / INTERVAL_*）只在
# 種子邊界經 Movement.seconds_to_frames_nearest 轉換一次。
var decision_cooldown_frames: int = 0
const DECISION_INTERVAL: float = 0.033  # 【FIX】 Re-evaluate every 2 frames (~33ms at 60 FPS) - reduced from 0.08 for responsiveness

@export var decision_interval_override: float = 0.0  # Allow tuning in Inspector; set to 0 to use DECISION_INTERVAL, >0 for custom, <0 for immediate updates

# ============================================================
# ADAPTIVE DECISION INTERVAL SYSTEM (Phase 2 Optimization)
# ============================================================
# 根據威脅等級動態調整決策速度，提高性能 5-8%
@export var enable_adaptive_interval: bool = true

const INTERVAL_CRITICAL: float = 0.016  # 【FIX】反應快速以應對危險 (~1 frame)
const INTERVAL_HIGH: float = 0.033      # 【FIX】正常反應 (~2 frames)
const INTERVAL_NORMAL: float = 0.05     # 【FIX】放鬆的思考 (~3 frames)
const INTERVAL_SAFE: float = 0.067      # 【FIX】非常放鬆 (~4 frames)

var current_adaptive_interval: float = INTERVAL_NORMAL

# ============================================================
# DYNAMIC ANIMATION DURATION SYSTEM
# ============================================================
# 從AnimationPlayer動態加載時長，避免硬編碼不同步問題
# 單一真理來源：.tscn 檔中的AnimationPlayer
var animation_durations: Dictionary = {}  # Dynamically loaded from AnimationPlayer

# Fallback durations for actions not in AnimationPlayer (movement, blocks, etc.)
# These are used if animation isn't found, providing conservative estimates
const ACTION_DURATIONS_FALLBACK = {
	# Movement - needs sustained execution to avoid twitching
	"walk_forward": {"min": 0.15, "max": 0.3},
	"walk_backward": {"min": 0.15, "max": 0.3},
	"dash_forward": {"min": 0.35, "max": 0.35},
	"backdash": {"min": 0.35, "max": 0.35},
	
	# Defensive actions
	"stand_block": {"min": 0.2, "max": 0.4},
	"crouch_block": {"min": 0.2, "max": 0.4},
	
	# Jumping
	"jump_forward": {"min": 0.5, "max": 0.5},
	"jump_backward": {"min": 0.5, "max": 0.5},
	"jump_neutral": {"min": 0.5, "max": 0.5},
	
	# Generic fallback if animation name not found
	"default": {"min": 0.3, "max": 0.3},
}

# 對手搜尋計時器（Stage 1：int 物理幀；種子秒數僅在邊界轉換）
var opponent_search_frames: int = 0
const OPPONENT_SEARCH_DELAY: float = 0.1  # 首次搜尋延遲（秒）
const OPPONENT_RETRY_DELAY: float = 0.5   # 找不到對手時的重試間隔（秒）

var _last_block_trace_attack_frame: int = -1
var _last_block_trace_action: String = ""

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
	add_to_group("ai_systems")
	parent = get_parent()
	world = get_tree().get_first_node_in_group("world")
	
	if not parent:
		push_warning("Warning: AIBehavior parent not found")
		return
	
	# Initialize the decision subsystems synchronously.  The AI can be enabled by
	# a button/key during the first rendered frame (especially in Web exports,
	# where the first frame can be delayed while assets are being uploaded).  The
	# old code deferred BOTH animation loading and subsystem creation, so an early
	# toggle made get_ai_input() call null subsystems and the player stopped
	# receiving AI input.
	_ensure_runtime_dependencies()

	# AnimationPlayer is initialized by the parent during its _ready().  Loading
	# animation durations can safely wait one frame, but must not delay the AI
	# itself from becoming usable.
	await get_tree().process_frame
	_load_animation_durations_from_player()
	
	opponent_search_frames = Movement.seconds_to_frames_nearest(OPPONENT_SEARCH_DELAY)
	decision_cooldown_frames = 0  # 【FIX】立即進行第一次決策評估，不要延遲
	
	if debug_mode and startup_logs:
		Debug.log("[AI] AIBehavior initialized for %s" % parent.name)

func _init_subsystems() -> void:
	"""初始化所有子系統"""
	if threat_system and decision_layers and frame_data and combo_system and space_control:
		decision_layers.threat_system = threat_system
		decision_layers.frame_data = frame_data
		decision_layers.combo_system = combo_system
		decision_layers.space_control = space_control
		decision_layers.debug_block_trace = debug_block_trace
		decision_layers.restricted_moves = restricted_moves
		return

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
	decision_layers.debug_block_trace = debug_block_trace
	decision_layers.restricted_moves = restricted_moves
	
	# Move restrictions initialized by CPUController

func _ensure_runtime_dependencies() -> void:
	if not parent:
		parent = get_parent()
	if not world:
		world = get_tree().get_first_node_in_group("world")
	if not threat_system or not decision_layers or not frame_data or not combo_system or not space_control:
		_init_subsystems()
	if parent and not opponent:
		find_opponent()

func _load_animation_durations_from_player() -> void:
	"""
	【動態加載系統】從角色的AnimationPlayer讀取所有動畫時長
	- 避免硬編碼導致的不同步問題
	- 單一真理來源：.tscn 檔中的AnimationPlayer
	- 自動化：新增動畫無需修改此代碼
	"""
	if not parent:
		push_warning("[AI DynLoad] ❌ Parent is null!")
		return
	
	if not "animation_player" in parent:
		push_warning("[AI DynLoad] ❌ Parent has no animation_player property!")
		return
	
	var anim_player = parent.animation_player
	if not anim_player:
		push_warning("[AI DynLoad] ❌ animation_player is null, anime list cannot be loaded!")
		return
	
	# 遍歷所有動畫並記錄其時長
	var anim_list = anim_player.get_animation_list()
	Debug.log("[AI DynLoad] ✅ AnimationPlayer found! Loading %d animations..." % anim_list.size())
	
	var loaded_count = 0
	for anim_name in anim_list:
		var anim = anim_player.get_animation(anim_name)
		if anim:
			animation_durations[anim_name] = anim.length
			loaded_count += 1
			if debug_mode and startup_logs:
				Debug.log("[AI DynLoad] ✓ %s: %.3fs (120fps physics timer: %d frames)" % [
					anim_name, 
					anim.length,
					Movement.seconds_to_frames_nearest(anim.length)
				])
	
	var char_id = parent.character_data.short_id if parent.character_data else "Unknown"
	Debug.log("[AI DynLoad] ✅ Successfully loaded %d animations from %s" % [loaded_count, char_id])

func get_action_duration(action: String) -> float:
	"""
	【智能查詢】取得動作時長，優先級由高到低：
	1. 從AnimationPlayer動態加載的實時值
	2. 備用硬編碼值（用於非動畫動作如移動/防守）
	3. 預設 0.3 秒（最後保障）
	"""
	# 【優先】使用動態加載的動畫時長
	if action in animation_durations:
		return animation_durations[action]
	
	# 【備用】使用硬編碼備用值（非動畫動作）
	if action in ACTION_DURATIONS_FALLBACK:
		var data = ACTION_DURATIONS_FALLBACK[action]
		return randf_range(data["min"], data["max"])
	
	# 【備用】如果是攻擊動作但未找到, 使用較長的預設 (0.65s)
	# 因為大多數攻擊動畫長度在 0.5-0.8 秒之間
	if action in ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
				  "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
				  "jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk"]:
		if animation_durations.is_empty():
			push_warning("[AI] WARNING: animation_durations is empty for attack '%s', using 0.65s fallback" % action)
		return 0.65  # Better fallback for attacks
	
	# 【保障】默認返回 0.3 秒
	if debug_mode:
		push_warning("[AI] Unknown action duration: '%s', using 0.3s default" % action)
	return 0.3

# Stage 1：對手搜尋由「_process 秒制」改為「_physics_process 物理幀制」，
# 與 AI 其餘計時器同一時間域（120 Hz tick，與渲染幀率脫鉤）。
func _physics_process(_delta: float) -> void:
	if not opponent and opponent_search_frames > 0:
		opponent_search_frames -= 1
		if opponent_search_frames <= 0:
			find_opponent()
			opponent_search_frames = Movement.seconds_to_frames_nearest(OPPONENT_RETRY_DELAY)
			# 【DEBUG】每次搜尋後顯示是否找到對手
			if Engine.get_physics_frames() % 30 == 0:
				Debug.log("[AI._physics_process] Frame=%d | opponent search result: %s" % [
					Engine.get_physics_frames(),
					str(opponent.name) if opponent else "NOT FOUND"
				])

func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	if enabled:
		_ensure_runtime_dependencies()
		decision_cooldown_frames = 0
	_invalidate_cached_input()
	if debug_mode:
		var parent_name := str(parent.name) if parent else "unknown"
		Debug.log("[AI] AI %s for %s" % ["enabled" if enabled else "disabled", parent_name])

func set_move_restrictions(restricted: Array[String], enable: bool) -> void:
	"""
	設定招式限制並將其傳遞給決策層
	由 CPUController 呼叫
	"""
	restricted_moves = restricted
	enable_move_restrictions = enable
	
	# 將限制傳遞給決策層
	if decision_layers:
		decision_layers.restricted_moves = restricted
	
	if debug_mode and startup_logs:
		var restriction_str = "None" if restricted.is_empty() else str(restricted)
		var parent_name := str(parent.name) if parent else "unknown"
		Debug.log("[AI.set_move_restrictions] %s - Restricted moves: %s (enabled: %s)" % [
			parent_name,
			restriction_str,
			enable
		])

func find_opponent() -> void:
	"""尋找對手玩家"""
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != parent:
			opponent = player
			if debug_mode and startup_logs:
				Debug.log("[AI] Found opponent: %s" % opponent.name)
			return
	if debug_mode:
		push_warning("[AI] No opponent found for %s" % parent.name)

func get_ai_input() -> Dictionary:
	var current_frame = Engine.get_physics_frames()
	if _cached_input_frame == current_frame:
		return _cached_input_result.duplicate(true)
	
	var input_result = _compute_ai_input()
	_cached_input_frame = current_frame
	_cached_input_result = input_result.duplicate(true)
	return input_result

func _compute_ai_input() -> Dictionary:
	"""Main entry point - Industry standard implementation"""
	var current_frame = Engine.get_physics_frames()
	var seat = parent.seat if parent and "seat" in parent else "?"
	if ai_enabled:
		_ensure_runtime_dependencies()
		seat = parent.seat if parent and "seat" in parent else seat

	# Be defensive around scene startup.  In a Web export the first physics
	# tick may occur before an awaited _ready() continuation resumes.  Returning
	# neutral input is preferable to throwing on a null subsystem, but normal
	# startup now initializes these synchronously above.
	if not threat_system or not decision_layers or not frame_data or not combo_system or not space_control:
		if current_frame % 120 == 0:
			Debug.log("[AI] Frame=%d Seat=%s | subsystems still initializing" % [current_frame, seat])
		return _neutral_input()
	
	# 【DEBUG】顯示初始狀態（每秒一次）
	if current_frame % 120 == 0:
		if not ai_enabled:
			Debug.log("[AI] Frame=%d Seat=%s | ⚠️ AI DISABLED" % [current_frame, seat])
		if not parent:
			Debug.log("[AI] Frame=%d | ⚠️ NO PARENT" % current_frame)
		if not opponent:
			Debug.log("[AI] Frame=%d Seat=%s | 🔍 Searching for opponent..." % [current_frame, seat])
	
	# ============================================================
	# HEALTH CHECK: STOP ALL ACTIONS IF ANY CHARACTER IS DEFEATED
	# ============================================================
	# When any player's health reaches 0 or below, AI stops all actions and calculations
	if parent and "healthbar" in parent and parent.healthbar:
		if parent.healthbar.current_health <= 0:
			if debug_mode and current_frame % 120 == 0:
				Debug.log("[AI] Frame=%d Seat=%s | 💀 AI SELF DEFEATED (health=%.1f) - Stopping all actions" % [
					current_frame, seat, parent.healthbar.current_health
				])
			return _neutral_input()
	
	if opponent and "healthbar" in opponent and opponent.healthbar:
		if opponent.healthbar.current_health <= 0:
			if debug_mode and current_frame % 120 == 0:
				Debug.log("[AI] Frame=%d Seat=%s | 💀 OPPONENT DEFEATED (health=%.1f) - Stopping all actions" % [
					current_frame, seat, opponent.healthbar.current_health
				])
			return _neutral_input()
	
	if not ai_enabled or not opponent or not parent:
		return _neutral_input()
	
	# 【DEBUG】每30幀顯示一次AI完整狀態摘要（0.25秒）
	if current_frame % 30 == 0 and current_frame > 0:
		var state_str = ""
		if commitment_frames > 0:
			state_str = "🔄 EXECUTING '%s' (%d frames)" % [current_committed_action, commitment_frames]
		elif decision_cooldown_frames > 0:
			state_str = "⏳ COOLDOWN (%d frames)" % decision_cooldown_frames
		else:
			state_str = "🤔 EVALUATING NEW DECISION"
		var summary_distance = abs(parent.global_position.x - opponent.global_position.x)
		Debug.log("[AI SUMMARY] Frame=%d Seat=%s | %s | dist=%.0f opp=%s" % [
			current_frame, seat, state_str, summary_distance, 
			opponent.attack_type if opponent.is_attacking else ("blocking" if opponent.is_blocking else "idle")
		])
	
	# ============================================================
	# LAYER 0: EMERGENCY BLOCK OVERRIDE (Highest Priority)
	# ============================================================
	# If opponent is attacking (normal OR special) and in range, ALWAYS block immediately
	# This bypasses all decision layers and commitments
	var opponent_move_set = opponent.get_node_or_null("MoveSet") if opponent else null
	var opponent_doing_special = opponent_move_set != null and "is_spmove" in opponent_move_set and opponent_move_set.is_spmove
	if opponent and (opponent.is_attacking or opponent_doing_special):
		var attack_distance = abs(parent.global_position.x - opponent.global_position.x)
		var attack_type = opponent.attack_type if "attack_type" in opponent else "st_mp"
		# 火球必殺技的威脅由 projectile 系統處理，不在近身範圍觸發 emergency block
		var is_projectile_special = attack_type in ["fireball", "spm2"]
		if not is_projectile_special:
			var attack_range = 150.0  # Conservative estimate
			if threat_system and threat_system.has_method("get_attack_range_for"):
				attack_range = threat_system.get_attack_range_for(opponent, attack_type)
			
			if attack_distance <= attack_range + 20.0:
				# Cancel any dash state
				_cancel_dash_state()
				
				# Force block immediately
				var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
				var input_dir = -int(relative_dir) if relative_dir != 0 else -int(parent.facing_direction)
				var block_input = _neutral_input()
				block_input.input_dir = input_dir
				block_input.block_pressed = true
				
				# Check if should crouch block
				if attack_type.begins_with("cr_"):
					block_input.crouch_pressed = true
				
				if debug_mode or debug_block_trace:
					Debug.log("[AI EMERGENCY BLOCK] attack=%s dist=%.1f range=%.1f input_dir=%d facing=%.1f" % [
						attack_type, attack_distance, attack_range, input_dir, parent.facing_direction
					])
				
				return block_input
	
	# ============================================================
	# LAYER 1: ACTION COMMITMENT (Highest Priority)
	# ============================================================
	# If currently committed to an action, continue executing it
	# This prevents jittery behavior and ensures smooth action completion
	if commitment_frames > 0:
		# Allow defensive override on high/critical threats or imminent contact
		var commitment_threat = threat_system.evaluate_threats(parent, opponent) if threat_system else null
		var imminent_contact = _is_attack_in_block_range(opponent)
		# 火球只有進入實際反應窗口後才中斷承諾，避免遠距火球造成過早跳躍或抖動。
		var has_fireball_threat = commitment_threat != null and commitment_threat.source == "fireball" and commitment_threat.level >= ThreatAssessment.ThreatLevel.MEDIUM
		
		# 🔴 【新增】 Tactical situation interrupt: If committed to approach (dash/walk) but entered throw range
		# Re-evaluate instead of blindly continuing approach
		var commitment_distance = abs(parent.global_position.x - opponent.global_position.x)
		var should_check_throw = current_committed_action in ["dash_forward", "walk_forward", "backdash", "walk_backward"]
		var entered_throw_range = should_check_throw and commitment_distance < 120.0  # Throw range
		
		if Engine.get_physics_frames() % 60 == 0 and should_check_throw:
			Debug.log("[AI COMMIT CHECK] Frame=%d | action='%s' | dist=%.0f | throw_range=%s | opp_attacking=%s" % [
				Engine.get_physics_frames(), current_committed_action, commitment_distance, entered_throw_range, str(opponent.is_attacking) if opponent else "?"
			])
		
		if (commitment_threat and commitment_threat.level >= ThreatAssessment.ThreatLevel.MEDIUM) or imminent_contact or has_fireball_threat:
			if current_committed_action in ["dash_forward", "backdash"]:
				_cancel_dash_state()
			if current_committed_action not in ["stand_block", "crouch_block"]:
				commitment_frames = 0
				committed_input = {}
		elif entered_throw_range and opponent and not opponent.is_attacking:
			# 【DEBUG】當進入投擲範圍但對手未攻擊時，中斷承諾以重新評估
			if Engine.get_physics_frames() % 30 == 0:
				Debug.log("[AI INTERRUPT] Frame=%d Seat=%s | Committed to '%s' but entered throw range (dist=%.0f) → Re-evaluating" % [
					Engine.get_physics_frames(), seat, current_committed_action, commitment_distance
				])
			commitment_frames = 0
			committed_input = {}
			decision_cooldown_frames = 0  # 【FIX】Also clear cooldown to allow immediate re-evaluation
			current_committed_action = ""
		else:
			# Release block commitment once blockstun ends to allow punish
			if current_committed_action in ["stand_block", "crouch_block"] and parent and not parent.is_blocking:
				commitment_frames = 0
				committed_input = {}
				current_committed_action = ""
			else:
				if current_committed_action in ["stand_block", "crouch_block"] and parent and "blockstun_frames" in parent:
					# Stage 1：blockstun 已是物理幀，直接同域鉗制（舊版要先 ÷120 換秒）
					commitment_frames = min(commitment_frames, parent.blockstun_frames)
				commitment_frames = max(0, commitment_frames - 1)
				if debug_mode and Engine.get_physics_frames() % 60 == 0:
					Debug.log("[AI] Committed: %s (%d frames remaining)" % [current_committed_action, commitment_frames])
				
				# 🔴 【FIX】Special moves and throws need different handling:
				# - throw: One-time button press (send once, then clear)
				# - special moves: Keep input active for full duration (fireball, dp, etc. need animation time)
				# - dashes/walks: Continuous input (keep direction active)
				var output = committed_input.duplicate()
				
				# Only use one-time send for throw (which is instantaneous)
				if current_committed_action == "throw":
					if not commitment_one_time_sent:
						commitment_one_time_sent = true
					else:
						# After first frame, clear throw_pressed
						output["throw_pressed"] = false
				# Special moves: keep ALL input active (spm2_pressed, dp_pressed, motion, etc.)
				elif current_committed_action in SPECIAL_MOVE_ACTIONS:
					# Keep the special move input active for full commitment duration
					# Don't clear spm2_pressed, dp_pressed, etc.
					pass  # output remains as committed_input
				# Other actions (dash, walk, block): also keep input active
				# This ensures smooth execution for multi-frame actions
				
				return output
	
	# 承諾動作剛剛自然結束：清除舊輸入，避免持續走路/重複按鍵
	if current_committed_action != "" and commitment_frames <= 0:
		committed_input = _neutral_input()
		current_committed_action = ""
		commitment_one_time_sent = false  # 【FIX】重置單次命令標記
		decision_cooldown_frames = 0  # 立即重新評估下一個動作

	# ============================================================
	# LAYER 2: COMBO PROTECTION (Special State)
	# ============================================================
	# Combos have absolute protection - cannot be interrupted
	if combo_system.is_executing_combo():
		var next_move = combo_system.get_next_combo_move()
		if next_move:
			if debug_mode:
				Debug.log("[AI] Combo step: %s" % next_move)
			return _commit_action(next_move, 0.4)
		else:
			combo_system.reset_combo()
	
	# ============================================================
	# LAYER 3: DECISION COOLDOWN
	# ============================================================
	# Don't re-evaluate every frame - simulates human reaction time
	if decision_cooldown_frames > 0:
		decision_cooldown_frames -= 1
		# 【DEBUG】每15幀顯示一次決策冷卻狀態（0.125秒）
		if Engine.get_physics_frames() % 15 == 0:
			var cooldown_threat = threat_system.evaluate_threats(parent, opponent) if threat_system else null
			var cooldown_threat_str = "NONE"
			if cooldown_threat:
				var threat_levels = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"]
				cooldown_threat_str = threat_levels[min(cooldown_threat.level, 4)] if cooldown_threat.level >= 0 else "NONE"
			var cooldown_distance = abs(parent.global_position.x - opponent.global_position.x)
			Debug.log("[AI COOLDOWN] Frame=%d Seat=%s | ⏳ %d frames remaining | action='%s' | threat=%s | dist=%.0f" % [
				Engine.get_physics_frames(), seat, decision_cooldown_frames, current_committed_action, cooldown_threat_str, cooldown_distance
			])
		return committed_input if committed_input.size() > 0 else _neutral_input()
	
	# ============================================================
	# LAYER 4: NEW DECISION
	# ============================================================
	# Only reached every DECISION_INTERVAL seconds
	# 【DEBUG】新決策評估開始 - 顯示威脅評估
	var threat = threat_system.evaluate_threats(parent, opponent) if threat_system else null
	var threat_str = "NONE"
	if threat:
		var threat_levels = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"]
		threat_str = threat_levels[min(threat.level, 4)] if threat.level >= 0 else "NONE"
		if threat.source != "":
			threat_str += " (" + threat.source + ")"
	
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var opp_state = ""
	if opponent:
		if opponent.is_attacking:
			opp_state = "ATTACKING"
		elif opponent.is_blocking:
			opp_state = "BLOCKING"
		elif opponent.is_knockfly:
			opp_state = "KNOCKFLY"
		else:
			opp_state = "IDLE"
	
	Debug.log("[AI EVAL] Frame=%d Seat=%s | 🎯 Evaluating... | opponent=%s(%s) | dist=%.0f | threat=%s" % [
		Engine.get_physics_frames(), seat, str(opponent.name) if opponent else "none", opp_state, distance, threat_str
	])
	
	var decision = decision_layers.get_best_decision(parent, opponent)
	
	# 【DEBUG】決策結果輸出
	Debug.log("[AI DECISION] Frame=%d Seat=%s | ✅ Selected: '%s' (priority: %.1f) | reason: %s" % [
		Engine.get_physics_frames(), seat, decision.action, decision.priority, decision.reason
	])
	if debug_block_trace and opponent and opponent.is_attacking:
		var attack_frame = opponent.attack_start_frame if "attack_start_frame" in opponent else Engine.get_physics_frames()
		var attack_type = opponent.attack_type if "attack_type" in opponent else "st_mp"
		if decision.action in ["stand_block", "crouch_block"] and (attack_frame != _last_block_trace_attack_frame or decision.action != _last_block_trace_action):
			var dist = abs(parent.global_position.x - opponent.global_position.x)
			var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
			var input_dir = -int(relative_dir) if relative_dir != 0 else -int(parent.facing_direction)
			var holding_back = input_dir * parent.facing_direction < 0
			Debug.log("[AI BLOCK TRACE] action=%s attack=%s dist=%.1f input_dir=%d facing=%.1f holding_back=%s dashing=%s backdash=%s attacking=%s" % [
				decision.action, attack_type, dist, input_dir, parent.facing_direction, holding_back,
				parent.is_dashing, parent.is_backdashing, parent.is_attacking
			])
			_last_block_trace_attack_frame = attack_frame
			_last_block_trace_action = decision.action
	
	# 檢查招式是否被限制，如果是則獲取替代決策
	if enable_move_restrictions and decision.action in restricted_moves:
		if debug_mode or Engine.get_physics_frames() % 60 == 0:
			Debug.log("[AI] Move '%s' (priority: %.1f) is restricted, finding alternative..." % [decision.action, decision.priority])
		decision = decision_layers.get_fallback_decision(parent, opponent)
		if debug_mode or Engine.get_physics_frames() % 60 == 0:
			Debug.log("[AI] Fallback decision: '%s' (priority: %.1f)" % [decision.action, decision.priority])
	
	# ============================================================
	# ADAPTIVE DECISION INTERVAL ADJUSTMENT (Phase 2)
	# ============================================================
	# 根據威脅等級調整決策間隔，在危急時刻反應迅速
	var active_interval: float
	if decision_interval_override > 0:
		active_interval = decision_interval_override
	elif decision_interval_override == 0:
		if enable_adaptive_interval:
			# 獲取威脅信息以調整間隔（重用已聲明的threat變數）
			if threat:
				_adjust_decision_interval(threat.level, distance)
				active_interval = current_adaptive_interval
			else:
				active_interval = DECISION_INTERVAL
		else:
			active_interval = DECISION_INTERVAL
	else:  # < 0, immediate updates
		active_interval = 0.0
	if frame_data and frame_data.get_punish_window_logic(parent, opponent) > 0:
		active_interval = min(active_interval, INTERVAL_CRITICAL)
	# Stage 1：設計者秒數 → 物理幀種子，經唯一邊界轉換（0.033s → 4 tick ≈ 2 邏輯幀，
	# 0.016s → 2，0.05s → 6，與註解的意圖一致；舊版依 _process 真實 delta 遞減，
	# 實際 tick 數隨渲染幀率浮動）。負 override → max(0, round(...)) = 0（立即重評）。
	decision_cooldown_frames = Movement.seconds_to_frames_nearest(active_interval)
	
	# ============================================================
	# 增強的調試輸出
	# ============================================================
	if debug_mode and verbose_decision_logs and not debug_block_trace:
		# 獲取威脅信息（重用已聲明的threat變數）
		if threat:
			var threat_level_str = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"][threat.level]
			Debug.log("\n[AI DECISION] %s" % parent.name)
			Debug.log("  動作: %s" % decision.action)
			Debug.log("  優先級: %.1f" % decision.priority)
			Debug.log("  理由: %s" % decision.reason)
			if enable_adaptive_interval:
				Debug.log("  決策間隔: %.3f (自適應)" % active_interval)
			
			if threat.level > 0:  # 有威脅時顯示威脅信息
				Debug.log("  威脅等級: %s" % threat_level_str)
				if threat.source != "":
					Debug.log("  威脅來源: %s" % threat.source)
				if threat.frames_until_hit < 999:
					Debug.log("  撞擊幀數: %d" % threat.frames_until_hit)
	elif debug_mode and verbose_decision_logs and not debug_block_trace and (Engine.get_physics_frames() % 20 == 0 or decision.action in SPECIAL_MOVE_ACTIONS):
		# 簡化日誌（保持原有行為）
		Debug.log("[AI] %s decision: %s (priority: %.1f) - %s" % [parent.name, decision.action, decision.priority, decision.reason])
	
	# Handle combo start
	if decision.action.begins_with("combo_"):
		var combo_name = decision.action.substr(6)
		combo_system.start_combo(combo_name)
		var first_move = combo_system.get_next_combo_move()
		if first_move:
			return _commit_action(first_move, 0.4)
	
	# ============================================================
	# FINAL SAFETY CHECK: Ensure no restricted moves slip through
	# ============================================================
	if enable_move_restrictions and decision.action in restricted_moves:
		if debug_mode or Engine.get_physics_frames() % 60 == 0:
			Debug.log("[AI] WARNING: Final check caught restricted move '%s', reverting to walk_forward" % decision.action)
		decision.action = "walk_forward"
	
	# Commit to the decided action
	var duration = _get_action_duration(decision.action)
	return _commit_action(decision.action, duration)

func _commit_action(action: String, duration: float) -> Dictionary:
	"""
	Commit to executing an action for a minimum duration
	This is the core of preventing jittery behavior
	"""
	if action in ["stand_block", "crouch_block"]:
		_cancel_dash_state()

	current_committed_action = action
	# Stage 1：承諾時長（動畫秒）→ 物理幀種子，經唯一邊界轉換
	commitment_frames = Movement.seconds_to_frames_nearest(duration)
	committed_input = _action_to_input(action)
	commitment_one_time_sent = false  # 【FIX】重置單次命令標記，確保新承諾時能正確發送
	
	# 【DEBUG】顯示承諾什麼動作（不受debug_mode限制）
	var special_keys = ["throw_pressed", "spm1_pressed", "spm2_pressed", "spm3_pressed", "dp_pressed"]
	var _special_input = ""
	for key in special_keys:
		if committed_input.get(key, false):
			_special_input = key.replace("_pressed", "")
			break
	
	var _movement = ""
	if committed_input.get("input_dir", 0) != 0:
		_movement = "→" if committed_input.get("input_dir", 0) > 0 else "←"
	if committed_input.get("crouch_pressed", false):
		_movement += "↓"
	
	var action_icon = ""
	if action in ["st_lp", "st_mp", "st_hp", "cr_lp", "cr_mp", "cr_hp"]:
		action_icon = "👊"
	elif action in ["st_lk", "st_mk", "st_hk", "cr_lk", "cr_mk", "cr_hk"]:
		action_icon = "🦵"
	elif action == "throw":
		action_icon = "🔗"
	elif action in ["fireball", "fireballL", "fireballM", "fireballH"]:
		action_icon = "🔥"
	elif action in ["dp", "dpL", "dpM", "dpH"]:
		action_icon = "⬆️"
	elif action in ["powerkk", "spnk"]:
		action_icon = "💥"
	elif "dash" in action:
		action_icon = "🚀"
	elif "walk" in action:
		action_icon = "🚶"
	elif "block" in action:
		action_icon = "🛡️"
	
	Debug.log("[AI COMMIT] Frame=%d Seat=%s | %s %s (%.2fs)" % [
		Engine.get_physics_frames(),
		parent.seat if "seat" in parent else "?",
		action_icon,
		action,
		duration
	])
	
	return committed_input

func _get_action_duration(action: String) -> float:
	"""
	【智能查詢】獲取動作承諾時長：
	1. 從AnimationPlayer動態加載的值（st_hk, st_mp 等攻擊）
	2. 備用硬編碼值（移動、防守等非動畫動作）
	3. 預設 0.3 秒
	
	使用變量時長增加不可預測性（特別是移動動作）
	"""
	if action.begins_with("combo_"):
		return 1.5  # Combos are always protected for full duration
	
	# 【動態優先】查詢動畫時長或備用值
	return get_action_duration(action)

func _action_to_input(action: String) -> Dictionary:
	"""將動作轉換為輸入字典"""
	var input = _neutral_input()
	
	if not opponent:
		return input
	
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)
	if relative_dir == 0:
		relative_dir = int(parent.facing_direction)
	
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
		"throw":
			input.throw_pressed = true
			if debug_mode:
				Debug.log("[AI._action_to_input] Frame=%d Seat=%s | Setting throw_pressed=true" % [
					Engine.get_physics_frames(),
					parent.seat if parent and "seat" in parent else "?"
				])
		"fireball", "spm2":
			# ⚠️ 檢查：不應該到達這裡（應該被決策層過濾）
			if enable_move_restrictions and "fireball" in restricted_moves:
				if debug_mode:
					Debug.log("[AI._action_to_input] WARNING: Fireball action reached input conversion despite being restricted!")
				# 返回中立輸入，不執行
				return _neutral_input()
			input.spm2_pressed = true
			input["ai_special_variant"] = "fireball"  # Store variant for MoveSet
			if debug_mode:
				Debug.log("[AI._action_to_input] %s: Setting spm2_pressed=true for action '%s'" % [parent.name, action])
		# 🔴 【新增】Fireball 變體 (L/M/H)
		"fireballL", "fireballM", "fireballH":
			if enable_move_restrictions and "fireball" in restricted_moves:
				return _neutral_input()
			input.spm2_pressed = true
			input["ai_special_variant"] = action  # Store the specific variant (fireballL, fireballM, fireballH)
			if debug_mode:
				Debug.log("[AI._action_to_input] %s: Setting spm2_pressed=true for variant '%s'" % [parent.name, action])
		"powerkk", "spm1":
			if enable_move_restrictions and "powerkk" in restricted_moves:
				if debug_mode:
					Debug.log("[AI._action_to_input] WARNING: Powerkk action reached input conversion despite being restricted!")
				return _neutral_input()
			input.spm1_pressed = true
			input["ai_special_variant"] = action  # Store variant
		"spnk":
			if enable_move_restrictions and "spnk" in restricted_moves:
				return _neutral_input()
			input.spm1_pressed = true
			input["ai_special_variant"] = action
		"hdk":
			if enable_move_restrictions and "hdk" in restricted_moves:
				return _neutral_input()
			input.spm3_pressed = true
			input["ai_special_variant"] = action
		"214K":
			# 🔴 【WOO 新招】214 + 任意腳（WOO 專屬）
			if parent.character_id != "WOO":
				return _neutral_input()
			if enable_move_restrictions and "214K" in restricted_moves:
				return _neutral_input()
			input["sp214k_pressed"] = true
			input["ai_special_variant"] = action
		"623K":
			# 🔴 【WOO 新招】623 + 任意腳（WOO 專屬）
			if parent.character_id != "WOO":
				return _neutral_input()
			if enable_move_restrictions and "623K" in restricted_moves:
				return _neutral_input()
			input["sp623k_pressed"] = true
			input["ai_special_variant"] = action
		# 🔴 【新增】DP 變體 (L/M/H)
		"dpL", "dpM", "dpH":
			if enable_move_restrictions and "dp" in restricted_moves:
				return _neutral_input()
			input.dp_pressed = true
			input["ai_special_variant"] = action
			if debug_mode:
				Debug.log("[AI._action_to_input] %s: Setting dp_pressed=true for DP variant '%s'" % [parent.name, action])
		"dp":
			if enable_move_restrictions and "dp" in restricted_moves:
				if debug_mode:
					Debug.log("[AI._action_to_input] WARNING: DP action reached input conversion despite being restricted!")
				return _neutral_input()
			input.dp_pressed = true
			input["ai_special_variant"] = "dp"
		# 🔴 【新增】100p 多段必殺技
		"100p":
			if parent.character_id == "DAV":
				input.super_pressed = true  # 使用super_pressed作為100p的輸入
				input["ai_special_variant"] = "100p"
				if debug_mode:
					Debug.log("[AI._action_to_input] %s: Setting super_pressed=true for 100p" % parent.name)
			else:
				# 非DAV角色不應該執行100p
				return _neutral_input()
		"super":
			if enable_move_restrictions and "super" in restricted_moves:
				return _neutral_input()
			input.super_pressed = true
			input["ai_special_variant"] = "super"
		"dash_forward":
			input.dash_pressed = true
			input.input_dir = int(relative_dir)
		"backdash":
			input.backdash_pressed = true
			input.input_dir = -int(relative_dir)
		"jump_forward":
			input.jump_pressed = true
			input.input_dir = int(relative_dir)
			if debug_mode:
				var frame_count = Engine.get_physics_frames()
				var dist = abs(parent.global_position.x - opponent.global_position.x) if opponent else 0
				Debug.log("[AI ACTION→INPUT] Frame=%d | jump_forward | dir=%d | dist=%.1f | opponent_y=%.1f | self_y=%.1f" % [
					frame_count, int(relative_dir), dist, 
					opponent.global_position.y if opponent else 0.0,
					parent.global_position.y
				])
		"jump_backward":
			input.jump_pressed = true
			input.input_dir = -int(relative_dir)
			if debug_mode:
				var frame_count = Engine.get_physics_frames()
				Debug.log("[AI ACTION→INPUT] Frame=%d | jump_backward | dir=%d" % [frame_count, -int(relative_dir)])
		"jump_neutral":
			input.jump_pressed = true
			input.input_dir = 0
			if debug_mode:
				var frame_count = Engine.get_physics_frames()
				var dist = abs(parent.global_position.x - opponent.global_position.x) if opponent else 0
				Debug.log("[AI ACTION→INPUT] Frame=%d | jump_neutral | dist=%.1f | opponent_y=%.1f | self_y=%.1f" % [
					frame_count, dist,
					opponent.global_position.y if opponent else 0.0,
					parent.global_position.y
				])
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
		"backdash_pressed": false,
		"throw_pressed": false,
		# Stage 4：補上 `attack_type` 鍵，讓 AI 路徑的 input 字典與人類路徑
		# 形狀一致。中立輸入一律為 "none"；實際值由 Player.get_input() 在
		# merge 之後呼叫 PlayerController.resolve_attack_type() 重算，
		# 所以這裡填什麼都會被覆寫 —— 但寫進去讓任何「AI 的 input 不帶
		# attack_type」這類下游讀取（除錯、日誌、測試）都得到一致答案。
		"attack_type": "none",
	}

func _cancel_dash_state() -> void:
	if not parent:
		return
	if "is_dashing" in parent:
		parent.is_dashing = false
	if "is_backdashing" in parent:
		parent.is_backdashing = false
	if "dash_timer" in parent:
		parent.dash_timer = 0
	# 🟢 【修復】不在 knockback / block_knockback 期間清零速度，
	# 否則每幀都會抹掉 PushManager 設置的格擋退後速度，導致 AI 格擋時沒有後退位移。
	var in_knockback = "knockback_frames" in parent and parent.knockback_frames > 0
	var in_block_knockback = "block_knockback_frames" in parent and parent.block_knockback_frames > 0
	if "fixed_velocity" in parent and not in_knockback and not in_block_knockback:
		parent.fixed_velocity.x = 0
	if "landing_facing_lock" in parent:
		parent.landing_facing_lock = false
	if "dash_initial_speed" in parent:
		parent.dash_initial_speed = 0.0
	if "dash_total_time" in parent:
		parent.dash_total_time = 0.0

# ============================================================
# SPECIAL MOVE COMMITMENT CLEARING (Combat Deduplication)
# ============================================================
func clear_special_move_commitment() -> void:
	"""
	【FIX】當特殊招式動畫完成時由 MoveSet 呼叫
	清除 AI 的特殊招式承諾，防止無限重複發射（如 fireball）
	
	根本原因：
	- AI commitment_frames 是為「決策時長」而設計（e.g., 0.8s ≈ 96 物理幀）
	- 但特殊招式的動畫比 commitment 短（e.g., 0.783秒）
	- 動畫完成後，commitment 仍在運行，導致 get_ai_input() 繼續返回 spm2_pressed=true
	- 結果：同一特殊招式無限重複執行
	
	解決方案：
	- 當 MoveSet.stop_special_move() 呼叫此方法時，
	  立即清除 commitment 和所有特殊招式輸入
	- 強制 AI 重新評估下一個決策
	"""
	if not ai_enabled or not parent:
		return
	
	var current_frame = Engine.get_physics_frames()
	var seat = parent.seat if "seat" in parent else "?"
	
	# 只清除特殊招式相關的承諾（防止誤清除其他承諾如投擲）
	if current_committed_action in SPECIAL_MOVE_ACTIONS:
		Debug.log("[AI FIX - CLEAR SPECIAL MOVE] Frame=%d Seat=%s | Clearing commitment for '%s'" % [
			current_frame, seat, current_committed_action
		])
		
		# 清除所有特殊招式輸入（防止重複）
		commitment_frames = 0
		committed_input = _neutral_input()
		current_committed_action = ""
		commitment_one_time_sent = false
		decision_cooldown_frames = 0  # 立即重新評估，允許下一個決策
		_invalidate_cached_input()

func _invalidate_cached_input() -> void:
	_cached_input_frame = -1
	_cached_input_result = {}

func _is_attack_in_block_range(target: Player) -> bool:
	if not target or not target.is_attacking or not parent:
		return false
	var attack_type = target.attack_type if "attack_type" in target else "st_mp"
	var attack_range = threat_system.get_attack_range_for(target, attack_type) if threat_system else 100.0
	var distance = abs(parent.global_position.x - target.global_position.x)
	return distance <= attack_range + 10.0
