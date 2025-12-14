extends Camera2D

@export var zoom_factor: float = 120.0
@export var min_zoom: float = 1.0
@export var max_zoom: float = 1.3
@export var initial_zoom_factor: float = 1.3
@export var base_y_offset: float = 160.0       # 基礎偏移（近距離時使用）
@export var far_y_offset: float = 200.0        # 拉遠時的更大偏移（模擬從上方拉遠）
@export var smooth_speed: float = 15.0
@export var y_smooth_speed: float = 8.0        # 降低Y軸平滑速度，讓整體追蹤更遲緩

# 新增：舒適距離門檻（世界單位），超過才開始拉遠
@export var comfort_distance: float = 900.0    # 玩家距離小於此值時不拉遠
@export var max_distance_for_zoom: float = 1200.0  # 超過此距離時強制最大拉遠

# 新增：Y軸緩衝追蹤（減少跳躍晃動）
@export var y_up_scale: float = 0.05           # 向上（跳起）追蹤比例：極小，避免過度向上
@export var y_down_scale: float = 0.4          # 向下追蹤比例：中等，讓鏡頭緩慢跟回
var y_target_buffer: float                     # Y軸緩衝目標

var player1: Node2D
var player2: Node2D
var players = []
var target_position: Vector2
var target_zoom: float = 1.3
var target_y_offset: float = 120.0
var world_bounds = Rect2(0, 0, 1600, 720)

func _ready():
	players += [$"../Player1", $"../Player2"]
	player1 = get_node("/root/World/Player1") if has_node("/root/World/Player1") else null
	player2 = get_node("/root/World/Player2") if has_node("/root/World/Player2") else null
	# 初始縮放設為最大（最靠近）
	var initial_zoom = 1.3
	zoom = Vector2(initial_zoom, initial_zoom)
	target_zoom = initial_zoom
	
	# 初始位置：平均 + 基礎偏移
	var ave = (players[0].position + players[1].position) / 2
	ave.y -= base_y_offset / initial_zoom
	target_position = ave
	target_y_offset = base_y_offset
	y_target_buffer = target_position.y  # 初始化Y緩衝
	position = target_position

func clamp_to_viewport_bounds(pos: Vector2, current_zoom: float) -> Vector2:
	var viewport_size = Vector2(1280, 720) / current_zoom
	var min_x = world_bounds.position.x + viewport_size.x / 2
	var max_x = world_bounds.end.x - viewport_size.x / 2
	return Vector2(clamp(pos.x, min_x, max_x), pos.y)

func move_and_offset():
	var ave = (players[0].position + players[1].position) / 2
	
	# 計算角色間水平距離
	var dist_x = abs(players[0].position.x - players[1].position.x)
	
	# 1. 決定目標縮放（有門檻）
	if dist_x <= comfort_distance:
		target_zoom = max_zoom  # 很近時保持最大縮放（最清楚）
	elif dist_x >= max_distance_for_zoom:
		target_zoom = min_zoom   # 極遠時強制最小縮放
	else:
		# 線性插值：在 comfort ~ max_distance 之間平滑拉遠
		var t = (dist_x - comfort_distance) / (max_distance_for_zoom - comfort_distance)
		target_zoom = lerp(max_zoom, min_zoom, t)
	
	# 2. 決定目標 Y 偏移（模擬從上方拉遠）
	var current_y_offset = base_y_offset
	if dist_x > comfort_distance:
		var t = (dist_x - comfort_distance) / (max_distance_for_zoom - comfort_distance)
		current_y_offset = lerp(base_y_offset, far_y_offset, t)
	target_y_offset = current_y_offset
	
	# 3. X軸目標直接更新
	target_position.x = ave.x
	
	# 4. Y軸目標：使用緩衝邏輯減少跳躍晃動
	var raw_y_target = ave.y - (target_y_offset / target_zoom)
	var y_delta = raw_y_target - y_target_buffer
	
	# 根據方向調整追蹤比例
	var current_scale = y_down_scale
	if y_delta < 0:  # 向上（跳起），追蹤極少
		current_scale = y_up_scale
	
	# 平滑更新緩衝
	y_target_buffer += y_delta * current_scale
	target_position.y = y_target_buffer

func _process(delta):
	move_and_offset()
	
	# 平滑縮放
	zoom.x = lerp(zoom.x, target_zoom, smooth_speed * delta)
	zoom.y = zoom.x  # 保持等比
	
	# 限制X軸邊界
	var clamped = clamp_to_viewport_bounds(target_position, zoom.x)
	target_position.x = clamped.x
	
	# 平滑移動（Y軸已透過緩衝預先遲緩）
	position.x = lerp(position.x, target_position.x, smooth_speed * delta)
	position.y = lerp(position.y, target_position.y, y_smooth_speed * delta)
	
	# 除錯資訊
	get_node("../UI/HitLabel").text = "Zoom: %.2f, Dist: %.0f, YBuf: %.0f" % [zoom.x, abs(players[0].global_position.x - players[1].global_position.x), y_target_buffer]
