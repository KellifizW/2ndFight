class_name Fighter extends Movement

@onready var collision_shape = $Pushbox
@onready var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
@onready var hitbox = $Hitbox/HitShape if has_node("Hitbox/HitShape") else null
@onready var proximitybox = $Proximitybox/ProxShape if has_node("Proximitybox/ProxShape") else null

var is_being_pushed: bool = false
var current_damage: float = 0.0
@export var min_hitstun_duration: float = 8.0 / 60.0

# ── 只用固定幀數控制 hitstun，blockstun 保留舊版 timer 邏輯（確保格擋動畫正常） ──
var hitstun_frames: int = 0          # 僅 hitstun 用固定幀數
const FPS: int = 60

func sec_to_frames(seconds: float) -> int:
	return int(round(seconds * FPS))

func _ready():
	super._ready()
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var collision_scale = collision_shape.scale
		colbox_half_width = collision_shape.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = collision_shape.shape.size.y * collision_scale.y / 2.0
	else:
		print("Warning: CollisionShape2D not found or invalid for %s" % name)
	if not healthbar:
		print("Warning: Healthbar not found for %s" % name)
	add_to_group("players")

func _physics_process(delta):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	# ── 【僅 hitstun 用固定幀數】前置檢查（不影響格擋）
	if hitstun_frames > 0:
		hitstun_frames -= 1
		is_hit = true
		if animation_state and animation_state.get_current_node() != "hit":
			animation_state.travel("hit")
		if hitstun_frames % 60 == 0:
			print("[FIXED-FRAME HITSTUN] %s 剩餘 %d 幀 (%.1f秒)" % [name, hitstun_frames, hitstun_frames / 60.0])
		if hitstun_frames <= 0:
			print("[FIXED-FRAME HITSTUN END] %s 完全結束！" % name)
			is_hit = false
	else:
		is_hit = false

	# ── 【完全對齊舊版】super 先執行（block_timer 在這裡減，格擋動畫自然結束）
	super._physics_process(delta)

	# ── 【完全對齊舊版】空中摩擦
	if (is_knockfly or is_hit) and not is_on_floor():
		var friction_amount = int(default_air_friction * world.SIMULATION_SCALE * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)

	# ── 【完全對齊舊版】攻擊輸入檢查
	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping

	if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_state and not (is_hit or is_knockfly or is_blocking):
		if input_data.has("damage"):
			current_damage = input_data.damage
		else:
			current_damage = 10.0
		is_attacking = true

	# ── 【完全對齊舊版】動畫更新邏輯（格擋動畫依賴 block_timer，自然結束）
	if is_hit or is_knockfly or is_blocking:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	else:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func post_physics_process(delta):
	pass

