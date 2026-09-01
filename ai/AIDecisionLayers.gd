class_name AIDecisionLayers extends Node

enum DecisionLayer { SURVIVAL, PUNISH, TACTICAL, POSITIONING, IDLE }

# ============================================================
# DECISION CACHING SYSTEM
# ============================================================
var decision_cache: Decision = null
var cache_timer: float = 0.0
const CACHE_DURATION: float = 0.1  # Cache for 6 frames at 60 FPS (100ms)

@export var enable_decision_cache: bool = true
@export var cache_duration_override: float = 0.0  # Set to 0 to use CACHE_DURATION, >0 for custom, <0 to disable caching
@export var debug_block_trace: bool = false

# ============================================================
# PRIORITY CONSTANTS (Deterministic Hierarchy)
# ============================================================
# Based on fighting game AI research - clear priority layers
# NO frame-by-frame randomization

# Critical priorities
const PRIORITY_CRITICAL = 100.0      # Immediate survival threats
const PRIORITY_SURVIVAL = 85.0       # High threats
const PRIORITY_PUNISH = 90.0         # Opponent recovery

# Tactical priorities (distance-based)
const PRIORITY_COMBO = 75.0          # Close range combo execution
const PRIORITY_SPECIAL_CLOSE = 70.0  # Close range special moves (DP, etc.)
const PRIORITY_NORMAL_HIGH = 67.0    # High priority normals (st_mk)
const PRIORITY_NORMAL_MID = 67.0     # Mid priority normals (st_mp)
const PRIORITY_NORMAL_LOW = 67.0     # Low priority normals (cr_mk)
const PRIORITY_CROUCH = 67.0         # Crouch attacks

# Movement priorities
const PRIORITY_DASH_APPROACH = 65.0  # Aggressive dash forward
const PRIORITY_APPROACH = 63.0       # Steady approach
const PRIORITY_WALK_FORWARD = 62.0   # Walk forward
const PRIORITY_WALK_FORWARD_MID = 59.0  # Walk forward (mid range, lower priority)
const PRIORITY_RETREAT = 60.0        # Tactical retreat
const PRIORITY_WALK_BACK = 58.0      # Walk backward

# Zoning/Defense priorities
const PRIORITY_FIREBALL = 64.0       # Projectile zoning (increased)
const PRIORITY_BLOCK = 72.0          # Defensive blocking (increased)
const PRIORITY_CROUCH_BLOCK = 71.0   # Crouch blocking (increased)
const PRIORITY_OBSERVE = 48.0        # Wait and observe
const PRIORITY_JUMP = 63.0           # Jump approach (increased)

# Positioning
const PRIORITY_POSITIONING = 30.0    # Space control
const PRIORITY_IDLE = 10.0           # Default behavior
const PRIORITY_CROUCH_LOW = 63.0     # Crouch attacks (alternative priority)

const FIREBALL_JUMP_MIN_FRAMES: int = 16
const FIREBALL_JUMP_MAX_FRAMES: int = 42
const FIREBALL_FAR_DISTANCE: float = 280.0

const SPECIAL_MOVE_ACTIONS = ["fireball", "fireballL", "fireballM", "fireballH", "spm2", "powerkk", "spnk", "hdk", "dp", "dpL", "dpM", "dpH", "100p", "super", "214K", "623K"]

class Decision:
	var layer: DecisionLayer
	var action: String
	var priority: float = 0.0
	var reason: String = ""

var threat_system: ThreatAssessment
var frame_data: FrameDataManager
var combo_system: AIComboSystem
var space_control: SpaceControl
var hitbox_cache: HitboxCache = null  # 【新增】投擲框碰撞檢測

# Move restrictions (set by AIBehavior)
var restricted_moves: Array[String] = []

func _can_jump_fireball(threat: ThreatAssessment.ThreatInfo, distance: float) -> bool:
	if threat.source != "fireball":
		return false
	if threat.frames_until_hit < FIREBALL_JUMP_MIN_FRAMES:
		return false
	if threat.frames_until_hit > FIREBALL_JUMP_MAX_FRAMES:
		return false
	return distance <= FIREBALL_FAR_DISTANCE

func _get_fireball_defense_action(threat: ThreatAssessment.ThreatInfo, distance: float) -> String:
	if _can_jump_fireball(threat, distance):
		return "jump_forward" if distance < 230.0 else "jump_neutral"
	if threat.frames_until_hit < FIREBALL_JUMP_MIN_FRAMES:
		return "stand_block"
	return "stand_block"

# ============================================================
# SPECIAL MOVE COOLDOWN SYSTEM
# ============================================================
# 防止必殺技刷屏：每次使用必殺技後必須等待一段時間
var special_cooldown_timer: float = 0.0
const SPECIAL_COOLDOWN: float = 2.2  # 必殺技使用後 2.2 秒內不可再次使用

# ============================================================
# HELPER METHODS FOR MOVE RESTRICTION CHECKING
# ============================================================
func _is_move_restricted(move_name: String) -> bool:
	"""Check if a move is in the restricted moves list"""
	if move_name.begins_with("fireball") and "fireball" in restricted_moves:
		return true
	if move_name.begins_with("dp") and "dp" in restricted_moves:
		return true
	return move_name in restricted_moves

func _get_unrestricted_alternative(primary_move: String, alternatives: Array[String]) -> String:
	"""Get the first unrestricted alternative from a list, or return primary if none restricted"""
	if not _is_move_restricted(primary_move):
		return primary_move
	
	for alt in alternatives:
		if not _is_move_restricted(alt):
			return alt
	
	# If all alternatives are restricted, return the least-priority one (last in alternatives)
	return alternatives[-1] if alternatives.size() > 0 else "stand_block"

func _ready() -> void:
	"""Initialize HitboxCache reference"""
	call_deferred("_init_hitbox_cache")

func _init_hitbox_cache() -> void:
	"""初始化 HitboxCache 引用"""
	hitbox_cache = get_tree().get_first_node_in_group("hitbox_cache")
	
	if not hitbox_cache:
		push_warning("[AIDecisionLayers] HitboxCache 未找到，投擲決策將使用後備距離")

