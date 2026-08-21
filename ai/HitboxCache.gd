class_name HitboxCache extends Node

# ============================================================
# HITBOX CACHE SYSTEM
# ============================================================
# 自動掃描所有角色的 Hitbox/Hurtbox 節點，讀取真實尺寸與位置
# 提供快速查詢接口供 AI 威脅評估系統使用
#
# 特色：
# - 零維護：自動掃描所有角色場景
# - 自動同步：編輯器修改 Hitbox → 遊戲重啟後自動讀取
# - 快速查詢：預先快取所有數據，避免實時查詢開銷
# - 詳細日誌：便於驗證和調試

# Hitbox 數據結構
class HitboxData:
	var size: Vector2 = Vector2.ZERO          # Hitbox 尺寸
	var position: Vector2 = Vector2.ZERO      # Hitbox 相對位置
	var offset: Vector2 = Vector2.ZERO        # 額外偏移（用於不同攻擊）
	var attack_name: String = ""              # 攻擊名稱（如 "st_mp"）
	var character_id: String = ""             # 角色 ID（如 "DAV", "DEN"）
	
	func _to_string() -> String:
		return "HitboxData(size=%s, pos=%s, offset=%s, attack=%s, char=%s)" % [
			size, position, offset, attack_name, character_id
		]

# Hurtbox 數據結構
class HurtboxData:
	var size: Vector2 = Vector2.ZERO          # Hurtbox 尺寸
	var position: Vector2 = Vector2.ZERO      # Hurtbox 相對位置
	var character_id: String = ""             # 角色 ID
	
	func _to_string() -> String:
		return "HurtboxData(size=%s, pos=%s, char=%s)" % [size, position, character_id]

# 快取數據
var hitbox_cache: Dictionary = {}  # Key: "character_id:attack_name" → HitboxData
var hurtbox_cache: Dictionary = {} # Key: "character_id" → HurtboxData

# 是否已初始化
var is_initialized: bool = false

# 調試模式
@export var debug_mode: bool = false

# ============================================================
# LAZY LOADING SYSTEM (Phase 2 Optimization)
# ============================================================
# 分幀載入 Hitbox 數據以避免初始化時的卡頓，提高性能
@export var enable_lazy_loading: bool = true

var lazy_loading_enabled: bool = false
var characters_to_cache: Array[String] = []
var cache_progress: int = 0
var players_to_scan: Array = []

func _ready() -> void:
	if debug_mode:
		Debug.log("\n[HITBOX CACHE] 開始初始化...")
	
	# 延遲初始化，確保場景已完全加載
	call_deferred("_initialize_cache")

func _initialize_cache() -> void:
	"""初始化快取系統：掃描所有角色場景"""
	var start_time = Time.get_ticks_msec()
	
	# 獲取所有玩家節點
	var players = get_tree().get_nodes_in_group("players")
	
	if players.is_empty():
		if debug_mode:
			Debug.log("[HITBOX CACHE] 警告：未找到玩家節點，將在玩家生成後重新初始化")
		return
	
	# ============================================================
	# 延迟加载或立即加载
	# ============================================================
	if enable_lazy_loading:
		# 準備延迟加载
		lazy_loading_enabled = true
		players_to_scan = players
		cache_progress = 0
		characters_to_cache.clear()
		
		# 收集所有角色 ID
		for player in players:
			var char_id = player.character_id if "character_id" in player else "UNKNOWN"
			if char_id not in characters_to_cache:
				characters_to_cache.append(char_id)
		
		if debug_mode:
			Debug.log("[HITBOX CACHE] 延迟加载已啟用，將分幀掃描 %d 個角色" % characters_to_cache.size())
		
		# 開始延迟加载
		call_deferred("_lazy_load_next_character")
	else:
		# 立即加載所有角色
		for player in players:
			_scan_player_hitboxes(player)
		
		is_initialized = true
		var elapsed = Time.get_ticks_msec() - start_time
		
		if debug_mode:
			Debug.log("[HITBOX CACHE] 初始化完成！耗時: %d ms" % elapsed)
			Debug.log("[HITBOX CACHE] 快取統計:")
			Debug.log("  📦 Hitbox 數據: %d 條" % hitbox_cache.size())
			Debug.log("  📦 Hurtbox 數據: %d 條" % hurtbox_cache.size())

