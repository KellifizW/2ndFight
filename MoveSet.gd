class_name MoveSet extends Node

@export var is_powerkk_penetrable: bool = true
@export var is_spnk_penetrable: bool = true
@export var is_fireball_penetrable: bool = true
@export var fireball_y_offset: float = 0.0
@export var fireball_x_offset: float = 15.0
@export var fireball_spawn_delay: float = 0.2667

var is_powerkk: bool = false
var is_spnk: bool = false
var is_fireball: bool = false
var is_spmove: bool = false
var is_special_moving: bool = false
var powerkk_time: float = 0.933
var spnk_time: float = 0.0
var fireball_time: float = 0.3
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var fireball_timer: float = 0.0
var fireball_spawn_timer: float = 0.0
var powerkk_damage: float = 12.0
var spnk_damage: float = 12.0
var fireball_damage: float = 10.0
var powerkk_move_distance: float = 100.0
var spnk_move_distance: float = 90.0
var fireball_move_distance: float = 0.0
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var fireball_initial_facing: float = 0.0
var powerkk_initial_parent_scale_x: float = 0.0
var powerkk_initial_sprite_scale_x: float = 0.0
var spnk_initial_parent_scale_x: float = 0.0
var spnk_initial_sprite_scale_x: float = 0.0
var fireball_initial_parent_scale_x: float = 0.0
var fireball_initial_sprite_scale_x: float = 0.0
var is_spmove_animation_playing: bool = false
@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")
	if animation_player:
		for anim_name in ["powerkk", "spnk", "fireball"]:
			if animation_player.has_animation(anim_name):
				var anim = animation_player.get_animation(anim_name)
				var track_count = anim.get_track_count()
				for track_idx in range(track_count):
					var track_path = anim.track_get_path(track_idx)
					if track_path.get_subname_count() > 0 and track_path.get_subname(0) == "Sprite2D:transform/scale.x":
						print("Warning: Animation '%s' modifies Sprite2D:transform/scale.x, which may override sprite.scale.x in %s. Consider removing this track." % [anim_name, parent.name])
		if not animation_player.animation_finished.is_connected(_on_spmove_animation_finished):
			animation_player.animation_finished.connect(_on_spmove_animation_finished)
	if parent and parent.has_signal("hit_detected"):
		parent.hit_detected.connect(_on_hit_detected)
	is_special_moving = false

