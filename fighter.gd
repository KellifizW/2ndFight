class_name Fighter extends Movement

signal block_detected(target: String, block_type: String)

static var PHYSICS_FPS: int = 60
const DISPLAY_FPS: int = 60

func _enter_tree() -> void:
	PHYSICS_FPS = Engine.physics_ticks_per_second   # 這裡才真正賦值

@onready var collision_shape = $Pushbox
@onready var hitbox = $Hitbox/HitShape if has_node("Hitbox/HitShape") else null
@onready var proximitybox = $Proximitybox/ProxShape if has_node("Proximitybox/ProxShape") else null

var is_being_pushed: bool = false
var current_damage: float = 0.0
@export var min_hitstun_duration: float = 8.0 / 60.0

# ── 固定幀數控制（hitstun & blockstun 都使用）──
var hitstun_frames: int = 0          # hitstun 固定幀數
var blockstun_frames: int = 0        # blockstun 固定幀數
var initial_blockstun_frames: int = 0 # 用於 push 計算
const FPS: int = 60

func sec_to_frames(seconds: float) -> int:
	return int(round(seconds * PHYSICS_FPS))

func _ready() -> void:
	super._ready()
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var collision_scale = collision_shape.scale
		colbox_half_width = collision_shape.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = collision_shape.shape.size.y * collision_scale.y / 2.0
	else:
		print("Warning: CollisionShape2D not found or invalid for %s" % name)
	
	add_to_group("players")

func _physics_process(delta: float) -> void:
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	# ── 【固定幀數 hitstun】──
	if hitstun_frames > 0:
		hitstun_frames -= 1
		is_hit = true
		if animation_state and animation_state.get_current_node() != "hit":
			animation_state.travel("hit")
		if hitstun_frames <= 0:
			print("[FIXED-FRAME HITSTUN END] %s 完全結束！" % name)
			is_hit = false
	else:
		is_hit = false

	# ── 【固定幀數 blockstun】與 hitstun 完全一致──
	if blockstun_frames > 0:
		blockstun_frames -= 1
		is_blocking = true
		if blockstun_frames <= 0:
			is_blocking = false
			block_type = "none"
			print("[FIXED-FRAME BLOCKSTUN END] %s 格擋結束！" % name)
	else:
		if blockstun_frames <= 0:
			is_blocking = false

	# ── super 先執行（舊的 block_timer 仍然會被減，但我們不再依賴它控制狀態）──
	super._physics_process(delta)

	# ── 【空中摩擦】保持舊版行為──
	if (is_knockfly or is_hit) and not is_on_floor():
		var friction_amount = int(default_air_friction * world.SIMULATION_SCALE * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)

	# ── 【攻擊輸入檢查】保持舊版──
	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping

	if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_state and not (is_hit or is_knockfly or is_blocking):
		if input_data.has("damage"):
			current_damage = input_data.damage
		else:
			current_damage = 10.0
		is_attacking = true

	# ── 【動畫更新】保持舊版邏輯──
	if is_hit or is_knockfly or is_blocking:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	else:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func post_physics_process(_delta: float) -> void:
	pass

