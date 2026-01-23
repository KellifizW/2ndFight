extends Label

# ============================================================
# HITBOX DEBUG DISPLAY
# ============================================================
# 實時顯示 Hitbox 檢測系統的狀態
# - 當前距離
# - 攻擊範圍
# - Hitbox/Hurtbox 尺寸
# - 碰撞檢測狀態
#
# 使用方法：
# 1. 在場景中添加一個 Label 節點
# 2. 附加此腳本
# 3. 在 Inspector 中配置選項
# 4. 運行遊戲即可看到實時數據

# ============================================================
# 配置選項
# ============================================================

@export var enabled: bool = true
@export var update_interval: float = 0.1  # 更新頻率（秒），避免影響性能
@export var show_distance: bool = true
@export var show_hitbox_info: bool = true
@export var show_collision_status: bool = true
@export var show_threat_level: bool = true

# ============================================================
# 內部變量
# ============================================================

var world: Node = null
var player_a: Player = null
var player_b: Player = null
var hitbox_cache: HitboxCache = null

var update_timer: float = 0.0

func _repeat_string(s: String, count: int) -> String:
	"""重複字符串 count 次"""
	var result = ""
	for i in range(count):
		result += s
	return result

func _ready() -> void:
	if not enabled:
		visible = false
		return
	
	# 延遲初始化，確保 world 和 HitboxCache 已準備好
	call_deferred("_initialize")

func _initialize() -> void:
	"""初始化調試顯示"""
	world = get_tree().get_first_node_in_group("world")
	
	if not world:
		push_warning("[HITBOX DEBUG] 警告：未找到 world 節點")
		return
	
	# 尋找 HitboxCache
	hitbox_cache = get_tree().get_first_node_in_group("hitbox_cache")
	
	if not hitbox_cache:
		push_warning("[HITBOX DEBUG] 警告：未找到 HitboxCache 節點")
		return
	
	# 獲取玩家
	_find_players()
	
	# 設置樣式
	add_theme_font_size_override("font_size", 12)
	
	print("[HITBOX DEBUG] 調試顯示已初始化")

func _find_players() -> void:
	"""尋找玩家節點"""
	var players = get_tree().get_nodes_in_group("players")
	
	if players.size() >= 2:
		player_a = players[0]
		player_b = players[1]
	elif players.size() == 1:
		player_a = players[0]

func _process(delta: float) -> void:
	if not enabled or not visible:
		return
	
	update_timer -= delta
	
	if update_timer <= 0.0:
		update_timer = update_interval
		_update_display()

func _update_display() -> void:
	"""更新顯示內容"""
	if not hitbox_cache or not player_a or not player_b:
		text = "[HITBOX DEBUG] 等待初始化..."
		return
	
	var display_text = "[HITBOX DEBUG]\n"
	display_text += _repeat_string("=", 40) + "\n"
	
	# 顯示距離
	if show_distance:
		var distance = abs(player_a.global_position.x - player_b.global_position.x)
		display_text += "📏 距離: %.1f px\n" % distance
	
	# 顯示 Hitbox 信息
	if show_hitbox_info:
		display_text += _get_hitbox_info()
	
	# 顯示碰撞狀態
	if show_collision_status:
		display_text += _get_collision_status()
	
	# 顯示威脅等級
	if show_threat_level:
		display_text += _get_threat_info()
	
	display_text += _repeat_string("=", 40)
	
	text = display_text

