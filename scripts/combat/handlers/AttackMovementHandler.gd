# AttackMovementHandler.gd
# 職責: 處理攻擊時的角色移動（forward moving, lunges）
# 遷移自 Player.gd 的攻擊移動系統
# 【已改為 frame-based】所有計時器現在使用幀計數

class_name AttackMovementHandler extends Node

var parent_player: Player = null
var world: Node = null

# 移動狀態
var active_movement: AttackMovement = null
var movement_timer: int = 0  # Frame-based timer
var is_movement_active: bool = false
var movement_duration_frames: int = 0  # 總移動幀數（轉換自 duration 秒）
var movement_start_delay_frames: int = 0  # 起始延遲幀數（轉換自 start_delay 秒）

func _ready() -> void:
	parent_player = get_parent() as Player
	if not parent_player:
		push_error("[AttackMovementHandler] Must be child of Player node!")
		return
	
	# 等待 world 初始化
	await get_tree().process_frame
	world = get_tree().get_first_node_in_group("world")

func start_movement(attack_name: String, attack_table: Dictionary) -> void:
	"""啟動攻擊移動（由攻擊執行時呼叫）"""
	# 【修正】throw 不在 ATTACK_TABLE 中，特殊處理（throw 通常沒有自定義移動）
	if attack_name == "throw_enter" or attack_name == "throw_seq":
		return
	
	if not attack_name in attack_table:
		return
	
	var attack_dict = attack_table[attack_name]
	if not "movement" in attack_dict or attack_dict.movement == null:
		return
	
	var movement_resource = attack_dict.movement
	
	# 檢查 movement 是否啟用
	if not movement_resource.enabled:
		return
	
	# 檢查基本參數
	if movement_resource.distance <= 0.0 or movement_resource.duration <= 0.0:
		return
	
	active_movement = movement_resource
	movement_timer = 0
	is_movement_active = true
	
	# 🔴 【關鍵修復】轉換為幀數：執行於 120 FPS 物理上下文，所以應乘以 120 而非 60
	movement_duration_frames = int(round(active_movement.duration * 120.0))
	movement_start_delay_frames = int(round(active_movement.start_delay * 120.0))

func process_movement(_delta: float) -> void:
	"""每幀更新攻擊移動（在 _physics_process 中調用）"""
	# 【注意】delta 參數保留以保持向後相容，但不在此函數中使用
	if not is_movement_active or active_movement == null or not parent_player or not world:
		return
	
	# 【關鍵】摔投期間禁用攻擊移動
	if "is_being_thrown" in parent_player and parent_player.is_being_thrown:
		return
	
	# 等待起始延遲（現在使用幀計數）
	if movement_timer < movement_start_delay_frames:
		movement_timer += 1
		return
	
	var effective_frames = movement_timer - movement_start_delay_frames
	
	# 檢查是否超過持續時間
	if effective_frames >= movement_duration_frames:
		is_movement_active = false
		return
	
	# 計算移動方向
	var move_direction: float = 1.0
	if active_movement.use_facing_direction:
		move_direction = parent_player.facing_direction
	if active_movement.reverse_direction:
		move_direction *= -1.0
	
	# 獲取當前速度倍率（基於曲線，轉換為秒數進行計算）
	# 🔴 【關鍵修復】effective_frames 是物理幀數（120 FPS），應除以 120 而非 60
	var effective_time = float(effective_frames) / 120.0  # Convert physics frames to seconds
	var speed_multiplier = active_movement.get_speed_multiplier(effective_time)
	
	# 計算基礎速度（距離 / 持續時間）
	var base_speed = active_movement.distance / active_movement.duration
	
	# 應用速度倍率和方向
	var current_speed = base_speed * speed_multiplier * move_direction
	
	# 轉換為固定點速度
	parent_player.fixed_velocity.x = int(current_speed * world.SIMULATION_SCALE)
	
	movement_timer += 1

func stop_movement() -> void:
	"""停止當前移動"""
	is_movement_active = false
	active_movement = null
	movement_timer = 0

func is_active() -> bool:
	"""檢查移動是否正在執行"""
	return is_movement_active
