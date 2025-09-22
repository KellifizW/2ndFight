class_name Movement extends CharacterBody2D

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback")
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null

var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var walk_speed: float = 120.0
var back_speed: float = walk_speed * 0.75
var jump_horizontal_speed: float = 130.0
var jump_dir: float = 0.0
var is_jumping: bool = false
var is_dashing: bool = false
var is_backdashing: bool = false
var is_attacking: bool = false
var attack_time: float = 0.4
var attack_timer: float = 0.0
var dash_speed: float = 160.0
var backdash_speed: float = 130.0
var dash_time: float = 0.35
var backdash_time: float = 0.4
var dash_timer: float = 0.0
var double_tap_timer: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: float = 0.0
var is_crouching: bool = false
var is_hit: bool = false
var is_knockfly: bool = false
var arena_left: float = 0.0
var arena_right: float = ProjectSettings.get_setting("display/window/size/viewport_width")
var hit_timer: float = 0.0
var block_timer: float = 0.0
var knockfly_timer: float = 0.0
@export var knockfly_duration: float = 0.75
var knockfly_push_speed: float = 300.0
var knockfly_velocity_x: float = 0.0
@export var block_push_distance: float = 20.0
var block_push_timer: float = 0.0
var initial_blockstun: float = 0.0
var block_push_velocity: float = 0.0
@export var hit_push_distance: float = 20.0
var hit_push_timer: float = 0.0
var initial_hitstun: float = 0.0
var hit_push_velocity: float = 0.0
var facing_direction: float = 1.0
var dash_direction: float = 0.0
var is_blocking: bool = false
var is_holding_back: bool = false
var is_crouch_blocking: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false
var air_hit_knockfly_distance: float = 10.0
var is_air_hit_knockfly: bool = false
var is_push_back: bool = false
var push_back_timer: float = 0.0
var initial_push_back: float = 0.0
var push_back_velocity: float = 0.0
var knockfly_accumulated_distance: float = 0.0
var knockfly_max_distance: float = 150.0

signal block_detected(target: String, block_type: String)

func _ready():
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	if has_node("Pushbox") and $Pushbox.shape is RectangleShape2D:
		var collision_scale = $Pushbox.scale
		colbox_half_width = $Pushbox.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = $Pushbox.shape.size.y * collision_scale.y / 2.0
	if has_node("Hurtbox"):
		$Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		$Hurtbox.area_exited.connect(_on_hurtbox_area_exited)
	if animation_player:
		animation_player.speed_scale = 1.0
	prev_position = global_position
	update_facing_direction()

