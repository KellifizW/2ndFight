extends Label

# ============================================================
# HITBOX DEBUG DISPLAY (SINGLE PLAYER)
# ============================================================
# 實時顯示單個玩家的 Hitbox 檢測系統狀態
# - 攻擊範圍
# - Hitbox/Hurtbox 尺寸
# - 碰撞檢測狀態
# - 威脅等級
#
# 使用方法：
# 1. 在場景中添加兩個 Label 節點（一個給 P1，一個給 P2）
# 2. 分別附加此腳本
# 3. 設置 target_player_seat 為 "player_a" 或 "player_b"
# 4. 在 Inspector 中配置其他選項
# 5. 運行遊戲即可看到實時數據

# ============================================================
# 配置選項
# ============================================================

## 選擇要追蹤的玩家座位
@export_enum("player_a", "player_b") var target_player_seat: String = "player_a"

## 啟用/禁用調試顯示
@export var enabled: bool = true

## 更新頻率（秒），避免影響性能
@export var update_interval: float = 0.1

## 顯示到對手的距離
@export var show_distance: bool = true

## 顯示 Hitbox 信息
@export var show_hitbox_info: bool = true

## 顯示碰撞檢測狀態
@export var show_collision_status: bool = true

## 顯示威脅等級（僅 AI 玩家）
@export var show_threat_level: bool = true

## 顯示 Proximitybox 狀態
@export var show_proximity_status: bool = true

## 始終顯示（即使不是AI模式也顯示）
@export var always_show: bool = true

# ============================================================
# 內部變量
## 啟用啟動日誌
@export var startup_logs: bool = false
# ============================================================

var world: Node = null
var target_player: Player = null  # 要追蹤的玩家
var opponent: Player = null  # 對手玩家
var hitbox_cache: HitboxCache = null

var update_timer: float = 0.0
var player_display_name: String = ""  # P1 或 P2

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
	
	Debug.log("[HITBOX DEBUG] 調試顯示已初始化")

func _find_players() -> void:
	if startup_logs:
		Debug.log("[HITBOX DEBUG] 調試顯示已初始化")
	var players = get_tree().get_nodes_in_group("players")
	
	if players.size() < 1:
		push_warning("[HITBOX DEBUG] 警告：未找到玩家節點")
		return
	
	# 根據 target_player_seat 設置目標玩家
	for player in players:
		if player.seat == target_player_seat:
			target_player = player
			player_display_name = "P1" if target_player_seat == "player_a" else "P2"
		else:
			opponent = player
	
	if not target_player:
		push_warning("[HITBOX DEBUG] 警告：未找到座位為 %s 的玩家" % target_player_seat)

func _process(delta: float) -> void:
	if not enabled or not visible:
		return
	
	update_timer -= delta
	
	if update_timer <= 0.0:
		update_timer = update_interval
		_update_display()

func _update_display() -> void:
	"""更新顯示內容"""
	if not hitbox_cache or not target_player:
		text = "[%s DEBUG] 等待初始化..." % player_display_name
		return
	
	var display_text = "[%s HITBOX]\n" % player_display_name
	display_text += _repeat_string("=", 30) + "\n"
	
	# 顯示距離（到對手）
	if show_distance and opponent:
		var distance = abs(target_player.global_position.x - opponent.global_position.x)
		display_text += "📏 距離: %.1f px\n" % distance
	
	# 顯示 Proximitybox 狀態（新增）
	if show_proximity_status:
		display_text += _get_proximity_status()
	
	# 顯示 Hitbox 信息
	if show_hitbox_info:
		display_text += _get_hitbox_info()
	
	# 顯示碰撞狀態
	if show_collision_status:
		display_text += _get_collision_status()
	
	# 顯示威脅等級（如果啟用always_show，即使非AI也顯示基本狀態）
	if show_threat_level:
		display_text += _get_threat_info()
	
	display_text += _repeat_string("=", 30)
	
	text = display_text

func _get_hitbox_info() -> String:
	"""獲取目標玩家的 Hitbox 信息"""
	var info = "\n📦 Hitbox:\n"
	
	# 目標玩家的攻擊信息
	if target_player.is_attacking and "attack_type" in target_player:
		var attack_name = target_player.attack_type
		var hitbox = hitbox_cache.get_hitbox_data(target_player.character_id, attack_name)
		var attack_range = hitbox_cache.get_attack_range(target_player.character_id, attack_name)
		info += "  🗡️ 攻擊: %s\n" % attack_name
		info += "    尺寸: %s\n" % hitbox.size
		info += "    範圍: %.1f px\n" % attack_range
	else:
		info += "  🗡️ 攻擊: 無\n"
	
	# Hurtbox 信息
	var hurtbox = hitbox_cache.get_hurtbox_data(target_player.character_id)
	info += "  🛡️ Hurtbox: %s\n" % hurtbox.size
	
	return info

