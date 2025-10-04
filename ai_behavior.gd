extends Node

enum AIState {
	IDLE,
	APPROACH,
	ATTACK,
	DEFEND,
	JUMP
}

@onready var parent: Node = get_parent()  # 抓Player父節點

# AI控制相關
var ai_enabled: bool = false  # AI開關（從CPUController傳來）
var current_state: AIState = AIState.IDLE  # AI狀態機

# 計時器
var state_timer := 0.0
var action_timer := 0.0
var block_timer := 0.0
var attack_timer := 0.0
var special_timer := 0.0
var is_crouching := false
var timers := {
	"input_dir": 0.0,   # 輸入方向穩定計時器
	"dash": 0.0,        # dash 冷卻計時器
	"recovery": 0.0,    # 被擊中後恢復計時器
	"block": 0.0,       # 格擋持續計時器
	"crouch": 0.0,      # 蹲下持續計時器
	"special": 0.0,     # 特殊招式冷卻計時器
	"attack": 0.0,      # 普通攻擊冷卻計時器
	"jump_attack": 0.0  # 跳攻冷卻計時器
}

# 技能冷卻時間設定
@export var normal_attack_cooldown: float = 1.8  # 普通攻擊冷卻時間
@export var special_attack_cooldown: float = 3.0  # 特殊招式冷卻時間
@export var jump_attack_cooldown: float = 2.0  # 跳攻冷卻時間

# 距離閾值
@export var attack_range: float = 45.0  # 攻擊範圍
@export var approach_range: float = 40.0  # 接近範圍
@export var danger_range: float = 30.0  # 危險範圍

# 輸入緩衝系統
var last_input: Dictionary = {}  # 上一次的輸入
var last_input_dir: Vector2 = Vector2.ZERO  # 上一次的輸入方向
var input_buffer_time: float = 0.1  # 輸入緩衝時間

# 狀態數據
var state_data: Dictionary = {}  # 用於存儲當前狀態的額外數據

# 戰鬥狀態變量
var in_danger := false
var can_attack := false
var is_cornered := false
var opponent_attacking := false
var distance := 0.0
var last_action_time := 0.0
var last_attack_time := 0.0
var last_jump_attack_time := 0.0
var last_special_move_time := 0.0
var input_dir := 0
var input_dir_timer := 0.0
var crouch_timer := 0.0
var recovery_timer := 0.0
var attack_choice := 0.0
var corner_pressure := 0.0

# 輸入相關變量
var crouch_pressed := false
var jump_pressed := false
var attack_pressed := false
var spm1_pressed := false
var dash_pressed := false
var attack_type := "none"
var blockstun_duration := 0.2
var damage := 0.0

func build_input_dict(dir: int, crouch: bool, jump: bool, attack: bool, atk_type: String, 
					blockstun: float, dmg: float, special: bool, dash: bool) -> Dictionary:
	return {
		"input_dir": dir,
		"crouch_pressed": crouch,
		"jump_pressed": jump,
		"attack_pressed": attack,
		"attack_type": atk_type,
		"blockstun_duration": blockstun,
		"damage": dmg,
		"spm1_pressed": special,
		"dash_pressed": dash
	}

func get_strategy() -> Dictionary:
	if not parent or not parent.healthbar:
		return {"aggressive": false, "defensive": false, "special": false, "cornered": false}
	
	var opponent = get_opponent()
	if not opponent or not opponent.healthbar:
		return {"aggressive": false, "defensive": false, "special": false, "cornered": false}
	
	var my_health = parent.healthbar.current_health / parent.healthbar.max_health
	var opp_health = opponent.healthbar.current_health / opponent.healthbar.max_health
	
	return {
		"aggressive": my_health < 0.5 and opp_health > 0.7,
		"defensive": my_health < opp_health,
		"special": my_health < 0.5 and opp_health > 0.7,
		"cornered": is_cornered
	}

