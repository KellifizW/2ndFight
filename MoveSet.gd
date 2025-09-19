class_name MoveSet extends Node

var is_powerkk: bool = false
var is_spnk: bool = false
var is_spmove: bool = false
var powerkk_time: float = 0.933
var spnk_time: float = 0.0
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var powerkk_damage: float = 20.0
var spnk_damage: float = 20.0
var powerkk_move_distance: float = 150.0
var spnk_move_distance: float = 150.0
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var powerkk_initial_parent_scale_x: float = 0.0
var powerkk_initial_sprite_scale_x: float = 0.0
var spnk_initial_parent_scale_x: float = 0.0
var spnk_initial_sprite_scale_x: float = 0.0
var is_spmove_animation_playing: bool = false
@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")
	if animation_player:
		for anim_name in ["powerkk", "spnk"]:
			if animation_player.has_animation(anim_name):
				var anim = animation_player.get_animation(anim_name)
				var track_count = anim.get_track_count()
				for track_idx in range(track_count):
					var track_path = anim.track_get_path(track_idx)
					if track_path.get_subname_count() > 0 and track_path.get_subname(0) == "Sprite2D:transform/scale.x":
						print("Warning: Animation '%s' modifies Sprite2D:transform/scale.x, which may override sprite.scale.x in %s. Consider removing this track." % [anim_name, parent.name])
		animation_player.animation_finished.connect(_on_spmove_animation_finished)