func _get_hitbox_info() -> String:
	"""獲取 Hitbox 信息"""
	var info = "\n📦 Hitbox 信息:\n"
	
	# Player A
	if player_a.is_attacking and "attack_type" in player_a:
		var attack_name = player_a.attack_type
		var hitbox = hitbox_cache.get_hitbox_data(player_a.character_id, attack_name)
		var attack_range = hitbox_cache.get_attack_range(player_a.character_id, attack_name)
		info += "  P1 攻擊: %s\n" % attack_name
		info += "    尺寸: %s\n" % hitbox.size
		info += "    範圍: %.1f px\n" % attack_range
	
	# Player B
	if player_b.is_attacking and "attack_type" in player_b:
		var attack_name = player_b.attack_type
		var hitbox = hitbox_cache.get_hitbox_data(player_b.character_id, attack_name)
		var attack_range = hitbox_cache.get_attack_range(player_b.character_id, attack_name)
		info += "  P2 攻擊: %s\n" % attack_name
		info += "    尺寸: %s\n" % hitbox.size
		info += "    範圍: %.1f px\n" % attack_range
	
	# Hurtbox 信息
	var p1_hurtbox = hitbox_cache.get_hurtbox_data(player_a.character_id)
	var p2_hurtbox = hitbox_cache.get_hurtbox_data(player_b.character_id)
	
	info += "  P1 Hurtbox: %s\n" % p1_hurtbox.size
	info += "  P2 Hurtbox: %s\n" % p2_hurtbox.size
	
	return info

func _get_collision_status() -> String:
	"""獲取碰撞檢測狀態"""
	var status = "\n🎯 碰撞檢測:\n"
	
	var has_collision = false
	
	# 檢查 Player A 的攻擊是否與 Player B 碰撞
	if player_a.is_attacking and "attack_type" in player_a:
		var attack_name = player_a.attack_type
		var facing = player_a.get("facing_direction") if "facing_direction" in player_a else 1.0
		var collision = hitbox_cache.check_hitbox_collision(
			player_a.global_position,
			player_a.character_id,
			attack_name,
			player_b.global_position,
			player_b.character_id,
			facing
		)
		
		if collision:
			status += "  ⚠️ P1 攻擊 (%s) 與 P2 碰撞！\n" % attack_name
			has_collision = true
	
	# 檢查 Player B 的攻擊是否與 Player A 碰撞
	if player_b.is_attacking and "attack_type" in player_b:
		var attack_name = player_b.attack_type
		var facing = player_b.get("facing_direction") if "facing_direction" in player_b else 1.0
		var collision = hitbox_cache.check_hitbox_collision(
			player_b.global_position,
			player_b.character_id,
			attack_name,
			player_a.global_position,
			player_a.character_id,
			facing
		)
		
		if collision:
			status += "  ⚠️ P2 攻擊 (%s) 與 P1 碰撞！\n" % attack_name
			has_collision = true
	
	if not has_collision:
		status += "  ✅ 無碰撞\n"
	
	return status

func _get_threat_info() -> String:
	"""獲取威脅等級信息"""
	var info = "\n🚨 威脅評估:\n"
	
	# 獲取 AI 行為節點
	var ai_behavior = null
	if player_a.has_node("AIBehavior") and player_a.get_node("AIBehavior").ai_enabled:
		ai_behavior = player_a.get_node("AIBehavior")
	elif player_b.has_node("AIBehavior") and player_b.get_node("AIBehavior").ai_enabled:
		ai_behavior = player_b.get_node("AIBehavior")
	
	if ai_behavior and ai_behavior.threat_system:
		var ai_player = player_a if player_a.has_node("AIBehavior") else player_b
		var opponent = player_b if ai_player == player_a else player_a
		
		var threat = ai_behavior.threat_system.evaluate_threats(ai_player, opponent)
		
		var threat_level_str = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"][threat.level]
		info += "  等級: %s\n" % threat_level_str
		
		if threat.source != "":
			info += "  來源: %s\n" % threat.source
		
		if threat.frames_until_hit < 999:
			info += "  撞擊幀數: %d\n" % threat.frames_until_hit
		
		if threat.recommended_response != "":
			info += "  建議: %s\n" % threat.recommended_response
	else:
		info += "  (AI 未啟用)\n"
	
	return info

# ============================================================
# 公開接口
# ============================================================

func set_enabled(value: bool) -> void:
	"""啟用/禁用調試顯示"""
	enabled = value
	visible = value

func set_update_interval(interval: float) -> void:
	"""設置更新頻率"""
	update_interval = max(0.05, interval)  # 最快 0.05 秒（20 FPS）
