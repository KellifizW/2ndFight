class_name MoveSet extends Node

<<<<<<< HEAD
# ============================================================
# Move data is now loaded from .tres files (data-driven)
# No need for MoveData class - we use SpecialMoveData Resource
# ============================================================

# ============================================================
# RUNTIME STATE - Only track active move states
# ============================================================

class MoveState:
	var active_move: SpecialMoveData  # Now uses SpecialMoveData Resource
	var timer: float = 0.0
	var jump_timer: float = 0.0
	var has_jumped: bool = false
	var initial_facing: float = 0.0
	var initial_parent_scale_x: float = 0.0
	var initial_sprite_scale_x: float = 0.0
	var spawn_timer: float = 0.0  # For projectiles
	
	func reset() -> void:
		active_move = null
		timer = 0.0
		jump_timer = 0.0
		has_jumped = false

# ============================================================
# MOVE DEFINITIONS
# ============================================================

var move_library: Dictionary = {}
var current_move_state: MoveState = MoveState.new()

=======
@export var is_powerkk_penetrable: bool = false
@export var is_spnk_penetrable: bool = true
@export var is_fireball_penetrable: bool = true
@export var is_dp_penetrable: bool = true
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
@export var fireball_y_offset: float = -40.0
@export var fireball_x_offset: float = 40.0
@export var fireball_spawn_delay: float = 0.2667
@export var super_duration: float = 2.6
@export var super_move_distance: float = 200.0
@export var super_gravity: float = 200000.0
@export var super_jump_delay: float = 0.9
@export var super_jump_vertical_speed: float = -210.0
@export var dp_duration: float = 0.9
@export var dp_jump_delay: float = 0.0667
@export var dp_horizontal_move: float = 100.0
@export var dp_vertical_speed: float = -2000.0
@export var dp_damage: float = 5.0
@export var dp_knockfly_vertical_speed: float = -2500.0
@export var dp_knockfly_gravity: float = 6000000.0
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
var hdk_timer: float = 0.0

# Jump flags
var has_jumped_in_super: bool = false
var has_jumped_in_dp: bool = false

# Damage values
var powerkk_damage: float = 12.0
var spnk_damage: float = 12.0
var fireball_damage: float = 10.0
var super_damage: float = 5.0
var hdk_damage: float = 15.0  # ← 新增 HDK 傷害，可自行調整

# Knockback distances (special moves)
var powerkk_knockback: float = 300.0
var spnk_knockback: float = 280.0
var fireball_knockback: float = 150.0
var super_knockback: float = 200.0
var dp_knockback: float = 320.0
var hdk_knockback: float = 290.0

# Move distances
var powerkk_move_distance: float = 300.0
var spnk_move_distance: float = 250.0
var hdk_move_distance: float = 200.0  # ← 新增 HDK 前衝距離，可自行調整

# Freeze
var super_freeze_time: float = 0.3

# Animation lengths (fallback)
var powerkk_time: float = 0.933
var spnk_time: float = 1.2
var fireball_time: float = 0.3
var hdk_time: float = 1.1  # ← HDK 預設持續時間，可自行調整

# Initial state caches
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var fireball_initial_facing: float = 0.0
var dp_initial_facing: float = 0.0
var super_initial_facing: float = 0.0
var hdk_initial_facing: float = 0.0
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

func _ready() -> void:
<<<<<<< HEAD
	var player_name = parent.name if parent else "unknown"
	print("[MoveSet._ready] Initializing MoveSet for player: %s" % player_name)
	_initialize_move_library()
	
=======
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
	if not parent or not hitbox or not animation_player or not sprite:
		push_warning("MoveSet initialization failed: missing required nodes")
	
	if animation_player:
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

