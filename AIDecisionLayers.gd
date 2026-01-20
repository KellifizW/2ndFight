class_name AIDecisionLayers extends Node

enum DecisionLayer { SURVIVAL, PUNISH, TACTICAL, POSITIONING, IDLE }

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
const PRIORITY_NORMAL_HIGH = 68.0    # High priority normals (st_mk)
const PRIORITY_NORMAL_MID = 66.0     # Mid priority normals (st_mp)
const PRIORITY_NORMAL_LOW = 64.0     # Low priority normals (cr_mk)
const PRIORITY_CROUCH = 65.0         # Crouch attacks

# Movement priorities
const PRIORITY_DASH_APPROACH = 65.0  # Aggressive dash forward
const PRIORITY_APPROACH = 63.0       # Steady approach
const PRIORITY_WALK_FORWARD = 62.0   # Walk forward
const PRIORITY_WALK_FORWARD_MID = 59.0  # Walk forward (mid range, lower priority)
const PRIORITY_RETREAT = 60.0        # Tactical retreat
const PRIORITY_WALK_BACK = 58.0      # Walk backward

# Zoning/Defense priorities
const PRIORITY_FIREBALL = 52.0       # Projectile zoning
const PRIORITY_BLOCK = 55.0          # Defensive blocking
const PRIORITY_CROUCH_BLOCK = 54.0   # Crouch blocking
const PRIORITY_OBSERVE = 48.0        # Wait and observe
const PRIORITY_JUMP = 46.0           # Jump approach (low priority)

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

func get_best_decision(ai_player: Player, opponent: Player) -> Decision:
	var decisions: Array[Decision] = []
	
	# Layer 1: 生存層（最高優先級）
	var survival = _evaluate_survival_layer(ai_player, opponent)
	if survival and survival.priority >= 95:
		return survival
	elif survival:
		decisions.append(survival)
	
	# Layer 2: 懲罰層
	var punish = _evaluate_punish_layer(ai_player, opponent)
	if punish:
		decisions.append(punish)
	
	# Layer 3: 戰術層
	decisions.append_array(_evaluate_tactical_layer(ai_player, opponent))
	
	# Layer 4: 定位層
	var positioning = _evaluate_positioning_layer(ai_player, opponent)
	if positioning:
		decisions.append(positioning)
	
	# Layer 5: 待機層（最低優先級）
	decisions.append(_get_idle_decision())
	
	# 排序並返回最高優先級決策
	decisions.sort_custom(func(a, b): return a.priority > b.priority)
	return decisions[0]