func _process(delta: float) -> void:
	"""Update cache and cooldown timers"""
	if cache_timer > 0:
		cache_timer -= delta
	if special_cooldown_timer > 0:
		special_cooldown_timer -= delta

func get_best_decision(ai_player: Player, opponent: Player) -> Decision:
	var current_threat = threat_system.evaluate_threats(ai_player, opponent) if threat_system else null
	var has_active_threat = current_threat != null and current_threat.level >= ThreatAssessment.ThreatLevel.MEDIUM
	var cached_special = decision_cache != null and decision_cache.action in SPECIAL_MOVE_ACTIONS
	
	# Use cached decision if valid
	if enable_decision_cache and cache_timer > 0 and decision_cache != null and not has_active_threat and not cached_special:
		return decision_cache
	
	# Original decision calculation logic follows
	var decisions: Array[Decision] = []
	var filtered_count = 0
	
	# Layer 1: 生存層（最高優先級）
	var survival = _evaluate_survival_layer(ai_player, opponent)
	if survival and survival.priority >= 95:
		# 關鍵生存決策，如果被限制則強制使用格擋
		if survival.action in restricted_moves:
			survival.action = "stand_block"
			survival.reason = "Survival (restricted move fallback)"
		_cache_decision(survival)
		return survival
	elif survival:
		if survival.action in restricted_moves:
			filtered_count += 1
		else:
			decisions.append(survival)
	
	# Layer 2: 懲罰層
	var punish = _evaluate_punish_layer(ai_player, opponent)
	if punish:
		if punish.action in restricted_moves:
			filtered_count += 1
		else:
			decisions.append(punish)
	
	# Layer 3: 戰術層
	var tactical = _evaluate_tactical_layer(ai_player, opponent)
	for t in tactical:
		if t.action in restricted_moves:
			filtered_count += 1
		else:
			decisions.append(t)
	
	# Layer 4: 定位層
	var positioning = _evaluate_positioning_layer(ai_player, opponent)
	if positioning:
		if positioning.action in restricted_moves:
			filtered_count += 1
		else:
			decisions.append(positioning)
	
	# Debug: 顯示過濾統計
	if filtered_count > 0 and Engine.get_physics_frames() % 120 == 0:
		Debug.log("[AI] Filtered %d restricted moves. Available decisions: %d" % [filtered_count, decisions.size()])
		if decisions.size() > 0:
			var top_5 = decisions.slice(0, min(5, decisions.size()))
			for d in top_5:
				Debug.log("  - %s (%.1f): %s" % [d.action, d.priority, d.reason])
	
	# Layer 5: 待機層（最低優先級）
	# 確保至少有一個決策
	if decisions.is_empty():
		var idle_decision = _get_idle_decision()
		_cache_decision(idle_decision)
		return idle_decision
	
	decisions.append(_get_idle_decision())
	
	# 排序並返回最高優先級決策
	decisions.sort_custom(func(a, b): return a.priority > b.priority)
	var best_decision = decisions[0]
	
	# 【DEBUG】 決策排序和選擇追蹤（只記錄 throw、special move 或每 60 幀一次）
	var is_throw_involved = best_decision.action == "throw" or decisions.any(func(d): return d.action == "throw")
	if is_throw_involved or best_decision.action in SPECIAL_MOVE_ACTIONS or Engine.get_physics_frames() % 60 == 0:
		Debug.log("[DECISION LAYER FINAL] Frame=%d Seat=%s | Selected: '%s' (%.1f) | reason: '%s'" % [
			Engine.get_physics_frames(),
			ai_player.seat if "seat" in ai_player else "?",
			best_decision.action,
			best_decision.priority,
			best_decision.reason
		])
		
		# 如果 throw 在決策列表中但沒被選中，說明優先級問題
		if is_throw_involved and best_decision.action != "throw":
			var throw_decisions = decisions.filter(func(d): return d.action == "throw")
			if throw_decisions.size() > 0:
				var throw_priority = throw_decisions[0].priority
				Debug.log("[THROW NOT SELECTED] Frame=%d | throw_priority=%.1f < selected_priority=%.1f | reason: '%s'" % [
					Engine.get_physics_frames(),
					throw_priority,
					best_decision.priority,
					best_decision.reason
				])
	
	_cache_decision(best_decision)
	return best_decision

func _cache_decision(decision: Decision) -> void:
	"""Cache the decision for reuse"""
	# 必殺技不能進入決策快取：一旦 commitment 被威脅中斷，舊 special 決策會被重複取出，造成同幀連續 COMMIT。
	if decision.action in SPECIAL_MOVE_ACTIONS:
		special_cooldown_timer = SPECIAL_COOLDOWN
		decision_cache = null
		cache_timer = 0.0
		return
	
	if enable_decision_cache:
		decision_cache = decision
		# Use override if > 0, use default if 0, disable if < 0
		if cache_duration_override > 0:
			cache_timer = cache_duration_override
		elif cache_duration_override == 0:
			cache_timer = CACHE_DURATION
		else:  # < 0, disable caching
			cache_timer = 0.0

