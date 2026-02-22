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

const SPECIAL_MOVE_ACTIONS = ["fireball", "spm2", "powerkk", "spnk", "hdk", "dp", "super"]

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

func _process(delta: float) -> void:
	"""Update cache and cooldown timers"""
	if cache_timer > 0:
		cache_timer -= delta
	if special_cooldown_timer > 0:
		special_cooldown_timer -= delta

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
		# Use override if > 0, use default if 0, disable if < 0
		if cache_duration_override > 0:
			cache_timer = cache_duration_override
		elif cache_duration_override == 0:
			cache_timer = CACHE_DURATION
		else:  # < 0, disable caching
			cache_timer = 0.0
	# 必殺技已選擇：啟動冷卻，避免刷屏
	if decision.action in SPECIAL_MOVE_ACTIONS:
		special_cooldown_timer = SPECIAL_COOLDOWN

func _evaluate_survival_layer(ai_player: Player, opponent: Player) -> Decision:
	var threat = threat_system.evaluate_threats(ai_player, opponent)
	
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
				return emergency
		return null
	
	var decision = Decision.new()
	decision.layer = DecisionLayer.SURVIVAL
	decision.action = threat.recommended_response
	if decision.action in SPECIAL_MOVE_ACTIONS and not _can_use_special(ai_player, opponent):
		decision.action = "stand_block"
		decision.reason = "Threat: %s (special gated)" % threat.source
		decision.priority = PRIORITY_SURVIVAL
		return decision
	
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
		return false
	# 懲罰窗口：永遠允許
	if opponent.is_hit or opponent.is_knockfly:
		return true
	if frame_data.is_in_recovery(opponent):
		return true
	# 中立狀態下允許：只要 AI 玩家自己不在攻擊/受傷/被擊飛/空中的狀態
	if not ai_player.is_attacking and not ai_player.is_hit and not ai_player.is_knockfly and ai_player.is_on_floor():
		return true
	return false

