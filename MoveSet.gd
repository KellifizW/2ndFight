class_name MoveSet extends Node

@export var is_powerkk_penetrable: bool = true
@export var is_spnk_penetrable: bool = true
@export var is_fireball_penetrable: bool = true
@export var is_dp_penetrable: bool = true
@export var fireball_y_offset: float = 0.0
@export var fireball_x_offset: float = 15.0
@export var fireball_spawn_delay: float = 0.2667
@export var super_duration: float = 2.6
@export var super_move_distance: float = 200.0
@export var super_gravity: float = 200000.0
@export var super_jump_delay: float = 0.9
@export var super_jump_vertical_speed: float = -210.0
@export var dp_duration: float = 1.0
@export var dp_jump_delay: float = 0.0667
@export var dp_horizontal_move: float = 80.0
@export var dp_vertical_speed: float = -700.0
@export var dp_damage: float = 5.0
@export var dp_knockfly_vertical_speed: float = -550.0  # DP 擊飛對手的垂直初速
@export var dp_knockfly_gravity: float = 2500000.0  # DP 擊飛對手的重力
@export var dp_hitstun: float = 0.65  # DP 專屬擊暈持續時間，讓擊飛更持久

var is_super: bool = false
var super_timer: float = 0.0
var super_jump_timer: float = 0.0
var super_freeze_time: float = 0.3
var is_powerkk: bool = false
var is_spnk: bool = false
var is_fireball: bool = false
var is_dp: bool = false
var is_spmove: bool = false
var is_special_moving: bool = false
var powerkk_time: float = 0.933
var spnk_time: float = 0.0
var fireball_time: float = 0.3
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var dp_timer: float = 0.0
var dp_jump_timer: float = 0.0
var fireball_timer: float = 0.0
var fireball_spawn_timer: float = 0.0
var powerkk_damage: float = 12.0
var spnk_damage: float = 12.0
var fireball_damage: float = 10.0
var super_damage: float = 5.0
var powerkk_move_distance: float = 100.0
var spnk_move_distance: float = 90.0
var fireball_move_distance: float = 0.0
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var fireball_initial_facing: float = 0.0
var dp_initial_facing: float = 0.0
var powerkk_initial_parent_scale_x: float = 0.0
var powerkk_initial_sprite_scale_x: float = 0.0
var spnk_initial_parent_scale_x: float = 0.0
var spnk_initial_sprite_scale_x: float = 0.0
var fireball_initial_parent_scale_x: float = 0.0
var fireball_initial_sprite_scale_x: float = 0.0
var is_spmove_animation_playing: bool = false
var super_initial_facing: float = 0.0
var has_jumped_in_super: bool = false
var has_jumped_in_dp: bool = false
@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")
	if animation_player:
		for anim_name in ["powerkk", "spnk", "fireball", "super", "dp"]:
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
	
	var special_call_player = parent.get_node_or_null("SpecialCallPlayer")
	var fireball_call_player = parent.get_node_or_null("FireballCallPlayer")
	if special_call_player:
		special_call_player.volume_db = 0.0
	if fireball_call_player:
		fireball_call_player.volume_db = 0.0

func start_powerkk():
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id != "p1" or is_powerkk or parent.is_attacking: return
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
	var world = get_tree().get_first_node_in_group("world")
	if world:
		parent.fixed_velocity.x = int((powerkk_move_distance / powerkk_time) * world.SIMULATION_SCALE * parent.facing_direction)
	powerkk_initial_facing = parent.facing_direction
	powerkk_initial_parent_scale_x = parent.scale.x
	powerkk_initial_sprite_scale_x = sprite.scale.x
	if "is_special_moving" in parent:
		parent.is_special_moving = true
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	animation_player.play("powerkk")
	var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
	print("Debug: Powerkk triggered for %s, current_damage=%s, attack_type=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, fixed_velocity.x=%s, Hitbox global_position: (%s, %s), is_crouching=%s" % [parent.name, powerkk_damage, parent.attack_type, powerkk_initial_facing, parent.scale.x, sprite.scale.x, parent.fixed_velocity.x, hitbox_pos.x, hitbox_pos.y, parent.is_crouching])
	is_spmove_animation_playing = true

	var special_call_player = parent.get_node_or_null("SpecialCallPlayer")
	if special_call_player:
		special_call_player.volume_db = 0.0
		special_call_player.play()
		print("Debug: Powerkk call sound played for %s (volume_db=%s)" % [parent.name, special_call_player.volume_db])
	else:
		print("Warning: SpecialCallPlayer not found for %s" % parent.name)