func _evaluate_survival_layer(ai_player: Player, opponent: Player) -> Decision:
	var threat = threat_system.evaluate_threats(ai_player, opponent)
	var frame_count = Engine.get_physics_frames()
	
	# React to any threat level (including LOW for fireballs)
	if threat.level == ThreatAssessment.ThreatLevel.NONE:
		if opponent and opponent.is_attacking:
			var attack_type = opponent.attack_type if "attack_type" in opponent else "st_mp"
			var distance = abs(ai_player.global_position.x - opponent.global_position.x)
			var attack_range = threat_system.get_attack_range_for(opponent, attack_type) if threat_system else 100.0
			if distance <= attack_range + 10.0:
				var emergency = Decision.new()
				emergency.layer = DecisionLayer.SURVIVAL
				emergency.action = threat_system.get_defense_for_attack(attack_type) if threat_system else "stand_block"
				emergency.priority = PRIORITY_SURVIVAL
				emergency.reason = "Emergency block: " + attack_type
				Debug.log("[AI JUMP DECISION] Frame=%d | EMERGENCY BLOCK: %s (dist=%.1f)" % [frame_count, emergency.action, distance])
				return emergency
		return null
	
	var decision = Decision.new()
	decision.layer = DecisionLayer.SURVIVAL
	decision.action = threat.recommended_response
	var threat_distance = abs(ai_player.global_position.x - opponent.global_position.x)
	if threat.source == "fireball":
		decision.action = _get_fireball_defense_action(threat, threat_distance)
		if threat.level == ThreatAssessment.ThreatLevel.LOW and not _can_jump_fireball(threat, threat_distance):
			decision.priority = PRIORITY_OBSERVE
			decision.reason = "Low fireball threat: hold position"
			return decision
	if decision.action in SPECIAL_MOVE_ACTIONS and not _can_use_special(ai_player, opponent):
		decision.action = "stand_block"
		decision.reason = "Threat: %s (special gated)" % threat.source
		decision.priority = PRIORITY_SURVIVAL
		Debug.log("[AI JUMP DECISION] Frame=%d | GATED: %s → block (special unavailable) | threat=%s" % [frame_count, threat.recommended_response, threat.source])
		return decision
	
	# Adjust priority based on threat level
	if threat.level == ThreatAssessment.ThreatLevel.CRITICAL:
		decision.priority = PRIORITY_CRITICAL
		if frame_count % 5 == 0:  # 只在每5幀輸出日志（CRITICAL需要更及時）
			Debug.log("[AI JUMP DECISION] Frame=%d | CRITICAL threat | action=%s | frames_until_hit=%d | distance=%.1f" % [
				frame_count, decision.action, threat.frames_until_hit, 
				abs(ai_player.global_position.x - opponent.global_position.x)
			])
	elif threat.level == ThreatAssessment.ThreatLevel.HIGH:
		decision.priority = PRIORITY_SURVIVAL
		if frame_count % 10 == 0:  # 只在每10幀輸出日志
			Debug.log("[AI JUMP DECISION] Frame=%d | HIGH threat | action=%s | frames_until_hit=%d | source=%s" % [
				frame_count, decision.action, threat.frames_until_hit, threat.source
			])
	elif threat.level == ThreatAssessment.ThreatLevel.MEDIUM:
		if threat.source == "fireball" and _can_jump_fireball(threat, threat_distance):
			var jump_decision = Decision.new()
			jump_decision.layer = DecisionLayer.SURVIVAL
			jump_decision.action = _get_fireball_defense_action(threat, threat_distance)
			jump_decision.priority = PRIORITY_BLOCK + 3.0
			jump_decision.reason = "Threat: avoid fireball by jumping"
			if frame_count % 10 == 0:  # 只在每10幀輸出日志
				Debug.log("[AI JUMP DECISION] Frame=%d | MEDIUM fireball → %s | distance=%.1f | frames_until_hit=%d" % [
					frame_count, jump_decision.action, threat_distance, threat.frames_until_hit
				])
			return jump_decision
		decision.priority = PRIORITY_BLOCK
	else:  # LOW
		if threat.source == "fireball":
			decision.action = "stand_block"
			decision.priority = PRIORITY_OBSERVE
			decision.reason = "Low fireball threat: wait"
			if frame_count % 30 == 0:
				Debug.log("[AI FIREBALL HOLD] Frame=%d | LOW threat, no early jump | distance=%.1f | frames_until_hit=%d" % [
					frame_count, threat_distance, threat.frames_until_hit
				])
			return decision
		# For LOW threats (non-fireball), use tactical priority
		decision.priority = 68.0  # Similar to normal attacks
	
	decision.reason = "Threat: " + threat.source
	return decision

func _evaluate_punish_layer(ai_player: Player, opponent: Player) -> Decision:
	# 檢查對手是否處於可懲罰狀態
	var punish_window = 0
	if opponent.is_hit or opponent.is_knockfly:
		punish_window = max(punish_window, frame_data.get_hitstun_frames_remaining_logic(opponent))
	if frame_data.is_in_recovery(opponent):
		punish_window = max(punish_window, frame_data.get_punish_window_logic(ai_player, opponent))
	if punish_window <= 0:
		return null
	
	var ai_blockstun = frame_data.get_blockstun_frames_remaining_logic(ai_player)
	if ai_blockstun > 1:
		return null
	
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	var best_punish = _select_punish_attack(ai_player, distance, punish_window)
	
	if best_punish == "":
		return null
	
	var decision = Decision.new()
	decision.layer = DecisionLayer.PUNISH
	decision.action = best_punish
	decision.priority = PRIORITY_PUNISH
	decision.reason = "Punish window %dF" % punish_window
	return decision

func _select_punish_attack(ai_player: Player, distance: float, punish_window: int) -> String:
	var char_id = ai_player.character_id if "character_id" in ai_player else "UNKNOWN"
	
	# 根據角色和距離選擇最佳懲罰招式
	var options = []
	
	if char_id == "DAV":
		options = [
			{"name": "dp", "range": 85.0, "damage": 15.0},
			{"name": "st_mk", "range": 95.0, "damage": 12.0},
			{"name": "st_mp", "range": 75.0, "damage": 10.0},
			{"name": "st_lp", "range": 65.0, "damage": 6.0},
			{"name": "cr_lp", "range": 60.0, "damage": 5.0},
		]
	else:  # DEN or others
		options = [
			{"name": "spnk", "range": 95.0, "damage": 12.0},
			{"name": "st_mk", "range": 95.0, "damage": 12.0},
			{"name": "st_mp", "range": 75.0, "damage": 10.0},
			{"name": "st_lp", "range": 65.0, "damage": 6.0},
			{"name": "cr_lp", "range": 60.0, "damage": 5.0},
		]
	
	var best_move = ""
	var best_score = -9999.0
	for option in options:
		if distance > option["range"]:
			continue
		var move_name = option["name"]
		if _is_move_restricted(move_name):
			continue
		var startup = frame_data.get_startup_frames(move_name)
		if startup > punish_window:
			continue
		var damage = option["damage"]
		var score = damage - (float(startup) * 0.35)
		if score > best_score:
			best_score = score
			best_move = move_name
	
	return best_move

