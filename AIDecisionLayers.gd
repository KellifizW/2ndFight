class_name AIDecisionLayers extends Node

enum DecisionLayer { SURVIVAL, PUNISH, TACTICAL, POSITIONING, IDLE }

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
	decision.priority = 100.0 if threat.level == ThreatAssessment.ThreatLevel.CRITICAL else 85.0
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
	decision.priority = 90.0
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
	
	# 遠距離戰術
	if distance > 250:
		var fb = Decision.new()
		fb.layer = DecisionLayer.TACTICAL
		fb.action = "fireball"
		fb.priority = 60.0
		fb.reason = "Far range zoning"
		decisions.append(fb)
	
	# 中距離戰術
	elif distance > 100:
		var poke = Decision.new()
		poke.layer = DecisionLayer.TACTICAL
		poke.action = "st_mk"
		poke.priority = 65.0
		poke.reason = "Mid range poke"
		decisions.append(poke)
		
		# 中距離也可以考慮接近
		var approach = Decision.new()
		approach.layer = DecisionLayer.TACTICAL
		approach.action = "dash_forward"
		approach.priority = 55.0
		approach.reason = "Close the gap"
		decisions.append(approach)
	
	# 近距離戰術
	else:
		# 嘗試執行連段
		var combo_names = combo_system.get_available_combos(ai_player, opponent)
		for combo_name in combo_names:
			var combo_dec = Decision.new()
			combo_dec.layer = DecisionLayer.TACTICAL
			combo_dec.action = "combo_" + combo_name
			combo_dec.priority = 70.0
			combo_dec.reason = "Execute combo: " + combo_name
			decisions.append(combo_dec)
		
		# 如果沒有可用連段，使用單招
		if combo_names.size() == 0:
			var close_attack = Decision.new()
			close_attack.layer = DecisionLayer.TACTICAL
			close_attack.action = "st_mp"
			close_attack.priority = 60.0
			close_attack.reason = "Close range attack"
			decisions.append(close_attack)
	
	return decisions

func _evaluate_positioning_layer(ai_player: Player, opponent: Player) -> Decision:
	var decision = Decision.new()
	decision.layer = DecisionLayer.POSITIONING
	decision.priority = 30.0
	
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
	decision.priority = 10.0
	decision.action = "walk_forward" if randf() < 0.6 else "stand_block"
	decision.reason = "Default behavior"
	return decision
