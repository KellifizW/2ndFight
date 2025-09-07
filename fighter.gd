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
		if not is_on_floor() or not other.is_on_floor():
			print("Debug: Skipping pushback for %s and %s due to airborne state" % [name, other.name])
			continue
		if get_is_dashing() or get_is_backdashing() or get_is_attacking() or get_is_hit() or get_is_knockfly():
			print("Debug: %s skipped pushback due to state (dashing: %s, backdashing: %s, attacking: %s, hit: %s, knockfly: %s)" % [name, get_is_dashing(), get_is_backdashing(), get_is_attacking(), get_is_hit(), get_is_knockfly()])
			continue
		if other.get_is_dashing() or other.get_is_backdashing() or other.get_is_attacking() or other.get_is_hit() or other.get_is_knockfly():
			print("Debug: %s skipped pushback due to other state (dashing: %s, backdashing: %s, attacking: %s, hit: %s, knockfly: %s)" % [other.name, other.get_is_dashing(), other.get_is_backdashing(), other.get_is_attacking(), other.get_is_hit(), other.get_is_knockfly()])
			continue
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
		var epsilon = 2.0
		if not (rightA >= leftB - epsilon and leftA <= rightB + epsilon and downA >= upB - epsilon and upA <= downB + epsilon):
			print("Debug: No overlap detected between %s and %s" % [name, other.name])
			continue
		var overlap = min(rightA - leftB, rightB - leftA)
		if overlap < -epsilon:
			print("Debug: Overlap < -epsilon between %s and %s" % [name, other.name])
			continue
		overlap = max(overlap, 12.0)  # 提高重疊門檻以減少過早推開
		var relative_pos = global_position.x - other.global_position.x
		var push_distance = overlap * push_distance_multiplier
		var new_self_x = global_position.x
		var new_other_x = other.global_position.x
		var can_push_self = new_self_x >= arena_left + colbox_half_width and new_self_x <= arena_right - colbox_half_width
		var can_push_other = new_other_x >= arena_left + other.colbox_half_width and new_other_x <= arena_right - other.colbox_half_width
		var distance_before = abs(global_position.x - other.global_position.x)
		
		# 單向推開邏輯：根據移動方向決定推開哪個角色
		var self_velocity = global_position.x - prev_position.x
		var other_velocity = other.global_position.x - other.prev_position.x
		var is_self_moving = abs(self_velocity) > 0.1
		var is_other_moving = abs(other_velocity) > 0.1
		
		if is_self_moving and not is_other_moving:
			# 自身移動，對方靜止，推開對方
			new_other_x = other.global_position.x + (-1 if relative_pos > 0 else 1) * push_distance
			if can_push_other:
				other.global_position.x = new_other_x
			else:
				other.global_position.x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
				if new_other_x > arena_right - other.colbox_half_width:
					# 對方在右邊界，推自身向左
					new_self_x = global_position.x - push_distance * 1.0
					print("Debug: %s at right boundary, pushing %s left" % [other.name, name])
				elif new_other_x < arena_left + other.colbox_half_width:
					# 對方在左邊界，推自身向右
					new_self_x = global_position.x + push_distance * 1.0
					print("Debug: %s at left boundary, pushing %s right" % [other.name, name])
				else:
					print("Debug: %s pushback restricted by boundary at x=%s" % [other.name, new_other_x])
				global_position.x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
		elif is_other_moving and not is_self_moving:
			# 對方移動，自身靜止，推開自身
			new_self_x = global_position.x + (1 if relative_pos > 0 else -1) * push_distance
			if can_push_self:
				global_position.x = new_self_x
			else:
				global_position.x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
				if new_self_x > arena_right - colbox_half_width:
					# 自身在右邊界，推對方向左
					new_other_x = other.global_position.x - push_distance * 1.0
					print("Debug: %s at right boundary, pushing %s left" % [name, other.name])
				elif new_self_x < arena_left + colbox_half_width:
					# 自身在左邊界，推對方向右
					new_other_x = other.global_position.x + push_distance * 1.0
					print("Debug: %s at left boundary, pushing %s right" % [name, other.name])
				else:
					print("Debug: %s pushback restricted by boundary at x=%s" % [name, new_self_x])
				other.global_position.x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
		else:
			# 雙方都移動或都靜止，按相對位置推開
			var pushbackDirA = (1 if relative_pos > 0 else -1)
			var pushbackDirB = -pushbackDirA
			new_self_x = global_position.x + pushbackDirA * push_distance * 0.5
			new_other_x = other.global_position.x + pushbackDirB * push_distance * 0.5
			if can_push_self:
				global_position.x = new_self_x
			else:
				global_position.x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
				if new_self_x > arena_right - colbox_half_width:
					new_other_x = other.global_position.x - push_distance * 1.0
					print("Debug: %s at right boundary, pushing %s left" % [name, other.name])
				elif new_self_x < arena_left + colbox_half_width:
					new_other_x = other.global_position.x + push_distance * 1.0
					print("Debug: %s at left boundary, pushing %s right" % [name, other.name])
				else:
					print("Debug: %s pushback restricted by boundary at x=%s" % [name, new_self_x])
				other.global_position.x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
			if can_push_other:
				other.global_position.x = new_other_x
			else:
				other.global_position.x = clamp(new_other_x, arena_left + other.colbox_half_width, arena_right - other.colbox_half_width)
				if new_other_x > arena_right - other.colbox_half_width:
					new_self_x = global_position.x - push_distance * 1.0
					print("Debug: %s at right boundary, pushing %s left" % [other.name, name])
				elif new_other_x < arena_left + other.colbox_half_width:
					new_self_x = global_position.x + push_distance * 1.0
					print("Debug: %s at left boundary, pushing %s right" % [other.name, name])
				else:
					print("Debug: %s pushback restricted by boundary at x=%s" % [other.name, new_other_x])
				global_position.x = clamp(new_self_x, arena_left + colbox_half_width, arena_right - colbox_half_width)
		
		is_being_pushed = true
		other.is_being_pushed = true
		var distance_after = abs(global_position.x - other.global_position.x)
		print("Debug: Pushback applied. Self: %s, Other: %s, Overlap: %s, Push dir self: %s, Push dir other: %s, Distance: %s, Distance change: %s -> %s" % [global_position, other.global_position, overlap, (1 if relative_pos > 0 else -1), (-1 if relative_pos > 0 else 1), push_distance, distance_before, distance_after])
	
	# 邊界檢查：限制角色在視口範圍內
	global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
	
	prev_position = global_position