# ── 【關鍵修復】take_hit：hitstun 用幀數，blockstun 保留舊版 timer（動畫完美） ──
func take_hit(
		hitstun_duration: float = 0.35,
		blockstun_duration: float = 0.267,
		damage: float = 10.0,
		skip_push: bool = false,
		force_knockfly: bool = false,
		knockfly_params: Dictionary = {}
):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	print("[DEBUG] take_hit() 接收 → hitstun: %.3f, blockstun: %.3f, damage: %.1f, force_knockfly: %s" % [hitstun_duration, blockstun_duration, damage, force_knockfly])

	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	var input_data = get_input()

	if is_attacking:
		is_attacking = false
	if is_spmove:
		move_set.stop_special_move()

	# ── 【完全保留舊版格擋邏輯】blockstun 用 timer（動畫自然結束）
	if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove:
		is_blocking = true
		is_crouch_blocking = input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0
		initial_blockstun = max(blockstun_duration, min_hitstun_duration)
		block_timer = initial_blockstun  # ← 舊版邏輯，確保動畫正常
		block_type = "ordinary"
		print("[BLOCKSTUN START] %s 進入 block，timer=%.3f秒" % [name, block_timer])
		
		fixed_velocity.x = 0
		fixed_velocity.y = 0
		if not skip_push:
			block_push_timer = initial_blockstun
			block_push_velocity = 2.0 * block_push_distance * world.SIMULATION_SCALE / initial_blockstun
		block_detected.emit(name, block_type)
		_update_animation_state(0, input_data.crouch_pressed)
		print("Debug: Block detected, no damage applied for %s" % name)
		return
	else:
		if is_blocking:
			is_blocking = false
			block_type = "none"

		var hurt_grunt_player = $HurtGruntPlayer if has_node("HurtGruntPlayer") else null
		if hurt_grunt_player:
			hurt_grunt_player.play()
			print("Debug: Hurt grunt sound played for %s (player_id=%s)" % [name, get("player_id") if "player_id" in self else "unknown"])

		if not is_on_floor():
			update_facing_direction()

		if healthbar:
			healthbar.take_damage(damage)
			print("Debug: Damage applied: %s to %s, current_health=%s" % [damage, name, healthbar.current_health])

		var facing_mult = get_facing_multiplier()

		if force_knockfly or damage > 10.0 or (healthbar and healthbar.current_health <= 0):
			var params = {
				"gravity": default_knockfly_gravity,
				"vertical_speed": default_knockfly_vertical_speed,
				"horizontal_speed": default_knockfly_horizontal_speed,
				"duration": default_knockfly_duration
			}
			params.merge(knockfly_params, true)

			is_knockfly = true
			knockfly_timer = max(params.duration, min_hitstun_duration)
			is_immune_to_floor_snap = true
			floor_snap_immunity_timer = floor_snap_immunity_duration
			knockfly_gravity = params.gravity
			knockfly_vertical_speed = params.vertical_speed
			knockfly_horizontal_speed = params.horizontal_speed

			fixed_velocity.y = int(params.vertical_speed * world.SIMULATION_SCALE)
			fixed_position.y -= 1
			is_jumping = true

			if not skip_push:
				knockfly_velocity_x = -knockfly_horizontal_speed * world.SIMULATION_SCALE * facing_mult

			print("Debug: Knockfly triggered for %s, force_knockfly=%s, velocity.y=%s, position.y=%s, gravity=%s, v_speed=%s, timer=%s" %
				[name, force_knockfly, fixed_velocity.y, fixed_position.y, params.gravity, params.vertical_speed, knockfly_timer])
		else:
			is_hit = true
			# ── 【僅 hitstun 用固定幀數】確保 4秒精準
			var hit_frames = max(sec_to_frames(hitstun_duration), sec_to_frames(min_hitstun_duration))
			hitstun_frames = hit_frames
			initial_hitstun = hitstun_duration  # 保留舊變數（相容 Movement）
			hit_timer = initial_hitstun
			
			print("[FIXED-FRAME HITSTUN START] %s 進入 hit，%d 幀 (%.3f秒)" % [name, hit_frames, hitstun_duration])
			
			if is_on_floor():
				if not skip_push:
					hit_push_timer = initial_hitstun
					hit_push_velocity = 2.0 * hit_push_distance * world.SIMULATION_SCALE / initial_hitstun
				fixed_velocity.x = 0
				fixed_velocity.y = 0
			else:
				is_air_hit_backjump = true
				air_hit_backjump_timer = air_hit_backjump_duration
				fixed_velocity.x = int(-air_hit_backjump_speed * world.SIMULATION_SCALE * facing_mult)
				fixed_velocity.y = int(air_hit_backjump_up_speed * world.SIMULATION_SCALE)
				is_immune_to_floor_snap = true
				floor_snap_immunity_timer = floor_snap_immunity_duration
				fixed_position.y -= 2
			print("Debug: Normal hit for %s, hitstun=%s" % [name, initial_hitstun])

	_update_animation_state(0, input_data.crouch_pressed)

func take_knockfly():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
		is_knockfly = true
		knockfly_timer = max(default_knockfly_duration, min_hitstun_duration)
		_update_animation_state(0, is_crouching)

