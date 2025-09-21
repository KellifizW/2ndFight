extends Node

@onready var parent: Node = get_parent()  # 抓Player父節點
var ai_enabled: bool = false  # AI開關（從CPUController傳來）
var current_state: String = "idle"  # AI狀態機 (idle, approach, attack, defend, jump)
var state_timer: float = 0.0  # 狀態延遲計時器
var last_action_time: float = 0.0  # 上次動作時間（避連續）

# 追蹤對手硬直（參考 fighter.gd 的 timer 值）
var opponent_recovery_time: float = 0.0  # 對手攻擊剩餘時間
var opponent_stun_remaining: float = 0.0  # 對手 stun/block 剩餘

func _ready():
	if not parent:
		print("Warning: No parent Player found for AIBehavior")
	if parent:
		print("Debug: AIBehavior ready for %s!" % parent.name)
	else:
		print("Debug: AIBehavior ready for unknown!")

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if enabled:
		current_state = "approach"  # 開啟時預設接近
	if parent:
		print("Debug: AI %s for %s" % ["enabled" if enabled else "disabled", parent.name])
	else:
		print("Debug: AI %s for unknown" % ["enabled" if enabled else "disabled"])

func _physics_process(delta):
	if not ai_enabled:
		return
	# Check if either the parent or opponent's health is zero or less
	var opponent = get_opponent()
	var parent_health = parent.healthbar.current_health if parent and parent.healthbar else 100.0
	var opponent_health = opponent.healthbar.current_health if opponent and opponent.healthbar else 100.0
	if parent_health <= 0.0 or opponent_health <= 0.0:
		return  # Stop all AI behavior if either character is defeated
	update_ai_state(delta)

func update_ai_state(delta: float):
	state_timer -= delta
	var opponent = get_opponent()
	if not opponent:
		return
	
	# 更新對手硬直時間（從 fighter.gd 讀取）
	opponent_recovery_time = opponent.attack_timer if opponent else 0.0
	opponent_stun_remaining = max(opponent.hit_timer, opponent.block_timer) if opponent else 0.0
	
	var can_attack = is_in_attack_range(parent, opponent)  # AI是否可攻擊
	var in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)  # 對手Hitbox是否威脅
	var opponent_attacking = opponent.is_attacking or opponent.is_dashing
	var opponent_blocking = opponent.is_blocking or opponent.is_hit
	var parent_health = parent.healthbar.current_health if parent.healthbar else 100.0
	var is_low_health = parent_health < 50.0
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	
	# 狀態轉換邏輯（優化：增加進攻頻率，新增 jump 狀態，並加強角落逃脫邏輯）
	match current_state:
		"idle":
			if last_action_time > 0.2:  # 縮短延遲，避免快速循環
				if can_attack and randf() > 0.1:  # 提高直接攻擊機率到90%
					current_state = "attack"
					print("Debug: Aggressive attack triggered for AI")
				elif in_danger or opponent_attacking:
					current_state = "defend"
				elif is_cornered and distance < 80.0 and randf() > 0.3:  # 角落跳脫機率從30%提高到70%（randf()>0.3）
					current_state = "jump"
					state_timer = 0.5  # 跳躍持續時間
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach"
					state_timer = randf() * 0.3 + 0.1  # 進一步縮短停頓，0.1-0.4秒，更主動
		"approach":
			if last_action_time > 0.2:  # 縮短延遲
				if can_attack and randf() > 0.1:  # 提高進攻機率到90%
					current_state = "attack"
					print("Debug: Aggressive attack from approach for AI")
				elif opponent_recovery_time < 0.2 and distance < 100.0 and randf() > 0.2:  # 對手剛結束攻擊，提高punish機率到80%
					current_state = "attack"
					print("Debug: Punish attack triggered for AI")
				elif in_danger or opponent_attacking:
					current_state = "defend"
				elif is_cornered and distance < 80.0 and randf() > 0.3:  # 加強角落跳脫，70%機率
					current_state = "jump"
					state_timer = 0.5
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach" if randf() > 0.3 else "idle"  # 提高保持追擊機率到70%
					state_timer = randf() * 0.3 + 0.1  # 更短延遲
		"attack":
			if in_danger or opponent_attacking:
				current_state = "defend"
			elif state_timer <= 0:
				current_state = "approach"
				state_timer = 0.2  # 攻後更快接近（考慮 attack_time=0.4s）
		"defend":
			if not (in_danger or opponent_attacking) and distance > 100.0:
				current_state = "approach" if not is_low_health else "idle"
			elif opponent_stun_remaining > 0.1 and randf() > 0.1:  # 對手硬直，提高反擊機率到90%
				current_state = "attack"
				print("Debug: Counterattack after stun for AI")
			elif state_timer <= 0:
				current_state = "attack" if can_attack and randf() > 0.1 else "idle"  # 防後反擊更快
				state_timer = randf() * 0.1 + 0.05  # 縮短延遲（考慮 blockstun=0.267s）
		"jump":
			if state_timer <= 0 or opponent.is_jumping:  # 跳完或對手跳，回到接近
				current_state = "approach"
				state_timer = randf() * 0.3 + 0.1  # 更快回應
			elif in_danger or opponent_attacking:
				current_state = "defend"
			elif is_cornered and randf() > 0.5:  # 角落連續跳脫，50%機率重跳
				state_timer = 0.5
	
	last_action_time += delta
	if parent:
		if OS.is_debug_build():  # 僅在除錯模式下輸出，減少 overflow
			print("Debug: AI state for %s: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s" % [parent.name, current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered])
	else:
		if OS.is_debug_build():
			print("Debug: AI state for unknown: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s" % [current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered])

