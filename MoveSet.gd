# MoveSet.gd
class_name MoveSet extends Node

@export var is_powerkk_penetrable: bool = false
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
@export var dp_duration: float = 0.9
@export var dp_jump_delay: float = 0.0667
@export var dp_horizontal_move: float = 30.0
@export var dp_vertical_speed: float = -700.0
@export var dp_damage: float = 5.0
@export var dp_knockfly_vertical_speed: float = -950.0
@export var dp_knockfly_gravity: float = 4000000.0
@export var dp_hitstun: float = 0.65
@export var dp_knockfly_horizontal_speed: float = 100.0

# Core flags
var is_super: bool = false
var is_powerkk: bool = false
var is_spnk: bool = false
var is_fireball: bool = false
var is_dp: bool = false
var is_spmove: bool = false
var is_special_moving: bool = false
var is_spmove_animation_playing: bool = false
var is_hdk: bool = false

# Timers
var super_timer: float = 0.0
var super_jump_timer: float = 0.0
var dp_timer: float = 0.0
var dp_jump_timer: float = 0.0
var fireball_timer: float = 0.0
var fireball_spawn_timer: float = 0.0
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var hdk_timer: float = 0.0             # ← 新增：hdk 專用計時器

# Jump flags
var has_jumped_in_super: bool = false
var has_jumped_in_dp: bool = false

# Damage values
var powerkk_damage: float = 12.0
var spnk_damage: float = 12.0
var fireball_damage: float = 10.0
var super_damage: float = 5.0

# Move distances
var powerkk_move_distance: float = 100.0
var spnk_move_distance: float = 90.0

# Freeze
var super_freeze_time: float = 0.3

# Animation lengths (fallback)
var powerkk_time: float = 0.933
var spnk_time: float = 1.2
var fireball_time: float = 0.3

# Initial state caches
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var fireball_initial_facing: float = 0.0
var dp_initial_facing: float = 0.0
var super_initial_facing: float = 0.0
var powerkk_initial_parent_scale_x: float = 0.0
var powerkk_initial_sprite_scale_x: float = 0.0
var spnk_initial_parent_scale_x: float = 0.0
var spnk_initial_sprite_scale_x: float = 0.0
var fireball_initial_parent_scale_x: float = 0.0
var fireball_initial_sprite_scale_x: float = 0.0

@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

# Debug toggle
const DEBUG: bool = false
func dprint(msg: String) -> void:
	if DEBUG: print(msg)

func _ready() -> void:
	if not parent or not hitbox or not animation_player or not sprite:
		push_warning("MoveSet initialization failed: missing required nodes")
	
	if animation_player:
		# ← 修改：檢查清單加 hdk（檢查動畫衝突）
		for anim_name in ["powerkk", "spnk", "fireball", "super", "dp", "hdk"]:
			if animation_player.has_animation(anim_name):
				var anim = animation_player.get_animation(anim_name)
				for i in anim.get_track_count():
					var path = anim.track_get_path(i)
					if path.get_subname_count() > 0 and path.get_subname(0) == "Sprite2D:transform/scale.x":
						push_warning("Animation '%s' modifies Sprite2D scale.x — may conflict with code" % anim_name)
		if not animation_player.animation_finished.is_connected(_on_spmove_animation_finished):
			animation_player.animation_finished.connect(_on_spmove_animation_finished)
	
	if parent.has_signal("hit_detected"):
		parent.hit_detected.connect(_on_hit_detected)
	
	is_special_moving = false
	var special_player = parent.get_node_or_null("SpecialCallPlayer")
	var fireball_player = parent.get_node_or_null("FireballCallPlayer")
	if special_player: special_player.volume_db = 0.0
	if fireball_player: fireball_player.volume_db = 0.0

# === Generic special move starter (no sound) ===
func _start_special(
	move_name: String,
	player_id_req: String,   # "*" = ignore player_id check
	damage: float,
	default_duration: float,
	move_distance: float,
	jump_delay: float = 0.0,
	jump_speed: float = 0.0,
	is_freeze: bool = false,
	is_projectile: bool = false
) -> void:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	
	# Skip player_id check when "*" is used
	if player_id_req != "*" and player_id != player_id_req:
		return
	if parent.is_attacking or is_spmove:
		return
	
	# Set core flags
	set("is_" + move_name, true)
	is_spmove = true
	is_special_moving = true
	is_spmove_animation_playing = true
	
	# Duration
	var duration = default_duration
	if animation_player and animation_player.has_animation(move_name):
		duration = max(animation_player.get_animation(move_name).length, 0.016)
	set(move_name + "_time", duration)
	set(move_name + "_timer", duration)
	
	# Damage & type
	parent.current_damage = damage
	parent.attack_type = move_name
	
	# Facing & scale cache
	set(move_name + "_initial_facing", parent.facing_direction)
	set(move_name + "_initial_parent_scale_x", parent.scale.x)
	set(move_name + "_initial_sprite_scale_x", sprite.scale.x)
	
	# Lock facing
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	if "is_special_moving" in parent:
		parent.is_special_moving = true
	
	# Movement
	var world = get_tree().get_first_node_in_group("world")
	if world:
		if move_distance > 0:
			parent.fixed_velocity.x = int((move_distance / duration) * world.SIMULATION_SCALE * parent.facing_direction)
		else:
			parent.fixed_velocity = Vector2i.ZERO
	else:
		parent.fixed_velocity = Vector2i.ZERO
	
	# Animation
	animation_player.play(move_name)
	if is_freeze:
		freeze_game(super_freeze_time)
	
	# Jump setup
	if jump_delay > 0:
		set(move_name + "_jump_timer", jump_delay)
		set("has_jumped_in_" + move_name, false)
	
	# Projectile-specific
	if is_projectile:
		fireball_spawn_timer = fireball_spawn_delay
		parent.fixed_position.y = world.FLOOR_Y
	
	dprint("Special %s triggered for %s" % [move_name, parent.name])

