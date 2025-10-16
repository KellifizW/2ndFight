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

# 用於懲罰反擊的變數
var punish_timer: float = 0.0  # 計時器，等 blockstun 結束後反擊
var last_blockstun_duration: float = 0.0  # 記錄最近的 blockstun 時間
var punish_opportunity: bool = false  # 是否有懲罰機會
var punish_attack: String = "st_mk"  # 動態選擇的最佳反擊招式（初始為 P2 最快）

# 簡單狀態機，讓AI行為更結構化
var current_state: String = "idle"  # 狀態：idle（初始）、approach（接近）、attack（攻擊）、defend（防守）
var previous_state: String = ""  # 用來偵測狀態改變，觸發除錯 print
var current_attack: String = "none"  # 當前選擇的攻擊類型，保持到下次更新
var current_crouch: bool = false  # 當前蹲下狀態，保持到下次更新

# 更新：frame data 字典，分開 P1 和 P2（從新提供數據），新增 startup 以優化選擇
var frame_data: Dictionary = {
	"p1": {
		"st_mp": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.267},
		"st_mk": {"startup": 0.2, "recovery": 0.4003, "blockstun": 0.3},
		"jump_mp": {"startup": 0.1333, "recovery": 0.2, "blockstun": 0.267},
		"jump_mk": {"startup": 0.1, "recovery": 0.3, "blockstun": 0.267},
		"powerkk": {"startup": 0.3, "recovery": 0.5, "blockstun": 0.267},
		"fireball": {"startup": 0.3, "recovery": 0.4667, "blockstun": 0.267}
	},
	"p2": {
		"st_mp": {"startup": 0.2, "recovery": 0.3667, "blockstun": 0.267},
		"st_mk": {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.3},
		"jump_mp": {"startup": 0.1, "recovery": 0.2333, "blockstun": 0.267},
		"jump_mk": {"startup": 0.1, "recovery": 0.267, "blockstun": 0.267},
		"spnk": {"startup": 0.2, "recovery": 0.4667, "blockstun": 0.267},
		"fireball": {"startup": 0.3, "recovery": 0.3667, "blockstun": 0.267}
	}
}

func _ready():
	parent = get_parent()
	if parent:
		print("AIBehavior ready for %s" % parent.name)
		# 根據 player_id 設定初始最快反擊招式
		if parent.player_id == "p1":
			punish_attack = "st_mp"  # P1 startup 0.1s
		else:
			punish_attack = "st_mk"  # P2 startup 0.1s
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
	# 更新懲罰計時器
	if punish_timer > 0:
		punish_timer -= delta
		if punish_timer <= 0:
			punish_timer = 0.0
			punish_opportunity = true  # blockstun 結束，反擊機會

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
			# 連接對手的 hit_detected 信號
			if opponent.has_signal("hit_detected"):
				opponent.hit_detected.connect(_on_hit_detected)
			return
	print("Warning: No opponent found for %s. Players in group: %s" % [parent.name, get_tree().get_nodes_in_group("players")])

