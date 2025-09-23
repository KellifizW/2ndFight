extends Node

@onready var parent: Node = get_parent()  # 抓Player父節點
var ai_enabled: bool = false  # AI開關（從CPUController傳來）
var current_state: String = "idle"  # AI狀態機 (idle, approach, attack, defend, jump)
var state_timer: float = 0.0  # 狀態延遲計時器
var last_action_time: float = 0.0  # 上次動作時間（避連續）
var input_dir_timer: float = 0.0  # 輸入方向穩定計時器
var dash_cooldown: float = 0.0  # dash 冷卻計時器
var recovery_timer: float = 0.0  # 被擊中後恢復計時器
var block_timer: float = 0.0  # 格擋持續計時器
var crouch_timer: float = 0.0  # 蹲下持續計時器
var random_poke_chance: float = 0.1  # 隨機poke機率（可調）

# 追蹤對手硬直（參考 fighter.gd 的 timer 值）
var opponent_recovery_time: float = 0.0  # 對手攻擊剩餘時間
var opponent_stun_remaining: float = 0.0  # 對手 stun/block 剩餘
var is_crouching: bool = false  # 當前是否蹲下

func _ready():
	if not parent:
		print("Warning: No parent Player found for AIBehavior")
	if parent:
		print("Debug: AIBehavior ready for %s!" % parent.name)
		# 隨機初始state_timer，打破對稱
		state_timer = randf() * 0.5 + 0.5  # 0.5-1.0秒
	else:
		print("Debug: AIBehavior ready for unknown!")

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if enabled:
		current_state = "approach" if randf() > 0.3 else "idle"  # 70%機率初始為approach
		state_timer = randf() * 0.5 + 0.5  # 隨機初始計時器
	if parent:
		print("Debug: AI %s for %s" % ["enabled" if enabled else "disabled", parent.name])
	else:
		print("Debug: AI %s for unknown" % ["enabled" if enabled else "disabled"])

func _physics_process(delta):
	if not ai_enabled:
		return
	# 檢查雙方血量，停止行為如果任一方血量為 0
	var opponent = get_opponent()
	var parent_health = parent.healthbar.current_health if parent and parent.healthbar else 100.0
	var opponent_health = opponent.healthbar.current_health if opponent and opponent.healthbar else 100.0
	if parent_health <= 0.0 or opponent_health <= 0.0:
		return  # 停止 AI 行為
	update_ai_state(delta)
	input_dir_timer -= delta
	dash_cooldown -= delta
	recovery_timer -= delta
	block_timer -= delta
	crouch_timer -= delta

func update_ai_state(delta: float):
	state_timer -= delta
	var opponent = get_opponent()
	if not opponent:
		return
	
	# 更新對手硬直時間
	opponent_recovery_time = opponent.attack_timer if opponent else 0.0
	opponent_stun_remaining = max(opponent.hit_timer, opponent.block_timer) if opponent else 0.0
	
	var can_attack = is_in_attack_range(parent, opponent)
	var in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)
	var opponent_attacking = opponent.is_attacking or opponent.is_dashing
	var opponent_blocking = opponent.is_blocking or opponent.is_hit
	var parent_health = parent.healthbar.current_health if parent.healthbar else 100.0
	var is_low_health = parent_health < 50.0
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	
	# 被擊中或擊飛時強制進入防禦狀態
	if parent.is_hit or parent.is_knockfly:
		current_state = "defend"
		recovery_timer = 1.2
		block_timer = 1.2
		state_timer = 1.2
		print("Debug: AI hit or knockfly, entering defend state for %s" % parent.name)
		return
	
	# 狀態轉換邏輯
	match current_state:
		"idle":
			if last_action_time > 0.8:
				if can_attack and randf() > 0.1:  # 90%機率進攻
					current_state = "attack"
					print("Debug: Aggressive attack triggered for AI")
				elif distance < 60.0 and randf() < random_poke_chance:  # 10%機率隨機poke
					current_state = "attack"
					print("Debug: Random poke triggered in idle for AI")
				elif in_danger or (opponent_attacking and distance < 50.0):
					current_state = "defend"
					block_timer = 1.2
					state_timer = 1.2
					print("Debug: Defend triggered due to danger or opponent attack")
				elif is_cornered and distance < 80.0 and randf() > 0.4:
					current_state = "jump"
					state_timer = 0.6
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach"
					state_timer = randf() * 0.5 + 0.5  # 縮短持續時間
		"approach":
			if last_action_time > 0.8:
				if can_attack and randf() > 0.1:
					current_state = "attack"
					print("Debug: Aggressive attack from approach for AI")
				elif distance < 60.0 and randf() < random_poke_chance:  # 10%機率隨機poke
					current_state = "attack"
					print("Debug: Random poke triggered in approach for AI")
				elif opponent_recovery_time < 0.1 and distance < 80.0 and randf() > 0.3:
					current_state = "attack"
					print("Debug: Punish attack triggered for AI")
				elif in_danger or (opponent_attacking and distance < 50.0):
					current_state = "defend"
					block_timer = 1.2
					state_timer = 1.2
					print("Debug: Defend triggered from approach")
				elif is_cornered and distance < 80.0 and randf() > 0.4:
					current_state = "jump"
					state_timer = 0.6
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach" if distance > 45.0 else "idle"
					state_timer = randf() * 0.5 + 0.5
		"attack":
			if in_danger or (opponent_attacking and distance < 50.0):
				current_state = "defend"
				block_timer = 1.2
				state_timer = 1.2
				print("Debug: Defend triggered from attack")
			elif state_timer <= 0 or distance > 45.0:
				current_state = "approach"
				state_timer = randf() * 0.5 + 0.5
		"defend":
			if recovery_timer > 0 or block_timer > 0:
				return
			if not in_danger and (not opponent_attacking or distance > 50.0):
				if opponent_recovery_time < 0.1 and can_attack and randf() > 0.3:
					current_state = "attack"
					print("Debug: Poke attack after defend for AI")
				else:
					current_state = "approach" if distance > 45.0 else "idle"
					state_timer = randf() * 0.5 + 0.5
			elif opponent_stun_remaining > 0.1 and randf() > 0.2:
				current_state = "attack"
				print("Debug: Counterattack after stun for AI")
			elif state_timer <= 0:
				current_state = "approach" if distance > 45.0 else "idle"
				state_timer = randf() * 0.5 + 0.5
		"jump":
			if state_timer <= 0 or opponent.is_jumping:
				current_state = "approach"
				state_timer = randf() * 0.5 + 0.5
			elif in_danger or (opponent_attacking and distance < 50.0):
				current_state = "defend"
				block_timer = 1.2
				state_timer = 1.2
				print("Debug: Defend triggered from jump")
			elif is_cornered and randf() > 0.5:
				state_timer = 0.6
	
	last_action_time += delta
	if parent:
		if OS.is_debug_build():
			print("Debug: AI state for %s: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s" % [parent.name, current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered])
	else:
		if OS.is_debug_build():
			print("Debug: AI state for unknown: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s" % [current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered])

