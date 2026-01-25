# AttackMovementHandler.gd
# 職責: 處理攻擊時的角色移動（forward moving, lunges）
# 遷移自 Player.gd 的攻擊移動系統

class_name AttackMovementHandler extends Node

var parent_player: Player = null
var world: Node = null

# 移動狀態
var active_movement: AttackMovement = null
var movement_timer: float = 0.0
var is_movement_active: bool = false

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
	if not attack_name in attack_table:
		print("[AttackMovementHandler] %s 不在 ATTACK_TABLE 中" % attack_name)
		return
	
	var attack_dict = attack_table[attack_name]
	if not "movement" in attack_dict or attack_dict.movement == null:
		print("[AttackMovementHandler] %s 沒有設定 movement 屬性" % attack_name)
		return
	
	var movement_resource = attack_dict.movement
	
	# 檢查 movement 是否啟用
	if not movement_resource.enabled:
		print("[AttackMovementHandler] %s 的 movement 未啟用 (enabled=false)" % attack_name)
		return
	
	# 檢查基本參數
	if movement_resource.distance <= 0.0 or movement_resource.duration <= 0.0:
		print("[AttackMovementHandler] %s 的 movement 參數無效 (distance=%.1f, duration=%.2f)" % [
			attack_name,
			movement_resource.distance,
			movement_resource.duration
		])
		return
	
	active_movement = movement_resource
	movement_timer = 0.0
	is_movement_active = true
	
	print("[AttackMovementHandler] ✓ 啟動 %s 移動：distance=%.1f, duration=%.2f, curve=%d, enabled=%s" % [
		attack_name,
		active_movement.distance,
		active_movement.duration,
		active_movement.curve_type,
		active_movement.enabled
	])

func process_movement(delta: float) -> void:
	"""每幀更新攻擊移動（在 _physics_process 中調用）"""
	if not is_movement_active or active_movement == null or not parent_player or not world:
		return
	
	# 等待起始延遲
	if movement_timer < active_movement.start_delay:
		movement_timer += delta
		return
	
	var effective_time = movement_timer - active_movement.start_delay
	
	# 檢查是否超過持續時間
	if effective_time >= active_movement.duration:
		is_movement_active = false
		print("[AttackMovementHandler] ✓ 移動完成")
		return
	
	# 計算移動方向
	var move_direction: float = 1.0
	if active_movement.use_facing_direction:
		move_direction = parent_player.facing_direction
	if active_movement.reverse_direction:
		move_direction *= -1.0
	
	# 獲取當前速度倍率（基於曲線）
	var speed_multiplier = active_movement.get_speed_multiplier(effective_time)
	
	# 計算基礎速度（距離 / 持續時間）
	var base_speed = active_movement.distance / active_movement.duration
	
	# 應用速度倍率和方向
	var current_speed = base_speed * speed_multiplier * move_direction
	
	# 轉換為固定點速度
	parent_player.fixed_velocity.x = int(current_speed * world.SIMULATION_SCALE)
	
	# 調試輸出（每 10 幀輸出一次）
	if int(movement_timer * 60) % 10 == 0:
		print("[AttackMovementHandler] time=%.2f, speed_mult=%.2f, velocity=%d" % [
			effective_time,
			speed_multiplier,
			parent_player.fixed_velocity.x
		])
	
	movement_timer += delta

func stop_movement() -> void:
	"""停止當前移動"""
	is_movement_active = false
	active_movement = null
	movement_timer = 0.0

func is_active() -> bool:
	"""檢查移動是否正在執行"""
	return is_movement_active