func _physics_process(delta):
	var current_position = global_position
	var is_landing = self is Player and get("is_landing") if is_class("Player") else false
	if is_push_back:
		if push_back_timer > 0:
			if not is_landing:
				update_facing_direction()
			velocity.x = -push_back_velocity * facing_direction
			push_back_timer -= delta
			if push_back_timer <= 0:
				is_push_back = false
				push_back_velocity = 0.0
				initial_push_back = 0.0
				velocity.x = 0
	if neutral_timer > 0:
		neutral_timer -= delta
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			is_attacking = false
	if hit_timer > 0:
		hit_timer -= delta
		if hit_push_timer > 0:
			velocity.x = -hit_push_velocity * facing_direction * (hit_push_timer / initial_hitstun)
			hit_push_timer -= delta
		if hit_timer <= 0:
			is_hit = false
			hit_push_timer = 0.0
			hit_push_velocity = 0.0
			initial_hitstun = 0.0
	if block_timer > 0:
		block_timer -= delta
		if block_push_timer > 0:
			velocity.x = -block_push_velocity * facing_direction * (block_push_timer / initial_blockstun)
			block_push_timer -= delta
		if block_timer <= 0:
			is_blocking = false
			is_crouch_blocking = false
			block_type = "none"
			block_push_timer = 0.0
			block_push_velocity = 0.0
			initial_blockstun = 0.0
	if knockfly_timer > 0:
		knockfly_timer -= delta
		if is_air_hit_knockfly:
			velocity.x = knockfly_velocity_x * (knockfly_timer / knockfly_duration)
		else:
			velocity.x = knockfly_velocity_x * pow(knockfly_timer / knockfly_duration, 2)
		var delta_x = abs(global_position.x - current_position.x)
		knockfly_accumulated_distance += delta_x
		if knockfly_accumulated_distance >= knockfly_max_distance:
			velocity.x = 0
			knockfly_velocity_x = 0.0
		if knockfly_timer <= 0 and is_knockfly:
			var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
			if healthbar and healthbar.current_health <= 0:
				pass
			else:
				velocity.x = 0
				knockfly_velocity_x = 0.0
				knockfly_accumulated_distance = 0.0
				if animation_player:
					animation_player.speed_scale = 1.0
	var input_data = get_input()
	var input_dir = input_data["input_dir"]
	var crouch_pressed = input_data["crouch_pressed"]
	var jump_pressed = input_data["jump_pressed"]
	is_crouching = crouch_pressed
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_powerkk = move_set.is_powerkk if move_set else false
	var is_spnk = move_set.is_spnk if move_set else false
	if is_on_floor() and not is_attacking and not is_dashing and not is_backdashing and not jump_pressed and not is_powerkk and not is_spnk:
		if input_dir * facing_direction < 0:
			is_holding_back = true
		else:
			is_holding_back = false
		if crouch_pressed:
			is_crouch_blocking = (input_dir * facing_direction < 0)
		else:
			is_crouch_blocking = false
	else:
		if not (is_hit or is_knockfly):
			is_holding_back = false
			is_crouch_blocking = false
	var arena_left = 0.0
	var arena_right = ProjectSettings.get_setting("display/window/size/viewport_width")
	if is_class("Fighter"):
		var arena_left_value = get("arena_left")
		var arena_right_value = get("arena_right")
		if arena_left_value != null:
			arena_left = arena_left_value
		if arena_right_value != null:
			arena_right = arena_right_value
	var is_disabled_state = is_hit or is_knockfly or is_blocking or is_push_back
	if not is_disabled_state:
		var current_input_dir = input_dir
		if current_input_dir != last_input_dir:
			if last_input_dir == 0 and current_input_dir != 0:
				if pending_dash_dir == current_input_dir and neutral_timer > 0 and is_on_floor() and not is_crouching and not is_jumping and not is_attacking and not is_powerkk and not is_spnk:
					if current_input_dir * facing_direction > 0:
						is_dashing = true
						dash_timer = dash_time
						dash_direction = current_input_dir
						velocity.x = 0
					elif current_input_dir * facing_direction < 0:
						is_backdashing = true
						dash_timer = backdash_time
						velocity.x = 0
					pending_dash_dir = 0
					neutral_timer = 0
				else:
					pending_dash_dir = current_input_dir
					neutral_timer = 0
			elif current_input_dir == 0 and last_input_dir != 0:
				neutral_timer = double_tap_timer
			else:
				pending_dash_dir = current_input_dir
				neutral_timer = 0
			last_input_dir = current_input_dir
		if is_dashing:
			velocity.x = dash_speed * dash_direction
			dash_timer -= delta
			if dash_timer <= 0:
				is_dashing = false
				velocity.x = 0
				dash_direction = 0.0
		elif is_backdashing:
			velocity.x = backdash_speed * -facing_direction
			dash_timer -= delta
			if dash_timer <= 0:
				is_backdashing = false
				velocity.x = 0
		else:
			if is_on_floor():
				if is_crouching:
					velocity.x = 0
				elif not is_attacking and not is_powerkk and not is_spnk and input_dir != 0:
					if input_dir * facing_direction > 0:
						velocity.x = walk_speed * input_dir
					else:
						velocity.x = back_speed * input_dir
				else:
					velocity.x = 0
					jump_dir = 0.0
					is_jumping = false
			else:
				velocity.x = jump_dir * jump_horizontal_speed
	if jump_pressed and is_on_floor() and not is_crouching and not is_dashing and not is_backdashing and not is_attacking and not is_powerkk and not is_spnk and not is_disabled_state:
		jump_dir = input_dir
		velocity.y = -600
		is_jumping = true
	if not is_on_floor():
		velocity.y += 1800 * delta
	move_and_slide()
	global_position.x = clamp(global_position.x, arena_left + colbox_half_width, arena_right - colbox_half_width)
	post_physics_process(delta)
	if is_on_floor() and was_in_air and not is_landing and not (is_powerkk or is_spnk):
		update_facing_direction()
	was_in_air = not is_on_floor()
	if is_on_floor() and prev_position.x != global_position.x and not (is_powerkk or is_spnk) and not is_landing:
		update_facing_direction()
	prev_position = global_position

func get_input() -> Dictionary:
	return {}

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	pass

func update_hitbox_position():
	pass

func post_physics_process(delta):
	pass

func get_facing_multiplier() -> float:
	return facing_direction

func get_is_dashing() -> bool:
	return is_dashing

func get_is_backdashing() -> bool:
	return is_backdashing

func get_is_attacking() -> bool:
	return is_attacking

func get_is_hit() -> bool:
	return is_hit

func get_is_knockfly() -> bool:
	return is_knockfly

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = true
		if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_blocking:
			is_blocking = true
			initial_blockstun = 0.1
			block_timer = 0.1
			block_type = "proximity"
			velocity.x = 0
			velocity.y = 0
			block_detected.emit(name, block_type)
			print("Debug: Proximity block triggered, is_holding_back=" + str(is_holding_back) + ", is_crouch_blocking=" + str(is_crouch_blocking))

func _on_hurtbox_area_exited(area: Area2D) -> void:
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false

func update_facing_direction():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_move = move_set and (move_set.is_powerkk or move_set.is_spnk)
	if is_special_move:
		return
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
			scale.x = -1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
		elif self_right < other_left:
			facing_direction = 1.0
			scale.x = 1
			scale.y = 1
			sprite.scale.x = 1.0
			rotation_degrees = 0
		update_hitbox_position()
	else:
		facing_direction = 1.0
		scale.x = 1
		scale.y = 1
		sprite.scale.x = 1.0
		rotation_degrees = 0