func get_ai_input() -> Dictionary:
	if not ai_enabled:
		return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false, false)
	
	# 檢查雙方血量
	var parent_health = parent.healthbar.current_health if parent and parent.healthbar else 100.0
	var opponent = get_opponent()
	var opponent_health = opponent.healthbar.current_health if opponent and opponent.healthbar else 100.0
	if parent_health <= 0.0 or opponent_health <= 0.0:
		return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false, false)
	
	var input_dir = 0
	var crouch_pressed = false
	var jump_pressed = false
	var attack_pressed = false
	var spm1_pressed = false
	var dash_pressed = false
	var attack_type = "none"
	var blockstun_duration = 0.2
	var damage = 0.0
	var last_input_dir = input_dir
	
	if not opponent:
		input_dir = 1
		return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed, dash_pressed)
	
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var opponent_attacking = opponent.is_attacking or opponent.is_dashing
	var time_since_last = last_action_time
	var can_attack = is_in_attack_range(parent, opponent)
	var in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)
	var is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	var opponent_stun_remaining = max(opponent.hit_timer, opponent.block_timer) if opponent else 0.0
	var opponent_recovery_time = opponent.attack_timer if opponent else 0.0
	
	# 被擊中或擊飛時強制後退並嘗試格擋
	if parent.is_hit or parent.is_knockfly or block_timer > 0:
		input_dir = -1 if parent.global_position.x < opponent.global_position.x else 1
		if crouch_timer > 0:
			crouch_pressed = is_crouching
		else:
			crouch_pressed = (opponent.is_crouching and opponent_attacking and randf() > 0.9) or (parent.is_hit and randf() > 0.9)
			if crouch_pressed:
				crouch_timer = 0.3
				is_crouching = true
				print("Debug: AI crouch block triggered for %s" % parent.name)
			else:
				is_crouching = false
				print("Debug: AI standing block triggered for %s" % parent.name)
		return build_input_dict(input_dir, crouch_pressed, false, false, "none", 0.2, 0.0, false, false)
	
	# 移動邏輯（縮減遲滯範圍為40-45像素）
	if distance > 100.0:
		input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
	elif distance > 45.0:
		input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
	elif distance < 40.0:
		if can_attack:
			input_dir = 0
		else:
			input_dir = -1 if parent.global_position.x < opponent.global_position.x else 1
	else:
		input_dir = 0  # 40-45像素間靜止
	
	# 穩定輸入方向
	if input_dir_timer <= 0:
		last_input_dir = input_dir
		input_dir_timer = 0.7
	
	if current_state == "defend" or (in_danger and opponent_attacking):
		input_dir = -last_input_dir
		if in_danger or opponent_attacking or block_timer > 0:
			if crouch_timer > 0:
				crouch_pressed = is_crouching
			else:
				crouch_pressed = (opponent.is_crouching and opponent_attacking and randf() > 0.9) or (parent.is_hit and randf() > 0.9)
				if crouch_pressed:
					crouch_timer = 0.3
					is_crouching = true
					print("Debug: AI crouch block triggered for %s" % parent.name)
				else:
					is_crouching = false
					print("Debug: AI standing block triggered for %s" % parent.name)
			if is_cornered and randf() > 0.6:
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Corner escape jump in defend for AI")
		else:
			if randf() > 0.995:
				input_dir = 0
				print("Debug: Neutral pause for AI")
			elif randf() > 0.995 and distance > 50.0:
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Neutral jump for AI")
	elif current_state == "approach":
		if time_since_last > 0.4 and dash_cooldown <= 0:
			if distance > 100.0 and not is_cornered and randf() > 0.85:
				dash_pressed = true
				dash_cooldown = 1.2
				print("Debug: Dash triggered for AI approach")
			elif randf() > 0.995 and distance > 50.0:
				input_dir = -last_input_dir
				input_dir_timer = 0.7
				print("Debug: Neutral backstep for AI")
			elif randf() > 0.995 and distance > 50.0:
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Neutral jump for AI")
		if is_cornered:
			input_dir = -last_input_dir
			if randf() > 0.6:
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Approach corner escape for AI")
	elif current_state == "attack":
		if distance < 50.0 and time_since_last > 0.6:
			if (opponent_stun_remaining > 0.2 and distance < 30) and randf() > 0.5:
				spm1_pressed = true
				damage = 20.0
				attack_pressed = false
				attack_type = "none"
				if OS.is_debug_build():
					print("Debug: Enhanced combo special attack triggered for AI")
			elif opponent_recovery_time < 0.1 and distance < 30 and randf() > 0.5:
				spm1_pressed = true
				damage = 20.0
				attack_pressed = false
				attack_type = "none"
				if OS.is_debug_build():
					print("Debug: Punish special attack triggered for AI")
			else:
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				spm1_pressed = false
			state_timer = 0.6
		else:
			if randf() > 0.995 and distance > 50.0:
				input_dir = 0
				print("Debug: Neutral pause after attack for AI")
	elif current_state == "jump":
		jump_pressed = true
		crouch_pressed = false
		crouch_timer = 0.0
		is_crouching = false
		input_dir = last_input_dir * (-1 if is_cornered else 1)
		if OS.is_debug_build():
			print("Debug: Jump input for corner escape")
	
	# 低血量更積極進攻
	if parent_health < 50.0:
		if randf() > 0.4:
			attack_pressed = true if can_attack else false
			spm1_pressed = true if distance < 30 and randf() > 0.5 else false
	
	# 跟跳
	if opponent.is_jumping and is_opponent_close(opponent) and randf() > 0.3:
		jump_pressed = true
		crouch_pressed = false
		crouch_timer = 0.0
		is_crouching = false
	
	if parent:
		if OS.is_debug_build():
			print("Debug: AI input for %s: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, dash=%s, cornered=%s" % [parent.name, current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed, dash_pressed, is_cornered])
	else:
		if OS.is_debug_build():
			print("Debug: AI input for unknown: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, dash=%s, cornered=%s" % [current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed, dash_pressed, is_cornered])
	
	return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed, dash_pressed)