func _lazy_load_next_character() -> void:
	"""逐幀加載每個角色的 Hitbox 數據，避免初始化卡頓"""
	if cache_progress >= players_to_scan.size():
		is_initialized = true
		lazy_loading_enabled = false
		
		if debug_mode:
			Debug.log("[HITBOX CACHE] 延迟加載完成！")
			Debug.log("[HITBOX CACHE] 快取統計:")
			Debug.log("  📦 Hitbox 數據: %d 條" % hitbox_cache.size())
			Debug.log("  📦 Hurtbox 數據: %d 條" % hurtbox_cache.size())
		
		return
	
	# 掃描當前玩家
	if cache_progress < players_to_scan.size():
		var player = players_to_scan[cache_progress]
		if is_instance_valid(player):
			_scan_player_hitboxes(player)
	
	cache_progress += 1
	
	# 排隊下一個角色的掃描
	call_deferred("_lazy_load_next_character")

func _scan_player_hitboxes(player: Node) -> void:
	"""掃描單個玩家的 Hitbox/Hurtbox 數據"""
	if not player or not player is Player:
		return
	
	var character_id = player.character_id if "character_id" in player else "UNKNOWN"
	
	if debug_mode:
		Debug.log("\n[HITBOX CACHE] 掃描角色: %s (ID: %s)" % [player.name, character_id])
	
	# 掃描 Hurtbox（角色本體碰撞箱）
	_scan_hurtbox(player, character_id)
	
	# 掃描 Hitbox（攻擊碰撞箱）
	_scan_hitboxes(player, character_id)

func _scan_hurtbox(player: Node, character_id: String) -> void:
	"""掃描 Hurtbox 數據"""
	var hurtbox_node = player.get_node_or_null("Hurtbox/HurtShape")
	
	if not hurtbox_node:
		if debug_mode:
			Debug.log("  ⚠️ 未找到 Hurtbox/HurtShape 節點")
		return
	
	var hurtbox_data = HurtboxData.new()
	hurtbox_data.character_id = character_id
	
	# 讀取 CollisionShape2D 的 shape
	if hurtbox_node is CollisionShape2D and hurtbox_node.shape:
		if hurtbox_node.shape is RectangleShape2D:
			hurtbox_data.size = hurtbox_node.shape.size * hurtbox_node.scale
			hurtbox_data.position = hurtbox_node.position
		else:
			if debug_mode:
				Debug.log("  ⚠️ Hurtbox shape 不是 RectangleShape2D: %s" % hurtbox_node.shape)
			return
	else:
		if debug_mode:
			Debug.log("  ⚠️ Hurtbox 沒有有效的 shape")
		return
	
	# 儲存到快取
	hurtbox_cache[character_id] = hurtbox_data
	
	if debug_mode:
		Debug.log("  ✅ Hurtbox: size=%s, pos=%s" % [hurtbox_data.size, hurtbox_data.position])

func _scan_throw_hitboxes(player: Node, character_id: String, animation_player: AnimationPlayer) -> void:
	"""【新增】掃描投擲框數據（ThrowBox）"""
	# 支援 throw_enter 動畫的 ThrowBox 掃描
	var throw_box = player.get_node_or_null("ThrowBox/ThrowHit")
	
	if not throw_box:
		if debug_mode:
			Debug.log("  ⚠️ 未找到 ThrowBox/ThrowHit 節點")
		return
	
	# 嘗試掃描 throw_enter 動畫
	var throw_enter_anim = animation_player.get_animation("throw_enter")
	if not throw_enter_anim:
		if debug_mode:
			Debug.log("  ⚠️ 未找到 throw_enter 動畫")
		return
	
	var track_count = throw_enter_anim.get_track_count()
	var throw_size: Vector2 = Vector2.ZERO
	var throw_position: Vector2 = Vector2.ZERO
	var found_throw_box = false
	
	# 查詢 throw_enter 動畫中的 ThrowBox 軌道
	for track_idx in range(track_count):
		var track_path = throw_enter_anim.track_get_path(track_idx)
		var path_string = str(track_path)
		
		# 查找 ThrowBox/ThrowHit:shape:size
		if "ThrowBox/ThrowHit" in path_string and "shape:size" in path_string:
			var key_count = throw_enter_anim.track_get_key_count(track_idx)
			if key_count > 0:
				for key_idx in range(key_count):
					var value = throw_enter_anim.track_get_key_value(track_idx, key_idx)
					if value != null and value is Vector2 and value != Vector2.ZERO:
						throw_size = value
						found_throw_box = true
						break
		
		# 查找 ThrowBox/ThrowHit:position
		if "ThrowBox/ThrowHit" in path_string and ":position" in path_string and "shape" not in path_string:
			var key_count = throw_enter_anim.track_get_key_count(track_idx)
			if key_count > 0:
				for key_idx in range(key_count):
					var value = throw_enter_anim.track_get_key_value(track_idx, key_idx)
					if value != null and value is Vector2:
						throw_position = value
						break
	
	# 如果動畫中找不到，嘗試直接讀取 CollisionShape2D
	if not found_throw_box and throw_box is CollisionShape2D and throw_box.shape:
		if throw_box.shape is RectangleShape2D:
			throw_size = throw_box.shape.size * throw_box.scale
			throw_position = throw_box.position
			found_throw_box = true
	
	if found_throw_box:
		var hitbox_data = HitboxData.new()
		hitbox_data.size = throw_size
		hitbox_data.position = throw_position
		hitbox_data.attack_name = "throw_enter"
		hitbox_data.character_id = character_id
		
		var cache_key = "%s:throw_enter" % character_id
		hitbox_cache[cache_key] = hitbox_data
		
		if debug_mode:
			Debug.log("  ✅ throw_enter: size=%s, pos=%s (throw_hit_range)" % [throw_size, throw_position])

