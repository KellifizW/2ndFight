class_name Fighter extends Movement

@onready var collision_shape = $Pushbox
@onready var sprite = $Sprite2D
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var is_being_pushed: bool = false
var prev_position: Vector2 = Vector2()
var arena_left: float = 0.0
var arena_right: float = ProjectSettings.get_setting("display/window/size/viewport_width")
var push_distance_multiplier: float = 0.5
var PUSH_FRICTION: float = 66.0
@export var push_trigger_distance: float = 5.0
@export var collision_epsilon: float = 5.0

func _ready():
	super._ready() # 調用父類 Movement 的 _ready()，確保已定義
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var collision_scale = collision_shape.scale
		colbox_half_width = collision_shape.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = collision_shape.shape.size.y * collision_scale.y / 2.0
	else:
		print("Warning: CollisionShape2D not found or invalid for %s" % name)
	add_to_group("players")
	prev_position = global_position

func _physics_process(delta):
	super._physics_process(delta)
	
	is_being_pushed = false
	
	var all_players = get_tree().get_nodes_in_group("players")
	
	for other in all_players:
		if other == self:
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
		
		var overlap_x = min(rightA - leftB, rightB - leftA)
		var overlap_y = min(downA - upB, downB - upA)
		var relative_pos_x = global_position.x - other.global_position.x
		var push_distance = max(overlap_x, 12.0) * push_distance_multiplier
		
		var is_overlapping = rightA >= leftB - push_trigger_distance and leftA <= rightB + push_trigger_distance and downA >= upB - push_trigger_distance and upA <= downB + push_trigger_distance
		var is_jump_overlapping = is_jumping or other.is_jumping
		
		if is_overlapping and (overlap_x > -collision_epsilon or is_jump_overlapping):
			if is_jump_overlapping:
				push_distance += PUSH_FRICTION * delta * 1.5
			else:
				push_distance += PUSH_FRICTION * delta
			
			var new_self_x = global_position.x
			var new_other_x = other.global_position.x
			var self_at_left = abs(global_position.x - (arena_left + colbox_half_width)) < collision_epsilon
			var self_at_right = abs(global_position.x - (arena_right - colbox_half_width)) < collision_epsilon
			var other_at_left = abs(other.global_position.x - (arena_left + other.colbox_half_width)) < collision_epsilon
			var other_at_right = abs(other.global_position.x - (arena_right - other.colbox_half_width)) < collision_epsilon
			
			if other_at_right and relative_pos_x > 0:
				new_self_x -= push_distance
				new_other_x = arena_right - other.colbox_half_width
			elif other_at_left and relative_pos_x < 0:
				new_self_x += push_distance
				new_other_x = arena_left + other.colbox_half_width
			elif self_at_right and relative_pos_x < 0:
				new_other_x += push_distance
				new_self_x = arena_right - colbox_half_width
			elif self_at_left and relative_pos_x > 0:
				new_other_x -= push_distance
				new_self_x = arena_left + colbox_half_width
			else:
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
	
	global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
	
	prev_position = global_position

func update_facing_direction():
	var players = get_tree().get_nodes_in_group("players")
	var other_player = null
	for player in players:
		if player != self:
			other_player = player
			break
	
	if other_player:
		var sprite_offset = sprite.position
		var other_sprite_offset = other_player.sprite.position
		var self_left = global_position.x - colbox_half_width + sprite_offset.x
		var self_right = global_position.x + colbox_half_width + sprite_offset.x
		var other_left = other_player.global_position.x - other_player.colbox_half_width + other_sprite_offset.x
		var other_right = other_player.global_position.x + other_player.colbox_half_width + other_sprite_offset.x
		
		if self_left > other_right:
			facing_direction = -1.0
			$Sprite2D.flip_h = true
		elif self_right < other_left:
			facing_direction = 1.0
			$Sprite2D.flip_h = false
		
		update_hitbox_position()

func update_hitbox_position():
	if has_node("Hitbox/HitShape"):
		$Hitbox.scale.x = facing_direction
	if has_node("Proximitybox/ProxShape"):
		$Proximitybox.scale.x = facing_direction