func _is_punish_opportunity(opponent: Player) -> bool:
	"""對手是否處於可懲罰狀態（被擊中、被擊飛、或在恢復動作）"""
	return opponent.is_hit or opponent.is_knockfly or frame_data.is_in_recovery(opponent)

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
		if ai_player and ai_player.move_set and not ai_player.move_set.is_spmove and _can_use_special(ai_player, opponent):
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
		if char_id == "DAV" and _can_use_special(ai_player, opponent):
			# DP (dragon punch) - anti-air and pressure
			var dp = Decision.new()
			dp.layer = DecisionLayer.TACTICAL
			dp.action = "dp"
			dp.priority = _get_special_priority(opponent)
			dp.reason = "Mid range: DP"
			decisions.append(dp)
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
		
		# Priority 2: st_mk poke (平衡優先級)
		var poke = Decision.new()
		poke.layer = DecisionLayer.TACTICAL
		poke.action = "st_mk"
		poke.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
		poke.reason = "Mid range: poke"
		decisions.append(poke)
		
		# Priority 3: st_mp quick attack (平衡優先級)
		var mp_poke = Decision.new()
		mp_poke.layer = DecisionLayer.TACTICAL
		mp_poke.action = "st_mp"
		mp_poke.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
		mp_poke.reason = "Mid range: quick poke"
		decisions.append(mp_poke)
		
		# Priority 4: Light attacks (faster startup, lower damage) - 提升優先級
		var st_lp = Decision.new()
		st_lp.layer = DecisionLayer.TACTICAL
		st_lp.action = "st_lp"
		st_lp.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
		st_lp.reason = "Mid range: quick light punch"
		decisions.append(st_lp)
		
		var st_lk = Decision.new()
		st_lk.layer = DecisionLayer.TACTICAL
		st_lk.action = "st_lk"
		st_lk.priority = PRIORITY_NORMAL_LOW + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
		st_lk.reason = "Mid range: light kick"
		decisions.append(st_lk)
		
		# Priority 5: cr_mk low poke (平衡優先級)
		var crouch_poke = Decision.new()
		crouch_poke.layer = DecisionLayer.TACTICAL
		crouch_poke.action = "cr_mk"
		crouch_poke.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
		crouch_poke.reason = "Mid range: low poke"
		decisions.append(crouch_poke)
		
		# Priority 6: cr_mp close low attack (平衡優先級)
		if distance < 150:
			var cr_mp_poke = Decision.new()
			cr_mp_poke.layer = DecisionLayer.TACTICAL
			cr_mp_poke.action = "cr_mp"
			cr_mp_poke.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
			cr_mp_poke.reason = "Mid range: cr_mp"
			decisions.append(cr_mp_poke)
			
			# Light crouch attacks - 提升優先級
			var cr_lp = Decision.new()
			cr_lp.layer = DecisionLayer.TACTICAL
			cr_lp.action = "cr_lp"
			cr_lp.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
			cr_lp.reason = "Mid range: cr_lp"
			decisions.append(cr_lp)
			
			var cr_lk = Decision.new()
			cr_lk.layer = DecisionLayer.TACTICAL
			cr_lk.action = "cr_lk"
			cr_lk.priority = PRIORITY_CROUCH + randf_range(-1.0, 3.0)  # 67 + (-1 to 3) = 66-70
			cr_lk.reason = "Mid range: cr_lk"
			decisions.append(cr_lk)
		
		# Priority 7: Heavy attacks (slower startup, higher damage) - 提升至與輕攻擊相同範圍
		var st_hp = Decision.new()
		st_hp.layer = DecisionLayer.TACTICAL
		st_hp.action = "st_hp"
		st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		st_hp.reason = "Mid range: heavy punch"
		decisions.append(st_hp)
		
		var st_hk = Decision.new()
		st_hk.layer = DecisionLayer.TACTICAL
		st_hk.action = "st_hk"
		st_hk.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		st_hk.reason = "Mid range: heavy kick"
		decisions.append(st_hk)
		
		var cr_hp = Decision.new()
		cr_hp.layer = DecisionLayer.TACTICAL
		cr_hp.action = "cr_hp"
		cr_hp.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		cr_hp.reason = "Mid range: cr_hp"
		decisions.append(cr_hp)
		
		var cr_hk = Decision.new()
		cr_hk.layer = DecisionLayer.TACTICAL
		cr_hk.action = "cr_hk"
		cr_hk.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		cr_hk.reason = "Mid range: cr_hk"
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
			# DP (dragon punch)
			var dp = Decision.new()
			dp.layer = DecisionLayer.TACTICAL
			dp.action = "dp"
			dp.priority = _get_special_priority(opponent)
			dp.reason = "Close range: DP"
			decisions.append(dp)
			# Power kick
			var powerkk = Decision.new()
			powerkk.layer = DecisionLayer.TACTICAL
			powerkk.action = "powerkk"
			powerkk.priority = _get_special_priority(opponent)
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
		if distance < 90 and not ai_player.is_attacking and not ai_player.is_hit and not ai_player.is_knockfly:
			var throw_dec = Decision.new()
			throw_dec.layer = DecisionLayer.TACTICAL
			throw_dec.action = "throw"
			if opponent.is_blocking:
				# 對手正在格擋時摔投優先級大幅提升（摔投無視格擋）
				throw_dec.priority = 76.0 + randf_range(-2.0, 3.0)
				throw_dec.reason = "Close range: throw beats block"
			else:
				# 中立時摔投優先級較低，讓普通攻擊和必殺技優先
				throw_dec.priority = 62.0 + randf_range(-2.0, 2.0)
				throw_dec.reason = "Close range: throw"
			decisions.append(throw_dec)
		
		# Priority 3: Medium-range normals (st_mp, st_mk, cr_mp) - 平衡優先級
		var close_rand = randf_range(-2.0, 3.0)  # 中攻击范围
		
		# st_mp (fast close attack)
		var mp = Decision.new()
		mp.layer = DecisionLayer.TACTICAL
		mp.action = "st_mp"
		mp.priority = PRIORITY_NORMAL_MID + close_rand  # 67 + (-2 to 3) = 65-70
		mp.reason = "Close range: st_mp"
		decisions.append(mp)
		
		# st_mk
		var mk = Decision.new()
		mk.layer = DecisionLayer.TACTICAL
		mk.action = "st_mk"
		mk.priority = PRIORITY_NORMAL_HIGH + randf_range(-2.0, 3.0)  # 67 + (-2 to 3) = 65-70
		mk.reason = "Close range: st_mk"
		decisions.append(mk)
		
		# cr_mp (very close low attack)
		var cr_mp = Decision.new()
		cr_mp.layer = DecisionLayer.TACTICAL
		cr_mp.action = "cr_mp"
		cr_mp.priority = PRIORITY_CROUCH + randf_range(-2.0, 3.0)  # 67 + (-2 to 3) = 65-70
		cr_mp.reason = "Close range: cr_mp"
		decisions.append(cr_mp)
		
		# cr_mk (low poke)
		var cr_mk = Decision.new()
		cr_mk.layer = DecisionLayer.TACTICAL
		cr_mk.action = "cr_mk"
		cr_mk.priority = PRIORITY_NORMAL_LOW + randf_range(-2.0, 3.0)  # 67 + (-2 to 3) = 65-70
		cr_mk.reason = "Close range: cr_mk"
		decisions.append(cr_mk)
		
		# Priority 4: Light attacks (faster startup, good for combos) - 提升優先級（近身适合轻攻击）
		var st_lp = Decision.new()
		st_lp.layer = DecisionLayer.TACTICAL
		st_lp.action = "st_lp"
		st_lp.priority = PRIORITY_NORMAL_MID + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		st_lp.reason = "Close range: quick light punch"
		decisions.append(st_lp)
		
		var st_lk = Decision.new()
		st_lk.layer = DecisionLayer.TACTICAL
		st_lk.action = "st_lk"
		st_lk.priority = PRIORITY_NORMAL_LOW + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		st_lk.reason = "Close range: light kick"
		decisions.append(st_lk)
		
		var cr_lp = Decision.new()
		cr_lp.layer = DecisionLayer.TACTICAL
		cr_lp.action = "cr_lp"
		cr_lp.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		cr_lp.reason = "Close range: cr_lp"
		decisions.append(cr_lp)
		
		var cr_lk = Decision.new()
		cr_lk.layer = DecisionLayer.TACTICAL
		cr_lk.action = "cr_lk"
		cr_lk.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		cr_lk.reason = "Close range: cr_lk"
		decisions.append(cr_lk)
		
		# Priority 5: Heavy attacks (slower startup, higher damage) - 提升至與輕攻擊相同範圍
		var st_hp = Decision.new()
		st_hp.layer = DecisionLayer.TACTICAL
		st_hp.action = "st_hp"
		st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		st_hp.reason = "Close range: heavy punch"
		decisions.append(st_hp)
		
		var st_hk = Decision.new()
		st_hk.layer = DecisionLayer.TACTICAL
		st_hk.action = "st_hk"
		st_hk.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		st_hk.reason = "Close range: heavy kick"
		decisions.append(st_hk)
		
		var cr_hp = Decision.new()
		cr_hp.layer = DecisionLayer.TACTICAL
		cr_hp.action = "cr_hp"
		cr_hp.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		cr_hp.reason = "Close range: cr_hp"
		decisions.append(cr_hp)
		
		var cr_hk = Decision.new()
		cr_hk.layer = DecisionLayer.TACTICAL
		cr_hk.action = "cr_hk"
		cr_hk.priority = PRIORITY_CROUCH + randf_range(-1.0, 4.0)  # 67 + (-1 to 4) = 66-71
		cr_hk.reason = "Close range: cr_hk"
		decisions.append(cr_hk)
		
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
			print("[AI.get_fallback_decision] Using normal attack fallback: %s" % alternative_normals[0].action)
		return alternative_normals[0]
	
	if not defensive_options.is_empty():
		defensive_options.sort_custom(func(a, b): return a.priority > b.priority)
		if Engine.get_physics_frames() % 120 == 0:
			print("[AI.get_fallback_decision] Using defensive fallback: %s" % defensive_options[0].action)
		return defensive_options[0]
	
	if not movement_options.is_empty():
		movement_options.sort_custom(func(a, b): return a.priority > b.priority)
		if Engine.get_physics_frames() % 120 == 0:
			print("[AI.get_fallback_decision] Using movement fallback: %s" % movement_options[0].action)
		return movement_options[0]
	
	# 最後的備選方案：待機
	if Engine.get_physics_frames() % 120 == 0:
		print("[AI.get_fallback_decision] All options exhausted, returning idle")
	return _get_idle_decision()
