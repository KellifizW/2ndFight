extends Camera2D

@export var zoom_factor: float = 120.0        # 保留，供未來微調靈敏度
@export var min_zoom: float = 1.0             # 最小縮放（完整480x240視口）
@export var max_zoom: float = 1.8             # 最大縮放（約240x120視口）
@export var initial_zoom_factor: float = 1.44 # 初始縮放因子，相對於360x180
@export var base_y_offset: float = 50.0       # 基礎y軸偏移，讓角色位於畫面下半部
@export var smooth_speed: float = 20.0        # x軸和縮放的平滑速度
@export var y_smooth_speed: float = 10.0      # y軸平滑速度，較慢以實現遲緩效果
@export var y_move_scale: float = 1        # y軸移動縮減因子（向下時使用，向上時調整為較小值）

var players = []
var target_position: Vector2
var target_zoom: float
var world_bounds = Rect2(0, 0, 480, 240)     # 世界邊界，基於項目設置
var y_target_buffer: float                   # 緩衝y軸目標位置

func _ready():
	players += [$"../Player1", $"../Player2"]
	# 計算初始縮放：基於360x180（縮放=1.333）並按initial_zoom_factor調整
	var initial_zoom = 1.333 / max(initial_zoom_factor, 0.1)  # 防止除以0
	zoom = Vector2(initial_zoom, initial_zoom)
	# 初始化目標位置，應用base_y_offset
	var ave: Vector2
	for s in players:
		ave += s.position
	ave /= players.size()
	var dynamic_y_offset = base_y_offset / initial_zoom
	ave.y -= dynamic_y_offset
	target_position = ave
	target_zoom = initial_zoom
	y_target_buffer = ave.y  # 初始化y軸緩衝
	# 將初始位置限制在視口邊界內（僅X軸）
	target_position = clamp_to_viewport_bounds(target_position, initial_zoom)
	position = target_position  # 立即設置初始位置，避免lerp延遲

func clamp_to_viewport_bounds(pos: Vector2, current_zoom: float) -> Vector2:
	# 根據縮放計算視口在世界單位中的大小
	var viewport_size = Vector2(480, 240) / current_zoom
	# 限制X軸位置，確保視口保持在世界邊界內
	var min_x = world_bounds.position.x + viewport_size.x / 2
	var max_x = world_bounds.end.x - viewport_size.x / 2
	# 僅對X軸進行限制，Y軸允許自由移動
	return Vector2(
		clamp(pos.x, min_x, max_x),
		pos.y  # 不限制Y軸
	)

func move():
	var ave: Vector2
	for s in players:
		ave += s.position
	ave /= players.size()
	# 應用動態y軸偏移
	var dynamic_y_offset = base_y_offset / zoom.x
	# x軸目標位置直接更新
	target_position.x = ave.x
	# y軸目標位置應用縮減因子
	var raw_y_target = ave.y - dynamic_y_offset
	var y_delta = raw_y_target - y_target_buffer
	# 根據方向調整縮減因子：向上（y_delta < 0，角色跳起）追蹤極少（0.05），向下追蹤正常（0.3）
	var current_scale = y_move_scale
	if y_delta < 0:
		current_scale = 0.005  # 向上追蹤只有5%，允許角色部分超出頂部
	var scaled_y_delta = y_delta * current_scale
	y_target_buffer += scaled_y_delta
	target_position.y = y_target_buffer

func zooming():
	# 計算角色間水平距離
	var min_x = min(players[0].global_position.x, players[1].global_position.x)
	var max_x = max(players[0].global_position.x, players[1].global_position.x)
	var dist_x = max_x - min_x
	# 計算所需縮放，確保角色在視野內
	var margin = 10.0  # 邊距，確保角色不貼邊
	var required_zoom = 480.0 / (dist_x + margin)
	# 檢查是否有角色靠近世界邊界
	var player_near_left = min_x <= world_bounds.position.x + margin
	var player_near_right = max_x >= world_bounds.end.x - margin
	# 如果角色靠近邊界，確保視口不超出邊界，但允許根據距離縮放
	if player_near_left or player_near_right:
		# 計算當前視口寬度
		var viewport_width = 480.0 / zoom.x
		# 如果角色間距離小於當前視口寬度減邊距，允許拉近
		if dist_x + margin < viewport_width:
			target_zoom = required_zoom
		else:
			# 保持當前縮放或拉遠以包含兩名角色
			target_zoom = min(zoom.x, required_zoom)
	else:
		# 正常情況下，根據角色間距離設置縮放
		target_zoom = required_zoom
	# 限制縮放範圍
	target_zoom = clamp(target_zoom, min_zoom, max_zoom)

func _process(delta):
	# 直接更新目標位置（移除y軸延遲邏輯）
	move()
	zooming()
	# 平滑插值縮放
	var current_zoom = zoom.x
	current_zoom = lerp(current_zoom, target_zoom, smooth_speed * delta)
	zoom = Vector2(current_zoom, current_zoom)
	# 將目標位置限制在視口邊界內（僅X軸）
	target_position = clamp_to_viewport_bounds(target_position, current_zoom)
	# 分別平滑插值x軸和y軸
	var new_position = position
	new_position.x = lerp(new_position.x, target_position.x, smooth_speed * delta)
	new_position.y = lerp(new_position.y, target_position.y, y_smooth_speed * delta)
	position = new_position
	# 除錯顯示：縮放和角色間距離
	get_node("../HitLabel").text = "Zoom: %.3f, Dist: %.1f" % [zoom.x, (max(players[0].global_position.x, players[1].global_position.x) - min(players[0].global_position.x, players[1].global_position.x))]
