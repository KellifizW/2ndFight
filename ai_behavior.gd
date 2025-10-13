class_name AIBehavior extends Node

@export var reaction_delay: float = 0.4  # AI狀態切換延遲（秒），0.4-0.6以穩定狀態
@export var attack_decision_delay: float = 0.3  # 攻擊指令選擇延遲（秒），0.3-0.5以減少指令閃爍
@export var defend_decision_delay: float = 0.3  # 防守指令選擇延遲（秒），0.3-0.5以減少蹲下切換

var ai_enabled: bool = false
var opponent: Node = null  # 對手引用
var decision_timer: float = 0.0  # 狀態決策計時器
var attack_decision_timer: float = 0.0  # 攻擊指令計時器
var defend_decision_timer: float = 0.0  # 防守指令計時器
var state_timer: float = 0.0 : set = _set_state_timer  # 兼容world.gd，指向decision_timer
var last_action_time: float = 0.0  # 占位符，兼容world.gd
var random_action_chance: float = 0.25  # 隨機動作機率，控制攻擊多樣性
var parent: Node  # 父節點（Player）
var opponent_search_timer: float = 0.0  # 對手查找重試計時器

# 簡單狀態機，讓AI行為更結構化
var current_state: String = "idle"  # 狀態：idle（初始）、approach（接近）、attack（攻擊）、defend（防守）
var previous_state: String = ""  # 用來偵測狀態改變，觸發除錯 print
var current_attack: String = "none"  # 當前選擇的攻擊類型，保持到下次更新
var current_crouch: bool = false  # 當前蹲下狀態，保持到下次更新

func _ready():
	parent = get_parent()
	if parent:
		print("AIBehavior ready for %s" % parent.name)
	else:
		print("Warning: AIBehavior parent not found")
	# 延遲查找對手，確保場景初始化完成
	opponent_search_timer = 0.1  # 等待0.1秒後首次查找

func _process(delta):
	# 如果尚未找到對手，持續嘗試
	if not opponent and opponent_search_timer > 0:
		opponent_search_timer -= delta
		if opponent_search_timer <= 0:
			find_opponent()
			opponent_search_timer = 0.5  # 每0.5秒重試一次，直到找到

func _set_state_timer(value: float):
	decision_timer = value  # state_timer 改變時同步更新 decision_timer

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	if ai_enabled:
		print("AI enabled for %s" % parent.name)
	else:
		print("AI disabled for %s" % parent.name)
		current_state = "idle"
		current_attack = "none"  # 重置攻擊選擇
		current_crouch = false  # 重置蹲下狀態

func find_opponent():
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player != parent:
			opponent = player
			print("AI opponent found: %s for %s" % [opponent.name, parent.name])
			return
	print("Warning: No opponent found for %s. Players in group: %s" % [parent.name, get_tree().get_nodes_in_group("players")])

