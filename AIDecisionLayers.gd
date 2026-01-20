class_name AIDecisionLayers extends Node

enum DecisionLayer { SURVIVAL, PUNISH, TACTICAL, POSITIONING, IDLE }

# Decision Priority Constants
const PRIORITY_CRITICAL = 100.0
const PRIORITY_SURVIVAL = 85.0
const PRIORITY_PUNISH = 90.0
const PRIORITY_COMBO = 70.0
const PRIORITY_MID_POKE_HIGH = 65.0
const PRIORITY_MID_POKE_LOW = 58.0
const PRIORITY_FIREBALL_HIGH = 60.0
const PRIORITY_FIREBALL_LOW = 50.0
const PRIORITY_CLOSE_ATTACK = 60.0
const PRIORITY_DASH = 60.0
const PRIORITY_MID_BLOCK = 55.0
const PRIORITY_CLOSE_RETREAT = 55.0
const PRIORITY_WALK = 52.0
const PRIORITY_JUMP = 48.0
const PRIORITY_POSITIONING = 30.0
const PRIORITY_IDLE = 10.0

# Probability Constants
const PROB_FIREBALL_HIGH_PRIORITY = 0.6  # 60% chance of high priority fireball
const PROB_WALK_FORWARD = 0.7            # 70% chance of walking forward vs backward
const PROB_JUMP = 0.2                    # 20% chance of jump at long range
const PROB_MID_POKE_HIGH = 0.7           # 70% chance of high priority poke
const PROB_MID_BLOCK = 0.3               # 30% chance of blocking at mid range
const PROB_CLOSE_ST_MP = 0.6             # 60% chance of st_mp vs st_mk
const PROB_CLOSE_RETREAT = 0.3           # 30% chance of backdash at close range
const PROB_IDLE_WALK = 0.6               # 60% chance of walk vs block when idle

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
	var decisions: Array[Decision] = []
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	
	# 遠距離戰術 (Far range - distance > 250)
	if distance > 250:
		# 1. Fireball (occasional, not constant)
		if ai_player and ai_player.move_set:
			var is_busy = ai_player.move_set.is_spmove
			if not is_busy and randf() < 0.3:  # Only 30% chance to even consider fireball
				var fb = Decision.new()
				fb.layer = DecisionLayer.TACTICAL
				fb.action = "fireball"
				fb.priority = 55.0  # Lower priority
				fb.reason = "Far range zoning"
				decisions.append(fb)
		
		# 2. Walking (primary long-range action)
		var walk = Decision.new()
		walk.layer = DecisionLayer.TACTICAL
		walk.action = "walk_forward" if randf() < 0.65 else "walk_backward"
		walk.priority = 60.0  # Higher than fireball
		walk.reason = "Far range approach/retreat"
		decisions.append(walk)
		
		# 3. Blocking/Observing
		if randf() < 0.4:
			var block = Decision.new()
			block.layer = DecisionLayer.TACTICAL
			block.action = "stand_block"
			block.priority = 58.0
			block.reason = "Far range observe"
			decisions.append(block)
		
		# 4. Crouching
		if randf() < 0.25:
			var crouch = Decision.new()
			crouch.layer = DecisionLayer.TACTICAL
			crouch.action = "crouch_block"
			crouch.priority = 57.0
			crouch.reason = "Far range crouch"
			decisions.append(crouch)
		
		# 5. Dashing forward
		if randf() < 0.35:
			var dash = Decision.new()
			dash.layer = DecisionLayer.TACTICAL
			dash.action = "dash_forward"
			dash.priority = 62.0
			dash.reason = "Far range dash approach"
			decisions.append(dash)
		
		# 6. Jumping
		if randf() < 0.2:
			var jump = Decision.new()
			jump.layer = DecisionLayer.TACTICAL
			jump.action = "jump_forward" if distance > 350 else "jump_neutral"
			jump.priority = 54.0
			jump.reason = "Far range jump"
			decisions.append(jump)
	
	# 中距離戰術 (Mid range - 100 < distance <= 250)
	elif distance > 100:
		# 1. Poking attacks
		var poke = Decision.new()
		poke.layer = DecisionLayer.TACTICAL
		poke.action = "st_mk"
		poke.priority = 65.0 if randf() < 0.6 else 58.0
		poke.reason = "Mid range poke"
		decisions.append(poke)
		
		# 2. Approach with dash
		if randf() < 0.5:
			var approach = Decision.new()
			approach.layer = DecisionLayer.TACTICAL
			approach.action = "dash_forward"
			approach.priority = 60.0
			approach.reason = "Close the gap"
			decisions.append(approach)
		
		# 3. Defensive blocking
		if randf() < 0.35:
			var block = Decision.new()
			block.layer = DecisionLayer.TACTICAL
			block.action = "stand_block"
			block.priority = 55.0
			block.reason = "Mid range defense"
			decisions.append(block)
		
		# 4. Walking
		if randf() < 0.3:
			var walk = Decision.new()
			walk.layer = DecisionLayer.TACTICAL
			walk.action = "walk_forward" if randf() < 0.7 else "walk_backward"
			walk.priority = 52.0
			walk.reason = "Mid range positioning"
			decisions.append(walk)
		
		# 5. Crouch pokes
		if randf() < 0.25:
			var crouch_attack = Decision.new()
			crouch_attack.layer = DecisionLayer.TACTICAL
			crouch_attack.action = "cr_mk"
			crouch_attack.priority = 63.0
			crouch_attack.reason = "Mid range low poke"
			decisions.append(crouch_attack)
	
	# 近距離戰術 (Close range - distance <= 100)
	else:
		# 1. Combo execution
		var combo_names = combo_system.get_available_combos(ai_player, opponent)
		for combo_name in combo_names:
			var combo_dec = Decision.new()
			combo_dec.layer = DecisionLayer.TACTICAL
			combo_dec.action = "combo_" + combo_name
			combo_dec.priority = 70.0
			combo_dec.reason = "Execute combo: " + combo_name
			decisions.append(combo_dec)
		
		# 2. Normal attacks (if no combos available)
		if combo_names.size() == 0:
			var close_attack = Decision.new()
			close_attack.layer = DecisionLayer.TACTICAL
			close_attack.action = "st_mp" if randf() < 0.5 else "st_mk"
			close_attack.priority = 60.0
			close_attack.reason = "Close range attack"
			decisions.append(close_attack)
		
		# 3. Crouching attacks
		if randf() < 0.4:
			var crouch_attack = Decision.new()
			crouch_attack.layer = DecisionLayer.TACTICAL
			crouch_attack.action = "cr_mp" if randf() < 0.6 else "cr_mk"
			crouch_attack.priority = 58.0
			crouch_attack.reason = "Close range low attack"
			decisions.append(crouch_attack)
		
		# 4. Defensive retreat
		if randf() < 0.3:
			var retreat = Decision.new()
			retreat.layer = DecisionLayer.TACTICAL
			retreat.action = "backdash"
			retreat.priority = 55.0
			retreat.reason = "Create space"
			decisions.append(retreat)
		
		# 5. Block/Wait
		if randf() < 0.25:
			var block = Decision.new()
			block.layer = DecisionLayer.TACTICAL
			block.action = "stand_block"
			block.priority = 53.0
			block.reason = "Close range defend"
			decisions.append(block)
	
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
	decision.action = "walk_forward" if randf() < PROB_IDLE_WALK else "stand_block"
	decision.reason = "Default behavior"
	return decision