<<<<<<< HEAD
func _initialize_move_library() -> void:
	print("[MoveSet._initialize_move_library] Loading moves from MovesDatabase...")
	
	# Load all special moves from MovesDatabase (data-driven approach)
	var moves_database = load("res://data/MovesDatabase.gd")
	var all_moves = moves_database.get_all_moves()
	
	var loaded_count = 0
	for move_name in all_moves.keys():
		var move_data = all_moves[move_name]
		
		if move_data == null:
			print("[MoveSet._initialize_move_library] [%s] ERROR: null data" % move_name)
			continue
		
		if move_data is SpecialMoveData:
			move_library[move_name] = move_data
			loaded_count += 1
			print("[MoveSet._initialize_move_library] [%s] SUCCESS loaded" % move_name)
		else:
			print("[MoveSet._initialize_move_library] [%s] ERROR: wrong type %s" % [move_name, move_data.get_class()])
	
	print("[MoveSet._initialize_move_library] Done: %d/6 loaded. Keys: %s" % [loaded_count, move_library.keys()])

# ============================================================
# START SPECIAL MOVE (Generic, handles ALL moves)
# ============================================================

func _start_special(move_name: String) -> void:
	print("[MoveSet._start_special] Starting move: %s" % move_name)
	print("[MoveSet._start_special] move_library contents: %s" % move_library.keys())
	
	if move_name not in move_library:
		push_error("Move '%s' not found in move library. Available moves: %s" % [move_name, move_library.keys()])
		return
	
	var move_data: SpecialMoveData = move_library[move_name]
	print("[MoveSet._start_special] Loaded move_data: %s (type: %s)" % [move_data, move_data.get_class()])
	
=======
# === Generic special move starter (no sound) ===
func _start_special(
	move_name: String,
	character_id_req: String,
	damage: float,
	default_duration: float,
	move_distance: float,
	jump_delay: float = 0.0,
	jump_speed: float = 0.0,
	is_freeze: bool = false,
	is_projectile: bool = false
) -> void:
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
	var character_id = parent.character_id if "character_id" in parent else "UNKNOWN"
	print("[MoveSet._start_special] Character ID: %s, Move requires: %s" % [character_id, move_data.character_requirement])
	
	if character_id_req != "*" and character_id != character_id_req:
		print("[MoveSet] %s 嘗試使用 %s，但角色不符（需要 %s）" % [parent.name, move_name, character_id_req])
		return
	if parent.is_attacking or is_spmove:
		print("[MoveSet] %s 無法使用 %s：正在攻擊或已有特殊招" % [parent.name, move_name])
		return
	
<<<<<<< HEAD
	print("[MoveSet._start_special] All checks passed, initializing move state...")
	
	# Set up move state
=======
	set("is_" + move_name, true)
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
	is_spmove = true
	is_special_moving = true
	is_spmove_animation_playing = true
	print("[MoveSet._start_special] Set is_spmove=true, is_special_moving=true")
	
<<<<<<< HEAD
	current_move_state.active_move = move_data
	current_move_state.timer = move_data.duration
	current_move_state.jump_timer = move_data.jump_delay
	current_move_state.has_jumped = false
	current_move_state.initial_facing = parent.facing_direction
	current_move_state.initial_parent_scale_x = parent.scale.x
	current_move_state.initial_sprite_scale_x = sprite.scale.x
	print("[MoveSet._start_special] Set move state (timer=%.3f, jump_delay=%.3f)" % [current_move_state.timer, current_move_state.jump_timer])
=======
	var duration = default_duration
	if animation_player and animation_player.has_animation(move_name):
		duration = max(animation_player.get_animation(move_name).length, 0.016)
	set(move_name + "_time", duration)
	set(move_name + "_timer", duration)
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
	
	parent.current_damage = damage
	parent.attack_type = move_name
	
	set(move_name + "_initial_facing", parent.facing_direction)
	set(move_name + "_initial_parent_scale_x", parent.scale.x)
	set(move_name + "_initial_sprite_scale_x", sprite.scale.x)
	
	if "is_facing_locked" in parent:
		parent.is_facing_locked = true
	if "is_special_moving" in parent:
		parent.is_special_moving = true
	
	var world = get_tree().get_first_node_in_group("world")
	if world:
		if move_distance > 0:
			parent.fixed_velocity.x = int((move_distance / duration) * world.SIMULATION_SCALE * parent.facing_direction)
		else:
			parent.fixed_velocity = Vector2i.ZERO
	else:
		parent.fixed_velocity = Vector2i.ZERO
	