func _scan_hitboxes(player: Node, character_id: String) -> void:
	"""掃描 Hitbox 數據（從 AnimationPlayer 讀取不同攻擊的 Hitbox）"""
	var animation_player = player.get_node_or_null("AnimationPlayer")
	
	if not animation_player:
		if debug_mode:
			Debug.log("  ⚠️ 未找到 AnimationPlayer 節點")
		return
	
	# 獲取所有動畫名稱
	var animations = animation_player.get_animation_list()
	var hitbox_node = player.get_node_or_null("Hitbox/HitShape")
	
	if not hitbox_node:
		if debug_mode:
			Debug.log("  ⚠️ 未找到 Hitbox/HitShape 節點")
		return
	
	# 掃描常見攻擊動畫
	var attack_animations = ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk", "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk", "jump_mp", "jump_mk"]
	
	for attack_name in attack_animations:
		if attack_name in animations:
			_scan_attack_hitbox(player, character_id, attack_name, animation_player, hitbox_node)
	
	# 【新增】掃描投擲框（ThrowBox）
	_scan_throw_hitboxes(player, character_id, animation_player)
	
	if debug_mode:
		Debug.log("  📊 共掃描 %d 個攻擊動畫的 Hitbox 數據" % attack_animations.size())

func _scan_attack_hitbox(
	player: Node,
	character_id: String,
	attack_name: String,
	animation_player: AnimationPlayer,
	hitbox_node: CollisionShape2D
) -> void:
	"""掃描單個攻擊的 Hitbox 數據"""
	var animation = animation_player.get_animation(attack_name)
	
	if not animation:
		return
	
	# 查找 Hitbox shape 的軌道
	var track_count = animation.get_track_count()
	var hitbox_size: Vector2 = Vector2.ZERO
	var hitbox_position: Vector2 = Vector2.ZERO
	var found_hitbox = false
	
	for track_idx in range(track_count):
		var track_path = animation.track_get_path(track_idx)
		var path_string = str(track_path)
		
		# 查找 Hitbox/HitShape:shape:size
		if "Hitbox/HitShape" in path_string and "shape:size" in path_string:
			var key_count = animation.track_get_key_count(track_idx)
			if key_count > 0:
				# 讀取第一個關鍵幀（通常是攻擊開始時的尺寸）
				for key_idx in range(key_count):
					var value = animation.track_get_key_value(track_idx, key_idx)
					if value != null and value is Vector2 and value != Vector2.ZERO:
						hitbox_size = value
						found_hitbox = true
						break
		
		# 查找 Hitbox/HitShape:position
		if "Hitbox/HitShape" in path_string and ":position" in path_string and "shape" not in path_string:
			var key_count = animation.track_get_key_count(track_idx)
			if key_count > 0:
				for key_idx in range(key_count):
					var value = animation.track_get_key_value(track_idx, key_idx)
					if value != null and value is Vector2:
						hitbox_position = value
						break
	
	if found_hitbox:
		var hitbox_data = HitboxData.new()
		hitbox_data.size = hitbox_size
		hitbox_data.position = hitbox_position
		hitbox_data.attack_name = attack_name
		hitbox_data.character_id = character_id
		
		var cache_key = "%s:%s" % [character_id, attack_name]
		hitbox_cache[cache_key] = hitbox_data
		
		if debug_mode:
			Debug.log("    ✅ %s: size=%s, pos=%s" % [attack_name, hitbox_size, hitbox_position])

# ============================================================
# 公開查詢接口
# ============================================================

func get_hitbox_data(character_id: String, attack_name: String) -> HitboxData:
	"""獲取指定角色和攻擊的 Hitbox 數據"""
	var cache_key = "%s:%s" % [character_id, attack_name]
	
	if cache_key in hitbox_cache:
		return hitbox_cache[cache_key]
	
	# 如果沒有找到，返回默認數據
	var default_data = HitboxData.new()
	default_data.size = Vector2(50, 50)  # 默認大小
	default_data.attack_name = attack_name
	default_data.character_id = character_id
	return default_data

