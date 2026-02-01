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

# ── 固定幀數控制（hitstun & blockstun & knockback 都使用）──
var hitstun_frames: int = 0          # hitstun 固定幀數
var blockstun_frames: int = 0        # blockstun 固定幀數
var knockback_frames: int = 0        # knockback 固定幀數（與 hitstun 同步）
var initial_knockback_frames: int = 0  # ✅ NEW: 保存初始 knockback 幀數（用於衰減計算）
var knockback_delay_frames: int = 0  # knockback 延遲幀數
var initial_blockstun_frames: int = 0 # 用於 push 計算
const FPS: int = 60

# 🟢 待執行的 hit 參數（等待 hit stop 完成後才實際啟動）
var pending_hit_params: Dictionary = {}  # 存儲 take_hit 的所有參數
var waiting_for_hit_stop_end: bool = false  # 標記是否在等待 hit stop 完成

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
	
	# 🟢 連接 SlowMoController 信號，在 hit stop 完成後啟動 hitstun/knockback/blockstun
	if world and world.has_node("SlowMoController"):
		var slowmo_controller = world.get_node("SlowMoController")
		slowmo_controller.hit_slowmo_finished.connect(_on_hit_slowmo_finished)

func _physics_process(delta: float) -> void:
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	# ── 【固定幀數 knockback_delay】──
	if knockback_delay_frames > 0:
		knockback_delay_frames -= 1
		# 延遲期間不移動
		if knockback_delay_frames <= 0:
			# 延遲結束，啟動 knockback
			knockback_frames = hitstun_frames  # 同步 knockback 幀數與當前 hitstun 幀數
			initial_knockback_frames = hitstun_frames  # ✅ NEW: 保存當前 hitstun 幀數作為 knockback 初始值
			hit_push_velocity = hit_push_initial_velocity  # 恢復 knockback 速度
			knockback_start_time = Time.get_ticks_msec() / 1000.0
			if knockback_frames > 0:
				print("[KNOCKBACK DELAY END] %s - knockback 開始，持續 %d 幀 (%.3f秒 @%d FPS)" % [
					name, knockback_frames, knockback_frames / float(PHYSICS_FPS), PHYSICS_FPS
				])

	# ── 【固定幀數 hitstun 和 knockback 同時遞減】──
	if hitstun_frames > 0:
		hitstun_frames -= 1
		# 🔴 同時遞減 knockback_frames，確保完全同步
		if knockback_frames > 0:
			knockback_frames -= 1
		
		is_hit = true
		if hitstun_frames <= 0:
			print("[FIXED-FRAME HITSTUN END] %s 完全結束！" % name)
			# 如果不是在空中受擊狀態，才清除 is_hit
			if not is_air_hit_backjump:
				is_hit = false
				was_hit_while_crouching = false  # 重置蹲姿受擊標記
		# 確保 knockback 也在 hitstun 結束時停止
		if knockback_frames <= 0:
			knockback_frames = 0
	else:
		# 如果不是在空中受擊狀態，才清除 is_hit
		if not is_air_hit_backjump:
			is_hit = false
			was_hit_while_crouching = false  # 重置蹲姿受擊標記
		knockback_frames = 0  # 確保 knockback 也被清除

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
	knockfly_params: Dictionary = {},
	knockback_distance: float = -1.0
) -> void:
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return
	
	print("[DEBUG] take_hit() 接收 → hitstun: %.3f, blockstun: %.3f, damage: %.1f" % [hitstun_duration, blockstun_duration, damage])
	
	# 記錄被擊中時是否處於蹲姿（用於選擇正確的受擊動畫）
	was_hit_while_crouching = is_crouching
	
	# Clear input buffer when getting hit
	if has_node("PlayerController"):
		var controller = get_node("PlayerController")
		if controller.has_method("clear_buffer"):
			controller.clear_buffer()
	
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
	
	# ── 清除跳躍延遲（避免與受擊狀態衝突）──
	if not is_on_floor():
		jump_delay_timer = 0.0
	
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
		# ── 普通受擊 → 空中/地面分別處理 ──
		is_hit = true
		var hit_frames = max(sec_to_frames(hitstun_duration), sec_to_frames(min_hitstun_duration))
		
		# 🟢 檢查是否有 hit stop 正在進行
		var slowmo_controller = world.get_node_or_null("SlowMoController") if world else null
		if slowmo_controller and slowmo_controller.is_hit_slowmo:
			# Hit stop 正在進行 → 延遲設置 hitstun/knockback/blockstun，等待 hit stop 完成
			print("[HITSTUN DELAYED] %s - Hit stop 進行中，延遲設置 hitstun/knockback/blockstun" % name)
			waiting_for_hit_stop_end = true
			pending_hit_params = {
				"hit_frames": hit_frames,
				"blockstun": 0,  # 普通受擊不設置 blockstun
				"skip_push": skip_push,
				"knockback_delay_frames": sec_to_frames(knockback_delay_duration),
				"hit_push_initial_velocity": 0.0  # 將在下面計算
			}
			
			# 計算 knockback 速度（必須在設置 pending_hit_params 之前）
			if not skip_push:
				var push_distance = knockback_distance if knockback_distance > 0 else hit_push_distance
				var knockback_velocity = push_distance * world.SIMULATION_SCALE * 4.0
				pending_hit_params["hit_push_initial_velocity"] = knockback_velocity
		else:
			# Hit stop 未進行或已完成 → 立即設置 hitstun/knockback/blockstun
			hitstun_frames = hit_frames
			initial_hitstun = hitstun_duration
		
		# hit_timer = 延遲 + hitstun時間，確保knockback完整執行
		hit_timer = knockback_delay_duration + hitstun_duration
		print("[FIXED-FRAME HITSTUN START] %s 進入 hit，%d 幀 (%.3f秒)，hit_timer=%.3fs" % [name, hit_frames, hitstun_duration, hit_timer])
		
		if not is_on_floor():
			# 空中普通攻擊：強制使用後跳邏輯，垂直速度為正常跳躍的 0.7 倍
			is_air_hit_backjump = true
			air_hit_backjump_timer = air_hit_backjump_duration
			is_jumping = true  # 確保 GravityHandler 正常應用重力
			just_jumped = true  # 防止 GravityHandler 重置速度為 0
			fixed_velocity.x = int(-air_hit_backjump_speed * world.SIMULATION_SCALE * facing_mult)
			# 使用正常跳躍速度的 0.7 倍作為垂直速度（jump_vertical_speed 約為 -2300）
			var normal_jump_speed = jump_vertical_speed if "jump_vertical_speed" in self else -2300.0
			fixed_velocity.y = int(normal_jump_speed * 0.7 * world.SIMULATION_SCALE)
			is_immune_to_floor_snap = true
			floor_snap_immunity_timer = floor_snap_immunity_duration
			fixed_position.y -= 2
			print("[AIR HIT] %s 空中受擊 → 後跳速度 x=%d, y=%d (0.7x 正常跳躍)" % [name, fixed_velocity.x, fixed_velocity.y])
		else:
			# 地面普通受擊 → 只有 hitstun，無垂直速度（讓 PushManager 處理水平推擊）
			fixed_velocity.y = 0
		
		if not skip_push:
			var push_distance = knockback_distance if knockback_distance > 0 else hit_push_distance
			# knockback 使用固定幀數系統，持續時間 = hitstun 時間
			knockback_delay_frames = sec_to_frames(knockback_delay_duration)  # 延遲也轉換為幀數
			
			# 🔴 DEBUG: 檢查 take_hit() 是否被多次調用
			if knockback_frames > 0 or initial_knockback_frames > 0:
				print("[KNOCKBACK INTERRUPTION] %s - take_hit() 在 knockback 執行中被調用！ 當前 knockback_frames: %d, initial: %d" % [
					name, knockback_frames, initial_knockback_frames
				])
			
			knockback_start_time = 0.0  # 重置時間戳，讓 PushManager 重新記錄
			# 使用合理的速度係數（4.0），搭配二次方衰減產生平滑後移
			# 🟢 降低初始速度係數，讓減速感更明顯（減速曲線可見度提高）
			hit_push_initial_velocity = push_distance * world.SIMULATION_SCALE * 4.0
			
			# 🟢 如果不在等待 hit stop 結束，才立即啟動 knockback
			if not waiting_for_hit_stop_end:
				# 如果沒有延遲，立即啟動 knockback
				if knockback_delay_frames <= 0:
					knockback_frames = hit_frames  # 立即設置為 hitstun 幀數
					initial_knockback_frames = hit_frames  # ✅ NEW: 保存初始幀數
					hit_push_velocity = hit_push_initial_velocity
					print("[KNOCKBACK RESET] %s - take_hit() 重置 knockback！新的 knockback_frames: %d" % [name, knockback_frames])
					# 不在這裡設置 knockback_start_time，讓 PushManager 首次執行時記錄
				else:
					# 有延遲時，knockback_frames 保持 0，等待延遲結束
					knockback_frames = 0
					initial_knockback_frames = hit_frames  # ✅ NEW: 預先保存初始值
					hit_push_velocity = 0.0  # 延遲期間無速度
			
			print("\n[KNOCKBACK SETUP] %s" % name)
			print("  - Push Distance: %.1f pixels" % push_distance)
			print("  - Initial Velocity: %.1f units" % hit_push_initial_velocity)
			print("  - Delay Duration: %.2fs (%d frames)" % [knockback_delay_duration, knockback_delay_frames])
			print("  - Knockback Duration: %.2fs (%d frames)" % [hitstun_duration, hit_frames])
			print("  - Total Duration: %.2fs" % (knockback_delay_duration + hitstun_duration))
			print("  - knockback_frames: %d, knockback_delay_frames: %d" % [knockback_frames, knockback_delay_frames])
			if waiting_for_hit_stop_end:
				print("  - ⏳ 等待 hit stop 結束...\n")
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
# 🟢 Hit stop 完成後的回調 - 啟動被延遲的 hitstun/knockback/blockstun
func _on_hit_slowmo_finished() -> void:
	if waiting_for_hit_stop_end and pending_hit_params.size() > 0:
		print("[HIT STOP END] %s - 啟動被延遲的 hitstun/knockback/blockstun" % name)
		_apply_pending_hit_effect()
		waiting_for_hit_stop_end = false
		pending_hit_params.clear()