func get_ai_input() -> Dictionary:
	if not ai_enabled:
		return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false)
	
	# Check if either the parent or opponent's health is zero or less
	var parent_health = parent.healthbar.current_health if parent and parent.healthbar else 100.0
	var opponent = get_opponent()
	var opponent_health = opponent.healthbar.current_health if opponent and opponent.healthbar else 100.0
	if parent_health <= 0.0 or opponent_health <= 0.0:
		return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false)  # Return neutral input if either character is defeated
	
	var input_dir = 0
	var crouch_pressed = false  # 預設不蹲
	var jump_pressed = false
	var attack_pressed = false
	var spm1_pressed = false
	var attack_type = "none"
	var blockstun_duration = 0.2
	var damage = 0.0
	
	if not opponent:
		input_dir = 1  # 沒對手走右
		return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed)
	
	var can_attack = is_in_attack_range(parent, opponent)
	var in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)
	var opponent_attacking = opponent.is_attacking or opponent.is_dashing
	var opponent_blocking = opponent.is_blocking or opponent.is_hit
	var time_since_last = last_action_time
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	var opponent_stun_remaining = max(opponent.hit_timer, opponent.block_timer) if opponent else 0.0
	var opponent_recovery_time = opponent.attack_timer if opponent else 0.0
	
	# 移動邏輯（優化：角落時強制後退或跳躍）
	if parent.global_position.x < opponent.global_position.x:
		input_dir = 1
	else:
		input_dir = -1
	
	# 輸入邏輯（優化：穩定攻擊輸出，加強角落逃脫與立回反擊）
	if current_state == "defend" or (in_danger and opponent_attacking):
		input_dir *= -1  # 後退
		if in_danger and randf() > 0.6:  # 降低蹲機率（40% 有效），優先後退
			crouch_pressed = true
		else:
			crouch_pressed = false
		if is_cornered and randf() > 0.7:  # 角落時70%機率跳脫
			jump_pressed = true
			print("Debug: Corner escape jump in defend for AI")
	elif current_state == "approach":
		if time_since_last > 0.05:  # 更快接近
			# 移除abs，讓input_dir保持朝向對手的方向（這是修bug關鍵）
			pass  # 直接用初始input_dir
		if is_cornered:  # 接近中偵測角落，轉後退
			input_dir *= -1
			if randf() > 0.5:
				jump_pressed = true
				print("Debug: Approach corner escape for AI")
	elif current_state == "attack":
		if can_attack and time_since_last > 0.5:  # 冷卻避免連續
			attack_pressed = true
			damage = 10.0
			attack_type = "attack"
			state_timer = 0.4
			# 擴大特殊招條件：硬直>0.15s 或 blocking + 近距 <50, 提高機率到80%
			if (opponent_stun_remaining > 0.15 or (opponent_blocking and distance < 50)) and randf() > 0.2:  # 80%機率
				spm1_pressed = true
				damage = 20.0
				if OS.is_debug_build():
					print("Debug: Enhanced combo special attack triggered for AI")
			# punish時優先特殊招，提高機率
			elif opponent_recovery_time < 0.2 and distance < 50 and randf() > 0.3:  # 70%機率
				spm1_pressed = true
				damage = 20.0
				if OS.is_debug_build():
					print("Debug: Punish special attack triggered for AI")
		else:
			# 移除abs，讓追擊朝向對手
			pass  # 直接用初始input_dir
	elif current_state == "jump":
		jump_pressed = true
		crouch_pressed = false
		input_dir = input_dir * (-1 if is_cornered else 1)  # 移除abs，角落時反向跳，其他時朝向對手
		if OS.is_debug_build():
			print("Debug: Jump input for corner escape")
	
	# 低血量更積極進攻（提高機率到70%）
	if parent_health < 50.0:
		if randf() > 0.3:  # 70% 機率進攻
			attack_pressed = true if can_attack else false
			spm1_pressed = true if distance < 50 and randf() > 0.4 else false
	
	# 跟跳（優化：如果對手跳且近，80%跟進）
	if opponent.is_jumping and is_opponent_close(opponent) and randf() > 0.2:
		jump_pressed = true
		crouch_pressed = false
	
	if parent:
		if OS.is_debug_build():
			print("Debug: AI input for %s: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, cornered=%s" % [parent.name, current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed, is_cornered])
	else:
		if OS.is_debug_build():
			print("Debug: AI input for unknown: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, cornered=%s" % [current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed, is_cornered])
	
	return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed)

# 輔助函數：檢查是否在Hitbox攻擊範圍（重疊或距離<40，調整為更近）
func is_in_attack_range(attacker: Node, target: Node) -> bool:
	if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
		return false
	var hitbox = attacker.get_node("Hitbox") as Area2D
	var hurtbox = target.get_node("Hurtbox") as Area2D
	for area in hitbox.get_overlapping_areas():
		if area == hurtbox and area.get_parent() != attacker:
			return true
	var distance = abs(attacker.global_position.x - target.global_position.x)
	return distance < 40.0  # 調整：縮短攻擊範圍從60到40

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

# 輔助函數：檢查對手是否「夠近」（距離<30像素）
func is_opponent_close(opponent: Node) -> bool:
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	return distance < 30.0

# 輔助函數：建輸入字典
func build_input_dict(input_dir: int, crouch: bool, jump: bool, attack: bool, a_type: String, bstun: float, dmg: float, spm1: bool) -> Dictionary:
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch,
		"jump_pressed": jump,
		"attack_pressed": attack,
		"attack_type": a_type,
		"blockstun_duration": bstun,
		"damage": dmg,
		"spm1_pressed": spm1
	}

# 輔助函數：抓對手
func get_opponent() -> Node:
	var all_players = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != parent:
			return p
	return null