# 處理 hit_detected 信號，計算 advantage（僅當自身被阻擋時）
func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	if ai_enabled and opponent and is_blocked and target == parent.name:  # 確認自身被阻擋
		var opponent_attack = opponent.attack_type if "attack_type" in opponent else "st_mp"
		# 新增：檢查特殊招式狀態，因為特殊招式時 attack_type 為 "none"
		var move_set = opponent.get_node("MoveSet") if opponent.has_node("MoveSet") else null
		if move_set:
			if move_set.is_powerkk:
				opponent_attack = "powerkk"
			elif move_set.is_spnk:
				opponent_attack = "spnk"
			elif move_set.is_fireball:
				opponent_attack = "fireball"
		var opponent_id = opponent.player_id if "player_id" in opponent else "p1"
		var data = frame_data.get(opponent_id, frame_data["p1"]).get(opponent_attack, {"startup": 0.1, "recovery": 0.2667, "blockstun": 0.267})
		last_blockstun_duration = stun_duration  # 使用實際 stun_duration 作為 blockstun
		var advantage = data["recovery"] - last_blockstun_duration  # 防守方優勢
		print("Debug: Block detected on self from %s (%s), attack: %s, advantage: %.4f" % [opponent.name, opponent_id, opponent_attack, advantage])
		# 根據優勢選擇最佳懲罰招式（優先更高傷害，若優勢足夠）
		if advantage >= 0.3:
			punish_attack = "spm2"  # fireball (更高傷害，但 startup 0.3s)
		elif advantage >= 0.2:
			punish_attack = "spm1"  # spnk (特殊招，傷害更高，startup 0.2s)
		elif advantage >= 0.1:
			punish_attack = "st_mk" if parent.player_id == "p2" else "st_mp"  # 最快基本招
		else:
			punish_attack = "none"
		if punish_attack != "none":
			punish_timer = last_blockstun_duration
			punish_opportunity = false  # 確保在計時器結束前不觸發
		else:
			punish_opportunity = false  # 無機會，重置

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
	
	# 偵測自己或對手血量 <= 0，返回空輸入
	var self_healthbar = parent.healthbar if "healthbar" in parent else null
	var opponent_healthbar = opponent.healthbar if "healthbar" in opponent else null
	if (self_healthbar and self_healthbar.current_health <= 0) or (opponent_healthbar and opponent_healthbar.current_health <= 0):
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
	
	# 計算距離和相對位置
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	var facing_mult = parent.get_facing_multiplier()  # 只用來除錯
	var relative_dir = sign(opponent.global_position.x - parent.global_position.x)  # 正=對手在右，負=對手在左
	
	# 偵測是否接近或已到角落
	var is_near_corner: bool = (parent.global_position.x - parent.arena_left < 50) or (parent.arena_right - parent.global_position.x < 50)
	var is_at_corner: bool = (parent.global_position.x - parent.arena_left < 10) or (parent.arena_right - parent.global_position.x < 10)
	
	# 決策邏輯：每隔reaction_delay秒重新決策狀態
	decision_timer -= get_process_delta_time()
	if decision_timer <= 0:
		decision_timer = reaction_delay + randf_range(0.0, 0.2)  # 隨機延遲範圍，0.4-0.6秒
		state_timer = decision_timer  # 同步更新 state_timer
		
		previous_state = current_state  # 記錄舊狀態
		
		# 更新狀態機
		var fireball_chance: float = 0.1  # 預設中距離 fireball 機率
		if is_near_corner:
			fireball_chance = 0.3  # 接近角落，提高 fireball 機率
		if is_at_corner:
			current_state = "attack"  # 已到角落，強制攻擊
			current_crouch = false  # 避免蹲下防守
		else:
			if distance > 120:  # 遠距離：強制接近
				current_state = "approach"
				current_attack = "none"  # 重置攻擊
				current_crouch = false  # 重置蹲下
			elif distance > 60:  # 中距離：(1 - fireball_chance) 接近，fireball_chance fireball
				if randf() < fireball_chance:
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
			print("AI 狀態改變為: %s (距離: %.1f, facing_mult: %.1f, relative_dir: %d, near_corner: %s, at_corner: %s)" % [current_state, distance, facing_mult, relative_dir, is_near_corner, is_at_corner])
	
	# 根據當前狀態生成輸入
	var input_dir: int = 0
	var crouch_pressed: bool = false
	var jump_pressed: bool = false
	var st_mp_pressed: bool = false
	var st_mk_pressed: bool = false
	var spm1_pressed: bool = false
	var spm2_pressed: bool = false
	
	# 如果有懲罰機會，強制攻擊並選擇最佳招式
	if punish_opportunity:
		current_state = "attack"
		current_attack = punish_attack  # 動態選擇的最佳招式
		punish_opportunity = false  # 重置
		print("Debug: Punish opportunity triggered, attacking with %s" % current_attack)
	
	# 處理攻擊指令的頻率控制
	if current_state == "attack":
		attack_decision_timer -= get_process_delta_time()
		if attack_decision_timer <= 0:
			attack_decision_timer = attack_decision_delay + randf_range(0.0, 0.2)  # 0.3-0.5秒
			# 根據距離選擇攻擊（<40近: st_mp/st_mk拳腳, 否則spm1衝刺 or spm2火球）
			if is_at_corner:
				if randf() < 0.7:
					current_attack = "spm1"  # 優先衝刺攻擊
				else:
					current_attack = punish_attack  # 用最佳招式
			elif distance < 40:  # 近距：拳腳攻擊
				if randf() < 0.5:
					current_attack = punish_attack
				else:
					current_attack = "st_mp" if parent.player_id == "p2" else "st_mk"
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
			if is_near_corner:
				current_crouch = randf() < 0.3  # 接近角落，降低蹲下機率
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
	
	# 修改：在已到角落時，提高到80%機率跳躍逃脫（加強脫困）
	if is_at_corner and randf() < 0.8:
		jump_pressed = true
		input_dir = int(relative_dir)  # 跳向對手方向，試圖逃脫
		st_mp_pressed = false
		st_mk_pressed = false
		spm1_pressed = false
		spm2_pressed = false
		crouch_pressed = false
	
	# 新增：讓AI在跳躍時有50%機率進行空中攻擊（jump_mp或jump_mk）
	if jump_pressed and randf() < 0.5:
		if randf() < 0.5:
			st_mp_pressed = true  # 觸發 jump_mp
		else:
			st_mk_pressed = true  # 觸發 jump_mk
	
	# 計算攻擊類型和傷害
	var attack_type = "st_mp" if st_mp_pressed else "st_mk" if st_mk_pressed else "none"
	var move_set = parent.get_node("MoveSet") if parent.has_node("MoveSet") else null
	var blockstun_duration = frame_data[parent.player_id][current_attack]["blockstun"] if move_set and current_attack in frame_data[parent.player_id] else 0.2
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