# 🟢 實際應用被延遲的 hit 效果（在 hit stop 完成後執行）
func _apply_pending_hit_effect() -> void:
	var hit_frames = pending_hit_params.get("hit_frames", 0)
	var blockstun = pending_hit_params.get("blockstun", 0)
	var skip_push = pending_hit_params.get("skip_push", false)
	
	# 啟動 hitstun（blockstun 只在格擋時設置）
	hitstun_frames = hit_frames
	if blockstun > 0:
		blockstun_frames = blockstun
		initial_blockstun_frames = blockstun
	
	# 啟動 knockback（如果不跳過 push）
	if not skip_push:
		var knockback_delay_frames_val = pending_hit_params.get("knockback_delay_frames", 0)
		var hit_frames_val = pending_hit_params.get("hit_frames", 0)
		var hit_push_initial_velocity_val = pending_hit_params.get("hit_push_initial_velocity", 0)
		
		knockback_delay_frames = knockback_delay_frames_val
		
		# 如果沒有延遲，立即啟動 knockback
		if knockback_delay_frames <= 0:
			knockback_frames = hit_frames_val
			initial_knockback_frames = hit_frames_val
			hit_push_velocity = hit_push_initial_velocity_val
		else:
			knockback_frames = 0
			initial_knockback_frames = hit_frames_val
			hit_push_velocity = 0.0
	
	print("[HIT EFFECT APPLIED] %s - hitstun: %d frames, blockstun: %d frames, knockback: %d frames" % [
		name, hitstun_frames, blockstun_frames, knockback_frames
	])