func get_ai_input() -> Dictionary:
	# 如果AI未啟用或無對手，返回空輸入
	if not ai_enabled or not opponent:
		return {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"st_mp_pressed": false,
			"st_mk_pressed": false,
			"attack_type": "none",
			"blockstun_duration": 0.2,
			"damage": 0.0,
			"spm1_pressed": false,
			"spm2_pressed": false
		}
	
	# 計算距離和相對位置（移除 * facing_mult，讓方向絕對）
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var facing_mult = parent.get_facing_multiplier()  # 只用來除錯，不影響計算
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)  # 正=對手在右，負=對手在左
	
	# 決策邏輯：每隔reaction_delay秒重新決策狀態
	decision_timer -= get_process_delta_time()
	if decision_timer <= 0:
		decision_timer = reaction_delay + randf_range(0.0, 0.2)  # 隨機延遲範圍，0.4-0.6秒
		state_timer = decision_timer  # 同步更新 state_timer
		
		previous_state = current_state  # 記錄舊狀態
		
		# 更新狀態機：基於距離（>120遠: approach, >60中: 偶爾fireball else approach, <60近: defend or attack）
		if distance > 120:  # 遠距離：強制接近
			current_state = "approach"
			current_attack = "none"  # 重置攻擊
			current_crouch = false  # 重置蹲下
		elif distance > 60:  # 中距離：90%接近，10% fireball
			if randf() < 0.1:
				current_state = "attack"
			else:
				current_state = "approach"
				current_attack = "none"
				current_crouch = false
		else:  # 近距離：根據對手狀態選擇
			if opponent.is_attacking or opponent.is_special_moving:  # 對手攻擊：防守
				current_state = "defend"
				current_attack = "none"
			else:  # 對手無攻擊：攻擊
				current_state = "attack"
				current_crouch = false
		
		# 除錯：只在狀態改變時 print
		if current_state != previous_state:
			print("AI 狀態改變為: %s (距離: %.1f, facing_mult: %.1f, relative_dir: %d)" % [current_state, distance, facing_mult, relative_dir])
	
	# 根據當前狀態生成輸入
	var input_dir: int = 0
	var crouch_pressed: bool = false
	var jump_pressed: bool = false
	var st_mp_pressed: bool = false
	var st_mk_pressed: bool = false
	var spm1_pressed: bool = false
	var spm2_pressed: bool = false
	
	# 處理攻擊指令的頻率控制
	if current_state == "attack":
		attack_decision_timer -= get_process_delta_time()
		if attack_decision_timer <= 0:
			attack_decision_timer = attack_decision_delay + randf_range(0.0, 0.2)  # 0.3-0.5秒
			# 根據距離選擇攻擊（<40近: st_mp/st_mk拳腳, 否則spm1衝刺 or spm2火球）
			if distance < 40:  # 近距：拳腳攻擊
				if randf() < 0.5:
					current_attack = "st_mp"
				else:
					current_attack = "st_mk"
			else:  # 中近距：特殊招式
				if randf() < random_action_chance:
					match randi() % 3:
						0: current_attack = "st_mk"
						1: current_attack = "spm1"
						2: current_attack = "spm2"
				else:
					current_attack = "spm1"
			# 除錯：確認攻擊選擇
			print("Debug: %s in attack, selected: %s" % [parent.name, current_attack])
	
	# 處理防守指令的頻率控制
	if current_state == "defend":
		defend_decision_timer -= get_process_delta_time()
		if defend_decision_timer <= 0:
			defend_decision_timer = defend_decision_delay + randf_range(0.0, 0.2)  # 0.3-0.5秒
			current_crouch = randf() < 0.6  # 決定是否蹲下，並保持
			# 除錯：確認蹲下選擇
			print("Debug: %s in defend, crouch: %s" % [parent.name, "true" if current_crouch else "false"])
	
	# 根據當前狀態和選擇生成輸入
	match current_state:
		"approach":
			input_dir = int(relative_dir)  # 絕對方向：正=向右接近，負=向左接近
			if distance > 200 and randf() < 0.1:  # 超遠距低機率跳躍
				jump_pressed = true
			# 除錯：確認approach方向
			print("Debug: %s in approach, input_dir: %d, opponent at x: %.1f, self at x: %.1f" % [parent.name, input_dir, opponent.global_position.x, parent.global_position.x])
		"attack":
			match current_attack:
				"st_mp":
					st_mp_pressed = true
				"st_mk":
					st_mk_pressed = true
				"spm1":
					spm1_pressed = true
				"spm2":
					spm2_pressed = true
		"defend":
			input_dir = -int(relative_dir)  # 反轉方向：遠離對手
			crouch_pressed = current_crouch  # 使用當前蹲下狀態
		"idle":
			pass  # 無動作，僅初始狀態使用
	
	# 計算攻擊類型和傷害（參考PlayerController.gd）
	var attack_type = "st_mp" if st_mp_pressed else "st_mk" if st_mk_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var blockstun_duration = 0.4 if move_set and ((move_set.is_powerkk and parent.player_id == "p1") or (move_set.is_spnk and parent.player_id == "p2")) else 0.3 if move_set and move_set.is_fireball else 0.2
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball) else (10.0 if (st_mp_pressed or st_mk_pressed) else 0.0)
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"st_mp_pressed": st_mp_pressed,
		"st_mk_pressed": st_mk_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed
	}