<<<<<<< HEAD
	# Play animation
	if animation_player and animation_player.has_animation(move_name):
		var anim = animation_player.get_animation(move_name)
		current_move_state.timer = anim.length
		print("[MoveSet._start_special] Animation '%s' found, length: %.3f" % [move_name, anim.length])
	else:
		print("[MoveSet._start_special] WARNING: animation_player=%s, has_animation(%s)=%s" % [animation_player != null, move_name, animation_player.has_animation(move_name) if animation_player else "N/A"])
	
	print("[MoveSet._start_special] Playing animation: %s" % move_name)
	animation_player.play(move_name)
	
	# Freeze if needed
	if move_data.is_freeze:
		freeze_game(move_data.freeze_duration)
=======
	animation_player.play(move_name)
	if is_freeze:
		freeze_game(super_freeze_time)
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
	
	if jump_delay > 0:
		set(move_name + "_jump_timer", jump_delay)
		set("has_jumped_in_" + move_name, false)
	
	if is_projectile:
		fireball_spawn_timer = fireball_spawn_delay
		parent.fixed_position.y = world.FLOOR_Y
	
	print("[MoveSet] 成功啟動 %s！角色：%s，持續時間：%.3f" % [move_name, character_id, duration])

# === Play sound helper ===
func _play_special_sound(is_projectile: bool) -> void:
	var player = parent.get_node_or_null("FireballCallPlayer" if is_projectile else "SpecialCallPlayer")
	if player:
		player.volume_db = 0.0
		player.play()

# === Individual starters ===
func start_powerkk() -> void:
	_start_special("powerkk", "DAV", powerkk_damage, powerkk_time, powerkk_move_distance)
	_play_special_sound(false)

func start_spnk() -> void:
	_start_special("spnk", "DEN", spnk_damage, spnk_time, spnk_move_distance)
	_play_special_sound(false)

func start_super() -> void:
	if parent.character_id != "DAV":
		return
	_start_special("super", "DAV", super_damage, super_duration, super_move_distance, super_jump_delay, super_jump_vertical_speed, true)
	_play_special_sound(false)

func start_dp() -> void:
	if parent.character_id != "DAV":
		return
	_start_special("dp", "DAV", dp_damage, dp_duration, dp_horizontal_move, dp_jump_delay, dp_vertical_speed)
	_play_special_sound(false)

func start_hdk() -> void:
	if parent.character_id != "DEN":
		return
	_start_special("hdk", "DEN", hdk_damage, hdk_time, hdk_move_distance)
	_play_special_sound(false)

# === Fireball starter ===
func _start_fireball() -> void:
	if parent.is_attacking or is_spmove:
		return
	_start_special("fireball", "*", fireball_damage, fireball_time, 0.0, 0.0, 0.0, false, true)
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
	if not (is_powerkk or is_spnk or is_fireball or is_super or is_dp or is_hdk):
		return
	
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
	hdk_timer = 0.0
	has_jumped_in_super = false
	has_jumped_in_dp = false
	
	animation_player.stop()
	
	if "is_facing_locked" in parent: 
		parent.is_facing_locked = false
	if "is_special_moving" in parent: 
		parent.is_special_moving = false
	
	parent.force_update_facing_direction()
	parent.fixed_velocity = Vector2i.ZERO
	
	var world = get_tree().get_first_node_in_group("world")
	if world and parent.is_jumping and parent.fixed_position.y >= world.FLOOR_Y:
		parent.is_jumping = false
		parent.fixed_velocity.y = 0
		parent.fixed_position.y = world.FLOOR_Y

# === Main process ===
func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if parent.is_hit or parent.is_knockfly:
		if is_spmove: stop_special_move()
		return false
	if not is_valid_state: return false
	
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		push_warning("World node missing")
		return false
	
	# Input triggers
