class_name Fighter extends Movement

@onready var collision_shape = $Pushbox
@onready var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null
@onready var hitbox = $Hitbox/HitShape if has_node("Hitbox/HitShape") else null
@onready var proximitybox = $Proximitybox/ProxShape if has_node("Proximitybox/ProxShape") else null

var is_being_pushed: bool = false
var current_damage: float = 0.0
@export var min_hitstun_duration: float = 8.0 / 60.0

# ── 真實時間 hitstun / blockstun 變數 ──────────────────────────────
var hitstun_real_start_ms: int = 0
var hitstun_real_duration_ms: int = 0
var blockstun_real_start_ms: int = 0
var blockstun_real_duration_ms: int = 0

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
	print("Fighter %s _physics_process: is_hit=%s, hitstun_real_duration_ms=%d" % [name, is_hit, hitstun_real_duration_ms])
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	
	# 先讓父類別跑完
	super._physics_process(delta)
	
	# ── 真實時間 hitstun 檢查 ──────────────────────
	if hitstun_real_duration_ms > 0:
		var elapsed_real_ms = Time.get_ticks_msec() - hitstun_real_start_ms
		var total_duration_sec = hitstun_real_duration_ms / 1000.0
		var remaining_real_sec = max(0, (hitstun_real_duration_ms - elapsed_real_ms)) / 1000.0
		
		# 強制鎖定狀態
		is_hit = true
		if animation_state and animation_state.get_current_node() != "hit":
			animation_state.travel("hit")
		
		# 每 100ms 印一次
		if int(elapsed_real_ms) % 100 == 0:
			print("[REAL-TIME HITSTUN] %s 剩餘 %.3f 秒 (已過 %.3f/%.3f 秒)" % [name, remaining_real_sec, elapsed_real_ms/1000.0, total_duration_sec])
		
		# ★★★ 修復：先檢查再重置，避免 print 錯誤 ★★★
		if elapsed_real_ms >= hitstun_real_duration_ms:
			print("[REAL-TIME HITSTUN END] %s 真實 hitstun 結束！總計 %.3f 秒" % [name, total_duration_sec])
			is_hit = false
			hit_timer = 0.0
			hitstun_real_duration_ms = 0
			hitstun_real_start_ms = 0
			if animation_state:
				animation_state.travel("Walk")
	
	# ── blockstun 檢查 ──────────────────────
	if is_blocking and blockstun_real_duration_ms > 0:
		var elapsed_real_ms = Time.get_ticks_msec() - blockstun_real_start_ms
		var total_block_duration = blockstun_real_duration_ms / 1000.0
		if elapsed_real_ms >= blockstun_real_duration_ms:
			print("[REAL-TIME BLOCKSTUN END] %s 結束！總計 %.3f 秒" % [name, total_block_duration])
			is_blocking = false
			is_crouch_blocking = false
			block_timer = 0.0
			block_type = "none"
			blockstun_real_duration_ms = 0
	
	# 空中摩擦（放在最後）
	if (is_knockfly or is_hit) and not is_on_floor():
		var friction_amount = int(default_air_friction * world.SIMULATION_SCALE * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)
	
	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping
	if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_state and not (is_hit or is_knockfly or is_blocking):
		current_damage = input_data.damage
		is_attacking = true
		
func post_physics_process(delta):
	pass

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

	# ── Block 判定 ──────────────────────
	if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove:
		is_blocking = true
		is_crouch_blocking = input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0

		blockstun_real_start_ms = Time.get_ticks_msec()
		blockstun_real_duration_ms = int(blockstun_duration * 1000)
		initial_blockstun = max(blockstun_duration, min_hitstun_duration)
		block_timer = initial_blockstun
		block_type = "ordinary"

		print("[REAL-TIME BLOCKSTUN START] %s 進入 block，預計真實持續 %.3f 秒 (%d ms)" % [name, blockstun_duration, blockstun_real_duration_ms])

		fixed_velocity.x = 0
		fixed_velocity.y = 0
		if not skip_push:
			block_push_timer = initial_blockstun
			block_push_velocity = 2.0 * block_push_distance * world.SIMULATION_SCALE / initial_blockstun
		block_detected.emit(name, block_type)
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
			print("Debug: Knockfly triggered for %s, force_knockfly=%s" % [name, force_knockfly])
		else:
			# ── 真實時間 hitstun ──────────────────────
			is_hit = true
			hitstun_real_start_ms = Time.get_ticks_msec()
			hitstun_real_duration_ms = int(hitstun_duration * 1000)
			initial_hitstun = max(hitstun_duration, min_hitstun_duration)
			hit_timer = initial_hitstun

			print("[REAL-TIME HITSTUN START] %s 進入 hit，預計真實持續 %.3f 秒 (%d ms)" % [name, hitstun_duration, hitstun_real_duration_ms])
			print("[FIX DEBUG] %s 設定真實 hitstun = %.3f 秒，推擠仍用遊戲時間 %.3f 秒" % [name, hitstun_duration, initial_hitstun])

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
			print("Debug: Normal hit for %s, hitstun=%.3f" % [name, initial_hitstun])

func take_knockfly():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
		is_knockfly = true
		knockfly_timer = max(default_knockfly_duration, min_hitstun_duration)

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