func check_hitbox_interaction(attacker: Node, target: Node, is_range_check := false) -> bool:
	if not target:
		return false
	
	var distance_val: float = abs(attacker.global_position.x - target.global_position.x)
	if is_range_check:
		return distance_val < attack_range
		
	if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
		return false
		
	var hitbox := attacker.get_node("Hitbox") as Area2D
	var hurtbox := target.get_node("Hurtbox") as Area2D
	
	for area in hitbox.get_overlapping_areas():
		if area == hurtbox and area.get_parent() != attacker:
			return true
	return false

func is_opponent_vulnerable_in_air(opponent: Node) -> bool:
	if not opponent:
		return false
	return not opponent.is_on_floor() and opponent.fixed_velocity.y > 0 and not opponent.is_air_attacking

# 追蹤對手硬直（參考 fighter.gd 的 timer 值）
var opponent_recovery_time: float = 0.0  # 對手攻擊剩餘時間
var opponent_stun_remaining: float = 0.0  # 對手 stun/block 剩餘
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
		current_state = AIState.APPROACH if randf() > 0.2 else AIState.IDLE  # 80%機率初始為approach，更積極
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
	
	# 更新所有計時器
	update_timers(delta)  # 統一更新所有計時器
	update_ai_state(delta)

func update_ai_state(delta: float):
	var opponent = get_opponent()
	if not opponent:
		return

	# 更新狀態
	action_timer += delta
	state_timer -= delta
	if state_timer <= 0:
		choose_next_state(opponent)

	# 更新對手狀態
	distance = abs(parent.global_position.x - opponent.global_position.x)
	can_attack = check_hitbox_interaction(parent, opponent, true)
	in_danger = check_hitbox_interaction(opponent, parent, false)

	# 強制狀態轉換
	if parent.is_hit or parent.is_knockfly:
		current_state = AIState.DEFEND
		state_timer = 0.5
		return
	
	# 獲取戰略信息
	var strategy = get_strategy()
	
	# 被擊中或擊飛時強制進入防禦狀態
	if parent.is_hit or parent.is_knockfly:
		current_state = AIState.DEFEND
		set_timer("recovery", 0.5)
		set_timer("block", 0.5)
		set_timer("state", 0.5)
		state_data["forced_defense"] = true
		print("Debug: AI hit or knockfly, entering defend state for %s" % parent.name)
		return
	
	# 重置輸入變數
	input_dir = 0
	crouch_pressed = false
	jump_pressed = false
	attack_pressed = false
	spm1_pressed = false
	attack_type = "none"
	damage = 0.0

	# 狀態轉換邏輯
	match current_state:
		AIState.IDLE:
			if get_timer("action") > 0.6:  # 增加反應時間，讓AI更冷靜
				var action_choice = randf()  # 統一使用一個隨機值來決定行動
				
				# 優先處理防禦情況
				if in_danger or (opponent_attacking and distance < 50.0):
					current_state = AIState.DEFEND
					set_timer("block", 0.5)
					set_timer("state", 0.5)
				# 距離控制
				elif distance > 80.0 or (distance > 40.0 and action_choice < 0.7):
					current_state = AIState.APPROACH
					state_timer = 0.4
				# 攻擊判斷
				elif can_attack and distance < attack_range:
					if action_choice < 0.4:  # 40%普通攻擊
						current_state = AIState.ATTACK
						state_data["normal_attack"] = true
					elif action_choice < 0.5 and should_use_special_move(opponent, distance):  # 10%特殊攻擊
						current_state = AIState.ATTACK
						state_data["use_special"] = true
					elif action_choice < 0.6 and check_opponent_air_status(opponent):  # 10%空中攻擊
						current_state = AIState.JUMP
						state_data["air_punish"] = true
				# 其他情況
				elif is_cornered and strategy.corner_pressure > 0.7 and action_choice < 0.8:
					current_state = AIState.JUMP
					set_timer("state", 0.4)
					state_data["corner_escape"] = true
				elif state_timer <= 0:
					current_state = AIState.IDLE  # 保持觀望
					state_timer = randf() * 0.5 + 0.5  # 更長的觀望時間

		AIState.APPROACH:
			if last_action_time > 0.4:
				# 優先處理防禦情況
				if in_danger or (opponent_attacking and distance < danger_range):
					current_state = AIState.DEFEND
					block_timer = 0.5
					state_timer = 0.5
					print("Debug: Defend triggered from approach")
				# 如果在角落且有壓力，優先考慮跳躍
				elif is_cornered and strategy.corner_pressure > 0.7:
					current_state = AIState.JUMP
					state_timer = 0.4
					state_data["corner_escape"] = true
					print("Debug: Corner jump escape triggered for AI")
				# 直接執行攻擊，而不是只改變狀態
				elif can_attack and distance < attack_range and get_timer("attack") <= 0 and randf() < 0.6:
					current_state = AIState.ATTACK
					attack_pressed = true
					damage = 10.0
					attack_type = "attack"
					set_timer("attack", normal_attack_cooldown)
					print("Debug: Executing attack from approach")
				# 特殊攻擊檢查
				elif should_use_special_move(opponent, distance) and get_timer("special") <= 0:
					current_state = AIState.ATTACK
					spm1_pressed = true
					damage = 20.0
					set_timer("special", special_attack_cooldown)
					print("Debug: Executing special move from approach")
				elif get_timer("state") <= 0:
					if distance > approach_range:
						current_state = AIState.APPROACH
						set_timer("state", randf() * 0.3 + 0.3)
					else:
						current_state = AIState.IDLE
						set_timer("state", randf() * 0.4 + 0.2)  # 縮短觀察時間

		AIState.ATTACK:
			# 優先檢查防禦需求
			if in_danger or (opponent_attacking and distance < danger_range):
				current_state = AIState.DEFEND
				block_timer = 0.5
				state_timer = 0.5
				print("Debug: Defend triggered from attack")
				return
			
			# 檢查距離是否合適
			if distance > attack_range:
				current_state = AIState.APPROACH
				state_timer = randf() * 0.3 + 0.3
				print("Debug: Distance too far in attack, switching to approach for AI")
				return
			
			# 檢查是否可以繼續連擊
			if opponent_stun_remaining > 0.15 and distance < 40.0 and last_attack_time <= 0 and randf() > 0.3:
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				last_attack_time = normal_attack_cooldown
				state_timer = 0.3
				state_data["continue_combo"] = true
				print("Debug: Executing combo attack")
				return
			elif check_opponent_air_status(opponent) and randf() < 0.4:  # 固定40%的跳攻機率
				state_timer = 0.5
				state_data["air_punish"] = true
				print("Debug: Air punish in attack state for AI")
			# 如果沒有執行任何攻擊，或者state_timer結束，轉換到其他狀態
			elif state_timer <= 0 or (not attack_pressed and not spm1_pressed and not jump_pressed):
				if distance > approach_range:
					current_state = AIState.APPROACH
					state_timer = randf() * 0.3 + 0.3
				else:
					current_state = AIState.IDLE
					state_timer = randf() * 0.5 + 0.3
				print("Debug: No attack executed, changing state to %s" % current_state)

		AIState.DEFEND:
			if recovery_timer > 0 or block_timer > 0:
				return
			if not in_danger and (not opponent_attacking or distance > danger_range):
				if should_use_special_move(opponent, distance):
					current_state = AIState.ATTACK
					state_data["use_special"] = true
					print("Debug: Special move after defend for AI")
				elif can_attack and distance < attack_range and randf() > 0.3:
					current_state = AIState.ATTACK
					print("Debug: Counter attack after defend for AI")
				else:
					current_state = AIState.APPROACH if distance > approach_range else AIState.IDLE
					state_timer = randf() * 0.3 + 0.3
			elif opponent_stun_remaining > 0.1 and randf() > 0.1:
				current_state = AIState.ATTACK
				state_data["counter_hit"] = true
				print("Debug: Counterattack after stun for AI")

		AIState.JUMP:
			if state_timer <= 0 or opponent.is_jumping:
				current_state = AIState.APPROACH
				state_timer = randf() * 0.3 + 0.3
			elif in_danger or (opponent_attacking and distance < danger_range):
				current_state = AIState.DEFEND
				block_timer = 0.5
				state_timer = 0.5
				print("Debug: Defend triggered from jump")
			elif is_cornered and strategy.corner_pressure > 0.7:
				state_timer = 0.4
				state_data["extend_escape"] = true
	
	set_timer("action", get_timer("action") + delta)
	if parent:
		if OS.is_debug_build():
			print("Debug: AI state for %s: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s, distance=%.1f" % [parent.name, current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered, distance])
	else:
		if OS.is_debug_build():
			print("Debug: AI state for unknown: %s, can_attack=%s, in_danger=%s, opponent_stun=%s, is_cornered=%s, distance=%.1f" % [current_state, can_attack, in_danger, opponent_stun_remaining, is_cornered, distance])

