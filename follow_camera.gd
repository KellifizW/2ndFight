# follow_camera.gd（完整最終版：解決初始化順序問題，保證鏡頭正確追蹤兩個動態生成的角色）

extends Camera2D

@export var zoom_factor: float = 120.0
@export var min_zoom: float = 1.0
@export var max_zoom: float = 1.3
@export var initial_zoom_factor: float = 1.3
@export var base_y_offset: float = 140.0      # 近距離時基礎向上偏移
@export var far_y_offset: float = 200.0        # 拉遠時更大向上偏移
@export var smooth_speed: float = 15.0
@export var y_smooth_speed: float = 8.0        # Y軸較慢平滑
@export var comfort_distance: float = 900.0    # 舒適距離，小於此值不拉遠
@export var max_distance_for_zoom: float = 1200.0  # 超過此距離強制最大拉遠
@export var y_up_scale: float = 0.05           # 向上（跳起）追蹤極慢
@export var y_down_scale: float = 0.4          # 向下追蹤中等速度
@export var max_camera_y: float = 350.0         # 鏡頭Y軸上限（防止過度向上）

var y_target_buffer: float = 0.0
var players: Array[Node2D] = []
var target_position: Vector2 = Vector2.ZERO
var target_zoom: float = 1.3
var target_y_offset: float = 160.0
var world_bounds = Rect2(0, 0, 1600, 720)

func _ready() -> void:
	# 使用 call_deferred 延後初始化，確保所有角色已生成並加入 "players" group
	call_deferred("_delayed_init")

func _delayed_init() -> void:
	var found_players: Array[Node] = get_tree().get_nodes_in_group("players")
	players = []
	for p in found_players:
		if p is Node2D:
			players.append(p as Node2D)
	
	if players.size() != 2:
		push_warning("鏡頭只找到 %d 個玩家（預期 2 個），請確認角色已呼叫 add_to_group(\"players\")" % players.size())
		return
	
	# 初始縮放
	zoom = Vector2(initial_zoom_factor, initial_zoom_factor)
	target_zoom = initial_zoom_factor
	
	# 初始位置：模仿舊版行為（平均位置 + 基礎向上偏移）
	var ave = (players[0].global_position + players[1].global_position) / 2
	ave.y -= base_y_offset / initial_zoom_factor
	target_position = ave
	y_target_buffer = target_position.y
	position = target_position  # 立即設定，避免第一幀卡在 (0,0)
	
	print("=== 鏡頭延後初始化完成 ===")
	print("追蹤玩家：%s 和 %s" % [players[0].name, players[1].name])
	print("初始鏡頭位置：%s" % position)

func _update_target_position_and_zoom() -> void:
	if players.size() < 2:
		return
	
	var p1_pos = players[0].global_position
	var p2_pos = players[1].global_position
	
	var ave = (p1_pos + p2_pos) / 2
	var dist_x = abs(p1_pos.x - p2_pos.x)
	
	# 目標縮放
	if dist_x <= comfort_distance:
		target_zoom = max_zoom
	elif dist_x >= max_distance_for_zoom:
		target_zoom = min_zoom
	else:
		var t = (dist_x - comfort_distance) / (max_distance_for_zoom - comfort_distance)
		target_zoom = lerp(max_zoom, min_zoom, t)
	
	# 目標 Y 偏移
	var current_y_offset = base_y_offset
	if dist_x > comfort_distance:
		var t = (dist_x - comfort_distance) / (max_distance_for_zoom - comfort_distance)
		current_y_offset = lerp(base_y_offset, far_y_offset, t)
	target_y_offset = current_y_offset
	
	# X 軸直接追平均
	target_position.x = ave.x
	
	# Y 軸緩衝追蹤（減少跳躍晃動）
	var raw_y_target = ave.y - (target_y_offset / target_zoom)
	var y_delta = raw_y_target - y_target_buffer
	
	var current_scale = y_down_scale
	if y_delta < 0:  # 向上跳
		current_scale = y_up_scale
	
	y_target_buffer += y_delta * current_scale
	target_position.y = y_target_buffer
	
	# 限制鏡頭不要向上超過上限
	target_position.y = max(target_position.y, max_camera_y)

func clamp_to_viewport_bounds(pos: Vector2, current_zoom: float) -> Vector2:
	var viewport_size = Vector2(1280, 720) / current_zoom
	var min_x = world_bounds.position.x + viewport_size.x / 2
	var max_x = world_bounds.end.x - viewport_size.x / 2
	return Vector2(clamp(pos.x, min_x, max_x), pos.y)

func _process(delta: float) -> void:
	_update_target_position_and_zoom()
	
	# 平滑縮放
	zoom.x = lerp(zoom.x, target_zoom, smooth_speed * delta)
	zoom.y = zoom.x
	
	# X 軸邊界限制
	var clamped = clamp_to_viewport_bounds(target_position, zoom.x)
	target_position.x = clamped.x
	
	# 平滑移動
	position.x = lerp(position.x, target_position.x, smooth_speed * delta)
	position.y = lerp(position.y, target_position.y, y_smooth_speed * delta)
	
	# 除錯顯示（可自行刪除）
	if has_node("../UI/HitLabel"):
		var dist = abs(players[0].global_position.x - players[1].global_position.x) if players.size() >= 2 else 0
		get_node("../UI/HitLabel").text = "Zoom: %.2f, Dist: %.0f, YBuf: %.0f, CamY: %.0f" % [zoom.x, dist, y_target_buffer, position.y]