func stop_special_move():
	if is_powerkk or is_spnk or is_fireball:
		is_powerkk = false
		is_spnk = false
		is_fireball = false
		is_spmove = false
		is_special_moving = false
		is_spmove_animation_playing = false
		fireball_spawn_timer = 0.0
		var final_position = sprite.position
		animation_player.stop()
		sprite.position = Vector2.ZERO
		var world = get_tree().get_first_node_in_group("world")
		if world:
			parent.fixed_position.x += int(final_position.x * world.SIMULATION_SCALE)
			parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		else:
			print("Warning: World node not found, fallback to direct global_position update")
			parent.global_position.x += final_position.x
		# 修正：強制更新 facing 並確保 sprite.scale.x 與 facing_direction 同步
		parent.force_update_facing_direction()
		sprite.scale.x = abs(sprite.scale.x) * sign(parent.facing_direction)
		parent.fixed_velocity.x = 0
		if "is_special_moving" in parent:
			parent.is_special_moving = false
		print("Debug: Special move stopped for %s, facing_direction=%s, parent.scale.x=%s, sprite.scale.x=%s, position=%s" % [parent.name, parent.facing_direction, parent.scale.x, sprite.scale.x, parent.global_position])

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if parent.is_hit or parent.is_knockfly:
		if is_spmove:
			stop_special_move()
		return false
	
	if not is_valid_state:
		return false
	
	var player_id = parent.player_id if "player_id" in parent else "p1"
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % parent.name)
		return false
	
	if input_data.spm2_pressed and not parent.is_attacking and not is_fireball and not is_powerkk and not is_spnk:
		is_fireball = true
		is_spmove = true
		is_special_moving = true
		if animation_player and animation_player.has_animation("fireball"):
			fireball_time = animation_player.get_animation("fireball").length
			if fireball_time <= 0:
				fireball_time = 0.3
			print("Debug: Fireball length detected: %.2fs" % fireball_time)
		else:
			fireball_time = 0.3
		fireball_timer = fireball_time
		fireball_spawn_timer = fireball_spawn_delay
		parent.current_damage = fireball_damage
		fireball_initial_facing = parent.facing_direction
		fireball_initial_parent_scale_x = parent.scale.x
		fireball_initial_sprite_scale_x = sprite.scale.x
		if "is_special_moving" in parent:
			parent.is_special_moving = true
		parent.fixed_velocity = Vector2i(0, 0)
		parent.fixed_position.y = world.FLOOR_Y
		animation_player.play("fireball")
		print("Debug: Fireball triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, spawn delay=%.2fs" % [parent.name, fireball_damage, fireball_initial_facing, parent.scale.x, sprite.scale.x, fireball_spawn_delay])
		is_spmove_animation_playing = true
		return true
	
	if is_fireball:
		fireball_timer -= delta
		fireball_spawn_timer -= delta
		if fireball_spawn_timer <= 0 and fireball_spawn_timer > -delta:
			var fireball_scene = load("res://P1_fireball.tscn" if player_id == "p1" else "res://P2_fireball.tscn")
			var fireball = fireball_scene.instantiate()
			fireball.direction = parent.facing_direction
			fireball.owner_id = player_id
			fireball.global_position = parent.global_position + Vector2(fireball_x_offset * parent.facing_direction, fireball_y_offset)
			get_tree().current_scene.add_child(fireball)
			var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
			print("Debug: Fireball spawned for %s at: (%s, %s), Hitbox global_position: (%s, %s), owner_id: %s" % [parent.name, fireball.global_position.x, fireball.global_position.y, hitbox_pos.x, hitbox_pos.y, player_id])
		if fireball_timer <= 0:
			stop_special_move()
			print("Debug: Fireball timer ended for %s" % parent.name)
		return true
	
	if input_data.spm1_pressed and not parent.is_attacking:
		if player_id == "p1" and not is_powerkk:
			is_powerkk = true
			is_spmove = true
			is_special_moving = true
			if animation_player and animation_player.has_animation("powerkk"):
				powerkk_time = animation_player.get_animation("powerkk").length
				if powerkk_time <= 0:
					powerkk_time = 0.933
				print("Debug: Powerkk length detected: %.2fs" % powerkk_time)
			else:
				powerkk_time = 0.933
			powerkk_timer = powerkk_time
			parent.current_damage = powerkk_damage
			parent.attack_type = "powerkk"
			parent.fixed_velocity.x = int((powerkk_move_distance / powerkk_time) * world.SIMULATION_SCALE * parent.facing_direction)
			powerkk_initial_facing = parent.facing_direction
			powerkk_initial_parent_scale_x = parent.scale.x
			powerkk_initial_sprite_scale_x = sprite.scale.x
			if "is_special_moving" in parent:
				parent.is_special_moving = true
			animation_player.play("powerkk")
			var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
			print("Debug: Powerkk triggered for %s, current_damage=%s, attack_type=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, fixed_velocity.x=%s, Hitbox global_position: (%s, %s), is_crouching=%s" % [parent.name, powerkk_damage, parent.attack_type, powerkk_initial_facing, parent.scale.x, sprite.scale.x, parent.fixed_velocity.x, hitbox_pos.x, hitbox_pos.y, parent.is_crouching])
			is_spmove_animation_playing = true
			return true
		elif player_id == "p2" and not is_spnk:
			is_spnk = true
			is_spmove = true
			is_special_moving = true
			if animation_player and animation_player.has_animation("spnk"):
				spnk_time = animation_player.get_animation("spnk").length
				if spnk_time <= 0:
					spnk_time = 1.2
				print("Debug: Spnk length detected: %.2fs" % spnk_time)
			else:
				spnk_time = 1.2
			spnk_timer = spnk_time
			parent.current_damage = spnk_damage
			parent.attack_type = "spnk"
			parent.fixed_velocity.x = int((spnk_move_distance / spnk_time) * world.SIMULATION_SCALE * parent.facing_direction)
			spnk_initial_facing = parent.facing_direction
			spnk_initial_parent_scale_x = parent.scale.x
			spnk_initial_sprite_scale_x = sprite.scale.x
			if "is_special_moving" in parent:
				parent.is_special_moving = true
			animation_player.play("spnk")
			var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
			print("Debug: Spnk triggered for %s, current_damage=%s, attack_type=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, fixed_velocity.x=%s, Hitbox global_position: (%s, %s), is_crouching=%s" % [parent.name, spnk_damage, parent.attack_type, spnk_initial_facing, parent.scale.x, sprite.scale.x, parent.fixed_velocity.x, hitbox_pos.x, hitbox_pos.y, parent.is_crouching])
			is_spmove_animation_playing = true
			return true
	
	if is_powerkk:
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
		var delta_move = int(parent.fixed_velocity.x * delta)
		parent.fixed_position.x += delta_move
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			stop_special_move()
		return true

	if is_spnk:
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
		var delta_move = int(parent.fixed_velocity.x * delta)
		parent.fixed_position.x += delta_move
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		spnk_timer -= delta
		if spnk_timer <= 0:
			stop_special_move()
			print("Debug: Spnk timer ended for %s" % parent.name)
		return true
	
	return false

