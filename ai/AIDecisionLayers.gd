class_name AIDecisionLayers extends Node

enum DecisionLayer { SURVIVAL, PUNISH, TACTICAL, POSITIONING, IDLE }

# ============================================================
# DECISION CACHING SYSTEM
# ============================================================
var decision_cache: Decision = null
var cache_timer: float = 0.0
const CACHE_DURATION: float = 0.1  # Cache for 6 frames (~100ms)

@export var enable_decision_cache: bool = true
@export var cache_duration_override: float = 0.1

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

class Decision:
	var layer: DecisionLayer
	var action: String
	var priority: float = 0.0
	var reason: String = ""

var threat_system: ThreatAssessment
var frame_data: FrameDataManager
var combo_system: AIComboSystem
var space_control: SpaceControl

# Move restrictions (set by AIBehavior)
var restricted_moves: Array[String] = []

func _process(delta: float) -> void:
	"""Update cache timer"""
	if cache_timer > 0:
		cache_timer -= delta

func get_best_decision(ai_player: Player, opponent: Player) -> Decision:
	# Use cached decision if valid
	if enable_decision_cache and cache_timer > 0 and decision_cache != null:
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
		print("[AI] Filtered %d restricted moves. Available decisions: %d" % [filtered_count, decisions.size()])
		if decisions.size() > 0:
			var top_5 = decisions.slice(0, min(5, decisions.size()))
			for d in top_5:
				print("  - %s (%.1f): %s" % [d.action, d.priority, d.reason])
	
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
	_cache_decision(best_decision)
	return best_decision

func _cache_decision(decision: Decision) -> void:
	"""Cache the decision for reuse"""
	if enable_decision_cache:
		decision_cache = decision
		cache_timer = cache_duration_override if cache_duration_override > 0 else CACHE_DURATION

func _evaluate_survival_layer(ai_player: Player, opponent: Player) -> Decision:
	var threat = threat_system.evaluate_threats(ai_player, opponent)
	
	# React to any threat level (including LOW for fireballs)
	if threat.level == ThreatAssessment.ThreatLevel.NONE:
		return null
	
	var decision = Decision.new()
	decision.layer = DecisionLayer.SURVIVAL
	decision.action = threat.recommended_response
	
	# Adjust priority based on threat level
	if threat.level == ThreatAssessment.ThreatLevel.CRITICAL:
		decision.priority = PRIORITY_CRITICAL
	elif threat.level == ThreatAssessment.ThreatLevel.HIGH:
		decision.priority = PRIORITY_SURVIVAL
	elif threat.level == ThreatAssessment.ThreatLevel.MEDIUM:
		decision.priority = PRIORITY_BLOCK
	else:  # LOW
		# For LOW threats (distant fireballs), use tactical priority
		decision.priority = 68.0  # Similar to normal attacks
	
	decision.reason = "Threat: " + threat.source
	return decision

func _evaluate_punish_layer(ai_player: Player, opponent: Player) -> Decision:
	# 檢查對手是否處於可懲罰狀態
	if not (opponent.is_hit or opponent.is_knockfly or frame_data.is_in_recovery(opponent)):
		return null
	
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	var best_punish = _select_punish_attack(ai_player, distance)
	
	if best_punish == "":
		return null
	
	var decision = Decision.new()
	decision.layer = DecisionLayer.PUNISH
	decision.action = best_punish
	decision.priority = PRIORITY_PUNISH
	decision.reason = "Punish opportunity"
	return decision