func _can_use_special(ai_player: Player, opponent: Player) -> bool:
	if not ai_player or not opponent:
		return false
	# 必殺技冷卻中，不允許再次使用
	if special_cooldown_timer > 0:
		if Engine.get_physics_frames() % 30 == 0:
			Debug.log("[_can_use_special] cooldown_timer=%.2f > 0 → BLOCK SPECIAL" % special_cooldown_timer)
		return false
	# 懲罰窗口：永遠允許
	if opponent.is_hit or opponent.is_knockfly:
		return true
	if frame_data and frame_data.is_in_recovery(opponent):
		return true
	# 中立狀態下允許：只要 AI 玩家自己不在攻擊/受傷/被擊飛/空中的狀態
	var is_attacking = ai_player.is_attacking
	var is_hit = ai_player.is_hit
	var is_knockfly = ai_player.is_knockfly
	var is_on_floor = ai_player.is_on_floor()
	var can_use = not is_attacking and not is_hit and not is_knockfly and is_on_floor
	
	if Engine.get_physics_frames() % 30 == 0:
		Debug.log("[_can_use_special] attacking=%s hit=%s knockfly=%s on_floor=%s → %s" % [
			is_attacking, is_hit, is_knockfly, is_on_floor, can_use
		])
	
	return can_use

func _is_punish_opportunity(opponent: Player) -> bool:
	"""對手是否處於可懲罰狀態（被擊中、被擊飛、或在恢復動作）"""
	return opponent.is_hit or opponent.is_knockfly or frame_data.is_in_recovery(opponent)

# 【新增】輔助函數：檢查攻擊是否在有效範圍內（使用 HitboxCache）
func _is_attack_in_range(ai_player: Player, opponent: Player, attack_name: String) -> bool:
	"""
	使用 HitboxCache 檢查攻擊是否能到達對手
	
	參數：
	- ai_player: AI 玩家
	- opponent: 對手
	- attack_name: 攻擊名稱 (e.g., "st_mp", "cr_lk")
	
	返回：
	- true: 攻擊能到達對手
	- false: 攻擊距離不足
	"""
	if not hitbox_cache or not hitbox_cache.is_initialized:
		# HitboxCache 未初始化，使用後備：沒有距離限制
		return true
	
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	var ai_facing = ai_player.facing_direction if "facing_direction" in ai_player else 1.0
	
	# 使用 HitboxCache 檢查 hitbox 碰撞
	var has_collision = hitbox_cache.check_hitbox_collision(
		ai_player.global_position,
		ai_player.character_id,
		attack_name,
		opponent.global_position,
		opponent.character_id,
		ai_facing
	)
	
	if debug_attack_range:
		var ai_id = ai_player.character_id if "character_id" in ai_player else "?"
		if Engine.get_physics_frames() % 60 == 0:
			Debug.log("[HITBOX RANGE CHECK] Frame=%d | attack=%s | dist=%.1f | collision=%s" % [
				Engine.get_physics_frames(),
				attack_name,
				distance,
				has_collision
			])
	
	return has_collision

@export var debug_attack_range: bool = false  # 【新增】調試標誌

func _get_special_priority(opponent: Player) -> float:
	"""取得必殺技優先級：懲罰時高於普通攻擊，中立時低於普通攻擊"""
	if _is_punish_opportunity(opponent):
		return PRIORITY_PUNISH + randf_range(0.0, 5.0)  # 90-95，確保懲罰時使用
	else:
		return PRIORITY_SPECIAL_CLOSE - 9.0 + randf_range(-1.0, 5.0)  # 61-66，與普通攻擊競爭但通常落敗

