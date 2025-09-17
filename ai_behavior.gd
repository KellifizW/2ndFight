extends Node

@onready var parent: Node = get_parent()  # 抓Player父節點
var ai_enabled: bool = false  # AI開關（從CPUController傳來）
var current_state: String = "idle"  # AI狀態機 (idle, approach, attack, defend)
var state_timer: float = 0.0  # 狀態延遲計時器
var last_action_time: float = 0.0  # 上次動作時間（避連續）

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
	
	var can_attack = is_in_attack_range(parent, opponent)  # AI是否可攻擊
	var in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)  # 對手Hitbox是否威脅
	var opponent_attacking = opponent.is_attacking or opponent.is_dashing
	var opponent_blocking = opponent.is_blocking or opponent.is_hit
	var parent_health = parent.healthbar.current_health if parent.healthbar else 100.0
	var is_low_health = parent_health < 50.0
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	
	# 狀態轉換邏輯（提高defend頻率）
	match current_state:
		"idle":
			if can_attack and randf() > 0.6:  # 降低攻擊機率，優先防禦
				current_state = "attack"
			elif in_danger or opponent_attacking or (distance < 100.0 and randf() > 0.5):  # 新增：近距離提前防禦
				current_state = "defend"
			elif state_timer <= 0:
				current_state = "approach"
				state_timer = randf() * 0.5 + 0.2  # 隨機停頓0.2-0.7秒
		"approach":
			if can_attack and randf() > 0.6:
				current_state = "attack"
			elif in_danger or opponent_attacking or (distance < 100.0 and randf() > 0.5):  # 近距離防禦
				current_state = "defend"
			elif state_timer <= 0:
				current_state = "idle"
				state_timer = randf() * 0.5 + 0.2
		"attack":
			if in_danger or opponent_attacking:
				current_state = "defend"
			elif not can_attack or state_timer <= 0:
				current_state = "approach"
				state_timer = 0.4  # 攻後接近
		"defend":
			if not (in_danger or opponent_attacking) and distance > 100.0:
				current_state = "approach" if not is_low_health else "idle"
			elif state_timer <= 0:
				current_state = "attack" if can_attack and opponent_blocking else "idle"
				state_timer = randf() * 0.3 + 0.1  # 防後反擊延遲
	
	last_action_time += delta
	if parent:
		print("Debug: AI state for %s: %s, can_attack=%s, in_danger=%s" % [parent.name, current_state, can_attack, in_danger])
	else:
		print("Debug: AI state for unknown: %s, can_attack=%s, in_danger=%s" % [current_state, can_attack, in_danger])

func get_ai_input() -> Dictionary:
	if not ai_enabled:
		return {}
	
	var input_dir = 0
	var crouch_pressed = false
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
	
	# 移動邏輯
	if parent.global_position.x < opponent.global_position.x:
		input_dir = 1
	else:
		input_dir = -1
	
	if current_state == "defend" or (in_danger and opponent_attacking):
		input_dir *= -1  # 後退
		crouch_pressed = true  # 蹲block
		if is_opponent_close(opponent) and randf() > 0.7:  # 提高跳防機率（30%）
			jump_pressed = true
			crouch_pressed = false  # 跳時不蹲
	elif current_state == "approach":
		if time_since_last > 0.2:
			input_dir = abs(input_dir)
	elif current_state == "attack":
		if can_attack:
			attack_pressed = true
			damage = 10.0
			attack_type = "attack"
			state_timer = 0.4
			if opponent_blocking and randf() > 0.6:  # 破防用特殊招
				spm1_pressed = true
				damage = 20.0
		else:
			input_dir = abs(input_dir)  # 追上再砍
	
	# 低血保守
	if parent.healthbar and parent.healthbar.current_health < 50.0:
		if randf() > 0.8:  # 80%只防/走
			attack_pressed = false
			spm1_pressed = false
	
	# 跟跳
	if opponent.is_jumping and is_opponent_close(opponent) and randf() > 0.7:
		jump_pressed = true
		crouch_pressed = false
	
	if parent:
		print("Debug: AI input for %s: state=%s, dir=%s, attack=%s, defend=%s" % [parent.name, current_state, input_dir, attack_pressed, crouch_pressed])
	else:
		print("Debug: AI input for unknown: state=%s, dir=%s, attack=%s, defend=%s" % [current_state, input_dir, attack_pressed, crouch_pressed])
	
	return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed)

# 輔助函數：檢查是否在Hitbox攻擊範圍（重疊或距離<50）
func is_in_attack_range(attacker: Node, target: Node) -> bool:
	if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
		return false
	var hitbox = attacker.get_node("Hitbox") as Area2D
	var hurtbox = target.get_node("Hurtbox") as Area2D
	for area in hitbox.get_overlapping_areas():
		if area == hurtbox and area.get_parent() != attacker:
			return true
	var distance = abs(attacker.global_position.x - target.global_position.x)
	return distance < 50.0  # 模擬Hitbox外緣

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
	return distance < 30.0  # 縮小範圍，模擬Hitbox

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

# 輔助函數：抓對手cv
func get_opponent() -> Node:
	var all_players = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != parent:
			return p
	return null
