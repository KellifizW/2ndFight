class_name Fighter extends Movement

@onready var collision_shape = $Pushbox
@onready var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % name) if get_tree().get_first_node_in_group("ui") else null

var is_being_pushed: bool = false
var current_damage: float = 0.0
var air_hit_knockfly_speed: float = 53.33 # 將縮放為 53330

# 新增暴露至Inspector的參數，用於調整Sakuga風格的空中推開
@export var air_knockback_horizontal_speed: float = 100.0 # 水平推開速度（像素/秒）
@export var air_knockback_vertical_speed: float = -300.0 # 垂直推開速度（負值向上）
@export var air_friction: float = 10.0 # 空中摩擦力（減速率）
@export var min_hitstun_duration: float = 8.0 / 60.0 # 最小hitstun時間（模擬Sakuga的MinHitstun=8幀，假設60FPS）

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
	# 修正：明確獲取world節點
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	super._physics_process(delta)

	# 新增：應用空中摩擦減速（模仿Sakuga PhysicsBody.AddLateralAcceleration(0)）
	if (is_knockfly or is_hit) and not is_on_floor():
		var friction_amount = int(air_friction * world.SIMULATION_SCALE * delta)
		if fixed_velocity.x > 0:
			fixed_velocity.x = max(0, fixed_velocity.x - friction_amount)
		elif fixed_velocity.x < 0:
			fixed_velocity.x = min(0, fixed_velocity.x + friction_amount)
		print("Debug: Air friction applied, fixed_velocity.x=%s for %s" % [fixed_velocity.x, name])

	var input_data = get_input()
	var is_valid_state = is_on_floor() and not is_dashing and not is_backdashing and not is_crouching and not is_jumping

	if is_hit or is_knockfly or is_blocking:
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	else:
		if (input_data.st_mp_pressed or input_data.st_mk_pressed) and is_valid_state:
			current_damage = input_data.damage
			is_attacking = true
			if has_node("Proximitybox/ProxShape"):
				$Proximitybox/ProxShape.disabled = false
			print("Debug: ProximityBox enabled during attack for %s" % name)
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func post_physics_process(delta):
	pass