func _evaluate_tactical_layer(ai_player: Player, opponent: Player) -> Array[Decision]:
	"""
	Tactical decision layer - DETERMINISTIC priority system
	NO random action selection - uses clear hierarchy
	"""
	var decisions: Array[Decision] = []
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	
	# ============================================================
	# FAR RANGE (> 250) - Primary goal: APPROACH with zoning
	# ============================================================
	if distance > 250:
		# Priority 1: Fireball (zoning) - only if not busy
		var can_special = _can_use_special(ai_player, opponent)
		var has_move_set = ai_player and ai_player.move_set and not ai_player.move_set.is_spmove
		
		if Engine.get_physics_frames() % 30 == 0:
			Debug.log("[TACTICAL LAYER] Frame=%d | dist=%.0f | can_special=%s move_set=%s restricted=%s" % [
				Engine.get_physics_frames(), distance, can_special, has_move_set, 
				"fireball" in restricted_moves
			])
		
		if has_move_set and can_special and "fireball" not in restricted_moves:
			# 🔴 【改進】DAV 使用 fireballL/M/H 變體；DEN 使用通用 fireball
			var fireball_variants = []
			var char_id = ai_player.character_id if "character_id" in ai_player else ""
			if char_id == "DAV":
				fireball_variants = ["fireballL", "fireballM", "fireballH"]
			else:
				fireball_variants = ["fireball"]
			
			for fb_variant in fireball_variants:
				var fb = Decision.new()
				fb.layer = DecisionLayer.TACTICAL
				fb.action = fb_variant
				fb.priority = PRIORITY_FIREBALL + randf_range(-2.0, 3.0)
				fb.reason = "Far range: zoning (%s)" % fb_variant
				decisions.append(fb)
		
		# Priority 2: Dash forward (aggressive approach)
		var dash = Decision.new()
		dash.layer = DecisionLayer.TACTICAL
		dash.action = "dash_forward"
		dash.priority = PRIORITY_DASH_APPROACH
		dash.reason = "Far range: aggressive approach"
		decisions.append(dash)
		
		# Priority 3: Jump approach (mobility)
		var jump = Decision.new()
		jump.layer = DecisionLayer.TACTICAL
		jump.action = "jump_forward" if distance > 350 else "jump_neutral"
		jump.priority = PRIORITY_JUMP + randf_range(-2.0, 2.0)
		jump.reason = "Far range: jump approach"
		decisions.append(jump)
		
		# Priority 4: Walk forward (steady approach)
		var walk = Decision.new()
		walk.layer = DecisionLayer.TACTICAL
		walk.action = "walk_forward"
		walk.priority = PRIORITY_WALK_FORWARD
		walk.reason = "Far range: steady approach"
		decisions.append(walk)
		
		# Priority 5: Observe (lowest - waiting)
		var observe = Decision.new()
		observe.layer = DecisionLayer.TACTICAL
		observe.action = "stand_block"
		observe.priority = PRIORITY_OBSERVE
		observe.reason = "Far range: observe"
		decisions.append(observe)
	
	# ============================================================
	# MID RANGE (100-250) - Mix of pokes and approach
	# ============================================================
	elif distance > 100:
		# Variety of mid-range normals with randomized priorities
		var rand_offset = randf_range(-2.0, 2.0)
		
		# Priority 1: Special moves (character-specific) - ADDED
		var char_id = ai_player.character_id if "character_id" in ai_player else ""
		if char_id == "DAV" and _can_use_special(ai_player, opponent):
			# 🔴 【改進】DP 變體 (L/M/H)
			for dp_variant in ["dpL", "dpM", "dpH"]:
				var dp = Decision.new()
				dp.layer = DecisionLayer.TACTICAL
				dp.action = dp_variant
				dp.priority = _get_special_priority(opponent) + randf_range(-1.0, 1.0)
				dp.reason = "Mid range: DP (%s)" % dp_variant
				decisions.append(dp)
			
			# 🔴 【改進】Fireball 變體 (L/M/H) - 中遠距也可以用
			for fb_variant in ["fireballL", "fireballM", "fireballH"]:
				var fb = Decision.new()
				fb.layer = DecisionLayer.TACTICAL
				fb.action = fb_variant
				fb.priority = PRIORITY_FIREBALL - 3.0 + randf_range(-1.0, 2.0)  # 稍低於 DP
				fb.reason = "Mid range: fireball (%s)" % fb_variant
				decisions.append(fb)
			
			# Power kick
			var powerkk = Decision.new()
			powerkk.layer = DecisionLayer.TACTICAL
			powerkk.action = "powerkk"
			powerkk.priority = _get_special_priority(opponent)
			powerkk.reason = "Mid range: power kick"
			decisions.append(powerkk)
		elif char_id == "DEN" and _can_use_special(ai_player, opponent):
			# Special NK
			var spnk = Decision.new()
			spnk.layer = DecisionLayer.TACTICAL
			spnk.action = "spnk"
			spnk.priority = _get_special_priority(opponent)
			spnk.reason = "Mid range: special"
			decisions.append(spnk)
			# HDK move
			var hdk = Decision.new()
			hdk.layer = DecisionLayer.TACTICAL
			hdk.action = "hdk"
			hdk.priority = _get_special_priority(opponent)
			hdk.reason = "Mid range: hdk"
			decisions.append(hdk)
		
		# Priority 2: st_mk poke (平衡優先級) - 【修復】使用 HitboxCache 驗證
		if _is_attack_in_range(ai_player, opponent, "st_mk"):
			var poke = Decision.new()
			poke.layer = DecisionLayer.TACTICAL
			poke.action = "st_mk"
			poke.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 3.0)
			poke.reason = "Mid range: poke (verified)"
			decisions.append(poke)
		
		# Priority 3: st_mp quick attack (平衡優先級) - 【修復】使用 HitboxCache 驗證
		if _is_attack_in_range(ai_player, opponent, "st_mp"):
			var mp_poke = Decision.new()
			mp_poke.layer = DecisionLayer.TACTICAL
			mp_poke.action = "st_mp"
			mp_poke.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 3.0)
			mp_poke.reason = "Mid range: quick poke (verified)"
			decisions.append(mp_poke)
		
		# Priority 4: Light attacks (faster startup, lower damage) - 【修復】使用 HitboxCache 驗證
		if _is_attack_in_range(ai_player, opponent, "st_lp"):
			var st_lp = Decision.new()
			st_lp.layer = DecisionLayer.TACTICAL
			st_lp.action = "st_lp"
			st_lp.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 3.0)
			st_lp.reason = "Mid range: quick light punch (verified)"
			decisions.append(st_lp)
		
		if _is_attack_in_range(ai_player, opponent, "st_lk"):
			var st_lk = Decision.new()
			st_lk.layer = DecisionLayer.TACTICAL
			st_lk.action = "st_lk"
			st_lk.priority = PRIORITY_NORMAL_LOW + randf_range(-1.0, 3.0)
			st_lk.reason = "Mid range: light kick (verified)"
			decisions.append(st_lk)
		
		# Priority 5: cr_mk low poke (平衡優先級) - 【修復】使用 HitboxCache 驗證
		if _is_attack_in_range(ai_player, opponent, "cr_mk"):
			var crouch_poke = Decision.new()
			crouch_poke.layer = DecisionLayer.TACTICAL
			crouch_poke.action = "cr_mk"
			crouch_poke.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
			crouch_poke.reason = "Mid range: low poke (verified)"
			decisions.append(crouch_poke)
		
		# Priority 6: cr_mp close low attack (平衡優先級) - 【修復】使用 HitboxCache 驗證
		if distance < 150:
			if _is_attack_in_range(ai_player, opponent, "cr_mp"):
				var cr_mp_poke = Decision.new()
				cr_mp_poke.layer = DecisionLayer.TACTICAL
				cr_mp_poke.action = "cr_mp"
				cr_mp_poke.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
				cr_mp_poke.reason = "Mid range: cr_mp (verified)"
				decisions.append(cr_mp_poke)
			
			# Light crouch attacks - 【修復】使用 HitboxCache 驗證
			if _is_attack_in_range(ai_player, opponent, "cr_lp"):
				var cr_lp = Decision.new()
				cr_lp.layer = DecisionLayer.TACTICAL
				cr_lp.action = "cr_lp"
				cr_lp.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
				cr_lp.reason = "Mid range: cr_lp (verified)"
				decisions.append(cr_lp)
			
			if _is_attack_in_range(ai_player, opponent, "cr_lk"):
				var cr_lk = Decision.new()
				cr_lk.layer = DecisionLayer.TACTICAL
				cr_lk.action = "cr_lk"
				cr_lk.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
				cr_lk.reason = "Mid range: cr_lk (verified)"
				decisions.append(cr_lk)
		
		# Priority 7: Heavy attacks (slower startup, higher damage) - 【修復】使用 HitboxCache 驗證
		if _is_attack_in_range(ai_player, opponent, "st_hp"):
			var st_hp = Decision.new()
			st_hp.layer = DecisionLayer.TACTICAL
			st_hp.action = "st_hp"
			st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)
			st_hp.reason = "Mid range: heavy punch (verified)"
			decisions.append(st_hp)
		
		if _is_attack_in_range(ai_player, opponent, "st_hk"):
			var st_hk = Decision.new()
			st_hk.layer = DecisionLayer.TACTICAL
			st_hk.action = "st_hk"
			st_hk.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)
			st_hk.reason = "Mid range: heavy kick (verified)"
			decisions.append(st_hk)
		
		if _is_attack_in_range(ai_player, opponent, "cr_hp"):
			var cr_hp = Decision.new()
			cr_hp.layer = DecisionLayer.TACTICAL
			cr_hp.action = "cr_hp"
			cr_hp.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)
			cr_hp.reason = "Mid range: cr_hp (verified)"
			decisions.append(cr_hp)
		
		if _is_attack_in_range(ai_player, opponent, "cr_hk"):
			var cr_hk = Decision.new()
			cr_hk.layer = DecisionLayer.TACTICAL
			cr_hk.action = "cr_hk"
			cr_hk.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)
			cr_hk.reason = "Mid range: cr_hk (verified)"
			decisions.append(cr_hk)
		
		# Priority 8: Jump attack (occasional)
		if distance > 120 and distance < 200:
			var jump_atk = Decision.new()
			jump_atk.layer = DecisionLayer.TACTICAL
			jump_atk.action = "jump_forward"
			jump_atk.priority = PRIORITY_JUMP + randf_range(-2.0, 2.0)
			jump_atk.reason = "Mid range: jump attack"
			decisions.append(jump_atk)
		
		# Priority 9: Continue approaching
		var approach = Decision.new()
		approach.layer = DecisionLayer.TACTICAL
		approach.action = "dash_forward"
		approach.priority = PRIORITY_APPROACH
		approach.reason = "Mid range: close gap"
		decisions.append(approach)
		
		# Priority 10: Walk forward
		var walk = Decision.new()
		walk.layer = DecisionLayer.TACTICAL
		walk.action = "walk_forward"
		walk.priority = PRIORITY_WALK_FORWARD_MID
		walk.reason = "Mid range: walk approach"
		decisions.append(walk)
		
		# Priority 11: Defensive block (LOWEST priority - only when cautious)
		var block = Decision.new()
		block.layer = DecisionLayer.TACTICAL
		block.action = "stand_block"
		block.priority = PRIORITY_OBSERVE + randf_range(-2.0, 5.0)  # 48 + (-2 to 5) = 46-53
		block.reason = "Mid range: defense"
		decisions.append(block)
	
	# ============================================================
	# CLOSE RANGE (< 100) - Offense focused
	# ============================================================
	else:
		# Priority 1: Execute combos if available
		var combo_names = combo_system.get_available_combos(ai_player, opponent)
		for combo_name in combo_names:
			var combo_dec = Decision.new()
			combo_dec.layer = DecisionLayer.TACTICAL
			combo_dec.action = "combo_" + combo_name
			combo_dec.priority = PRIORITY_COMBO
			combo_dec.reason = "Close range: combo"
			decisions.append(combo_dec)
		
		# Priority 2: Special moves (character-specific) - INCREASED PRIORITY
		var char_id = ai_player.character_id if "character_id" in ai_player else ""
		if char_id == "DAV" and _can_use_special(ai_player, opponent):
			# 🔴 【改進】DP 變體 (L/M/H)
			for dp_variant in ["dpL", "dpM", "dpH"]:
				var dp = Decision.new()
				dp.layer = DecisionLayer.TACTICAL
				dp.action = dp_variant
				dp.priority = _get_special_priority(opponent) + randf_range(-1.0, 1.0)
				dp.reason = "Close range: DP (%s)" % dp_variant
				decisions.append(dp)
			
			# 🔴 【改進】100p (多段必殺技) - 優先級低於DP但高於普通攻擊
			var super_punch = Decision.new()
			super_punch.layer = DecisionLayer.TACTICAL
			super_punch.action = "100p"
			super_punch.priority = _get_special_priority(opponent) - 5.0 + randf_range(-2.0, 2.0)
			super_punch.reason = "Close range: 100p multi-hit"
			decisions.append(super_punch)
			
			# Power kick
			var powerkk = Decision.new()
			powerkk.layer = DecisionLayer.TACTICAL
			powerkk.action = "powerkk"
			powerkk.priority = _get_special_priority(opponent) + randf_range(-1.0, 1.0)
			powerkk.reason = "Close range: power kick"
			decisions.append(powerkk)
		elif char_id == "DEN" and _can_use_special(ai_player, opponent):
			# Special NK
			var spnk = Decision.new()
			spnk.layer = DecisionLayer.TACTICAL
			spnk.action = "spnk"
			spnk.priority = _get_special_priority(opponent)
			spnk.reason = "Close range: special"
			decisions.append(spnk)
			# HDK move
			var hdk = Decision.new()
			hdk.layer = DecisionLayer.TACTICAL
			hdk.action = "hdk"
			hdk.priority = _get_special_priority(opponent)
			hdk.reason = "Close range: hdk"
			decisions.append(hdk)
		
		# Priority 2b: Throw - 破格擋的利器，近身必學
		# 【修復】使用真實投擲框範圍 (HitboxCache) 來判斷
		var throw_hitbox_collision = false
		var throw_range = 100.0
		
		if hitbox_cache and hitbox_cache.is_initialized:
			# 使用真實投擲框碰撞檢測
			throw_range = hitbox_cache.get_throw_range(ai_player.character_id)
			var ai_facing = ai_player.facing_direction if "facing_direction" in ai_player else 1.0
			throw_hitbox_collision = hitbox_cache.check_throw_collision(
				ai_player.global_position,
				ai_player.character_id,
				opponent.global_position,
				opponent.character_id,
				ai_facing
			)
		else:
			# 後備：使用硬編碼距離 (100 像素)
			throw_hitbox_collision = distance < 100
		
		var throw_eligible = throw_hitbox_collision and not ai_player.is_attacking and not ai_player.is_hit and not ai_player.is_knockfly
		if throw_eligible:
			var throw_dec = Decision.new()
			throw_dec.layer = DecisionLayer.TACTICAL
			throw_dec.action = "throw"
			throw_dec.priority = 71.0 + randf_range(-1.0, 1.0)  # 70-72，確保在普通攻擊（~67）之上
			throw_dec.reason = "Close range: throw (real hitbox collision)"
			decisions.append(throw_dec)
		
		# Priority 3: 【修復】站立攻擊 - 使用 HitboxCache 驗證距離
		if _is_attack_in_range(ai_player, opponent, "st_hp"):
			var st_hp = Decision.new()
			st_hp.layer = DecisionLayer.TACTICAL
			st_hp.action = "st_hp"
			st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)
			st_hp.reason = "Close range: st_hp (verified by hitbox)"
			decisions.append(st_hp)
		
		if _is_attack_in_range(ai_player, opponent, "st_mk"):
			var st_mk = Decision.new()
			st_mk.layer = DecisionLayer.TACTICAL
			st_mk.action = "st_mk"
			st_mk.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 3.0)
			st_mk.reason = "Close range: st_mk (verified by hitbox)"
			decisions.append(st_mk)
		
		if _is_attack_in_range(ai_player, opponent, "st_mp"):
			var st_mp = Decision.new()
			st_mp.layer = DecisionLayer.TACTICAL
			st_mp.action = "st_mp"
			st_mp.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 3.0)
			st_mp.reason = "Close range: st_mp (verified by hitbox)"
			decisions.append(st_mp)
		
		if _is_attack_in_range(ai_player, opponent, "st_lp"):
			var st_lp = Decision.new()
			st_lp.layer = DecisionLayer.TACTICAL
			st_lp.action = "st_lp"
			st_lp.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 3.0)
			st_lp.reason = "Close range: st_lp (verified by hitbox)"
			decisions.append(st_lp)
		
		if _is_attack_in_range(ai_player, opponent, "st_hk"):
			var st_hk = Decision.new()
			st_hk.layer = DecisionLayer.TACTICAL
			st_hk.action = "st_hk"
			st_hk.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)
			st_hk.reason = "Close range: st_hk (verified by hitbox)"
			decisions.append(st_hk)
		
		if _is_attack_in_range(ai_player, opponent, "st_lk"):
			var st_lk = Decision.new()
			st_lk.layer = DecisionLayer.TACTICAL
			st_lk.action = "st_lk"
			st_lk.priority = PRIORITY_NORMAL_LOW + randf_range(-1.0, 3.0)
			st_lk.reason = "Close range: st_lk (verified by hitbox)"
			decisions.append(st_lk)
		
		# Priority 4: 【修復】蹲下攻擊 - 使用 HitboxCache 驗證距離
		if _is_attack_in_range(ai_player, opponent, "cr_hp"):
			var cr_hp = Decision.new()
			cr_hp.layer = DecisionLayer.TACTICAL
			cr_hp.action = "cr_hp"
			cr_hp.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)
			cr_hp.reason = "Close range: cr_hp (verified by hitbox)"
			decisions.append(cr_hp)
		
		if _is_attack_in_range(ai_player, opponent, "cr_mk"):
			var cr_mk = Decision.new()
			cr_mk.layer = DecisionLayer.TACTICAL
			cr_mk.action = "cr_mk"
			cr_mk.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
			cr_mk.reason = "Close range: cr_mk (verified by hitbox)"
			decisions.append(cr_mk)
		
		if _is_attack_in_range(ai_player, opponent, "cr_mp"):
			var cr_mp = Decision.new()
			cr_mp.layer = DecisionLayer.TACTICAL
			cr_mp.action = "cr_mp"
			cr_mp.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
			cr_mp.reason = "Close range: cr_mp (verified by hitbox)"
			decisions.append(cr_mp)
		
		if _is_attack_in_range(ai_player, opponent, "cr_lp"):
			var cr_lp = Decision.new()
			cr_lp.layer = DecisionLayer.TACTICAL
			cr_lp.action = "cr_lp"
			cr_lp.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
			cr_lp.reason = "Close range: cr_lp (verified by hitbox)"
			decisions.append(cr_lp)
		
		if _is_attack_in_range(ai_player, opponent, "cr_hk"):
			var cr_hk = Decision.new()
			cr_hk.layer = DecisionLayer.TACTICAL
			cr_hk.action = "cr_hk"
			cr_hk.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)
			cr_hk.reason = "Close range: cr_hk (verified by hitbox)"
			decisions.append(cr_hk)
		
		if _is_attack_in_range(ai_player, opponent, "cr_lk"):
			var cr_lk = Decision.new()
			cr_lk.layer = DecisionLayer.TACTICAL
			cr_lk.action = "cr_lk"
			cr_lk.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)
			cr_lk.reason = "Close range: cr_lk (verified by hitbox)"
			decisions.append(cr_lk)
		
		# Priority 5: Continue attacking or defensive
		var approach = Decision.new()
		approach.layer = DecisionLayer.TACTICAL
		approach.action = "dash_forward"
		approach.priority = PRIORITY_APPROACH
		approach.reason = "Close range: press advantage"
		decisions.append(approach)
		
		# Priority 6: Defensive block (LOWEST priority)
		var block = Decision.new()
		block.layer = DecisionLayer.TACTICAL
		block.action = "stand_block"
		block.priority = PRIORITY_OBSERVE + randf_range(-2.0, 3.0)
		block.reason = "Close range: defense"
		decisions.append(block)
		
		if throw_eligible:
			var throw_dec = Decision.new()
			throw_dec.layer = DecisionLayer.TACTICAL
			throw_dec.action = "throw"
			if opponent.is_blocking:
				# 對手正在格擋時摔投優先級大幅提升（摔投無視格擋）
				throw_dec.priority = 79.0 + randf_range(-1.0, 1.0)
				throw_dec.reason = "Close range: throw beats block (real hitbox)"
			else:
				# 【修復】優先級提升至 70，確保優先於普通攻擊（~67）
				throw_dec.priority = 71.0 + randf_range(-1.0, 1.0)
				throw_dec.reason = "Close range: throw (real hitbox collision)"
			
			# 【DEBUG】throw 被加入決策
			Debug.log("[TACTICAL THROW ADDED] Frame=%d Seat=%s | priority=%.1f reason='%s' | throw_range=%.1f" % [
				Engine.get_physics_frames(),
				ai_player.seat if "seat" in ai_player else "?",
				throw_dec.priority,
				throw_dec.reason,
				throw_range
			])
			decisions.append(throw_dec)
	
	return decisions

