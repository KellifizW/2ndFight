class_name Pushback extends CharacterBody2D

var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var push_speed: float = 75.0 # 推開速度
var is_being_pushed: bool = false # 是否正在被推
var prev_position: Vector2 = Vector2() # 上一幀位置

func _ready():
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape and collision_shape.shape is RectangleShape2D:
		# 考慮旋轉：x 軸對應 size.y * scale.y，y 軸對應 size.x * scale.x
		colbox_half_width = collision_shape.shape.extents.x * collision_shape.scale.x
		colbox_half_height = collision_shape.shape.extents.y * collision_shape.scale.y
		print("Debug: %s CollisionShape2D initialized. Half width: %s, Half height: %s, Layer: %s, Mask: %s" % [name, colbox_half_width, colbox_half_height, collision_layer, collision_mask])
	else:
		print("Warning: %s CollisionShape2D not found or not RectangleShape2D. Pushback may not work correctly." % name)
	add_to_group("players")
	prev_position = global_position # 初始化 prev_position

func _physics_process(delta):
	var current_position = global_position
	is_being_pushed = false
	var all_players = get_tree().get_nodes_in_group("players")
	var arena_left = 0.0
	var arena_right = get_viewport_rect().size.x
	
	for other in all_players:
		if other == self:
			continue
		# 避免雙向推開，優先 x 較小的角色
		if is_being_pushed or other.is_being_pushed or global_position.x > other.global_position.x:
			print("Debug: %s or %s already pushed or self x > other x, skipping pushback" % [name, other.name])
			continue
		# 檢查狀態
		if has_state_preventing_pushback() or other.has_state_preventing_pushback():
			print("Debug: %s skipped pushback due to state or other state" % name)
			continue
		# 碰撞箱計算
		var leftA = global_position.x - colbox_half_width
		var rightA = global_position.x + colbox_half_width
		var upA = global_position.y - colbox_half_height
		var downA = global_position.y + colbox_half_height
		var leftB = other.global_position.x - other.colbox_half_width
		var rightB = other.global_position.x + other.colbox_half_width
		var upB = other.global_position.y - other.colbox_half_height
		var downB = other.global_position.y + other.colbox_half_height
		# 檢查中心距離
		var center_distance = abs(global_position.x - other.global_position.x)
		var total_col_width = colbox_half_width + other.colbox_half_width
		if center_distance > total_col_width * 2.0:
			print("Debug: Center distance %s > total collision width * 2.0 %s, skipping pushback" % [center_distance, total_col_width * 2.0])
			continue
		# 檢查 y 軸中心距離
		var y_center_distance = abs(global_position.y - other.global_position.y)
		if y_center_distance > 20.0:
			print("Debug: Y center distance %s > 20.0, skipping pushback" % y_center_distance)
			continue
		# 檢查重疊
		var epsilon = 2.0
		var y_overlap = min(downA - upB, downB - upA)
		if not (rightA >= leftB - epsilon and leftA <= rightB + epsilon and y_overlap > 5.0):
			print("Debug: No overlap detected between %s and %s (y_overlap: %s)" % [name, other.name, y_overlap])
			continue
		var overlap = min(rightA - leftB, rightB - leftA)
		if overlap <= 2.0:
			print("Debug: Overlap <= 2.0 between %s and %s (overlap: %s)" % [name, other.name, overlap])
			continue
		# 推開方向
		var pushbackDirA = (-1 if other.global_position.x > global_position.x else 1)
		# 平滑推開：使用速度
		var push_distance = overlap / 2.0
		velocity.x = pushbackDirA * push_speed
		other.velocity.x = -pushbackDirA * push_speed
		move_and_slide()
		other.move_and_slide()
		# 檢查邊界
		if global_position.x < arena_left + colbox_half_width:
			global_position.x = arena_left + colbox_half_width
			velocity.x = 0
			print("Debug: %s hit left boundary during pushback, position set to %s" % [name, global_position.x])
		elif global_position.x > arena_right - colbox_half_width:
			global_position.x = arena_right - colbox_half_width
			velocity.x = 0
			print("Debug: %s hit right boundary during pushback, position set to %s" % [name, global_position.x])
		if other.global_position.x < arena_left + other.colbox_half_width:
			other.global_position.x = arena_left + other.colbox_half_width
			other.velocity.x = 0
			print("Debug: %s hit left boundary during pushback, position set to %s" % [other.name, other.global_position.x])
		elif other.global_position.x > arena_right - other.colbox_half_width:
			other.global_position.x = arena_right - other.colbox_half_width
			other.velocity.x = 0
			print("Debug: %s hit right boundary during pushback, position set to %s" % [other.name, other.global_position.x])
		is_being_pushed = true
		other.is_being_pushed = true
		var distance_after = abs(global_position.x - other.global_position.x)
		_log_pushback(other, overlap, pushbackDirA, push_distance, center_distance, y_center_distance, leftA, rightA, upA, downA, leftB, rightB, upB, downB, y_overlap)
	
	prev_position = current_position # 更新 prev_position

# 虛擬函數，子類實現以檢查狀態
func has_state_preventing_pushback() -> bool:
	return false

func _log_pushback(other, overlap: float, pushbackDirA: float, push_distance: float, center_distance: float, y_center_distance: float, leftA: float, rightA: float, upA: float, downA: float, leftB: float, rightB: float, upB: float, downB: float, y_overlap: float) -> void:
	print("Debug Pushback for %s: Collided with %s" % [name, other.name])
	print("  Self collision box: left=%s, right=%s, up=%s, down=%s" % [leftA, rightA, upA, downA])
	print("  Other collision box: left=%s, right=%s, up=%s, down=%s" % [leftB, rightB, upB, downB])
	print("  Center distance: %s, Y center distance: %s, Overlap: %s, Y overlap: %s" % [center_distance, y_center_distance, overlap, y_overlap])
	print("  Push direction: %s, Push distance: %s" % [pushbackDirA, push_distance])