func _get_collision_status() -> String:
	"""獲取碰撞檢測狀態"""
	if not opponent:
		return "\n🎯 碰撞: (無對手)\n"
	
	var status = "\n🎯 碰撞:\n"
	
	# 檢查目標玩家的攻擊是否命中對手
	if target_player.is_attacking and "attack_type" in target_player:
		var attack_name = target_player.attack_type
		var facing = target_player.get("facing_direction") if "facing_direction" in target_player else 1.0
		var collision = hitbox_cache.check_hitbox_collision(
			target_player.global_position,
			target_player.character_id,
			attack_name,
			opponent.global_position,
			opponent.character_id,
			facing
		)
		
		if collision:
			status += "  ⚠️ 命中對手！\n"
		else:
			status += "  ❌ 未命中\n"
	else:
		status += "  ➖ 未攻擊\n"
	
	return status

func _get_proximity_status() -> String:
	"""獲取 Proximitybox 狀態"""
	var status = "\n📍 Proximity:\n"
	
	if not opponent:
		return status + "  (無對手)\n"
	
	# 檢查 is_opponent_proximity 和 is_proximity_blocking
	var is_opp_prox = target_player.get("is_opponent_proximity") if "is_opponent_proximity" in target_player else false
	var is_prox_block = target_player.get("is_proximity_blocking") if "is_proximity_blocking" in target_player else false
	var is_holding_back = target_player.get("is_holding_back") if "is_holding_back" in target_player else false
	var facing = target_player.get("facing_direction") if "facing_direction" in target_player else 1.0
	
	status += "  對手在範圍: %s\n" % ("✅ 是" if is_opp_prox else "❌ 否")
	status += "  按後退鍵: %s\n" % ("✅ 是" if is_holding_back else "❌ 否")
	status += "  Prox Block: %s\n" % ("🛡️ 激活" if is_prox_block else "❌ 未激活")
	status += "  面向: %s\n" % ("→ 右" if facing > 0 else "← 左")
	
	# 檢查對手的 Proximitybox 是否有效
	if opponent.has_node("Proximitybox"):
		var prox_box = opponent.get_node("Proximitybox")
		var prox_shape = prox_box.get_node_or_null("ProxShape")
		if prox_shape and prox_shape.shape:
			var prox_disabled = prox_shape.disabled
			status += "  對手Prox啟用: %s\n" % ("✅ 是" if not prox_disabled else "❌ 否")
			if not prox_disabled:
				var shape_size = prox_shape.shape.size if prox_shape.shape is RectangleShape2D else Vector2.ZERO
				status += "    尺寸: %s\n" % shape_size
		else:
			status += "  對手Prox: ❌ 無Shape\n"
	else:
		status += "  對手Prox: ❌ 無節點\n"
	
	# 檢查 Hurtbox 碰撞層級設置
	if target_player.has_node("Hurtbox"):
		var hurtbox = target_player.get_node("Hurtbox")
		var collision_mask = hurtbox.collision_mask
		var can_detect_prox = (collision_mask & 64) != 0  # Layer 7 = 64
		status += "  Hurtbox可檢測Prox: %s (mask=%d)\n" % ["✅ 是" if can_detect_prox else "❌ 否", collision_mask]
	
	return status

func _get_threat_info() -> String:
	"""獲取威脅等級信息（僅適用於 AI 玩家）"""
	var info = "\n🚨 威脅:\n"
	
	if not opponent:
		return info + "  (無對手)\n"
	
	# 如果 always_show 啟用，即使非 AI 也顯示基本攻擊狀態
	if always_show and not target_player.has_node("AIBehavior"):
		if opponent.get("is_attacking") if "is_attacking" in opponent else false:
			info += "  對手攻擊: ✅ 是\n"
			if "attack_type" in opponent:
				info += "  攻擊類型: %s\n" % opponent.attack_type
		else:
			info += "  對手攻擊: ❌ 否\n"
		return info
	
	# 檢查目標玩家是否有 AI
	if not target_player.has_node("AIBehavior"):
		return info + "  (非 AI)\n"
	
	var ai_behavior = target_player.get_node("AIBehavior")
	
	if not ai_behavior.ai_enabled or not ai_behavior.threat_system:
		return info + "  (AI 未啟用)\n"
	
	var threat = ai_behavior.threat_system.evaluate_threats(target_player, opponent)
	
	var threat_level_str = ["NONE", "LOW", "MEDIUM", "HIGH", "CRITICAL"][threat.level]
	info += "  等級: %s\n" % threat_level_str
	
	if threat.source != "":
		info += "  來源: %s\n" % threat.source
	
	if threat.frames_until_hit < 999:
		info += "  幀數: %d\n" % threat.frames_until_hit
	
	if threat.recommended_response != "":
		info += "  建議: %s\n" % threat.recommended_response
	
	return info