func _evaluate_positioning_layer(ai_player: Player, opponent: Player) -> Decision:
	var decision = Decision.new()
	decision.layer = DecisionLayer.POSITIONING
	decision.priority = PRIORITY_POSITIONING
	
	# 檢查角落逃脫
	var escape_action = space_control.get_escape_action(ai_player, opponent, ai_player.world)
	if escape_action != "":
		decision.action = escape_action
		decision.reason = "Escape corner"
		decision.priority = 40.0  # 角落逃脫優先級略高
		return decision
	
	# 距離管理
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	var char_id = ai_player.character_id if "character_id" in ai_player else "UNKNOWN"
	var opp_id = opponent.character_id if "character_id" in opponent else "UNKNOWN"
	var ideal = space_control.get_ideal_distance(char_id, opp_id)
	
	if distance > ideal + 50:
		decision.action = "walk_forward"
		decision.reason = "Move to ideal range"
	elif distance < ideal - 50:
		decision.action = "walk_backward"
		decision.reason = "Maintain distance"
	else:
		decision.action = "walk_forward"
		decision.priority = 20.0
		decision.reason = "Maintain pressure"
	
	return decision

func _get_idle_decision() -> Decision:
	var decision = Decision.new()
	decision.layer = DecisionLayer.IDLE
	decision.priority = PRIORITY_IDLE
	decision.action = "walk_forward"  # Default to forward approach
	decision.reason = "Default behavior"
	return decision