func _select_punish_attack(ai_player: Player, distance: float) -> String:
	var char_id = ai_player.character_id if "character_id" in ai_player else "UNKNOWN"
	
	# 根據角色和距離選擇最佳懲罰招式
	var options = []
	
	if char_id == "DAV":
		options = [
			{"name": "dp", "range": 85.0, "damage": 15.0},
			{"name": "st_mk", "range": 95.0, "damage": 12.0},
			{"name": "st_mp", "range": 75.0, "damage": 10.0},
		]
	else:  # DEN or others
		options = [
			{"name": "spnk", "range": 95.0, "damage": 12.0},
			{"name": "st_mk", "range": 95.0, "damage": 12.0},
			{"name": "st_mp", "range": 75.0, "damage": 10.0},
		]
	
	for option in options:
		if distance <= option["range"]:
			return option["name"]
	return ""

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
		if ai_player and ai_player.move_set and not ai_player.move_set.is_spmove:
			var fb = Decision.new()
			fb.layer = DecisionLayer.TACTICAL
			fb.action = "fireball"
			fb.priority = PRIORITY_FIREBALL + randf_range(-2.0, 3.0)
			fb.reason = "Far range: zoning"
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
		if char_id == "DAV":
			# DP (dragon punch) - anti-air and pressure
			var dp = Decision.new()
			dp.layer = DecisionLayer.TACTICAL
			dp.action = "dp"
			dp.priority = PRIORITY_SPECIAL_CLOSE + randf_range(-1.0, 4.0)  # 70 + (-1 to 4) = 69-74
			dp.reason = "Mid range: DP"
			decisions.append(dp)
			# Power kick
			var powerkk = Decision.new()
			powerkk.layer = DecisionLayer.TACTICAL
			powerkk.action = "powerkk"
			powerkk.priority = PRIORITY_SPECIAL_CLOSE + randf_range(-2.0, 3.0)  # 70 + (-2 to 3) = 68-73
			powerkk.reason = "Mid range: power kick"
			decisions.append(powerkk)
		elif char_id == "DEN":
			# Special NK
			var spnk = Decision.new()
			spnk.layer = DecisionLayer.TACTICAL
			spnk.action = "spnk"
			spnk.priority = PRIORITY_SPECIAL_CLOSE + randf_range(-1.0, 4.0)  # 70 + (-1 to 4) = 69-74
			spnk.reason = "Mid range: special"
			decisions.append(spnk)
			# HDK move
			var hdk = Decision.new()
			hdk.layer = DecisionLayer.TACTICAL
			hdk.action = "hdk"
			hdk.priority = PRIORITY_SPECIAL_CLOSE + randf_range(-2.0, 3.0)  # 70 + (-2 to 3) = 68-73
			hdk.reason = "Mid range: hdk"
			decisions.append(hdk)
		
		# Priority 2: st_mk poke (INCREASED PRIORITY)
		var poke = Decision.new()
		poke.layer = DecisionLayer.TACTICAL
		poke.action = "st_mk"
		poke.priority = PRIORITY_NORMAL_HIGH + rand_offset + 3.0  # 67 + rand + 3 = 68-72
		poke.reason = "Mid range: poke"
		decisions.append(poke)
		
		# Priority 3: st_mp quick attack (INCREASED PRIORITY)
		var mp_poke = Decision.new()
		mp_poke.layer = DecisionLayer.TACTICAL
		mp_poke.action = "st_mp"
		mp_poke.priority = PRIORITY_NORMAL_MID + randf_range(-2.0, 2.0) + 3.0  # 67 + rand + 3 = 68-72
		mp_poke.reason = "Mid range: quick poke"
		decisions.append(mp_poke)
		
		# Priority 4: cr_mk low poke (INCREASED PRIORITY)
		var crouch_poke = Decision.new()
		crouch_poke.layer = DecisionLayer.TACTICAL
		crouch_poke.action = "cr_mk"
		crouch_poke.priority = PRIORITY_CROUCH + randf_range(-2.0, 2.0) + 3.0  # 67 + rand + 3 = 68-72
		crouch_poke.reason = "Mid range: low poke"
		decisions.append(crouch_poke)
		
		# Priority 5: cr_mp close low attack (INCREASED PRIORITY)
		if distance < 150:
			var cr_mp_poke = Decision.new()
			cr_mp_poke.layer = DecisionLayer.TACTICAL
			cr_mp_poke.action = "cr_mp"
			cr_mp_poke.priority = PRIORITY_CROUCH + randf_range(-2.0, 2.0) + 3.0  # 67 + rand + 3 = 68-72
			cr_mp_poke.reason = "Mid range: cr_mp"
			decisions.append(cr_mp_poke)
		
		# Priority 6: Jump attack (occasional)
		if distance > 120 and distance < 200:
			var jump_atk = Decision.new()
			jump_atk.layer = DecisionLayer.TACTICAL
			jump_atk.action = "jump_forward"
			jump_atk.priority = PRIORITY_JUMP + randf_range(-2.0, 2.0)
			jump_atk.reason = "Mid range: jump attack"
			decisions.append(jump_atk)
		
		# Priority 7: Continue approaching
		var approach = Decision.new()
		approach.layer = DecisionLayer.TACTICAL
		approach.action = "dash_forward"
		approach.priority = PRIORITY_APPROACH
		approach.reason = "Mid range: close gap"
		decisions.append(approach)
		
		# Priority 8: Walk forward
		var walk = Decision.new()
		walk.layer = DecisionLayer.TACTICAL
		walk.action = "walk_forward"
		walk.priority = PRIORITY_WALK_FORWARD_MID
		walk.reason = "Mid range: walk approach"
		decisions.append(walk)
		
		# Priority 8: Defensive block (LOWEST priority - only when cautious)
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
		if char_id == "DAV":
			# DP (dragon punch)
			var dp = Decision.new()
			dp.layer = DecisionLayer.TACTICAL
			dp.action = "dp"
			dp.priority = PRIORITY_SPECIAL_CLOSE + randf_range(0.0, 5.0)  # 70 + (0 to 5) = 70-75
			dp.reason = "Close range: DP"
			decisions.append(dp)
			# Power kick
			var powerkk = Decision.new()
			powerkk.layer = DecisionLayer.TACTICAL
			powerkk.action = "powerkk"
			powerkk.priority = PRIORITY_SPECIAL_CLOSE + randf_range(-1.0, 4.0)  # 70 + (-1 to 4) = 69-74
			powerkk.reason = "Close range: power kick"
			decisions.append(powerkk)
		elif char_id == "DEN":
			# Special NK
			var spnk = Decision.new()
			spnk.layer = DecisionLayer.TACTICAL
			spnk.action = "spnk"
			spnk.priority = PRIORITY_SPECIAL_CLOSE + randf_range(0.0, 5.0)  # 70 + (0 to 5) = 70-75
			spnk.reason = "Close range: special"
			decisions.append(spnk)
			# HDK move
			var hdk = Decision.new()
			hdk.layer = DecisionLayer.TACTICAL
			hdk.action = "hdk"
			hdk.priority = PRIORITY_SPECIAL_CLOSE + randf_range(-1.0, 4.0)  # 70 + (-1 to 4) = 69-74
			hdk.reason = "Close range: hdk"
			decisions.append(hdk)
		
		# Priority 3: Variety of close range normals with randomization
		var close_rand = randf_range(-3.0, 3.0)
		
		# st_mp (fast close attack)
		var mp = Decision.new()
		mp.layer = DecisionLayer.TACTICAL
		mp.action = "st_mp"
		mp.priority = PRIORITY_NORMAL_MID + close_rand
		mp.reason = "Close range: st_mp"
		decisions.append(mp)
		
		# st_mk
		var mk = Decision.new()
		mk.layer = DecisionLayer.TACTICAL
		mk.action = "st_mk"
		mk.priority = PRIORITY_NORMAL_HIGH + randf_range(-3.0, 3.0)
		mk.reason = "Close range: st_mk"
		decisions.append(mk)
		
		# cr_mp (very close low attack)
		var cr_mp = Decision.new()
		cr_mp.layer = DecisionLayer.TACTICAL
		cr_mp.action = "cr_mp"
		cr_mp.priority = PRIORITY_CROUCH + randf_range(-3.0, 3.0)
		cr_mp.reason = "Close range: cr_mp"
		decisions.append(cr_mp)
		
		# cr_mk (low poke)
		var cr_mk = Decision.new()
		cr_mk.layer = DecisionLayer.TACTICAL
		cr_mk.action = "cr_mk"
		cr_mk.priority = PRIORITY_NORMAL_LOW + randf_range(-3.0, 3.0)
		cr_mk.reason = "Close range: cr_mk"
		decisions.append(cr_mk)
		
		# Priority 6: Jump escape (when cornered or pressured)
		if distance < 60:
			var jump_escape = Decision.new()
			jump_escape.layer = DecisionLayer.TACTICAL
			jump_escape.action = "jump_backward"
			jump_escape.priority = PRIORITY_RETREAT + randf_range(-2.0, 3.0)
			jump_escape.reason = "Close range: jump escape"
			decisions.append(jump_escape)
		
		# Priority 7: Tactical retreat (lowest)
		var retreat = Decision.new()
		retreat.layer = DecisionLayer.TACTICAL
		retreat.action = "backdash"
		retreat.priority = PRIORITY_RETREAT
		retreat.reason = "Close range: retreat"
		decisions.append(retreat)
	
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
	"""
	var decisions: Array[Decision] = []
	
	# 再次評估所有層級
	var survival = _evaluate_survival_layer(ai_player, opponent)
	if survival and survival.action not in restricted_moves:
		decisions.append(survival)
	
	var punish = _evaluate_punish_layer(ai_player, opponent)
	if punish and punish.action not in restricted_moves:
		decisions.append(punish)
	
	var tactical = _evaluate_tactical_layer(ai_player, opponent)
	for t in tactical:
		if t.action not in restricted_moves:
			decisions.append(t)
	
	var positioning = _evaluate_positioning_layer(ai_player, opponent)
	if positioning and positioning.action not in restricted_moves:
		decisions.append(positioning)
	
	# 如果所有招式都被限制，返回安全的待機決策
	if decisions.is_empty():
		return _get_idle_decision()
	
	# 排序並返回最高優先級
	decisions.sort_custom(func(a, b): return a.priority > b.priority)
	return decisions[0]
