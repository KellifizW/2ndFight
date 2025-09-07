class_name Fighter extends Movement

@onready var collision_shape = $CollisionShape2D
@onready var sprite = $Sprite2D
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var is_being_pushed: bool = false
var prev_position: Vector2 = Vector2()
var arena_left: float = 0.0
var arena_right: float = ProjectSettings.get_setting("display/window/size/viewport_width")
var push_distance_multiplier: float = 0.5  # 保持推開速度
var PUSH_FRICTION: float = 66.0  # 輕推效果的摩擦常數

func _ready():
	super._ready()
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
	super._physics_process(delta)
	
	# 推開邏輯
	var all_players = get_tree().get_nodes_in_group("players")
	print("Debug: Arena boundaries: left=%s, right=%s" % [arena_left, arena_right])
	
	for other in all_players:
		if other == self:
			continue
			
		# 計算碰撞框範圍
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
		print("Debug: %s collision box: left=%s, right=%s, up=%s, down=%s" % [name, leftA, rightA, upA, downA])
		print("Debug: %s collision box: left=%s, right=%s, up=%s, down=%s" % [other.name, leftB, rightB, upB, downB])
		var epsilon = 5.0  # 增加容差以提高碰撞檢測穩定性
		
		# 計算重疊
		var overlap_x = min(rightA - leftB, rightB - leftA)
		var overlap_y = min(downA - upB, downB - upA)
		var relative_pos_x = global_position.x - other.global_position.x
		var push_distance = max(overlap_x, 12.0) * push_distance_multiplier
		var distance_before = abs(global_position.x - other.global_position.x)
		
		# 空中推開邏輯
		if not is_on_floor() and (other.is_on_floor() or other.is_jumping or other.crouch_pressed):
			if rightA >= leftB - epsilon and leftA <= rightB + epsilon and downA >= upB - epsilon and upA <= downB + epsilon:
				if overlap_x > -epsilon and overlap_y > -epsilon:
					print("Debug: Air overlap detected between %s and %s, x_overlap=%s, y_overlap=%s" % [name, other.name, overlap_x, overlap_y])
					push_distance += PUSH_FRICTION * delta
					var new_self_x = global_position.x
					var new_other_x = other.global_position.x
					
					if relative_pos_x > 0:
						new_self_x += push_distance
						new_other_x -= push_distance
					else:
						new_self_x -= push_distance
						new_other_x += push_distance
					
					new_self_x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
					new_other_x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
					
					global_position.x = new_self_x
					other.global_position.x = new_other_x
					
					is_being_pushed = true
					other.is_being_pushed = true
					var distance_after = abs(global_position.x - other.global_position.x)
					print("Debug: Air pushback applied. Self: %s, Other: %s, Push distance: %s, Distance: %s -> %s" % [global_position, other.global_position, push_distance, distance_before, distance_after])
		
		# 地面推開邏輯（簡化）
		elif rightA >= leftB - epsilon and leftA <= rightB + epsilon and downA >= upB - epsilon and upA <= downB + epsilon:
			if overlap_x > -epsilon and overlap_y > -epsilon:
				print("Debug: Ground overlap detected between %s and %s, x_overlap=%s, y_overlap=%s" % [name, other.name, overlap_x, overlap_y])
				var new_self_x = global_position.x
				var new_other_x = other.global_position.x
				
				if relative_pos_x > 0:
					new_self_x += push_distance * 0.5
					new_other_x -= push_distance * 0.5
				else:
					new_self_x -= push_distance * 0.5
					new_other_x += push_distance * 0.5
				
				new_self_x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
				new_other_x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
				
				global_position.x = new_self_x
				other.global_position.x = new_other_x
				
				is_being_pushed = true
				other.is_being_pushed = true
				var distance_after = abs(global_position.x - other.global_position.x)
				print("Debug: Ground pushback applied. Self: %s, Other: %s, Push distance: %s, Distance: %s -> %s" % [global_position, other.global_position, push_distance, distance_before, distance_after])
	
	# 邊界檢查
	global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
	
	prev_position = global_position