func start_spnk():
	var player_id = parent.player_id if "player_id" in parent else "p2"
	if player_id != "p2" or is_spnk or parent.is_attacking: return
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
	var world = get_tree().get_first_node_in_group("world")
	if world:
		parent.fixed_velocity.x = int((spnk_move_distance / spnk_time) * world.SIMULATION_SCALE * parent.facing_direction)
	spnk_initial_facing = parent.facing_direction
	spnk_initial_parent_scale_x = parent.scale.x
	spnk_initial_sprite_scale_x = sprite.scale.x
	if "is_special_moving" in parent:
		parent.is_special_moving = true
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	animation_player.play("spnk")
	var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
	print("Debug: Spnk triggered for %s, current_damage=%s, attack_type=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, fixed_velocity.x=%s, Hitbox global_position: (%s, %s), is_crouching=%s" % [parent.name, spnk_damage, parent.attack_type, spnk_initial_facing, parent.scale.x, sprite.scale.x, parent.fixed_velocity.x, hitbox_pos.x, hitbox_pos.y, parent.is_crouching])
	is_spmove_animation_playing = true

	var special_call_player = parent.get_node_or_null("SpecialCallPlayer")
	if special_call_player:
		special_call_player.volume_db = 0.0
		special_call_player.play()
		print("Debug: Spnk call sound played for %s (volume_db=%s)" % [parent.name, special_call_player.volume_db])
	else:
		print("Warning: SpecialCallPlayer not found for %s" % parent.name)

func start_super():
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id != "p1" or is_super or parent.is_attacking: return
	is_super = true
	is_spmove = true
	is_special_moving = true
	super_timer = super_duration
	super_jump_timer = super_jump_delay
	has_jumped_in_super = false
	parent.fixed_velocity = Vector2i.ZERO
	super_initial_facing = parent.facing_direction
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	animation_player.play("super")
	animation_player.seek(0, true)
	var world = get_tree().get_first_node_in_group("world")
	if world:
		parent.fixed_velocity.x = int((super_move_distance / super_duration) * world.SIMULATION_SCALE * super_initial_facing)
	parent.current_damage = super_damage
	freeze_game(super_freeze_time)
	print("Debug: Super triggered for %s, animation started, fixed_velocity.x=%s" % [parent.name, parent.fixed_velocity.x])

func start_dp():
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id != "p1" or is_dp or parent.is_attacking: return
	is_dp = true
	is_spmove = true
	is_special_moving = true
	is_dp_penetrable = true
	dp_timer = dp_duration
	dp_jump_timer = dp_jump_delay
	has_jumped_in_dp = false
	parent.fixed_velocity = Vector2i.ZERO
	dp_initial_facing = parent.facing_direction
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	animation_player.play("dp")
	animation_player.seek(0, true)
	var world = get_tree().get_first_node_in_group("world")
	if world:
		parent.fixed_velocity.x = int((dp_horizontal_move / dp_duration) * world.SIMULATION_SCALE * dp_initial_facing)
	parent.current_damage = dp_damage
	print("Debug: DP triggered for %s, fixed_velocity.x=%s" % [parent.name, parent.fixed_velocity.x])

func freeze_game(duration: float):
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	Engine.time_scale = 0.0
	tween.tween_interval(duration)
	tween.tween_property(Engine, "time_scale", 1.0, 0.1)
	tween.tween_callback(resume_after_freeze)

func resume_after_freeze():
	if animation_player and animation_player.current_animation == "super":
		animation_player.play()
		print("Debug: Super freeze ended, resuming animation for %s" % parent.name)

