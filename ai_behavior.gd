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
	
	# 狀態轉換邏輯（優化：增加進攻頻率，新增 jump 狀態）
	match current_state:
		"idle":
			if last_action_time > 0.3:  # 新增：簡短延遲避免快速循環
				if can_attack and randf() > 0.2:  # 80% 機率直接攻擊
					current_state = "attack"
					print("Debug: Aggressive attack triggered for AI")
				elif in_danger or opponent_attacking:
					current_state = "defend"
				elif is_cornered and distance < 80.0 and randf() > 0.3:  # 角落跳脫
					current_state = "jump"
					state_timer = 0.5  # 跳躍持續時間
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach"
					state_timer = randf() * 0.4 + 0.2  # 縮短停頓，0.2-0.6秒
		"approach":
			if last_action_time > 0.3:  # 新增：簡短延遲避免快速循環
				if can_attack and randf() > 0.2:  # 80% 機率進攻
					current_state = "attack"
					print("Debug: Aggressive attack from approach for AI")
				elif opponent_recovery_time < 0.2 and distance < 100.0 and randf() > 0.5:  # 對手剛結束攻擊，50% 機率 punish
					current_state = "attack"
					print("Debug: Punish attack triggered for AI")
				elif in_danger or opponent_attacking:
					current_state = "defend"
				elif is_cornered and distance < 80.0 and randf() > 0.3:  # 角落跳脫
					current_state = "jump"
					state_timer = 0.5
					print("Debug: Corner jump escape triggered for AI")
				elif state_timer <= 0:
					current_state = "approach" if randf() > 0.5 else "idle"  # 50% 保持追擊
					state_timer = randf() * 0.4 + 0.2
		"attack":
			if in_danger or opponent_attacking:
				current_state = "defend"
			elif state_timer <= 0:
				current_state = "approach"
				state_timer = 0.3  # 攻後快速接近（考慮 attack_time=0.4s）
		"defend":
			if not (in_danger or opponent_attacking) and distance > 100.0:
				current_state = "approach" if not is_low_health else "idle"
			elif opponent_stun_remaining > 0.1 and randf() > 0.2:  # 對手硬直初期，80% 反擊
				current_state = "attack"
				print("Debug: Counterattack after stun for AI")
			elif state_timer <= 0:
				current_state = "attack" if can_attack and randf() > 0.2 else "idle"
				state_timer = randf() * 0.2 + 0.1  # 防後反擊延遲（考慮 blockstun=0.267s）
		"jump":
			if state_timer <= 0 or opponent.is_jumping:  # 跳完或對手跳，回到接近
				current_state = "approach"
				state_timer = randf() * 0.4 + 0.2
			elif in_danger or opponent_attacking:
				current_state = "defend"
	
	last_action_time += delta
	if parent:
		if OS.is_debug_build():  # 僅在除錯模式下輸出，減少 overflow
			print("Debug: AI state for %s: %s, can_attack=%s, in_danger=%s, opponent_stun=%s" % [parent.name, current_state, can_attack, in_danger, opponent_stun_remaining])
	else:
		if OS.is_debug_build():
			print("Debug: AI state for unknown: %s, can_attack=%s, in_danger=%s, opponent_stun=%s" % [current_state, can_attack, in_danger, opponent_stun_remaining])

func get_ai_input() -> Dictionary:
	if not ai_enabled:
		return {}
	
	var input_dir = 0
	var crouch_pressed = false  # 預設不蹲
	var jump_pressed = false
	var attack_pressed = false
	var spm1_pressed = false
	var attack_type = "none"
	var blockstun_duration = 0.2
	var damage = 0.0
	
	var opponent = get_opponent()
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
	
	# 移動邏輯
	if parent.global_position.x < opponent.global_position.x:
		input_dir = 1
	else:
		input_dir = -1
	
	# 輸入邏輯（優化：穩定攻擊輸出）
	if current_state == "defend" or (in_danger and opponent_attacking):
		input_dir *= -1  # 後退
		if in_danger and randf() > 0.7:  # 降低蹲機率（30% 有效）
			crouch_pressed = true
		else:
			crouch_pressed = false
	elif current_state == "approach":
		if time_since_last > 0.1:  # 更快接近
			input_dir = abs(input_dir)
	elif current_state == "attack":
		if can_attack and time_since_last > 0.6:  # 新增：冷卻避免連續攻擊
			attack_pressed = true
			damage = 10.0
			attack_type = "attack"
			state_timer = 0.4
			# 擴大特殊招條件：硬直>0.15s 或 blocking + 近距 <50, 70%機率
			if (opponent_stun_remaining > 0.15 or (opponent_blocking and distance < 50)) and randf() > 0.3:  # 70%機率
				spm1_pressed = true
				damage = 20.0
				if OS.is_debug_build():
					print("Debug: Enhanced combo special attack triggered for AI")
			# punish時優先特殊招
			elif opponent_recovery_time < 0.2 and distance < 50 and randf() > 0.4:  # 60%機率
				spm1_pressed = true
				damage = 20.0
				if OS.is_debug_build():
					print("Debug: Punish special attack triggered for AI")
		else:
			input_dir = abs(input_dir)  # 追上再砍
	elif current_state == "jump":
		jump_pressed = true
		crouch_pressed = false
		input_dir = abs(input_dir)  # 前跳朝對手反方向
		if OS.is_debug_build():
			print("Debug: Jump input for corner escape")
	
	# 低血量仍進攻
	if parent.healthbar and parent.healthbar.current_health < 50.0:
		if randf() > 0.5:  # 50% 機率禁用攻擊（原 80%）
			attack_pressed = false
			spm1_pressed = false
	
	# 跟跳
	if opponent.is_jumping and is_opponent_close(opponent) and randf() > 0.7:
		jump_pressed = true
		crouch_pressed = false
	
	if parent:
		if OS.is_debug_build():
			print("Debug: AI input for %s: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s" % [parent.name, current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed])
	else:
		if OS.is_debug_build():
			print("Debug: AI input for unknown: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s" % [current_state, input_dir, attack_pressed, crouch_pressed, jump_pressed])
	
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