# === Play sound helper ===
func _play_special_sound(is_projectile: bool) -> void:
	var player = parent.get_node_or_null("FireballCallPlayer" if is_projectile else "SpecialCallPlayer")
	if player:
		player.volume_db = 0.0
		player.play()

# === Individual starters ===
func start_powerkk() -> void:
	_start_special("powerkk", "p1", powerkk_damage, 0.933, powerkk_move_distance)
	_play_special_sound(false)

func start_spnk() -> void:
	_start_special("spnk", "p2", spnk_damage, 1.2, spnk_move_distance)
	_play_special_sound(false)

func start_super() -> void:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id != "p1" or is_super or parent.is_attacking: return
	_start_special("super", "p1", super_damage, super_duration, super_move_distance, super_jump_delay, super_jump_vertical_speed, true)
	super_initial_facing = parent.facing_direction

func start_dp() -> void:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id != "p1" or is_dp or parent.is_attacking: return
	_start_special("dp", "p1", dp_damage, dp_duration, dp_horizontal_move, dp_jump_delay, dp_vertical_speed)
	dp_initial_facing = parent.facing_direction
	is_dp_penetrable = true

func start_hdk() -> void:
	_start_special("hdk", "p2", 5.0, 1.1, 50.0)
	is_hdk = true                   # 這一行決定動畫能不能切！
	_play_special_sound(false)

# === Fireball starter (P1 & P2 both allowed) ===
func _start_fireball() -> void:
	if parent.is_attacking or is_fireball or is_powerkk or is_spnk: return
	_start_special("fireball", "*", fireball_damage, 0.3, 0.0, 0.0, 0.0, false, true)
	_play_special_sound(true)

# === Freeze logic ===
func freeze_game(duration: float) -> void:
	var tween = create_tween().set_ignore_time_scale(true)
	Engine.time_scale = 0.0
	tween.tween_interval(duration)
	tween.tween_property(Engine, "time_scale", 1.0, 0.1)
	tween.tween_callback(resume_after_freeze)

func resume_after_freeze() -> void:
	if animation_player and animation_player.current_animation == "super":
		animation_player.play()

# === Stop all special moves ===
func stop_special_move() -> void:
	if not (is_powerkk or is_spnk or is_fireball or is_super or is_dp or is_hdk): return  # ← 修改：加 is_hdk 檢查
	
	is_powerkk = false
	is_spnk = false
	is_fireball = false
	is_super = false
	is_dp = false
	is_hdk = false
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
	hdk_timer = 0.0             # ← 新增：復歸 hdk 計時器
	has_jumped_in_super = false
	has_jumped_in_dp = false
	
	var final_pos = sprite.position
	animation_player.stop()
	sprite.position = Vector2.ZERO
	var world = get_tree().get_first_node_in_group("world")
	if world:
		parent.fixed_position.x += int(final_pos.x * world.SIMULATION_SCALE)
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
	else:
		parent.global_position.x += final_pos.x
	
	if "is_facing_locked" in parent: parent.is_facing_locked = false
	if "is_special_moving" in parent: parent.is_special_moving = false
	parent.force_update_facing_direction()
	sprite.scale.x = abs(sprite.scale.x) * sign(parent.facing_direction)
	parent.fixed_velocity.x = 0
	
	if parent.is_jumping and parent.fixed_position.y >= world.FLOOR_Y:
		parent.is_jumping = false
		parent.fixed_velocity.y = 0
		parent.fixed_position.y = world.FLOOR_Y
	
	var tween = create_tween().set_parallel(true)
	const FADE: float = 0.1
	const MIN_DB: float = -80.0
	const INIT_DB: float = 0.0
	for node_name in ["SpecialCallPlayer", "FireballCallPlayer"]:
		var player = parent.get_node_or_null(node_name)
		if player and player.playing:
			tween.tween_property(player, "volume_db", MIN_DB, FADE)
			tween.tween_callback(func():
				player.stop()
				player.volume_db = INIT_DB
			).set_delay(FADE)