func get_hurtbox_data(character_id: String) -> HurtboxData:
	"""獲取指定角色的 Hurtbox 數據"""
	if character_id in hurtbox_cache:
		return hurtbox_cache[character_id]
	
	# 如果沒有找到，返回默認數據
	var default_data = HurtboxData.new()
	default_data.size = Vector2(100, 200)  # 默認大小
	default_data.character_id = character_id
	return default_data

func check_hitbox_collision(
	attacker_pos: Vector2,
	attacker_char_id: String,
	attack_name: String,
	target_pos: Vector2,
	target_char_id: String,
	attacker_facing: float = 1.0
) -> bool:
	"""
	檢查 Hitbox 是否與對手的 Hurtbox 碰撞（AABB 碰撞檢測）
	
	參數：
	- attacker_pos: 攻擊者世界位置
	- attacker_char_id: 攻擊者角色 ID
	- attack_name: 攻擊名稱
	- target_pos: 目標世界位置
	- target_char_id: 目標角色 ID
	- attacker_facing: 攻擊者朝向（1.0 或 -1.0）
	
	返回：
	- true: 有碰撞
	- false: 無碰撞
	"""
	var hitbox = get_hitbox_data(attacker_char_id, attack_name)
	var hurtbox = get_hurtbox_data(target_char_id)
	
	# 計算 Hitbox 的世界邊界（考慮朝向）
	var hitbox_world_pos = attacker_pos + hitbox.position * Vector2(attacker_facing, 1.0)
	var hitbox_half_size = hitbox.size / 2.0
	var hitbox_min = hitbox_world_pos - hitbox_half_size
	var hitbox_max = hitbox_world_pos + hitbox_half_size
	
	# 計算 Hurtbox 的世界邊界
	var hurtbox_world_pos = target_pos + hurtbox.position
	var hurtbox_half_size = hurtbox.size / 2.0
	var hurtbox_min = hurtbox_world_pos - hurtbox_half_size
	var hurtbox_max = hurtbox_world_pos + hurtbox_half_size
	
	# AABB 碰撞檢測
	var collision = (
		hitbox_min.x <= hurtbox_max.x and hitbox_max.x >= hurtbox_min.x and
		hitbox_min.y <= hurtbox_max.y and hitbox_max.y >= hurtbox_min.y
	)
	
	return collision

func get_attack_range(character_id: String, attack_name: String) -> float:
	"""
	獲取攻擊的有效範圍（從角色中心到 Hitbox 最遠端的距離）
	
	返回：
	- 攻擊範圍（像素）
	"""
	var hitbox = get_hitbox_data(character_id, attack_name)
	
	# 計算從角色中心到 Hitbox 最遠端的距離
	var hitbox_center = hitbox.position.x
	var hitbox_half_width = hitbox.size.x / 2.0
	var max_reach = abs(hitbox_center) + hitbox_half_width
	
	return max_reach

func get_throw_range(character_id: String) -> float:
	"""【新增】獲取投擲框的有效範圍（從角色中心到 ThrowBox 最遠端的距離）"""
	var throw_hitbox = get_hitbox_data(character_id, "throw_enter")
	
	# 計算從角色中心到 ThrowBox 最遠端的距離
	var throw_center = throw_hitbox.position.x
	var throw_half_width = throw_hitbox.size.x / 2.0
	var max_reach = abs(throw_center) + throw_half_width
	
	return max_reach

func check_throw_collision(
	attacker_pos: Vector2,
	attacker_char_id: String,
	target_pos: Vector2,
	target_char_id: String,
	attacker_facing: float = 1.0
) -> bool:
	"""【新增】檢查投擲框是否與對手的 Hurtbox 碰撞"""
	return check_hitbox_collision(attacker_pos, attacker_char_id, "throw_enter", target_pos, target_char_id, attacker_facing)

# ============================================================
# 調試工具
# ============================================================

func print_cache_summary() -> void:
	"""打印快取摘要"""
	Debug.log("\n[HITBOX CACHE] 快取摘要:")
	Debug.log("============================================================")
	
	Debug.log("\n📦 Hurtbox 數據:")
	for character_id in hurtbox_cache:
		var data = hurtbox_cache[character_id]
		Debug.log("  %s: %s" % [character_id, data])
	
	Debug.log("\n📦 Hitbox 數據:")
	for cache_key in hitbox_cache:
		var data = hitbox_cache[cache_key]
		Debug.log("  %s: %s" % [cache_key, data])
	
	Debug.log("============================================================")

func force_refresh() -> void:
	"""強制刷新快取（用於調試）"""
	hitbox_cache.clear()
	hurtbox_cache.clear()
	is_initialized = false
	_initialize_cache()