func stop_special_move():
	if is_powerkk or is_spnk:
		is_powerkk = false
		is_spnk = false
		is_spmove = false
		is_spmove_animation_playing = false
		var final_position = sprite.position
		animation_player.stop()
		sprite.position = Vector2.ZERO
		parent.global_position.x += final_position.x
		sprite.scale.x = abs(sprite.scale.x) * sign(parent.facing_direction)
		parent.update_facing_direction()
		if parent.has_node("Proximitybox"):
			var prox_shape = parent.get_node("Proximitybox/ProxShape")
			if prox_shape:
				prox_shape.disabled = true
			var proxbox_pos = parent.get_node("Proximitybox").global_position
			print("Debug: Special move stopped for %s, Proximitybox global_position: (%s, %s)" % [parent.name, proxbox_pos.x, proxbox_pos.y])
		print("Debug: Special move stopped for %s, final position: %s, sprite.scale.x=%s" % [parent.name, parent.global_position, sprite.scale.x])

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if parent.is_hit or parent.is_knockfly:
		if is_spmove:
			stop_special_move()
		return false
	
	if not is_valid_state:
		return false
	
	var player_id = parent.player_id if "player_id" in parent else "p1"
	
	if input_data.spm1_pressed:
		if player_id == "p1" and not is_powerkk:
			is_powerkk = true
			is_spmove = true
			powerkk_timer = powerkk_time
			parent.current_damage = powerkk_damage
			parent.velocity.x = 0
			powerkk_initial_facing = parent.facing_direction
			powerkk_initial_parent_scale_x = parent.scale.x
			powerkk_initial_sprite_scale_x = sprite.scale.x
			animation_player.play("powerkk")
			if parent.has_node("Proximitybox"):
				var prox_shape = parent.get_node("Proximitybox/ProxShape")
				if prox_shape:
					prox_shape.disabled = false
			var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
			print("Debug: Powerkk triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, Hitbox global_position: (%s, %s)" % [parent.name, powerkk_damage, powerkk_initial_facing, parent.scale.x, sprite.scale.x, hitbox_pos.x, hitbox_pos.y])
			return true
		elif player_id == "p2" and not is_spnk:
			is_spnk = true
			is_spmove = true
			if animation_player and animation_player.has_animation("spnk"):
				spnk_time = animation_player.get_animation("spnk").length
				spnk_timer = spnk_time
				print("Debug: Spnk length detected: %.2fs" % spnk_time)
			else:
				spnk_timer = 1.2
			parent.current_damage = spnk_damage
			parent.velocity.x = 0
			spnk_initial_facing = parent.facing_direction
			spnk_initial_parent_scale_x = parent.scale.x
			spnk_initial_sprite_scale_x = sprite.scale.x
			animation_player.play("spnk")
			if parent.has_node("Proximitybox"):
				var prox_shape = parent.get_node("Proximitybox/ProxShape")
				if prox_shape:
					prox_shape.disabled = false
			var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
			print("Debug: Spnk triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, Hitbox global_position: (%s, %s)" % [parent.name, spnk_damage, spnk_initial_facing, parent.scale.x, sprite.scale.x, hitbox_pos.x, hitbox_pos.y])
			if not animation_player.animation_finished.is_connected(_on_spmove_animation_finished):
				animation_player.animation_finished.connect(_on_spmove_animation_finished)
			is_spmove_animation_playing = true
			return true
	
	if is_powerkk:
		parent.velocity.x = 0
		var move_speed = (powerkk_move_distance / powerkk_time) * powerkk_initial_facing
		parent.global_position.x += move_speed * delta
		parent.call_deferred("set", "scale/x", powerkk_initial_parent_scale_x)
		sprite.call_deferred("set", "scale/x", powerkk_initial_sprite_scale_x)
		if parent.has_node("Proximitybox"):
			var proxbox_pos = parent.get_node("Proximitybox").global_position
			print("Debug: Powerkk active for %s, Proximitybox global_position: (%s, %s)" % [parent.name, proxbox_pos.x, proxbox_pos.y])
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			is_powerkk = false
			is_spmove = false
			is_spmove_animation_playing = false
			if parent.has_node("Proximitybox"):
				var prox_shape = parent.get_node("Proximitybox/ProxShape")
				if prox_shape:
					prox_shape.disabled = true
				var proxbox_pos = parent.get_node("Proximitybox").global_position
				print("Debug: Powerkk ended for %s, Proximitybox final global_position: (%s, %s)" % [parent.name, proxbox_pos.x, proxbox_pos.y])
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
			sprite.scale.x = abs(sprite.scale.x) * sign(powerkk_initial_facing)
			parent.update_facing_direction()
			print("Debug: Powerkk ended for %s, final position: %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, parent.global_position, powerkk_initial_facing, parent.scale.x, sprite.scale.x])
		return true

	if is_spnk:
		parent.velocity.x = 0
		var move_speed = (spnk_move_distance / spnk_time) * spnk_initial_facing
		parent.global_position.x += move_speed * delta
		parent.call_deferred("set", "scale/x", spnk_initial_parent_scale_x)
		sprite.call_deferred("set", "scale/x", spnk_initial_sprite_scale_x)
		if parent.has_node("Proximitybox"):
			var proxbox_pos = parent.get_node("Proximitybox").global_position
			print("Debug: Spnk active for %s, Proximitybox global_position: (%s, %s)" % [parent.name, proxbox_pos.x, proxbox_pos.y])
		spnk_timer -= delta
		if spnk_timer <= 0:
			is_spnk = false
			is_spmove = false
			is_spmove_animation_playing = false
			if parent.has_node("Proximitybox"):
				var prox_shape = parent.get_node("Proximitybox/ProxShape")
				if prox_shape:
					prox_shape.disabled = true
				var proxbox_pos = parent.get_node("Proximitybox").global_position
				print("Debug: Spnk ended for %s, Proximitybox final global_position: (%s, %s)" % [parent.name, proxbox_pos.x, proxbox_pos.y])
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
			sprite.scale.x = abs(sprite.scale.x) * sign(spnk_initial_facing)
			parent.update_facing_direction()
			print("Debug: Spnk ended for %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, spnk_initial_facing, parent.scale.x, sprite.scale.x])
		return true
	
	return false

func _on_spmove_animation_finished(anim_name: String):
	if anim_name == "spnk" and is_spmove_animation_playing:
		is_spmove_animation_playing = false
		if parent.has_node("Proximitybox"):
			var prox_shape = parent.get_node("Proximitybox/ProxShape")
			if prox_shape:
				prox_shape.disabled = true
			var proxbox_pos = parent.get_node("Proximitybox").global_position
			print("Debug: Spnk animation finished for %s, Proximitybox global_position: (%s, %s)" % [parent.name, proxbox_pos.x, proxbox_pos.y])

func _process(delta: float):
	if not is_spmove_animation_playing or not animation_player or not animation_player.is_playing():
		return
	
	var current_time = animation_player.get_current_animation_position()
	var anim = animation_player.get_current_animation()
	if anim != "spnk":
		return
	
	var hitbox_track_index = 9
	if animation_player.has_animation(anim) and hitbox_track_index < animation_player.get_animation(anim).get_track_count():
		var track = animation_player.get_animation(anim).track_get_path(hitbox_track_index)
		if str(track) == "NodePath(Hitbox/HitShape:disabled)":
			var keys_times = animation_player.get_animation(anim).track_get_key_times(hitbox_track_index)
			var keys_values = []
			for i in range(animation_player.get_animation(anim).track_get_key_count(hitbox_track_index)):
				keys_values.append(animation_player.get_animation(anim).track_get_key_value(hitbox_track_index, i))
			
			var should_enable = false
			for i in range(keys_times.size()):
				if abs(current_time - keys_times[i]) < 0.01:
					should_enable = not keys_values[i]
					break
			
			if parent.has_node("Hitbox"):
				var hitbox_pos = parent.get_node("Hitbox").global_position
				var shape_status = "disabled" if hitbox and hitbox.disabled else "enabled" if hitbox else "null"
				print("Debug: Spnk time %.2f for %s, Hitbox global_position: (%s, %s), shape: %s" % [current_time, parent.name, hitbox_pos.x, hitbox_pos.y, shape_status])
			if parent.has_node("Proximitybox"):
				var proxbox_pos = parent.get_node("Proximitybox").global_position
				print("Debug: Spnk time %.2f for %s, Proximitybox global_position: (%s, %s)" % [current_time, parent.name, proxbox_pos.x, proxbox_pos.y])

func get_special_damage() -> float:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p1" and is_powerkk:
		return powerkk_damage
	elif player_id == "p2" and is_spnk:
		return spnk_damage
	return 0.0