func _evaluate_survival_layer(ai_player: Player, opponent: Player) -> Decision:
	var threat = threat_system.evaluate_threats(ai_player, opponent)
	
	if threat.level < ThreatAssessment.ThreatLevel.HIGH:
		return null
	
	var decision = Decision.new()
	decision.layer = DecisionLayer.SURVIVAL
	decision.action = threat.recommended_response
	decision.priority = PRIORITY_CRITICAL if threat.level == ThreatAssessment.ThreatLevel.CRITICAL else PRIORITY_SURVIVAL
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
	# FAR RANGE (> 250) - Primary goal: APPROACH
	# ============================================================
	if distance > 250:
		# Priority 1: Dash forward (fastest approach)
		var dash = Decision.new()
		dash.layer = DecisionLayer.TACTICAL
		dash.action = "dash_forward"
		dash.priority = PRIORITY_DASH_APPROACH
		dash.reason = "Far range: aggressive approach"
		decisions.append(dash)
		
		# Priority 2: Walk forward (steady approach)
		var walk = Decision.new()
		walk.layer = DecisionLayer.TACTICAL
		walk.action = "walk_forward"
		walk.priority = PRIORITY_WALK_FORWARD
		walk.reason = "Far range: steady approach"
		decisions.append(walk)
		
		# Priority 3: Fireball (occasional zoning) - only if not busy
		if ai_player and ai_player.move_set and not ai_player.move_set.is_spmove:
			var fb = Decision.new()
			fb.layer = DecisionLayer.TACTICAL
			fb.action = "fireball"
			fb.priority = PRIORITY_FIREBALL
			fb.reason = "Far range: zoning"
			decisions.append(fb)
		
		# Priority 4: Observe (lowest - waiting)
		var observe = Decision.new()
		observe.layer = DecisionLayer.TACTICAL
		observe.action = "stand_block"
		observe.priority = PRIORITY_OBSERVE
		observe.reason = "Far range: observe"
		decisions.append(observe)
		
		# Priority 5: Jump (occasional mobility)
		var jump = Decision.new()
		jump.layer = DecisionLayer.TACTICAL
		jump.action = "jump_forward" if distance > 350 else "jump_neutral"
		jump.priority = PRIORITY_JUMP
		jump.reason = "Far range: jump approach"
		decisions.append(jump)
	
	# ============================================================
	# MID RANGE (100-250) - Mix of pokes and approach
	# ============================================================
	elif distance > 100:
		# Priority 1: st_mk poke (best mid-range tool)
		var poke = Decision.new()
		poke.layer = DecisionLayer.TACTICAL
		poke.action = "st_mk"
		poke.priority = PRIORITY_NORMAL_HIGH
		poke.reason = "Mid range: poke"
		decisions.append(poke)
		
		# Priority 2: cr_mk low poke
		var crouch_poke = Decision.new()
		crouch_poke.layer = DecisionLayer.TACTICAL
		crouch_poke.action = "cr_mk"
		crouch_poke.priority = PRIORITY_CROUCH
		crouch_poke.reason = "Mid range: low poke"
		decisions.append(crouch_poke)
		
		# Priority 3: Continue approaching
		var approach = Decision.new()
		approach.layer = DecisionLayer.TACTICAL
		approach.action = "dash_forward"
		approach.priority = PRIORITY_APPROACH
		approach.reason = "Mid range: close gap"
		decisions.append(approach)
		
		# Priority 4: Walk forward
		var walk = Decision.new()
		walk.layer = DecisionLayer.TACTICAL
		walk.action = "walk_forward"
		walk.priority = PRIORITY_WALK_FORWARD_MID
		walk.reason = "Mid range: walk approach"
		decisions.append(walk)
		
		# Priority 5: Defensive block
		var block = Decision.new()
		block.layer = DecisionLayer.TACTICAL
		block.action = "stand_block"
		block.priority = PRIORITY_BLOCK
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
		
		# Priority 2: Special moves (character-specific)
		var char_id = ai_player.character_id if "character_id" in ai_player else ""
		if char_id == "DAV":
			var dp = Decision.new()
			dp.layer = DecisionLayer.TACTICAL
			dp.action = "dp"
			dp.priority = PRIORITY_SPECIAL_CLOSE
			dp.reason = "Close range: DP"
			decisions.append(dp)
		elif char_id == "DEN":
			var spnk = Decision.new()
			spnk.layer = DecisionLayer.TACTICAL
			spnk.action = "spnk"
			spnk.priority = PRIORITY_SPECIAL_CLOSE
			spnk.reason = "Close range: special"
			decisions.append(spnk)
		
		# Priority 3: st_mp (fast close attack)
		var mp = Decision.new()
		mp.layer = DecisionLayer.TACTICAL
		mp.action = "st_mp"
		mp.priority = PRIORITY_NORMAL_MID
		mp.reason = "Close range: st_mp"
		decisions.append(mp)
		
		# Priority 4: st_mk
		var mk = Decision.new()
		mk.layer = DecisionLayer.TACTICAL
		mk.action = "st_mk"
		mk.priority = PRIORITY_NORMAL_LOW
		mk.reason = "Close range: st_mk"
		decisions.append(mk)
		
		# Priority 5: Crouch attacks
		var crouch = Decision.new()
		crouch.layer = DecisionLayer.TACTICAL
		crouch.action = "cr_mp" if distance < 50 else "cr_mk"
		crouch.priority = PRIORITY_CROUCH_LOW
		crouch.reason = "Close range: low attack"
		decisions.append(crouch)
		
		# Priority 6: Tactical retreat (lowest)
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
