# AttackMovement.gd - 攻擊移動數據類
class_name AttackMovement extends Resource

# 移動曲線類型
enum MovementCurve {
	NONE,              # 無移動
	LINEAR,            # 線性移動（恆速）
	EASE_IN_OUT,       # 加速再減速（平滑）
	EASE_IN,           # 開始加速（衝刺型）
	EASE_OUT,          # 開始快速然後減速（爆發型）
	BURST,             # 瞬間爆發後減速（重拳型）
	DASH,              # 持續加速後急停（衝刺型）
	CUSTOM             # 自定義曲線（使用 custom_curve）
}

# === 基本移動屬性 ===
@export var enabled: bool = false                      # 是否啟用移動
@export var distance: float = 0.0                      # 移動距離（像素）
@export var duration: float = 0.0                      # 移動持續時間（秒）
@export var curve_type: MovementCurve = MovementCurve.NONE  # 曲線類型

# === 進階屬性 ===
@export var start_delay: float = 0.0                  # 開始移動前的延遲（秒）
@export var acceleration_ratio: float = 0.5           # 加速階段佔總時間的比例（0.0-1.0）
@export var peak_speed_multiplier: float = 1.5        # 峰值速度倍數（用於爆發型）
@export var custom_curve: Curve = null                # 自定義速度曲線（0.0-1.0）

# === 方向控制 ===
@export var use_facing_direction: bool = true         # 是否使用角色面向方向
@export var reverse_direction: bool = false           # 反轉移動方向（例如後退攻擊）
@export var lock_direction: bool = true                # 移動期間鎖定面向

# === 物理屬性 ===
@export var ignore_walls: bool = false                # 是否無視牆壁碰撞
@export var can_be_blocked: bool = true                # 移動是否可被防禦打斷

# 獲取指定時間點的速度倍數（0.0-1.0）
func get_speed_multiplier(elapsed_time: float) -> float:
	if not enabled or duration <= 0.0:
		return 0.0
	
	# 扣除延遲時間
	var t = elapsed_time - start_delay
	if t < 0.0:
		return 0.0
	if t > duration:
		return 0.0
	
	# 標準化時間 (0.0-1.0)
	var normalized_t = t / duration
	
	# 根據曲線類型計算速度倍數
	match curve_type:
		MovementCurve.NONE:
			return 0.0
		
		MovementCurve.LINEAR:
			return 1.0  # 恆速
		
		MovementCurve.EASE_IN_OUT:
			# 標準加速-減速曲線（平滑）
			return _ease_in_out_cubic(normalized_t)
		
		MovementCurve.EASE_IN:
			# 開始慢後來快（衝刺型）
			return _ease_in_cubic(normalized_t)
		
		MovementCurve.EASE_OUT:
			# 開始快後來慢（爆發型）
			return _ease_out_cubic(normalized_t)
		
		MovementCurve.BURST:
			# 瞬間爆發後減速（重拳型）
			if normalized_t < acceleration_ratio:
				# 快速加速到峰值
				var accel_t = normalized_t / acceleration_ratio
				return _ease_out_quad(accel_t) * peak_speed_multiplier
			else:
				# 緩慢減速
				var decel_t = (normalized_t - acceleration_ratio) / (1.0 - acceleration_ratio)
				return (1.0 - _ease_in_cubic(decel_t)) * peak_speed_multiplier
		
		MovementCurve.DASH:
			# 持續加速後急停（衝刺型）
			if normalized_t < acceleration_ratio:
				# 持續加速
				var accel_t = normalized_t / acceleration_ratio
				return _ease_in_quad(accel_t)
			else:
				# 急停
				var decel_t = (normalized_t - acceleration_ratio) / (1.0 - acceleration_ratio)
				return 1.0 - _ease_out_expo(decel_t)
		
		MovementCurve.CUSTOM:
			# 使用自定義曲線
			if custom_curve:
				return custom_curve.sample(normalized_t)
			return 1.0
		
		_:
			return 0.0

# === 緩動函數 ===
func _ease_in_cubic(t: float) -> float:
	return t * t * t

func _ease_out_cubic(t: float) -> float:
	var f = t - 1.0
	return f * f * f + 1.0

func _ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var f = (2.0 * t) - 2.0
		return 0.5 * f * f * f + 1.0

func _ease_in_quad(t: float) -> float:
	return t * t

func _ease_out_quad(t: float) -> float:
	return t * (2.0 - t)

func _ease_out_expo(t: float) -> float:
	if t >= 1.0:
		return 1.0
	return 1.0 - pow(2.0, -10.0 * t)

# 獲取總移動距離（考慮方向）
func get_total_distance(facing_direction: float) -> float:
	if not enabled:
		return 0.0
	
	var dir = facing_direction if use_facing_direction else 1.0
	if reverse_direction:
		dir *= -1.0
	
	return distance * dir

# 創建預設配置
static func create_none() -> AttackMovement:
	var movement = AttackMovement.new()
	movement.enabled = false
	return movement

static func create_light_punch_forward() -> AttackMovement:
	var movement = AttackMovement.new()
	movement.enabled = true
	movement.distance = 20.0
	movement.duration = 0.15
	movement.curve_type = MovementCurve.EASE_OUT
	movement.start_delay = 0.05
	return movement

static func create_heavy_punch_burst() -> AttackMovement:
	var movement = AttackMovement.new()
	movement.enabled = true
	movement.distance = 60.0
	movement.duration = 0.25
	movement.curve_type = MovementCurve.BURST
	movement.start_delay = 0.08
	movement.acceleration_ratio = 0.3
	movement.peak_speed_multiplier = 2.0
	return movement

static func create_dash_kick() -> AttackMovement:
	var movement = AttackMovement.new()
	movement.enabled = true
	movement.distance = 80.0
	movement.duration = 0.35
	movement.curve_type = MovementCurve.DASH
	movement.start_delay = 0.05
	movement.acceleration_ratio = 0.6
	return movement