# 輔助函數：檢查是否在攻擊範圍（重疊或距離<45，基於Hitbox設置）
func is_in_attack_range(attacker: Node, target: Node) -> bool:
	if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
		return false
	var hitbox = attacker.get_node("Hitbox") as Area2D
	var hurtbox = target.get_node("Hurtbox") as Area2D
	for area in hitbox.get_overlapping_areas():
		if area == hurtbox and area.get_parent() != attacker:
			return true
	var distance = abs(attacker.global_position.x - target.global_position.x)
	return distance < 45.0  # 匹配Hitbox(25+13.5)

# 輔助函數：檢查對手Hitbox是否與AI的Hurtbox重疊
func is_hitbox_overlapping_hurtbox(attacker: Node, target: Node) -> bool:
	if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
		return false
	var hitbox = attacker.get_node("Hitbox") as Area2D
	var hurtbox = target.get_node("Hurtbox") as Area2D
	for area in hitbox.get_overlapping_areas():
		if area == hurtbox and area.get_parent() != attacker:
			return true
	return false

# 輔助函數：檢查對手是否夠近
func is_opponent_close(opponent: Node) -> bool:
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	return distance < 30.0

# 輔助函數：建輸入字典
func build_input_dict(input_dir: int, crouch: bool, jump: bool, attack: bool, a_type: String, bstun: float, dmg: float, spm1: bool, dash: bool) -> Dictionary:
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch,
		"jump_pressed": jump,
		"attack_pressed": attack,
		"attack_type": a_type,
		"blockstun_duration": bstun,
		"damage": dmg,
		"spm1_pressed": spm1,
		"dash_pressed": dash
	}

# 輔助函數：抓對手
func get_opponent() -> Node:
	var all_players = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != parent:
			return p
	return null