func stop_special_move():
	if is_powerkk or is_spnk or is_fireball or is_super or is_dp:
		is_powerkk = false
		is_spnk = false
		is_fireball = false
		is_super = false
		is_dp = false
		is_spmove = false
		is_special_moving = false
		is_spmove_animation_playing = false
		fireball_spawn_timer = 0.0
		super_timer = 0.0
		super_jump_timer = 0.0
		dp_timer = 0.0
		dp_jump_timer = 0.0
		powerkk_timer = 0.0
		spnk_timer = 0.0
		has_jumped_in_super = false
		has_jumped_in_dp = false
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
		if "is_facing_locked" in parent:
			parent.is_facing_locked = false
		parent.force_update_facing_direction()
		sprite.scale.x = abs(sprite.scale.x) * sign(parent.facing_direction)
		parent.fixed_velocity.x = 0
		if parent.is_jumping and parent.fixed_position.y >= world.FLOOR_Y:
			parent.is_jumping = false
			parent.fixed_velocity.y = 0
			parent.fixed_position.y = world.FLOOR_Y
		if "is_special_moving" in parent:
			parent.is_special_moving = false

		var special_call_player = parent.get_node_or_null("SpecialCallPlayer")
		var fireball_call_player = parent.get_node_or_null("FireballCallPlayer")
		var tween = create_tween()
		tween.set_parallel(true)
		const FADE_OUT_DURATION: float = 0.1
		const MIN_VOLUME_DB: float = -80.0
		const INITIAL_VOLUME_DB: float = 0.0

		if special_call_player and special_call_player.playing:
			tween.tween_property(special_call_player, "volume_db", MIN_VOLUME_DB, FADE_OUT_DURATION)
			tween.tween_callback(func():
				special_call_player.stop()
				special_call_player.volume_db = INITIAL_VOLUME_DB
			).set_delay(FADE_OUT_DURATION)
			print("Debug: Fading out and resetting SpecialCallPlayer for %s" % parent.name)

		if fireball_call_player and fireball_call_player.playing:
			tween.tween_property(fireball_call_player, "volume_db", MIN_VOLUME_DB, FADE_OUT_DURATION)
			tween.tween_callback(func():
				fireball_call_player.stop()
				fireball_call_player.volume_db = INITIAL_VOLUME_DB
			).set_delay(FADE_OUT_DURATION)
			print("Debug: Fading out and resetting FireballCallPlayer for %s" % parent.name)

		print("Debug: Special move stopped for %s, facing_direction=%s, parent.scale.x=%s, sprite.scale.x=%s, position=%s, is_facing_locked=%s, is_jumping=%s" % [parent.name, parent.facing_direction, parent.scale.x, sprite.scale.x, parent.global_position, parent.is_facing_locked if "is_facing_locked" in parent else false, parent.is_jumping])

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
	
	if input_data.super_pressed and not parent.is_attacking and not is_spmove and player_id == "p1":
		start_super()
		return true
	
	if input_data.dp_pressed and not parent.is_attacking and not is_spmove and player_id == "p1":
		start_dp()
		return true
	
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
		parent.attack_type = "fireball"
		fireball_initial_facing = parent.facing_direction
		fireball_initial_parent_scale_x = parent.scale.x
		fireball_initial_sprite_scale_x = sprite.scale.x
		if "is_special_moving" in parent:
			parent.is_special_moving = true
		if "is_facing_locked" in parent:
			parent.is_facing_locked = true
		parent.fixed_velocity = Vector2i(0, 0)
		parent.fixed_position.y = world.FLOOR_Y
		animation_player.play("fireball")
		var hitbox_pos = parent.get_node("Hitbox").global_position if parent.has_node("Hitbox") else Vector2.ZERO
		print("Debug: Fireball triggered for %s, current_damage=%s, attack_type=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, Hitbox global_position: (%s, %s), is_crouching=%s" % [parent.name, fireball_damage, parent.attack_type, fireball_initial_facing, parent.scale.x, sprite.scale.x, hitbox_pos.x, hitbox_pos.y, parent.is_crouching])
		is_spmove_animation_playing = true

		var fireball_call_player = parent.get_node_or_null("FireballCallPlayer")
		if fireball_call_player:
			fireball_call_player.volume_db = 0.0
			fireball_call_player.play()
			print("Debug: Fireball call sound played for %s (volume_db=%s)" % [parent.name, fireball_call_player.volume_db])
		else:
			print("Warning: FireballCallPlayer not found for %s" % parent.name)

		return true
	
	if input_data.spm1_pressed and not parent.is_attacking and not is_powerkk and not is_spnk and not is_fireball:
		if player_id == "p1":
			start_powerkk()
			return true
		elif player_id == "p2":
			start_spnk()
			return true
	
	if is_dp:
		dp_timer -= delta
		dp_jump_timer -= delta
		var delta_move = int(parent.fixed_velocity.x * delta)
		parent.fixed_position.x += delta_move
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		if dp_jump_timer <= 0.0 and not parent.is_jumping and parent.fixed_position.y == world.FLOOR_Y and not has_jumped_in_dp:
			parent.fixed_velocity.y = int(dp_vertical_speed * world.SIMULATION_SCALE)
			parent.fixed_position.y = world.FLOOR_Y - 1
			parent.is_jumping = true
			has_jumped_in_dp = true
			print("Debug: DP jump triggered for %s at dp_jump_timer=%.2f" % [parent.name, dp_jump_timer])
		
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
				parent.is_jumping = false
		
		if dp_timer <= 0:
			stop_special_move()
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
	
	if is_super:
		super_timer -= delta
		super_jump_timer -= delta
		var delta_move = int(parent.fixed_velocity.x * delta)
		parent.fixed_position.x += delta_move
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		if super_jump_timer <= 0.0 and not parent.is_jumping and parent.fixed_position.y == world.FLOOR_Y and not has_jumped_in_super:
			parent.fixed_velocity.y = int(super_jump_vertical_speed * world.SIMULATION_SCALE)
			parent.fixed_position.y = world.FLOOR_Y - 1
			parent.is_jumping = true
			has_jumped_in_super = true
			print("Debug: Super jump triggered for %s at super_jump_timer=%.2f, fixed_velocity.y=%s" % [parent.name, super_jump_timer, parent.fixed_velocity.y])
		
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(super_gravity * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
				parent.is_jumping = false
				print("Debug: Super landed for %s at super_timer=%.2f" % [parent.name, super_timer])
		
		if super_timer <= 0:
			stop_special_move()
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
	if (anim_name == "spnk" or anim_name == "powerkk" or anim_name == "fireball" or anim_name == "super" or anim_name == "dp") and is_spmove_animation_playing:
		is_spmove_animation_playing = false
		if "is_special_moving" in parent:
			parent.is_special_moving = false
		if (anim_name == "spnk" and spnk_timer > 0) or (anim_name == "powerkk" and powerkk_timer > 0) or (anim_name == "fireball" and fireball_timer > 0) or (anim_name == "super" and super_timer > 0) or (anim_name == "dp" and dp_timer > 0):
			print("Debug: Animation %s finished but timer still active for %s, skipping stop_special_move" % [anim_name, parent.name])
			return
		stop_special_move()
		parent.force_update_facing_direction()
		print("Debug: Animation %s finished for %s, facing_direction=%s, parent.scale.x=%s, sprite.scale.x=%s" % [anim_name, parent.name, parent.facing_direction, parent.scale.x, sprite.scale.x])

func _process(delta: float):
	if is_spmove_animation_playing and animation_player and animation_player.is_playing():
		var current_anim = animation_player.current_animation
		var current_time = animation_player.current_animation_position
		print("Debug: Playing animation %s at %.2f seconds for %s" % [current_anim, current_time, parent.name])

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	var player_id = parent.player_id if "player_id" in parent else "p1"
	var target_node = null
	for player in get_tree().get_nodes_in_group("players"):
		if player.name == target:
			target_node = player
			break
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
	elif is_dp:
		if is_blocked:
			is_dp_penetrable = false
			print("Debug: DP hit blocked by %s, is_dp_penetrable=false" % target)
		else:
			is_dp_penetrable = true
			print("Debug: DP hit %s (not blocked), is_dp_penetrable=true, relying on player.gd for knockfly handling" % target)

func get_special_damage() -> float:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p1" and is_powerkk:
		return powerkk_damage
	elif player_id == "p2" and is_spnk:
		return spnk_damage
	elif is_fireball:
		return fireball_damage
	elif is_super:
		return super_damage
	elif is_dp:
		return dp_damage
	return 0.0
