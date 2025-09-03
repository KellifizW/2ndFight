class_name Fighter extends CharacterBody2D

@onready var collision_shape = $CollisionShape2D
@onready var sprite = $Sprite2D
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var is_being_pushed: bool = false
var prev_position: Vector2 = Vector2()

func _ready():
	# 初始化碰撞箱尺寸
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var collision_scale = collision_shape.scale
		colbox_half_width = collision_shape.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = collision_shape.shape.size.y * collision_scale.y / 2.0
		print("Debug: CollisionShape2D initialized for %s. Half width: %s, Half height: %s, Layer: %s, Mask: %s, Sprite offset: %s" % [name, colbox_half_width, colbox_half_height, collision_layer, collision_mask, sprite.position])
	else:
		print("Warning: CollisionShape2D not found or not RectangleShape2D for %s. Pushback may not work correctly." % name)
	add_to_group("players")
	prev_position = global_position

func _physics_process(delta):
	var current_position = global_position
	is_being_pushed = false
	
	# 推開邏輯
	var all_players = get_tree().get_nodes_in_group("players")
	var arena_left = 0.0
	var arena_right = ProjectSettings.get_setting("display/window/size/viewport_width")  # 使用與 world.gd 一致的視口寬度
	print("Debug: Arena boundaries: left=%s, right=%s" % [arena_left, arena_right])
	
	for other in all_players:
		if other == self:
			continue
		# 跳過特定狀態下的推開
		if get_is_dashing() or get_is_backdashing() or get_is_attacking() or get_is_hit() or get_is_knockfly():
			print("Debug: %s skipped pushback due to state (dashing: %s, backdashing: %s, attacking: %s, hit: %s, knockfly: %s)" % [name, get_is_dashing(), get_is_backdashing(), get_is_attacking(), get_is_hit(), get_is_knockfly()])
			continue
		if other.get_is_dashing() or other.get_is_backdashing() or other.get_is_attacking() or other.get_is_hit() or other.get_is_knockfly():
			print("Debug: %s skipped pushback due to other state (dashing: %s, backdashing: %s, attacking: %s, hit: %s, knockfly: %s)" % [other.name, other.get_is_dashing(), other.get_is_backdashing(), other.get_is_attacking(), other.get_is_hit(), other.get_is_knockfly()])
			continue
		# 計算碰撞箱
		var sprite_offset = sprite.position
		var other_sprite_offset = other.sprite.position
		var leftA = global_position.x - colbox_half_width + sprite_offset.x
		var rightA = global_position.x + colbox_half_width + sprite_offset.x
		var upA = global_position.y - colbox_half_height + sprite_offset.y
		var downA = global_position.y + colbox_half_height + sprite_offset.y
		var leftB = other.global_position.x - other.colbox_half_width + other_sprite_offset.x
		var rightB = other.global_position.x + other.colbox_half_width + other_sprite_offset.x
		var upB = other.global_position.y - other.colbox_half_height + other_sprite_offset.y
		var downB = other.global_position.y + other.colbox_half_height + other_sprite_offset.y
		# 除錯日誌：碰撞箱與速度
		print("Debug: %s collision box: left=%s, right=%s, up=%s, down=%s, velocity=%s, global_y=%s" % [name, leftA, rightA, upA, downA, velocity, global_position.y])
		print("Debug: %s collision box: left=%s, right=%s, up=%s, down=%s, velocity=%s, global_y=%s" % [other.name, leftB, rightB, upB, downB, other.velocity, other.global_position.y])
		# 檢查重疊
		var epsilon = 0.05
		var x_overlap = rightA > leftB + epsilon and leftA < rightB - epsilon
		var y_overlap = downA > upB + epsilon and upA < downB - epsilon
		if not (x_overlap and y_overlap):
			print("Debug: No overlap detected between %s and %s (x_overlap=%s, y_overlap=%s, rightA-leftB=%s, leftA-rightB=%s, downA-upB=%s, upA-downB=%s)" % [name, other.name, x_overlap, y_overlap, rightA - leftB, leftA - rightB, downA - upB, upA - downB])
			continue
		# 計算重疊距離
		var overlap_x = min(rightA - leftB, rightB - leftA)
		var overlap_y = min(downA - upB, downB - upA)
		if overlap_x <= 0 or overlap_y <= 0:
			print("Debug: Overlap <= 0 between %s and %s (overlap_x=%s, overlap_y=%s)" % [name, other.name, overlap_x, overlap_y])
			continue
		var overlap = min(overlap_x, overlap_y)
		# 推開方向
		var prevXA = prev_position.x
		var prevXB = other.prev_position.x
		var pushbackDirA = (-1 if prevXB > prevXA else 1)
		if prevXA == prevXB:
			pushbackDirA = (-1 if other.global_position.x > global_position.x else 1)
		# 考慮速度影響推開距離
		var push_distance = overlap / 2.0
		if velocity.x * pushbackDirA > 0:
			push_distance += abs(velocity.x) * delta
		if other.velocity.x * -pushbackDirA > 0:
			push_distance += abs(other.velocity.x) * delta
		var new_self_x = global_position.x + pushbackDirA * push_distance
		var new_other_x = other.global_position.x - pushbackDirA * push_distance
		# 檢查邊界
		var can_push_self = new_self_x >= colbox_half_width and new_self_x <= arena_right - colbox_half_width
		var can_push_other = new_other_x >= other.colbox_half_width and new_other_x <= arena_right - other.colbox_half_width
		var distance_before = abs(global_position.x - other.global_position.x)
		if can_push_self:
			global_position.x = new_self_x
		else:
			print("Debug: %s pushback restricted by boundary at x=%s" % [name, new_self_x])
		if can_push_other:
			other.global_position.x = new_other_x
		else:
			print("Debug: %s pushback restricted by boundary at x=%s" % [other.name, new_other_x])
		is_being_pushed = true
		other.is_being_pushed = true
		var distance_after = abs(global_position.x - other.global_position.x)
		print("Debug: Pushback applied. Self: %s, Other: %s, Overlap: %s (x=%s, y=%s), Push dir: %s, Distance: %s, Distance change: %s -> %s" % [global_position, other.global_position, overlap, overlap_x, overlap_y, pushbackDirA, push_distance, distance_before, distance_after])
	
	prev_position = current_position

# 虛擬方法，子類必須實現
func get_is_dashing() -> bool:
	return false
func get_is_backdashing() -> bool:
	return false
func get_is_attacking() -> bool:
	return false
func get_is_hit() -> bool:
	return false
func get_is_knockfly() -> bool:
	return false