func get_ai_input() -> Dictionary:
	# 基本檢查
	if not ai_enabled or not parent or not parent.healthbar:
		return make_input()
	
	var opponent = get_opponent()
	if not opponent or parent.healthbar.current_health <= 0 or opponent.healthbar.current_health <= 0:
		return make_input()
	
	distance = abs(parent.global_position.x - opponent.global_position.x)
	var strat = get_strategy()
	var input = make_input()
	
	# 基本檢查
	if not opponent:
		input_dir = 1
		return build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, attack_type, blockstun_duration, damage, spm1_pressed, dash_pressed)
	
	# 更新狀態檢查
	opponent_attacking = opponent.is_attacking or opponent.is_dashing
	last_action_time = action_timer
	can_attack = check_hitbox_interaction(parent, opponent, true)
	in_danger = check_hitbox_interaction(opponent, parent)
		# 檢查對手空中狀態
	is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
	# 檢查對手跳躍和空中狀態只在需要時再檢查
	if state_data.get("air_punish", false):
		is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false

	# 更新對手狀態追踪
	if opponent:
		opponent_recovery_time = opponent.attack_timer
		opponent_stun_remaining = max(opponent.hit_timer, opponent.block_timer)
	else:
		opponent_recovery_time = 0.0
		opponent_stun_remaining = 0.0
	
	# 獲取健康狀態策略
	var strategy = get_strategy()
	
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
		last_input_dir = Vector2(input_dir, 0)  # 將 int 轉換為 Vector2
		input_dir_timer = 0.5  # 縮短從0.7到0.5，更靈活轉向
	
	# 檢查輸入緩衝
	var buffered_input = state_data.get("buffered_input", {})
	if not buffered_input.is_empty():
		var should_use_buffer = false
		
		# 根據場景決定是否使用緩衝輸入，並檢查冷卻時間
		if state_data.get("continue_combo", false) and buffered_input.get("attack_pressed", false) and last_attack_time <= 0:
			should_use_buffer = true
		elif state_data.get("air_punish", false) and buffered_input.get("jump_pressed", false) and last_jump_attack_time <= 0:
			should_use_buffer = true
		elif state_data.get("use_special", false) and buffered_input.get("spm1_pressed", false) and last_special_move_time <= 0:
			should_use_buffer = true
			
		if should_use_buffer:
			print("Debug: Using buffered input for AI")
			state_data.erase("buffered_input")  # 使用後清除緩存
			return buffered_input
	
	# 根據狀態生成輸入
	match current_state:
		AIState.DEFEND:
			input.input_dir = -1 if parent.global_position.x < opponent.global_position.x else 1
			if opponent.is_crouching:
				input.crouch_pressed = true
			elif strat.cornered and randf() > 0.7:
				input.jump_pressed = true
			
		AIState.APPROACH:
			input.input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
			if distance > 80.0 and action_timer > 0.3:
				input.dash_pressed = true
				action_timer = 0
				
				# 特殊情況處理
				if should_use_special_move(opponent, distance):
					spm1_pressed = true
					damage = 20.0
					print("Debug: Approach special move opportunity")
				elif check_opponent_air_status(opponent):
					jump_pressed = true
					attack_pressed = true
					damage = 10.0
					attack_type = "attack"
					print("Debug: Air punish from approach")
			
			# 角落處理
			if is_cornered and strategy.corner_pressure > 0.6:
				input_dir *= -1
				if randf() > 0.4:
					jump_pressed = true
		
		AIState.ATTACK:
			if not check_combat_status(parent, opponent, "range"):
				current_state = AIState.APPROACH
				state_timer = 0.4
				return make_input()
			
			if check_combat_status(opponent, parent, "air") and randf() > 0.4:
				return make_input(0, "jump_attack")
			elif attack_timer <= 0:
				attack_timer = normal_attack_cooldown
				return make_input(0, "attack")
			# 普通攻擊邏輯
			elif last_attack_time <= 0 and attack_choice < 0.6:  # 60%普通攻擊
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				last_attack_time = normal_attack_cooldown
				print("Debug: Executing normal attack")
			# 特殊攻擊邏輯
			elif last_special_move_time <= 0 and attack_choice < 0.8 and state_data.get("use_special", false):  # 20%特殊攻擊
				spm1_pressed = true
				damage = 20.0
				attack_type = "none"
				last_special_move_time = special_attack_cooldown
				print("Debug: Executing special attack")
			# 跳攻邏輯
			elif last_jump_attack_time <= 0 and attack_choice < 0.9:  # 10%跳攻
				jump_pressed = true
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
				last_jump_attack_time = jump_attack_cooldown
				print("Debug: Executing jump attack")
				
				# 追擊判定
				if opponent_stun_remaining > 0.15 and distance < 40.0:
					state_data["continue_combo"] = true
			
			# 攻擊時的位置調整
			if distance > approach_range:
				input_dir = 1 if parent.global_position.x < opponent.global_position.x else -1
		
		AIState.JUMP:
			jump_pressed = true
			input_dir = -1 if state_data.get("corner_escape", false) else 1
			
			# 空中攻擊判定
			if is_opponent_vulnerable_in_air(opponent) and randf() < 0.4:  # 固定40%的跳攻機率
				attack_pressed = true
				damage = 10.0
				attack_type = "attack"
	
	# 根據血量調整策略
	if strategy.aggressive:  # 更激進的攻擊策略
		if can_attack and distance < attack_range:
			attack_pressed = true
		elif distance > 30 and should_use_special_move(opponent, distance):
			spm1_pressed = true
	
	# 跟跳攻擊機會
	if check_opponent_air_status(opponent) and can_attack and randf() > 0.4:
		jump_pressed = true
		attack_pressed = true
		damage = 10.0
		attack_type = "attack"
		crouch_pressed = false
		crouch_timer = 0.0
		is_crouching = false
		print("Debug: Air punish opportunity taken")
	
	# 創建當前輸入
	var current_input = build_input_dict(input_dir, crouch_pressed, jump_pressed, attack_pressed, 
		attack_type, blockstun_duration, damage, spm1_pressed, dash_pressed)
	
	# 緩存重要輸入用於下一幀
	if attack_pressed or jump_pressed or spm1_pressed:
		state_data["buffered_input"] = current_input.duplicate()
		state_data["buffer_time"] = input_buffer_time
	elif state_data.get("buffer_time", 0.0) > 0:
		state_data["buffer_time"] -= get_physics_process_delta_time()
		if state_data["buffer_time"] <= 0:
			state_data.erase("buffered_input")
	
	# 除錯輸出
	if OS.is_debug_build():
		var debug_msg = "AI input for %s: state=%s, dir=%s, attack=%s, crouch=%s, jump=%s, dash=%s, corner=%.2f, buffer=%s" % [
			str(parent.name) if parent else "unknown",
			current_state,
			input_dir,
			attack_pressed,
			crouch_pressed,
			jump_pressed,
			dash_pressed,
			corner_pressure,
			"active" if state_data.has("buffered_input") else "none"
		]
		print(debug_msg)
	
	return current_input