<<<<<<< HEAD
	if _handle_input(input_data, world):
		return true
	
	# If no active move, nothing to process
	if not is_spmove or current_move_state.active_move == null:
		return false
	
	var move = current_move_state.active_move
	
	# Handle projectile spawning
	if move.is_projectile:
		_process_projectile_spawn(delta, world)
	
	# Handle jump logic
	if move.jump_delay > 0:
		_process_jump(delta, world, move)
	
	# Handle gravity
	if move.gravity > 0:
		_apply_gravity(delta, world, move.gravity)
	else:
		_apply_gravity(delta, world, world.GRAVITY if world else 0.0)
	
	# Update position
	parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
	parent.global_position = world.to_scaled_vector2(parent.fixed_position)
	
	# Update timer
	current_move_state.timer -= delta
	
	# Check if move is finished
	if current_move_state.timer <= 0:
		stop_special_move()
	
	return true

func _handle_input(input_data: Dictionary, _world: Node) -> bool:
	# Debug: Log what inputs we're receiving
	if input_data.get("spm1_pressed") or input_data.get("spm2_pressed") or input_data.get("spm3_pressed") or input_data.get("dp_pressed") or input_data.get("super_pressed"):
		print("[MoveSet._handle_input] Received input - spm1:%s spm2:%s spm3:%s dp:%s super:%s | is_attacking:%s is_spmove:%s" % [
			input_data.get("spm1_pressed"),
			input_data.get("spm2_pressed"),
			input_data.get("spm3_pressed"),
			input_data.get("dp_pressed"),
			input_data.get("super_pressed"),
			parent.is_attacking,
			is_spmove
		])
	
	if input_data.get("super_pressed", false) and not parent.is_attacking and not is_spmove:
		print("[MoveSet] SUPER pressed!")
		start_super()
		return true
	
	if input_data.get("dp_pressed", false) and not parent.is_attacking and not is_spmove:
		print("[MoveSet] DP pressed!")
=======
	if input_data.get("super_pressed", false) and not parent.is_attacking and not is_spmove and parent.character_id == "DAV":
		start_super()
		return true
	
	if input_data.get("dp_pressed", false) and not parent.is_attacking and not is_spmove and parent.character_id == "DAV":
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
		start_dp()
		return true
	
	if input_data.get("spm2_pressed", false):
<<<<<<< HEAD
		print("[MoveSet] SPM2 (Fireball) pressed!")
		start_fireball()
=======
		_start_fireball()
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
		return true
	
	if input_data.get("spm1_pressed", false) and not parent.is_attacking and not is_spmove:
		print("[MoveSet] SPM1 pressed! Character: %s" % parent.character_id)
		if parent.character_id == "DAV":
			start_powerkk()
		elif parent.character_id == "DEN":
			start_spnk()
		return true
	
	if input_data.get("spm3_pressed", false) and parent.character_id == "DEN" and not parent.is_attacking and not is_spmove:
		print("[MoveSet] SPM3 (HDK) pressed!")
		start_hdk()
		return true
	
	# === DP ===
	if is_dp:
		dp_timer -= delta
		dp_jump_timer -= delta
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
		
		if dp_timer <= 0:
			stop_special_move()
		return true
	
	# === Fireball ===
	if is_fireball:
		fireball_timer -= delta
		fireball_spawn_timer -= delta
		
		if fireball_spawn_timer <= 0 and fireball_spawn_timer > -delta:
			var scene_path = "res://%s_fireball.tscn" % parent.character_id
			var fireball_scene: PackedScene = load(scene_path)
			if fireball_scene == null:
				push_error("無法載入火球場景：%s（請確認檔案存在且名稱正確）" % scene_path)
				stop_special_move()
				return true
			
			var fb = fireball_scene.instantiate()
			fb.direction = parent.facing_direction
			fb.owner_character_id = parent.character_id
			fb.fireball_owner = parent
			fb.global_position = parent.global_position + Vector2(fireball_x_offset * parent.facing_direction, fireball_y_offset)
			get_tree().current_scene.add_child(fb)
			print("[MoveSet] 成功生成火球：%s，fireball_owner 已設定" % scene_path)
		
		if fireball_timer <= 0:
			stop_special_move()
		return true
	
	# === Super ===
	if is_super:
		super_timer -= delta
		super_jump_timer -= delta
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
		
		if super_timer <= 0:
			stop_special_move()
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
		if is_powerkk:
			powerkk_timer = timer_ref
		else:
			spnk_timer = timer_ref
		
		if timer_ref <= 0:
			stop_special_move()
		return true
	
	# === HDK ===
	if is_hdk:
		if parent.fixed_position.y < world.FLOOR_Y:
			parent.fixed_velocity.y += int(world.GRAVITY * delta)
			if parent.fixed_position.y >= world.FLOOR_Y:
				parent.fixed_position.y = world.FLOOR_Y
				parent.fixed_velocity.y = 0
		
		parent.fixed_position.x += int(parent.fixed_velocity.x * delta)
		parent.global_position = world.to_scaled_vector2(parent.fixed_position)
		
		hdk_timer -= delta
		if hdk_timer <= 0:
			stop_special_move()
		return true
	
	return false

