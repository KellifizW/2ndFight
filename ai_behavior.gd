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
var random_poke_chance: float = 0.15  # 隨機poke機率（增加以更積極）
var jump_attack_chance: float = 0.6  # 跳攻擊機率（降低到60%，避免過頻）
var proactive_jump_chance: float = 0.3  # 新：中距離主動跳攻機率（30%）

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
		state_timer = randf() * 0.3 + 0.3  # 縮短初始：0.3-0.6秒，更快啟動
	else:
		print("Debug: AIBehavior ready for unknown!")

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if enabled:
		current_state = "approach" if randf() > 0.2 else "idle"  # 80%機率初始為approach，更積極
		state_timer = randf() * 0.3 + 0.3  # 縮短初始計時器
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
	var opponent_jumping = opponent.is_jumping  # 新：追蹤對手是否跳躍
	
	# 被擊中或擊飛時強制進入防禦狀態
	if parent.is_hit or parent.is_knockfly:
		current_state = "defend"
		recovery_timer = 0.5  # 進一步縮短：從0.8到0.5，更快反擊
		block_timer = 0.5
		state_timer = 0.5
		print("Debug: AI hit or knockfly, entering defend state for %s" % parent.name)
		return
	
	# 狀態轉換邏輯（更積極：縮短計時器，增加追擊）
	match current_state:
		"idle":
			if last_action_time > 0.4:  # 縮短從0.8到0.4，更快反應
				if can_attack and distance < 45.0 and randf() > 0.05:  # 新增：嚴格距離檢查才進攻
					current_state = "attack"
					print("Debug: Aggressive attack triggered for AI")
				elif distance < 60.0 and randf() < random_poke_chance:
					current_state = "attack"
					print("Debug: Random poke triggered in idle for AI")
				elif in_danger or (opponent_attacking and distance < 50.0):
					current_state = "defend"
					block_timer = 0.5
					state_timer = 0.5
					print("Debug: Defend triggered due to danger or opponent attack")
				elif is_cornered and distance < 80.0 and randf() > 0.3:  # 增加逃角機率
					current_state = "jump"
					state_timer = 0.4  # 縮短跳躍持續
					print("Debug: Corner jump escape triggered for AI")
				elif opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance:  # 修正：縮小範圍到<50，並綁定can_attack
					current_state = "attack"
					state_timer = 0.5
					print("Debug: Jump attack opportunity detected in idle for AI")
				elif distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance:  # 新：中距離主動跳攻
					current_state = "attack"
					state_timer = 0.5
					print("Debug: Proactive jump attack triggered in idle for AI")
				elif state_timer <= 0:
					current_state = "approach"
					state_timer = randf() * 0.3 + 0.3  # 縮短持續時間
		"approach":
			if last_action_time > 0.4:  # 縮短門檻
				if can_attack and distance < 45.0 and randf() > 0.05:  # 新增：嚴格距離檢查
					current_state = "attack"
					print("Debug: Aggressive attack from approach for AI")
				elif distance < 60.0 and randf() < random_poke_chance:
					current_state = "attack"
					print("Debug: Random poke triggered in approach for AI")
				elif opponent_recovery_time < 0.1 and distance < 80.0 and randf() > 0.2:  # 增加懲罰攻擊機率
					current_state = "attack"
					print("Debug: Punish attack triggered for AI")
				elif opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance:  # 修正：跟跳或中距離跳攻，縮小範圍並綁定can_attack
					current_state = "attack"
					state_timer = 0.5
					print("Debug: Jump attack from approach for AI")
				elif distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance:  # 新：approach中主動跳攻
					current_state = "attack"
					state_timer = 0.5
					print("Debug: Proactive jump attack from approach for AI")
				elif in_danger or (opponent_attacking and distance < 50.0):
					current_state = "defend"
					block_timer = 0.5
					state_timer = 0.5
					print("Debug: Defend triggered from approach")
				elif is_cornered and distance < 80.0 and randf() > 0.3:
					current_state = "jump"
					state_timer = 0.4
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach" if distance > 40.0 else "idle"  # 縮短距離門檻，從45到40
					state_timer = randf() * 0.3 + 0.3
		"attack":
			if in_danger or (opponent_attacking and distance < 30.0):  # 縮短危險距離，從50到30，只在超近時防禦
				current_state = "defend"
				block_timer = 0.5
				state_timer = 0.5
				print("Debug: Defend triggered from attack")
			elif distance > 45.0:  # 新增：距離太遠時強制修正，轉approach前進
				current_state = "approach"
				state_timer = randf() * 0.3 + 0.3
				print("Debug: Distance too far in attack, switching to approach for AI")
			elif opponent_stun_remaining > 0.15 and distance < 40.0 and randf() > 0.1:  # 強化追擊：提高門檻到0.15，增加機率到0.9，留在attack
				state_timer = 0.3  # 進一步縮短，加快連擊
				print("Debug: Chase attack continued for AI")
			elif opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance:  # 修正：擴大跳攻條件，縮小範圍並綁定can_attack
				state_timer = 0.5
				print("Debug: Jump attack in attack state for AI")
			elif distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance:  # 新：attack中主動跳攻
				state_timer = 0.5
				print("Debug: Proactive jump attack in attack state for AI")
			elif state_timer <= 0 or distance > 40.0:  # 縮短距離門檻，避免過早退後
				current_state = "approach"
				state_timer = randf() * 0.3 + 0.3
		"defend":
			if recovery_timer > 0 or block_timer > 0:
				return
			if not in_danger and (not opponent_attacking or distance > 50.0):
				if opponent_recovery_time < 0.1 and can_attack and distance < 45.0 and randf() > 0.3:  # 新增：嚴格距離檢查
					current_state = "attack"
					print("Debug: Poke attack after defend for AI")
				elif opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance:  # 修正：防禦後跳攻，縮小範圍並綁定can_attack
					current_state = "attack"
					state_timer = 0.5
					print("Debug: Jump attack after defend for AI")
				elif distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance:  # 新：防禦後主動跳攻
					current_state = "attack"
					state_timer = 0.5
					print("Debug: Proactive jump attack after defend for AI")
				else:
					current_state = "approach" if distance > 40.0 else "idle"
					state_timer = randf() * 0.3 + 0.3
			elif opponent_stun_remaining > 0.1 and randf() > 0.1:  # 增加反擊機率
				current_state = "attack"
				print("Debug: Counterattack after stun for AI")
			elif state_timer <= 0:
				current_state = "approach" if distance > 40.0 else "idle"
				state_timer = randf() * 0.3 + 0.3
		"jump":
			if state_timer <= 0 or opponent.is_jumping:
				current_state = "approach"
				state_timer = randf() * 0.3 + 0.3
			elif in_danger or (opponent_attacking and distance < 50.0):
				current_state = "defend"
				block_timer = 0.5
				state_timer = 0.5
				print("Debug: Defend triggered from jump")
			elif is_cornered and randf() > 0.4:  # 增加逃角延長
				state_timer = 0.4
	
	last_action_time += delta
	if parent:
		if OS.is_debug_build():
			print("Debug: AI state for %s: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s, opponent_jumping=%s, distance=%.1f" % [parent.name, current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered, opponent_jumping, distance])
	else:
		if OS.is_debug_build():
			print("Debug: AI state for unknown: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s, opponent_jumping=%s, distance=%.1f" % [current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered, opponent_jumping, distance])

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
	var opponent_jumping = opponent.is_jumping
	
	# 被擊中或擊飛時強制後退並嘗試格擋（縮短持續）
	if parent.is_hit or parent.is_knockfly or block_timer > 0:
		input_dir = -1 if parent.global_position.x < opponent.global_position.x else 1
		if crouch_timer > 0:
			crouch_pressed = is_crouching
		else:
			crouch_pressed = (opponent.is_crouching and opponent_attacking and randf() > 0.8) or (parent.is_hit and randf() > 0.8)  # 增加蹲擋機率
			if crouch_pressed:
				crouch_timer = 0.2  # 縮短從0.3到0.2
				is_crouching = true
				print("Debug: AI crouch block triggered for %s" % parent.name)
			else:
				is_crouching = false
				print("Debug: AI standing block triggered for %s" % parent.name)
		return build_input_dict(input_dir, crouch_pressed, false, false, "none", 0.2, 0.0, false, false)
	
	# 移動邏輯（縮減遲滯範圍為35-40像素，更緊湊；減少後退）
	if distance > 100.0:
		input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
	elif distance > 40.0:
		input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
	elif distance < 35.0:
		if can_attack:
			input_dir = 0  # 近距離靜止攻擊，避免後退
		else:
			input_dir = -1 if parent.global_position.x < opponent.global_position.x else 1
	else:
		input_dir = 0  # 35-40像素間靜止
	
	# 只在真正危險時後退（新：in_danger且距離<30）
	if in_danger and distance < 30.0:
		input_dir = -1 if parent.global_position.x < opponent.global_position.x else 1
	
	# 穩定輸入方向
	if input_dir_timer <= 0:
		last_input_dir = input_dir
		input_dir_timer = 0.5  # 縮短從0.7到0.5，更靈活轉向
	
	if current_state == "defend" or (in_danger and opponent_attacking):
		input_dir = -last_input_dir if distance < 30.0 else 0  # 只近距離後退
		if in_danger or opponent_attacking or block_timer > 0:
			if crouch_timer > 0:
				crouch_pressed = is_crouching
			else:
				crouch_pressed = (opponent.is_crouching and opponent_attacking and randf() > 0.8) or (parent.is_hit and randf() > 0.8)
				if crouch_pressed:
					crouch_timer = 0.2
					is_crouching = true
					print("Debug: AI crouch block triggered for %s" % parent.name)
				else:
					is_crouching = false
					print("Debug: AI standing block triggered for %s" % parent.name)
			if is_cornered and randf() > 0.5:  # 增加逃角機率
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Corner escape jump in defend for AI")
		else:
			if randf() > 0.98:  # 減少中立暫停機率
				input_dir = 0
				print("Debug: Neutral pause for AI")
			elif randf() > 0.98 and distance > 50.0:
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Neutral jump for AI")
	elif current_state == "approach":
		# 強化：如果距離>45，強制前進調整位置
		if distance > 45.0:
			input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
			print("Debug: Forcing approach movement due to far distance for AI")
		if time_since_last > 0.3 and dash_cooldown <= 0:  # 縮短從0.4到0.3
			if distance > 100.0 and not is_cornered and randf() > 0.7:  # 增加dash機率
				dash_pressed = true
				dash_cooldown = 1.0  # 縮短冷卻從1.2到1.0
				print("Debug: Dash triggered for AI approach")
			elif randf() > 0.98 and distance > 50.0:
				input_dir = -last_input_dir
				input_dir_timer = 0.5
				print("Debug: Neutral backstep for AI")
			elif opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance:  # 修正：approach時主動跳攻，綁定can_attack
				jump_pressed = true
				attack_pressed = true  # 同時攻擊，觸發跳攻擊
				damage = 10.0
				attack_type = "attack"
				print("Debug: Jump attack in approach for AI")
			elif distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance:  # 新：approach中主動跳攻
				jump_pressed = true
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				print("Debug: Proactive jump attack in approach for AI")
			# 新增：approach 中隨機觸發招式（中遠距離 >50，機率 30%）
			elif distance > 50.0 and opponent_stun_remaining > 0.0 and randf() < 0.3:
				spm1_pressed = true
				damage = 20.0
				attack_pressed = false
				attack_type = "none"
				print("Debug: Special move in approach for AI (mid-range)")
		if is_cornered:
			input_dir = -last_input_dir
			if randf() > 0.5:  # 增加逃角機率
				jump_pressed = true
				crouch_pressed = false
				crouch_timer = 0.0
				is_crouching = false
				print("Debug: Approach corner escape for AI")
	elif current_state == "attack":
		if distance < 50.0 and time_since_last > 0.4 and distance < 45.0:  # 新增：嚴格距離檢查才觸發攻擊
			# 優化：新增動作選擇邏輯，增加多元性（40%普通、30%跳攻、20%招式、10%其他）
			var action_roll = randf()
			# 修正：放寬招式觸發，不限近距離；提高機率到 40%（action_roll < 0.4），並在對手硬直或隨機時觸發
			if (opponent_stun_remaining > 0.05 or randf() < 0.3) and action_roll < 0.4:
				spm1_pressed = true
				damage = 20.0
				attack_pressed = false
				attack_type = "none"
				print("Debug: Random special poke triggered for AI")
			elif opponent_recovery_time < 0.1 and action_roll < 0.4:
				spm1_pressed = true
				damage = 20.0
				attack_pressed = false
				attack_type = "none"
				print("Debug: Punish special move triggered for AI")
			elif opponent_jumping and distance < 50.0 and can_attack and action_roll < 0.5:
				jump_pressed = true
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				print("Debug: Jump attack in attack state for AI")
			elif distance > 40.0 and distance < 50.0 and action_roll < 0.5:
				jump_pressed = true
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				print("Debug: Proactive jump attack in attack state for AI")
			else:  # 默認普通攻
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				spm1_pressed = false
				print("Debug: Normal attack in attack state for AI")
			state_timer = 0.4  # 縮短攻擊持續
		else:
			if distance > 45.0:  # 新增：距離太遠時不攻擊
				print("Debug: Distance too far for attack, holding back for AI")
			if randf() > 0.98 and distance > 50.0:  # 減少暫停
				input_dir = 0
				print("Debug: Neutral pause after attack for AI")
			# 新增：attack 中遠距離隨機招式（>50，機率 20%）
			elif distance > 50.0 and randf() < 0.2:
				spm1_pressed = true
				damage = 20.0
				attack_pressed = false
				attack_type = "none"
				print("Debug: Special move in attack for AI (long-range)")
	elif current_state == "jump":
		jump_pressed = true
		crouch_pressed = false
		crouch_timer = 0.0
		is_crouching = false
		input_dir = last_input_dir * (-1 if is_cornered else 1)
		if opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance:  # 修正：跳躍中轉跳攻，綁定can_attack
			attack_pressed = true
			damage = 10.0
			attack_type = "attack"
			print("Debug: Jump attack during jump for AI")
		print("Debug: Jump input for corner escape")
	
	# 低血量更積極進攻
	if parent_health < 50.0:
		if randf() > 0.3:  # 增加從0.4到0.3，更積極
			attack_pressed = true if can_attack and distance < 45.0 else false  # 新增：嚴格距離檢查
			spm1_pressed = true if distance > 30 and randf() > 0.4 else false
	
	# 跟跳攻擊（修正：縮小範圍到<50，並綁定can_attack，避免無限觸發）
	if opponent_jumping and distance < 50.0 and can_attack and randf() > 0.4:  # 提高門檻到0.4（60%機率），並綁定can_attack
		jump_pressed = true
		attack_pressed = true  # 觸發跳攻擊
		damage = 10.0
		attack_type = "attack"
		crouch_pressed = false
		crouch_timer = 0.0
		is_crouching = false
		print("Debug: Follow-up jump attack for AI")
	
	if parent:
		if OS.is_debug_build():
			print("Debug: AI input for %s: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, dash=%s, cornered=%s, opponent_jumping=%s, distance=%.1f" % [parent.name, current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed, dash_pressed, is_cornered, opponent_jumping, distance])
	else:
		if OS.is_debug_build():
			print("Debug: AI input for unknown: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, dash=%s, cornered=%s, opponent_jumping=%s, distance=%.1f" % [current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed, dash_pressed, is_cornered, opponent_jumping, distance])
	
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