# === Main process ===
func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if parent.is_hit or parent.is_knockfly:
		if is_spmove: stop_special_move()
		return false
	if not is_valid_state: return false
	
	var player_id = parent.player_id if "player_id" in parent else "p1"
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		push_warning("World node missing")
		return false
	
	# Input triggers
	if input_data.get("super_pressed", false) and not parent.is_attacking and not is_spmove and player_id == "p1":
		start_super(); return true
	if input_data.get("dp_pressed", false) and not parent.is_attacking and not is_spmove and player_id == "p1":
		start_dp(); return true
	
	# Fireball: P1 & P2 both allowed
	if input_data.get("spm2_pressed", false) and not parent.is_attacking and not (is_fireball or is_powerkk or is_spnk):
		_start_fireball(); return true
	
	if input_data.get("spm1_pressed", false) and not parent.is_attacking and not (is_powerkk or is_spnk or is_fireball):
		if player_id == "p1": start_powerkk()
		elif player_id == "p2": start_spnk()
		return true
	if input_data.get("spm3_pressed", false) and player_id == "p2" and not parent.is_attacking and not is_spmove:
		start_hdk()                    # ← 呼叫我們新寫的函數
		return true
	
	# === DP ===
	if is_dp:
		dp_timer -= delta; dp_jump_timer -= delta
		parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		if dp_jump_timer <= 0 and not parent.is_jumping and parent.fixed_position.y == world.FLOOR_Y and not has_jumped_in_dp:
			parent.fixed_velocity.y = int(dp_vertical_speed * world.SIMULATION_SCALE)
			parent.fixed_position.y = world.FLOOR_Y - 1
			parent.is_jumping = true
			has_jumped_in_dp = true
		
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
				parent.is_jumping = false
		
		if dp_timer <= 0: stop_special_move()
		return true
	
	# === Fireball ===
	if is_fireball:
		fireball_timer -= delta; fireball_spawn_timer -= delta
		if fireball_spawn_timer <= 0 and fireball_spawn_timer > -delta:
			var scene_path = "res://P1_fireball.tscn" if player_id == "p1" else "res://P2_fireball.tscn"
			var fb = load(scene_path).instantiate()
			fb.direction = parent.facing_direction
			fb.owner_id = player_id
			fb.global_position = parent.global_position + Vector2(fireball_x_offset * parent.facing_direction, fireball_y_offset)
			get_tree().current_scene.add_child(fb)
		if fireball_timer <= 0: stop_special_move()
		return true
	
	# === Super ===
	if is_super:
		super_timer -= delta; super_jump_timer -= delta
		parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		if super_jump_timer <= 0 and not parent.is_jumping and parent.fixed_position.y == world.FLOOR_Y and not has_jumped_in_super:
			parent.fixed_velocity.y = int(super_jump_vertical_speed * world.SIMULATION_SCALE)
			parent.fixed_position.y = world.FLOOR_Y - 1
			parent.is_jumping = true
			has_jumped_in_super = true
		
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(super_gravity * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
				parent.is_jumping = false
		
		if super_timer <= 0: stop_special_move()
		return true
	
	# === PowerKK / Spnk ===
	if is_powerkk or is_spnk:
		var timer_ref = powerkk_timer if is_powerkk else spnk_timer
		
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
		
		parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		timer_ref -= delta
		if is_powerkk: powerkk_timer = timer_ref
		else: spnk_timer = timer_ref
		
		if timer_ref <= 0: stop_special_move()
		return true
	
	# === 新增：hdk 持續處理（跟 spnk 一樣，沒跳躍） ===
	if is_hdk:
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
		
		parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		hdk_timer -= delta
		if hdk_timer <= 0: stop_special_move()
		return true
	
	return false

# === Animation finished ===
func _on_spmove_animation_finished(anim_name: String) -> void:
	# ← 修改：檢查清單加 hdk（讓動畫播完能自動結束）
	if anim_name in ["powerkk", "spnk", "fireball", "super", "dp", "hdk"] and is_spmove_animation_playing:
		is_spmove_animation_playing = false
		if "is_special_moving" in parent: parent.is_special_moving = false
		
		var timer = get(anim_name + "_timer")
		if timer > 0: return
		
		stop_special_move()
		parent.force_update_facing_direction()

# === Hit detection ===
func _on_hit_detected(_target: String, _stun: float, is_blocked: bool, _was_stun: bool) -> void:
	if is_spnk:
		is_spnk_penetrable = not is_blocked
	elif is_fireball:
		is_fireball_penetrable = not is_blocked
	elif is_dp:
		is_dp_penetrable = not is_blocked

# === Damage getter ===
func get_special_damage() -> float:
	var pid = parent.player_id if "player_id" in parent else "p1"
	if pid == "p1" and is_powerkk: return powerkk_damage
	if pid == "p2" and is_spnk: return spnk_damage
	if is_fireball: return fireball_damage
	if is_super: return super_damage
	if is_dp: return dp_damage
	return 0.0