func get_fallback_decision(ai_player: Player, opponent: Player) -> Decision:
	"""
	當主要決策被限制時，獲取替代決策
	這個函數再次評估所有層級，但跳過被限制的招式
	智能備選方案：普通攻擊 > 防禦 > 移動 > 待機
	"""
	var decisions: Array[Decision] = []
	var alternative_normals: Array[Decision] = []
	var defensive_options: Array[Decision] = []
	var movement_options: Array[Decision] = []
	
	# 再次評估所有層級
	var survival = _evaluate_survival_layer(ai_player, opponent)
	if survival and not _is_move_restricted(survival.action):
		decisions.append(survival)
	
	var punish = _evaluate_punish_layer(ai_player, opponent)
	if punish and not _is_move_restricted(punish.action):
		decisions.append(punish)
	
	var tactical = _evaluate_tactical_layer(ai_player, opponent)
	for t in tactical:
		if not _is_move_restricted(t.action):
			# 分類決策，優先級：正常攻擊 > 防禦 > 移動
			if t.action.begins_with("st_") or t.action.begins_with("cr_") or t.action.begins_with("jump_"):
				alternative_normals.append(t)
			elif "block" in t.action:
				defensive_options.append(t)
			elif "walk" in t.action or "dash" in t.action or "jump" in t.action:
				movement_options.append(t)
			else:
				decisions.append(t)
	
	var positioning = _evaluate_positioning_layer(ai_player, opponent)
	if positioning and not _is_move_restricted(positioning.action):
		movement_options.append(positioning)
	
	# 優先級順序：關鍵決策 > 普通攻擊 > 防禦 > 移動 > 待機
	if not decisions.is_empty():
		decisions.sort_custom(func(a, b): return a.priority > b.priority)
		return decisions[0]
	
	if not alternative_normals.is_empty():
		alternative_normals.sort_custom(func(a, b): return a.priority > b.priority)
		if Engine.get_physics_frames() % 120 == 0:
			Debug.log("[AI.get_fallback_decision] Using normal attack fallback: %s" % alternative_normals[0].action)
		return alternative_normals[0]
	
	if not defensive_options.is_empty():
		defensive_options.sort_custom(func(a, b): return a.priority > b.priority)
		if Engine.get_physics_frames() % 120 == 0:
			Debug.log("[AI.get_fallback_decision] Using defensive fallback: %s" % defensive_options[0].action)
		return defensive_options[0]
	
	if not movement_options.is_empty():
		movement_options.sort_custom(func(a, b): return a.priority > b.priority)
		if Engine.get_physics_frames() % 120 == 0:
			Debug.log("[AI.get_fallback_decision] Using movement fallback: %s" % movement_options[0].action)
		return movement_options[0]
	
	# 最後的備選方案：待機
	if Engine.get_physics_frames() % 120 == 0:
		Debug.log("[AI.get_fallback_decision] All options exhausted, returning idle")
	return _get_idle_decision()