# 輔助函數：戰鬥狀態檢查
func check_combat_status(attacker: Node, target: Node, check_type: String = "") -> bool:
	if not target:
		return false
	match check_type:
		"hitbox":
			if not attacker.has_node("Hitbox") or not target.has_node("Hurtbox"):
				return false
			var hitbox = attacker.get_node("Hitbox") as Area2D
			var hurtbox = target.get_node("Hurtbox") as Area2D
			for area in hitbox.get_overlapping_areas():
				if area == hurtbox and area.get_parent() != attacker:
					return true
			return false
		"range":
			return abs(attacker.global_position.x - target.global_position.x) < attack_range
		"air":
			return not target.is_on_floor() and not target.is_air_attacking and target.fixed_velocity.y > 0
		"landing":
			return target.is_landing and target.landing_lock_timer > 0
		_:
			return false

# 輔助函數：特殊招式相關
func can_use_special_move() -> bool:
	if not parent or not parent.move_set:
		return false
	return get_timer("special") <= 0 and not parent.is_special_moving

func should_use_special_move(opponent: Node, dist_to_target: float) -> bool:
	if not can_use_special_move() or last_special_move_time > 0:
		return false
		
	var strategy = get_strategy()
	
	# 檢查對手狀態
	var opponent_vulnerable = opponent.is_hit or opponent.is_knockfly or opponent.is_landing
	opponent_attacking = opponent.is_attacking or opponent.is_air_attacking
	
	# 進一步降低特殊招式使用頻率，統一行為邏輯
	return (
		(opponent_vulnerable and dist_to_target < 60.0 and randf() > 0.85) or  # 15%機率在對手受傷時使用
		(opponent_attacking and dist_to_target < 50.0 and strategy.aggressive) or  # 積極策略下使用
		(strategy.special and dist_to_target < 80.0 and randf() > 0.8) or  # 血量策略下20%機率使用
		(dist_to_target < attack_range and randf() > 0.95)  # 近距離只有5%機率使用特殊招式
	) and randf() > 0.7  # 額外30%的抑制機率