func take_hit(blockstun_duration: float = 0.2, damage: float = 10.0, skip_push: bool = false):
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Warning: World node not found in group 'world' for %s" % name)
		return

	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	var input_data = get_input()  # 移至函數開頭，確保全域可用

	if not is_hit and not is_knockfly:
		if is_attacking:
			is_attacking = false
			print("Debug: Attack interrupted by hit for %s" % name)
		if is_spmove:
			move_set.stop_special_move()
			print("Debug: Special move interrupted by hit for %s" % name)

		print("Debug: take_hit called, input_dir=%s, crouch_pressed=%s, is_holding_back=%s, is_crouch_blocking=%s, is_blocking=%s, block_type=%s" % [input_data.input_dir, input_data.crouch_pressed, is_holding_back, is_crouch_blocking, is_blocking, block_type])

		if is_blocking or ((is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove):
			is_blocking = true
			is_crouch_blocking = input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0 # 修正：明確設置蹲防狀態
			# 修正：take_hit 總是 ordinary block，強制應用 stun/push 並設 block_type = "ordinary"（覆寫 proximity）
			initial_blockstun = 0.4 if damage >= 20.0 else 0.267
			block_timer = initial_blockstun
			block_type = "ordinary"  # 強制設為 ordinary，無論先前狀態
			fixed_velocity.x = 0
			fixed_velocity.y = 0
			if not skip_push:
				block_push_timer = initial_blockstun
				block_push_velocity = 2.0 * block_push_distance * world.SIMULATION_SCALE / initial_blockstun
				print("Debug: Block push set - timer=%.2f, velocity=%.2f, skip_push=%s" % [block_push_timer, block_push_velocity, skip_push])
			print("Debug: Ordinary block successful (from hit), blockstun duration %s for %s, crouch_blocking=%s" % [initial_blockstun, name, is_crouch_blocking])
			block_detected.emit(name, block_type)
			_update_animation_state(0, input_data.crouch_pressed)
			return # 格擋時不扣血，直接返回
		else:
			print("Debug: No block triggered, proceeding to hit logic, is_on_floor=%s" % is_on_floor())

		if not is_on_floor():
			update_facing_direction()

		if healthbar:
			healthbar.take_damage(damage)
			var facing_mult = get_facing_multiplier()

			if damage > 10.0:
				is_knockfly = true
				knockfly_timer = max(knockfly_duration, min_hitstun_duration)
				if not skip_push:
					knockfly_velocity_x = -knockfly_push_speed * world.SIMULATION_SCALE * facing_mult
					print("Debug: Knockfly push set - velocity_x=%.2f, skip_push=%s" % [knockfly_velocity_x, skip_push])
				print("Debug: Special move hit, triggering knockfly for %s" % name)
			elif healthbar.current_health <= 0:
				is_knockfly = true
				knockfly_timer = max(knockfly_duration, min_hitstun_duration)
				if not skip_push:
					knockfly_velocity_x = -knockfly_push_speed * world.SIMULATION_SCALE * facing_mult
					print("Debug: Health zero knockfly push set - velocity_x=%.2f, skip_push=%s" % [knockfly_velocity_x, skip_push])
				print("Debug: Health reached zero, triggering knockfly for %s" % name)
			else:
				if is_on_floor():
					is_hit = true
					initial_hitstun = max(0.35, min_hitstun_duration)
					hit_timer = initial_hitstun
					if not skip_push:
						hit_push_timer = initial_hitstun
						hit_push_velocity = 2.0 * hit_push_distance * world.SIMULATION_SCALE / initial_hitstun
						print("Debug: Hit push set - timer=%.2f, velocity=%.2f, skip_push=%s" % [hit_push_timer, hit_push_velocity, skip_push])
					fixed_velocity.x = 0
					fixed_velocity.y = 0
					print("Debug: Ground hitstun triggered, duration %s for %s, damage %s" % [initial_hitstun, name, damage])
				else:
					is_hit = true
					initial_hitstun = max(0.35, min_hitstun_duration)
					hit_timer = initial_hitstun
					fixed_velocity.y = int(air_knockback_vertical_speed * world.SIMULATION_SCALE)
					fixed_velocity.x = int(-air_knockback_horizontal_speed * world.SIMULATION_SCALE * facing_mult)
					print("Debug: Air hit push set - velocity.y=%s, velocity.x=%s" % [fixed_velocity.y, fixed_velocity.x])
					print("Debug: Air hit triggered for %s, fixed_velocity.y=%s, fixed_velocity.x=%s" % [name, fixed_velocity.y, fixed_velocity.x])
		else:
			is_hit = true
			initial_hitstun = max(0.35, min_hitstun_duration)
			hit_timer = initial_hitstun
			if not skip_push:
				hit_push_timer = initial_hitstun
				hit_push_velocity = 2.0 * hit_push_distance * world.SIMULATION_SCALE / initial_hitstun
				print("Debug: Hit push set (no healthbar) - timer=%.2f, velocity=%.2f, skip_push=%s" % [hit_push_timer, hit_push_velocity, skip_push])
			fixed_velocity.x = 0
			fixed_velocity.y = 0
			print("Warning: No healthbar, hitstun triggered without damage for %s" % name)

	_update_animation_state(0, input_data.crouch_pressed)

func take_knockfly():
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
			print("Debug: Special move interrupted by knockfly for %s" % name)

		is_knockfly = true
		knockfly_timer = max(knockfly_duration, min_hitstun_duration)
		print("Debug: Knockfly taken for %s, knockfly_timer set to %.2f" % [name, knockfly_duration])
		_update_animation_state(0, is_crouching)