<<<<<<< HEAD
func _process_projectile_spawn(delta: float, _world: Node) -> void:
	current_move_state.spawn_timer -= delta
	
	if current_move_state.spawn_timer <= 0 and current_move_state.spawn_timer > -delta:
		var scene_path = "res://%s_fireball.tscn" % parent.character_id
		var fireball_scene: PackedScene = load(scene_path)
		if fireball_scene == null:
			push_error("Cannot load fireball scene: %s" % scene_path)
			stop_special_move()
			return
		
		var fb = fireball_scene.instantiate()
		fb.direction = parent.facing_direction
		fb.owner_character_id = parent.character_id
		fb.fireball_owner = parent
		fb.global_position = parent.global_position + Vector2(fireball_x_offset * parent.facing_direction, fireball_y_offset)
		get_tree().current_scene.add_child(fb)
		print("[MoveSet] Spawned fireball: %s" % scene_path)

func _process_jump(delta: float, world: Node, move: SpecialMoveData) -> void:
	current_move_state.jump_timer -= delta
	
	if current_move_state.jump_timer <= 0 and not parent.is_jumping and parent.fixed_position.y == world.FLOOR_Y and not current_move_state.has_jumped:
		parent.fixed_velocity.y = int(move.jump_speed * world.SIMULATION_SCALE)
		parent.fixed_position.y = world.FLOOR_Y - 1
		parent.is_jumping = true
		current_move_state.has_jumped = true

func _apply_gravity(delta: float, world: Node, gravity: float) -> void:
	if parent.fixed_position.y < world.FLOOR_Y:
		parent.fixed_velocity.y += int(gravity * delta)
		if parent.fixed_position.y >= world.FLOOR_Y:
			parent.fixed_position.y = world.FLOOR_Y
			parent.fixed_velocity.y = 0
			parent.is_jumping = false
# ============================================================
# UTILITY FUNCTIONS
# ============================================================

=======
# === Animation finished ===
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
func _on_spmove_animation_finished(anim_name: String) -> void:
	if anim_name in ["powerkk", "spnk", "fireball", "super", "dp", "hdk"] and is_spmove_animation_playing:
		is_spmove_animation_playing = false
		if "is_special_moving" in parent:
			parent.is_special_moving = false
		
		var timer = get(anim_name + "_timer") if has_method("get") else 0.0
		if timer > 0:
			return
		
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
<<<<<<< HEAD
	if is_spmove and current_move_state.active_move:
		return current_move_state.active_move.damage
	return 0.0

# ============================================================
# HELPER: Get active move name
# ============================================================

func get_active_move_name() -> String:
	if is_spmove and current_move_state.active_move:
		return current_move_state.active_move.move_name
	return ""

# ============================================================
# HELPER: Check if specific move is active
# ============================================================

func is_move_active(move_name: String) -> bool:
	return is_spmove and current_move_state.active_move and current_move_state.active_move.move_name == move_name
=======
	if parent.character_id == "DAV" and is_powerkk: return powerkk_damage
	if parent.character_id == "DEN" and is_spnk: return spnk_damage
	if parent.character_id == "DEN" and is_hdk: return hdk_damage
	if is_fireball: return fireball_damage
	if is_super: return super_damage
	if is_dp: return dp_damage
	return 0.0 
>>>>>>> parent of 08bff10 (rewritemoveset1.gd)