# ── get_contact_point 完全保留舊版 ──
func get_contact_point(hit_area: Area2D, hurt_area: Area2D) -> Vector2:
	var hit_shape_node = hit_area.get_node_or_null("HitShape") as CollisionShape2D
	var hurt_shape_node = hurt_area.get_node_or_null("HurtShape") as CollisionShape2D

	if not hit_shape_node or not hurt_shape_node or not (hit_shape_node.shape is RectangleShape2D) or not (hurt_shape_node.shape is RectangleShape2D):
		print("Warning: Invalid shapes for contact point calculation in get_contact_point for %s" % name)
		return (hit_area.global_position + hurt_area.global_position) / 2.0

	var world = get_tree().get_first_node_in_group("world")
	var SIMULATION_SCALE = world.SIMULATION_SCALE if world else 1000.0
	var TOLERANCE = 2.0 * SIMULATION_SCALE

	var hit_shape_pos = hit_shape_node.global_position
	var hit_half_size = hit_shape_node.shape.extents * abs(hit_shape_node.global_scale)
	var hit_left = (hit_shape_pos.x - hit_half_size.x) * SIMULATION_SCALE
	var hit_right = (hit_shape_pos.x + hit_half_size.x) * SIMULATION_SCALE
	var hit_bottom = (hit_shape_pos.y - hit_half_size.y) * SIMULATION_SCALE
	var hit_top = (hit_shape_pos.y + hit_half_size.y) * SIMULATION_SCALE

	var hurt_shape_pos = hurt_shape_node.global_position
	var hurt_half_size = hurt_shape_node.shape.extents * abs(hurt_shape_node.global_scale)
	var hurt_left = (hurt_shape_pos.x - hurt_half_size.x) * SIMULATION_SCALE
	var hurt_right = (hurt_shape_pos.x + hurt_half_size.x) * SIMULATION_SCALE
	var hurt_bottom = (hurt_shape_pos.y - hurt_half_size.y) * SIMULATION_SCALE
	var hurt_top = (hurt_shape_pos.y + hurt_half_size.y) * SIMULATION_SCALE

	var overlap_left = max(int(hit_left), int(hurt_left))
	var overlap_right = min(int(hit_right), int(hurt_right))
	var overlap_bottom = max(int(hit_bottom), int(hurt_bottom))
	var overlap_top = min(int(hit_top), int(hurt_top))

	if overlap_left <= overlap_right + TOLERANCE and overlap_bottom <= overlap_top + TOLERANCE:
		var median_x = (overlap_left + overlap_right) / 2.0 / SIMULATION_SCALE
		var median_y = (overlap_bottom + overlap_top) / 2.0 / SIMULATION_SCALE
		var contact_point = Vector2(median_x, median_y)
		print("Debug: Contact point calculated: %s" % contact_point)
		return contact_point

	print("Warning: No overlap detected in get_contact_point for %s vs %s" % [hit_area.get_parent().name, hurt_area.get_parent().name])
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.set_shape(hit_shape_node.shape)
	query.transform = hit_shape_node.global_transform
	query.collision_mask = hurt_area.collision_layer
	var result = space_state.intersect_shape(query, 1)
	if result and result[0].has("point"):
		var collision_point = result[0].point
		print("Debug: Physics query found collision point: %s" % collision_point)
		return collision_point

	var hurt_left_edge = Vector2(hurt_shape_pos.x - hurt_half_size.x, hurt_shape_pos.y)
	var point_query = PhysicsPointQueryParameters2D.new()
	point_query.position = hurt_left_edge
	point_query.collision_mask = hit_area.collision_layer
	var point_result = space_state.intersect_point(point_query, 1)
	if point_result and point_result[0].has("collider"):
		var collision_point = hurt_left_edge
		print("Debug: Point query found collision at Hurtbox left edge: %s" % collision_point)
		return collision_point

	print("Warning: Physics query failed, using fallback midpoint position")
	return (hit_area.global_position + hurt_area.global_position) / 2.0
	
func is_in_hitstun() -> bool:
	return hitstun_frames > 0