# ── 【關鍵修復】take_hit：hitstun & blockstun 都使用固定幀數，並改用新版掉血方式──
func take_hit(
	hitstun_duration: float = 0.35,
	blockstun_duration: float = 0.267,
	damage: float = 10.0,
	skip_push: bool = false,
	force_knockfly: bool = false,
	knockfly_params: Dictionary = {}
) -> void:
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	
	print("[DEBUG] take_hit() 接收 → hitstun: %.3f, blockstun: %.3f, damage: %.1f" % [hitstun_duration, blockstun_duration, damage])
	
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove
	
	var input_data = get_input()
	
	if is_attacking:
		is_attacking = false
		if is_spmove:
			move_set.stop_special_move()
	
	# ── 格擋判斷（不變）──
	if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove:
		# ...（格擋部分保持原樣，不改動）
		is_blocking = true
		is_crouch_blocking = input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0
		var block_frames = max(sec_to_frames(blockstun_duration), sec_to_frames(min_hitstun_duration))
		blockstun_frames = block_frames
		initial_blockstun_frames = block_frames
		initial_blockstun = blockstun_duration
		block_timer = blockstun_duration
		print("[FIXED-FRAME BLOCKSTUN START] %s 進入格擋，%d 幀 (%.3f秒)" % [name, block_frames, blockstun_duration])
		fixed_velocity.x = 0
		fixed_velocity.y = 0
		if not skip_push:
			block_push_timer = initial_blockstun
			block_push_velocity = 2.0 * block_push_distance * world.SIMULATION_SCALE / initial_blockstun
		block_detected.emit(name, block_type)
		_update_animation_state(0, input_data.crouch_pressed)
		print("Debug: Block detected, no damage applied for %s" % name)
		return
	
	# ── 離開格擋狀態 ──
	if is_blocking:
		is_blocking = false
		block_type = "none"
	
	var hurt_grunt_player = $HurtGruntPlayer if has_node("HurtGruntPlayer") else null
	if hurt_grunt_player:
		hurt_grunt_player.play()
	
	if not is_on_floor():
		update_facing_direction()
	
	# ── 扣血（不變）──
	if healthbar != null:
		healthbar.current_health -= damage
		print("Debug: %s 受到 %.1f 傷害，剩餘血量 %.1f" % [name, damage, healthbar.current_health])
	else:
		print("Warning: healthbar 未設定，無法扣血（%s）" % name)
	
	var facing_mult = get_facing_multiplier()
	var should_knockfly: bool = force_knockfly or damage > 10.0 or (healthbar != null and healthbar.current_health <= 0)
	
	# ── 關鍵修正：空中受擊時，強制清除跳躍相關狀態，避免速度疊加 ──
	if not is_on_floor():
		# 取消任何正在進行的跳躍延遲或剛跳狀態
		jump_delay_timer = 0.0
		just_jumped = false
		is_jumping = false
		is_air_hit_backjump = false
		air_hit_backjump_timer = 0.0
	
	if should_knockfly:
		# ── Knockfly 專用處理 ──
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
		
		# 強制設定垂直速度（避免任何殘留跳躍速度）
		fixed_velocity.y = int(params.vertical_speed * world.SIMULATION_SCALE)
		fixed_position.y -= 1
		
		# 記錄並打印垂直速度來源
		var final_vertical = params.vertical_speed * world.SIMULATION_SCALE
		print("[KNOCKFLY VERTICAL SPEED] %s 被擊飛 → 垂直速度 = %d (原始: %.1f * SIMULATION_SCALE %.1f)" % [
			name, final_vertical, params.vertical_speed, world.SIMULATION_SCALE
		])
		
		is_jumping = true
		
		if not skip_push:
			knockfly_velocity_x = -knockfly_horizontal_speed * world.SIMULATION_SCALE * facing_mult
		
		_update_animation_state(0, input_data.crouch_pressed)
		
	else:
		# ── 普通空中受擊 → 只觸發後跳，不會進入 knockfly ──
		is_hit = true
		var hit_frames = max(sec_to_frames(hitstun_duration), sec_to_frames(min_hitstun_duration))
		hitstun_frames = hit_frames
		initial_hitstun = hitstun_duration
		hit_timer = initial_hitstun
		print("[FIXED-FRAME HITSTUN START] %s 進入 hit，%d 幀 (%.3f秒)" % [name, hit_frames, hitstun_duration])
		
		# 空中普通攻擊：強制使用後跳邏輯
		is_air_hit_backjump = true
		air_hit_backjump_timer = air_hit_backjump_duration
		fixed_velocity.x = int(-air_hit_backjump_speed * world.SIMULATION_SCALE * facing_mult)
		fixed_velocity.y = int(air_hit_backjump_up_speed * world.SIMULATION_SCALE)  # 只用後跳上升速度
		is_immune_to_floor_snap = true
		floor_snap_immunity_timer = floor_snap_immunity_duration
		fixed_position.y -= 2
		
		_update_animation_state(0, input_data.crouch_pressed)

func take_knockfly() -> void:
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
		is_knockfly = true
		knockfly_timer = max(default_knockfly_duration, min_hitstun_duration)
		_update_animation_state(0, is_crouching)

func get_contact_point(hit_area: Area2D, hurt_area: Area2D) -> Vector2:
	var hit_shape_node = hit_area.get_node_or_null("HitShape") as CollisionShape2D
	var hurt_shape_node = hurt_area.get_node_or_null("HurtShape") as CollisionShape2D

	if not hit_shape_node or not hurt_shape_node or not (hit_shape_node.shape is RectangleShape2D) or not (hurt_shape_node.shape is RectangleShape2D):
		return (hit_area.global_position + hurt_area.global_position) / 2.0

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
		return Vector2(median_x, median_y)

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.set_shape(hit_shape_node.shape)
	query.transform = hit_shape_node.global_transform
	query.collision_mask = hurt_area.collision_layer
	var result = space_state.intersect_shape(query, 1)
	if result and result.size() > 0 and result[0].has("point"):
		return result[0].point

	return (hit_area.global_position + hurt_area.global_position) / 2.0

func is_in_hitstun() -> bool:
	return hitstun_frames > 0

func is_in_blockstun() -> bool:
	return blockstun_frames > 0