func _on_spmove_animation_finished(anim_name: String):
	if (anim_name == "spnk" or anim_name == "powerkk" or anim_name == "fireball") and is_spmove_animation_playing:
		is_spmove_animation_playing = false
		if "is_special_moving" in parent:
			parent.is_special_moving = false
		if (anim_name == "spnk" and spnk_timer > 0) or (anim_name == "powerkk" and powerkk_timer > 0) or (anim_name == "fireball" and fireball_timer > 0):
			print("Debug: Animation %s finished but timer still active for %s, skipping stop_special_move" % [anim_name, parent.name])
			return
		stop_special_move()
		parent.force_update_facing_direction()
		print("Debug: Animation %s finished for %s, facing_direction=%s, parent.scale.x=%s, sprite.scale.x=%s" % [anim_name, parent.name, parent.facing_direction, parent.scale.x, sprite.scale.x])

func _process(delta: float):
	if not is_spmove_animation_playing or not animation_player or not animation_player.is_playing():
		return
	
	var current_time = animation_player.get_current_animation_position()
	var anim = animation_player.get_current_animation()
	if anim != "spnk" and anim != "powerkk" and anim != "fireball":
		return
	
func _on_hit_detected(target: String, blockstun_duration: float, is_blocked: bool):
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p2" and is_spnk:
		if is_blocked:
			is_spnk_penetrable = false
			print("Debug: Spnk hit blocked by %s, is_spnk_penetrable=false" % target)
		else:
			is_spnk_penetrable = true
			print("Debug: Spnk hit %s (not blocked), is_spnk_penetrable=true" % target)
	elif is_fireball:
		if is_blocked:
			is_fireball_penetrable = false
			print("Debug: Fireball hit blocked by %s, is_fireball_penetrable=false" % target)
		else:
			is_fireball_penetrable = true
			print("Debug: Fireball hit %s (not blocked), is_fireball_penetrable=true" % target)

func get_special_damage() -> float:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p1" and is_powerkk:
		return powerkk_damage
	elif player_id == "p2" and is_spnk:
		return spnk_damage
	elif is_fireball:
		return fireball_damage
	return 0.0