# 輔助函數：檢查對手空中狀態和著陸機會
func check_opponent_air_status(opponent: Node, check_landing: bool = false) -> bool:
	if not opponent:
		return false
	if check_landing:
		return opponent.is_landing and opponent.landing_lock_timer > 0
	return not opponent.is_on_floor() and not opponent.is_air_attacking and opponent.fixed_velocity.y > 0

# 輔助函數：輸入緩衝
func buffer_input(input: Dictionary) -> void:
	last_input = input
	state_data["input_buffered"] = true
	await get_tree().create_timer(input_buffer_time).timeout
	if last_input == input:
		last_input = {}
		state_data["input_buffered"] = false

# 根據情況選擇下一個狀態
func choose_next_state(opponent: Node) -> void:
	distance = abs(parent.global_position.x - opponent.global_position.x)
	var strat = get_strategy()
	
	if check_combat_status(opponent, parent, "hitbox"):
		current_state = AIState.DEFEND
		state_timer = 0.5
	elif distance > attack_range:
		current_state = AIState.APPROACH
		state_timer = 0.4
	elif check_combat_status(opponent, parent, "air"):
		current_state = AIState.ATTACK
		state_timer = 0.3
	elif strat.aggressive and attack_timer <= 0:
		current_state = AIState.ATTACK
		state_timer = 0.3
	else:
		current_state = AIState.IDLE
		state_timer = 0.5

# 輔助函數：計時器管理
func update_timers(delta: float) -> void:
	for key in timers.keys():
		timers[key] = max(0.0, timers[key] - delta)

func set_timer(timer_name: String, duration: float) -> void:
	if timer_name in timers:
		timers[timer_name] = duration

func get_timer(timer_name: String) -> float:
	return timers.get(timer_name, 0.0)

# 輔助函數：生成輸入
func make_input(dir := 0, action := "") -> Dictionary:
	var input = {
		"input_dir": dir,
		"crouch_pressed": false,
		"jump_pressed": false,
		"attack_pressed": false,
		"attack_type": "none",
		"blockstun_duration": 0.2,
		"damage": 0.0,
		"spm1_pressed": false,
		"dash_pressed": false
	}
	
	match action:
		"attack": input.attack_pressed = true
		"jump": input.jump_pressed = true
		"crouch": input.crouch_pressed = true
		"special": input.spm1_pressed = true
		"dash": input.dash_pressed = true
	
	return input

# 輔助函數：抓對手
func get_opponent() -> Node:
	var all_players = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p != parent:
			return p
	return null
