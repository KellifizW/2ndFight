class_name Player extends Fighter

signal hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool)

@export var character_data: CharacterData      # 在角色場景中拖入對應的 .character.tres
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 250.0
@export var cancel_window_duration: float = 0.3
@export var skip_pushbox: bool = false
@export var attack_data: AttackData

@onready var ATTACK_TABLE: Dictionary = {
	"st_lp": attack_data.st_lp,
	"st_mp": attack_data.st_mp,
	"st_hp": attack_data.st_hp,
	"st_lk": attack_data.st_lk,
	"st_mk": attack_data.st_mk,
	"st_hk": attack_data.st_hk,
	"cr_lp": attack_data.cr_lp,
	"cr_mp": attack_data.cr_mp,
	"cr_hp": attack_data.cr_hp,
	"cr_lk": attack_data.cr_lk,
	"cr_mk": attack_data.cr_mk,
	"cr_hk": attack_data.cr_hk,
	"jump_mp": attack_data.jump_mp,
	"jump_mk": attack_data.jump_mk,
}.duplicate(true)

@export var powerkk_blockstun: float = 0.3833

@onready var move_set = $MoveSet if has_node("MoveSet") else null
@onready var player_controller = $PlayerController if has_node("PlayerController") else null

# 新增：由 world.gd 動態生成時設定，決定這個角色是左邊還是右邊玩家
var seat: String = "player_a"  # "player_a" 或 "player_b"

# 角色唯一 ID（例如 "DAV" 或 "DEN"），用來判斷特殊招式
var character_id: String:
	get: return character_data.short_id if character_data else "UNKNOWN"

# ── 攻擊移動系統 ─────────────────────
var current_attack_movement: AttackMovement = null
var attack_movement_timer: float = 0.0
var attack_movement_active: bool = false

# ── 狀態旗標 ─────────────────────
var current_mode: String = "ground_stand"
var attack_type: String = "none"
var is_landing: bool = false
var is_wakeup: bool = false
var is_wakeup_locked: bool = false
var is_air_attacking: bool = false
var is_special_moving: bool = false
var landing_lock_timer: float = 0.0
var has_air_attacked: bool = false
var is_cancel_window_open: bool = false  # 取消窗口是否開啟（由動畫 call method 控制）
var is_facing_locked: bool = false
var allowed_cancel_targets: Array = []  # 當前允許取消成的招式清單

# 擊中確認取消系統（Hit-Confirm Cancel）
var pending_cancel_targets: Array = []  # 待開啟的取消目標（等待擊中確認）

var special_input_data: Dictionary = {
	"spm1_pressed": false,
	"spm2_pressed": false,
	"dp_pressed": false,
	"super_pressed": false
}

# ── 重置函式 ─────────────────────
func reset_attack_state() -> void:
	is_attacking = false
	attack_type = "none"
	is_cancel_window_open = false
	allowed_cancel_targets = []
	pending_cancel_targets = []
	attack_movement_active = false
	current_attack_movement = null
	update_facing_direction()
	_update_animation_state(0, false)

func reset_landing_state() -> void:
	is_landing = false
	landing_lock_timer = 0.0
	landing_facing_lock = false
	update_facing_direction()
	_update_animation_state(0, false)

func reset_air_state() -> void:
	if is_on_floor():
		is_air_attacking = false
		has_air_attacked = false
		var input_data = get_input()
		if (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed
			or input_data.st_lp_pressed or input_data.st_mp_pressed or input_data.st_hp_pressed
			or input_data.st_lk_pressed or input_data.st_mk_pressed or input_data.st_hk_pressed
			or input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed):
			is_landing = false
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
		else:
			is_landing = true
			landing_lock_timer = landing_duration

func reset_special_state() -> void:
	if move_set and move_set.is_spmove:
		move_set.stop_special_move()
	is_facing_locked = false
	force_update_facing_direction()
	_update_animation_state(0, false)

var player_anim_resets: Dictionary = {
	"wakeup": func():
		is_wakeup = false
		is_wakeup_locked = false
		is_landing = false
		_update_animation_state(0, false),
	"st_lp": func(): reset_attack_state(),
	"st_mp": func(): reset_attack_state(),
	"st_hp": func(): reset_attack_state(),
	"st_lk": func(): reset_attack_state(),
	"st_mk": func(): reset_attack_state(),
	"st_hk": func(): reset_attack_state(),
	"cr_lp": func(): reset_attack_state(),
	"cr_mp": func(): reset_attack_state(),
	"cr_hp": func(): reset_attack_state(),
	"cr_lk": func(): reset_attack_state(),
	"cr_mk": func(): reset_attack_state(),
	"cr_hk": func(): reset_attack_state(),
	"jump_mp": func(): reset_air_state(),
	"jump_mk": func(): reset_air_state(),
	"jump_v": func():
		if is_on_floor():
			is_jumping = false
			var input_data = get_input()
			if (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed
				or input_data.st_mp_pressed or input_data.st_mk_pressed
				or input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed):
				is_landing = false
				landing_facing_lock = false
				update_facing_direction()
				_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
			else:
				is_landing = true
				landing_lock_timer = landing_duration,
	"Jump_V": func(): player_anim_resets["jump_v"].call(),
	"Jump_F": func(): player_anim_resets["jump_v"].call(),
	"Jump_B": func(): player_anim_resets["jump_v"].call(),
	"fireball": func(): reset_special_state(),
	"powerkk": func(): reset_special_state(),
	"spnk": func(): reset_special_state(),
	"dp": func(): reset_special_state(),
	"hdk": func(): reset_special_state(),  # ← 加上這一行！
}

func _ready() -> void:
	super._ready()
	world = get_tree().get_first_node_in_group("world")
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	if animation_tree:
		animation_tree.animation_finished.connect(_on_animation_tree_finished)
		animation_tree.active = true
		animation_state.travel("Walk")
	add_to_group("players")
	if player_controller:
		player_controller.player_seat = seat  # ← 這一行一定要加！
	hit_detected.connect(_on_hit_detected)
	skip_pushbox = false
	
	var ui_root = get_tree().get_first_node_in_group("ui")
	if ui_root:
		healthbar = ui_root.get_node("PlayerAHealthbar" if seat == "player_a" else "PlayerBHealthbar")
		
func set_input_data(data: Dictionary) -> void:
	special_input_data = data

var default_input: Dictionary = {
	"input_dir": 0,
	"crouch_pressed": false,
	"jump_pressed": false,
	"st_lp_pressed": false,
	"st_mp_pressed": false,
	"st_hp_pressed": false,
	"st_lk_pressed": false,
	"st_mk_pressed":  false,
	"st_hk_pressed": false,
	"spm1_pressed": false,
	"spm2_pressed": false,
	"dp_pressed": false,
	"super_pressed": false
}

func get_input() -> Dictionary:
	if is_knockfly or is_wakeup or is_hit or is_layground:
		return default_input.duplicate()
	if is_ai_controlled:
		var ai = $AIBehavior if has_node("AIBehavior") else null
		if ai: return ai.get_ai_input()
	if player_controller:
		var data = player_controller.get_input_data()
		data.super_pressed = Input.is_key_pressed(KEY_P)
		data.merge(special_input_data, true)
		return data
	return default_input.duplicate()

func _physics_process(delta: float) -> void:
	if has_node("InputManager"):
		$InputManager.update_input()
	
	# ── 攻擊移動處理（必須在 super._physics_process 之前，確保速度在應用前被設置） ──
	_process_attack_movement(delta)
	
	super._physics_process(delta)
	if not world: return

	if is_air_attacking and is_on_floor():
		is_air_attacking = false
		has_air_attacked = false

	# 取消窗口由動畫 call method 控制（_open_cancel_window / _close_cancel_window）
	# 不需要 timer 倒數

	var input_data = get_input()
	input_data.merge(special_input_data, true)

	# 移除：這段邏輯會在取消判定前清空按鈕，導致 attack_type 無法正確檢測
	# if input_data.spm2_pressed or input_data.dp_pressed or input_data.spm1_pressed or input_data.super_pressed:
	#     input_data.st_mp_pressed = false
	#     input_data.st_mk_pressed = false

	var is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup and not is_layground

	if move_set and move_set.is_spmove:
		is_attacking = false
		attack_type = "none"
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false

	# 取消判定：必須在清空按鈕輸入之前檢查！
	if is_attacking and is_cancel_window_open and allowed_cancel_targets.size() > 0:
		var input_move = input_data.get("attack_type", "none")
		print("[Cancel Debug] 進入取消判定 - is_attacking=%s, is_cancel_window_open=%s, targets_size=%d" % [is_attacking, is_cancel_window_open, allowed_cancel_targets.size()])
		print("[Cancel Debug] input_move='%s', allowed_cancel_targets=%s" % [input_move, allowed_cancel_targets])
		# 只在有實際輸入時才處理和顯示訊息
		if input_move != "none":
			if input_move in allowed_cancel_targets:
				print("[Cancel] ✓ 取消 %s → %s" % [attack_type, input_move])
				stop_attack()
			else:
				print("[Cancel] ✗ %s 不能取消成 %s（允許: %s）" % [attack_type, input_move, allowed_cancel_targets])
		else:
			print("[Cancel Debug] input_move 是 'none'，不執行取消")

	# 在取消判定之後才清空按鈕輸入，避免影響特殊招檢測
	if is_attacking and animation_state.get_current_node() in ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk", "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk"]:
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false

	if move_set and move_set.process_move(delta, input_data, is_valid_ground_state):
		return

	if is_cancel_window_open:
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false

	if (input_data.st_lp_pressed or input_data.st_mp_pressed or input_data.st_hp_pressed or input_data.st_lk_pressed or input_data.st_mk_pressed or input_data.st_hk_pressed) and is_valid_ground_state:
		force_update_facing_direction()
		if is_crouching:
			if input_data.st_lp_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_lp")
				_execute_attack("cr_lp")
			elif input_data.st_mp_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_mp")
				_execute_attack("cr_mp")
			elif input_data.st_hp_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_hp")
				_execute_attack("cr_hp")
			elif input_data.st_lk_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_lk")
				_execute_attack("cr_lk")
			elif input_data.st_mk_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_mk")
				_execute_attack("cr_mk")
			elif input_data.st_hk_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_hk")
				_execute_attack("cr_hk")
		else:
			if input_data.st_lp_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_lp")
				_execute_attack("st_lp")
			elif input_data.st_mp_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_mp")
				_execute_attack("st_mp")
			elif input_data.st_hp_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_hp")
				_execute_attack("st_hp")
			elif input_data.st_lk_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_lk")
				_execute_attack("st_lk")
			elif input_data.st_mk_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_mk")
				_execute_attack("st_mk")
			elif input_data.st_hk_pressed:
				# Consume the buffered input
				if player_controller and player_controller.has_method("consume_button_input"):
					player_controller.consume_button_input("st_hk")
				_execute_attack("st_hk")
		# 只有在沒有攻擊移動激活時才清零速度
		if not is_push_back and not attack_movement_active:
			fixed_velocity.x = 0

	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup and not has_air_attacked and not is_layground
	if input_data.st_lp_pressed and is_valid_air_state:
		# Consume the buffered input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("st_lp")
		is_air_attacking = true
		has_air_attacked = true
		_execute_attack("jump_mp")
	elif input_data.st_mp_pressed and is_valid_air_state:
		# Consume the buffered input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("st_mp")
		is_air_attacking = true
		has_air_attacked = true
		_execute_attack("jump_mp")
	elif input_data.st_hp_pressed and is_valid_air_state:
		# Consume the buffered input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("st_hp")
		is_air_attacking = true
		has_air_attacked = true
		_execute_attack("jump_mp")
	elif input_data.st_lk_pressed and is_valid_air_state:
		# Consume the buffered input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("st_lk")
		is_air_attacking = true
		has_air_attacked = true
		_execute_attack("jump_mk")
	elif input_data.st_mk_pressed and is_valid_air_state:
		# Consume the buffered input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("st_mk")
		is_air_attacking = true
		has_air_attacked = true
		_execute_attack("jump_mk")
	elif input_data.st_hk_pressed and is_valid_air_state:
		# Consume the buffered input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("st_hk")
		is_air_attacking = true
		has_air_attacked = true
		_execute_attack("jump_mk")

	if landing_lock_timer > 0:
		landing_lock_timer -= delta
		if is_landing and (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed or
						   input_data.st_lp_pressed or input_data.st_mp_pressed or input_data.st_hp_pressed or
						   input_data.st_lk_pressed or input_data.st_mk_pressed or input_data.st_hk_pressed or
						   input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed):
			is_landing = false
			landing_lock_timer = 0.0
			landing_facing_lock = false
			update_facing_direction()
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

	if not (landing_lock_timer > 0):
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func _physics_process_jump(_delta: float) -> void:
	var input_data = get_input()
	if input_data.jump_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_attacking and not is_hit and not is_knockfly and not is_blocking and not is_layground:
		# Consume the buffered jump input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("jump")
		
		is_jumping = true
		landing_facing_lock = true
		if world:
			fixed_position.y = world.FLOOR_Y - 1
			fixed_velocity.y = 0
			if input_data.input_dir != 0:
				var jump_speed = jump_horizontal_speed if input_data.input_dir * facing_direction > 0 else jump_horizontal_speed * 0.75
				fixed_velocity.x = int(jump_speed * world.SIMULATION_SCALE * input_data.input_dir)
			else:
				fixed_velocity.x = 0

func _compute_target_state(dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	if is_layground: return "layground"
	if is_knockfly: return "knockfly"
	if is_wakeup_locked: return "wakeup"
	if is_hit:
		if not on_floor and ("is_air_hit_backjump" in self and self.is_air_hit_backjump):
			return "Jump_B"
		return "hit" if on_floor else "Jump_B"

	if move_set and move_set.is_spmove:
		var active_move_name = move_set.get_active_move_name()
		if active_move_name in ["super", "powerkk", "dp", "spnk", "fireball"]:
			return active_move_name

	if is_blocking:
		return "cr_block" if is_crouch_blocking and crouch_input else "block"

	if is_landing and landing_lock_timer > 0:
		return "landing"

	if not on_floor and (is_jumping or is_air_attacking):
		if is_air_attacking or has_air_attacked:
			return attack_type
		else:
			if anim_jump_dir > 0: return "Jump_F"
			elif anim_jump_dir < 0: return "Jump_B"
			else: return "Jump_V"

	return super._compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	super._update_animation_state(dir_x, crouch_input)

func _on_animation_tree_finished(anim_name: StringName) -> void:
	if anim_name == "layground" and is_layground:
		if healthbar and healthbar.current_health <= 0:
			return
		is_layground = false
		is_wakeup = true
		is_wakeup_locked = true
		fixed_velocity = Vector2i.ZERO
		animation_state.travel("wakeup")
	else:
		if anim_name in player_anim_resets:
			player_anim_resets[anim_name].call()

# ── 擊中處理 ─────────────────────
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.name != "Hurtbox" or not area.get_parent().is_in_group("players") or area.get_parent() == self:
		return
	var target = area.get_parent()
	var was_in_stun = target.is_hit or target.is_knockfly
	if not world: return

	var slowmo = world.get_node_or_null("SlowMoController")
	if slowmo: slowmo.request_hit_freeze()

	var hitstun := 0.35
	var blockstun := 0.267
	var damage := current_damage
	var skip_push := false
	var force_knockfly := false
	var knockfly_params := {}

	if ATTACK_TABLE.has(attack_type):
		var a = ATTACK_TABLE[attack_type]
		hitstun = a.hitstun
		blockstun = a.blockstun
		damage = a.damage
	elif move_set and move_set.is_spmove and move_set.current_move_state.active_move:
		var active_move = move_set.current_move_state.active_move
		damage = active_move.damage
		if active_move.name == "powerkk":
			hitstun = 0.65
			blockstun = powerkk_blockstun
		elif active_move.name == "spnk":
			hitstun = 0.45
			blockstun = powerkk_blockstun
			var pos = animation_player.current_animation_position if animation_player else 0.0
			if pos < 0.2667: damage = 6.0
		elif active_move.name == "fireball":
			hitstun = 0.35
			blockstun = 0.233
			skip_push = true
		elif active_move.name == "super":
			hitstun = 0.45
			blockstun = 0.3
		elif active_move.name == "dp":
			hitstun = 0.65
			blockstun = powerkk_blockstun
			# DP 应该在对方没有格挡时强制触发 knockfly（无论对方是否在使用特殊技能）
			force_knockfly = true
			knockfly_params = {
				"gravity": active_move.knockfly_gravity,
				"vertical_speed": active_move.knockfly_vertical_speed,
				"horizontal_speed": active_move.knockfly_horizontal_speed,
				"duration": hitstun
			}

	var knockback_dist = -1.0
	if ATTACK_TABLE.has(attack_type):
		knockback_dist = ATTACK_TABLE[attack_type].get("knockback", -1.0)
	elif move_set and move_set.is_spmove and move_set.current_move_state.active_move:
		knockback_dist = move_set.current_move_state.active_move.knockback
	
	target.take_hit(hitstun, blockstun, damage, skip_push, force_knockfly, knockfly_params, knockback_dist)

	var is_blocked: bool = target.is_blocking
	var stun_duration = blockstun if is_blocked else hitstun
	hit_detected.emit(target.name, stun_duration, is_blocked, was_in_stun)

	var hit_sound = $HitSoundPlayer if has_node("HitSoundPlayer") else null
	var block_sound = $BlockSoundPlayer if has_node("BlockSoundPlayer") else null
	if is_blocked and block_sound:
		block_sound.play()
	elif not is_blocked and hit_sound:
		hit_sound.play()

	var vfx_type = "block" if is_blocked else "hit"
	var contact = get_contact_point($Hitbox, area)
	if contact == Vector2.ZERO:
		contact = (area.global_position + $Hitbox.global_position) / 2.0
	if not target.is_on_floor():
		contact.y += 10
	VFXImpact.spawn_vfx(world, vfx_type, contact, facing_direction)

	if move_set and move_set.is_spmove and move_set.current_move_state.active_move and move_set.current_move_state.active_move.penetrable:
		return
	var push_manager = get_tree().get_first_node_in_group("push_manager")
	if push_manager and push_manager.is_at_corner(target):
		var push_duration = stun_duration
		is_push_back = true
		push_back_timer = push_duration
		initial_push_back = push_duration
		push_back_velocity = 2.0 * corner_push_distance * world.SIMULATION_SCALE / push_duration
		fixed_velocity.x = int(-push_back_velocity * get_facing_multiplier())

func _on_hit_detected(_target: String, _stun_duration: float, _is_blocked: bool, _was_in_stun: bool) -> void:
	# 擊中確認取消（Hit-Confirm Cancel）：只有在擊中對手時才真正開啟取消窗口
	if pending_cancel_targets.size() > 0:
		is_cancel_window_open = true
		allowed_cancel_targets = pending_cancel_targets.duplicate()
		print("[Cancel] ✓ 擊中確認！%s 開啟取消窗口，允許: %s" % [attack_type, allowed_cancel_targets])
		# 使用後立即清空，避免重複觸發
		pending_cancel_targets = []
	else:
		print("[Cancel] ✗ 擊中但無待開啟的取消窗口（pending_cancel_targets 為空）")

# ═══════════════════════════════════════════════════════════
# 取消窗口系統（純 Call Method Track - Option 1）
# ═══════════════════════════════════════════════════════════
# 這些方法會被 AnimationPlayer 的 Call Method Track 調用
# open_cancel_window 時開啟，close_cancel_window 時關閉，不需要 timer

# 準備取消窗口（由動畫軌道調用，等待擊中確認）
# allowed_moves: 允許取消成的招式陣列，例如 ["powerkk", "fireball"]
func _open_cancel_window(allowed_moves: Array = []) -> void:
	# 設置待開啟狀態，等待擊中確認
	pending_cancel_targets = allowed_moves.duplicate()
	print("[Cancel] %s 準備取消窗口（等待擊中確認），允許: %s" % [attack_type, allowed_moves])

# 關閉取消窗口（由動畫軌道調用）
func _close_cancel_window() -> void:
	is_cancel_window_open = false
	allowed_cancel_targets = []
	# 保留 pending_cancel_targets，因為擊中確認可能在窗口關閉後才觸發（slowmo延遲）
	print("[Cancel] 取消窗口關閉（pending targets 保留給擊中確認）")

# ═══════════════════════════════════════════════════════════

func stop_attack() -> void:
	is_attacking = false
	attack_type = "none"
	is_cancel_window_open = false
	allowed_cancel_targets = []
	pending_cancel_targets = []
	if animation_player:
		animation_player.stop()
	update_facing_direction()
	_update_animation_state(0, false)

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()

func update_facing_direction() -> void:
	if is_facing_locked: return
	super.update_facing_direction()

func force_update_facing_direction() -> void:
	var players = get_tree().get_nodes_in_group("players")
	var other = null
	for p in players:
		if p != self:
			other = p
			break
	if other:
		var self_left  = global_position.x - colbox_half_width
		var self_right = global_position.x + colbox_half_width
		var other_left  = other.global_position.x - other.colbox_half_width
		var other_right = other.global_position.x + other.colbox_half_width
		if self_left > other_right:
			facing_direction = -1.0
			scale.x = -1
		elif self_right < other_left:
			facing_direction = 1.0
			scale.x = 1
		update_hitbox_position()

func _process(_delta: float) -> void:
	_sync_shadow_animation()

func _sync_shadow_animation() -> void:
	var body_sprite = $AnimatedSprite2D
	if not body_sprite:
		return
	
	# 陰影節點現在固定用席位名稱，不再用舊的 P1/P2
	var shadow_node_name = "PlayerAShadowSprite" if seat == "player_a" else "PlayerBShadowSprite"
	var shadow_sprite = get_parent().get_node(shadow_node_name)
	
	if shadow_sprite and shadow_sprite.material is ShaderMaterial:
		var mat: ShaderMaterial = shadow_sprite.material

		shadow_sprite.animation = body_sprite.animation
		shadow_sprite.frame = body_sprite.frame
		shadow_sprite.offset = body_sprite.offset
		shadow_sprite.flip_h = facing_direction < 0
		shadow_sprite.global_position.x = global_position.x
		shadow_sprite.global_position.y = 570 + 110
		
		if is_on_floor():
			mat.set_shader_parameter("blur_factor", 0.0)
		else:
			var height = 570.0 - global_position.y
			var blur = clamp(height / 200.0, 0.0, 1.0)
			mat.set_shader_parameter("blur_factor", blur)

# ══════════════════════════════════════════════════════════════════
# ── 攻擊移動系統 ─────────────────────
# ══════════════════════════════════════════════════════════════════

func _execute_attack(attack_name: String) -> void:
	"""統一的攻擊執行函式，處理傷害設置、狀態變更和移動啟動"""
	if not attack_name in ATTACK_TABLE:
		return
	
	current_damage = ATTACK_TABLE[attack_name].damage
	is_attacking = true
	attack_type = attack_name
	
	# 啟動攻擊移動（如果有設定）
	_start_attack_movement(attack_name)

func _start_attack_movement(attack_name: String) -> void:
	"""啟動攻擊移動（由攻擊執行時呼叫）"""
	if not attack_name in ATTACK_TABLE:
		print("[Movement] %s 不在 ATTACK_TABLE 中" % attack_name)
		return
	
	var attack_dict = ATTACK_TABLE[attack_name]
	if not "movement" in attack_dict or attack_dict.movement == null:
		print("[Movement] %s 沒有設定 movement 屬性" % attack_name)
		return
	
	current_attack_movement = attack_dict.movement
	attack_movement_timer = 0.0
	attack_movement_active = true
	
	print("[Movement] ✓ 啟動 %s 移動：distance=%.1f, duration=%.2f, curve=%d, enabled=%s" % [
		attack_name,
		current_attack_movement.distance,
		current_attack_movement.duration,
		current_attack_movement.curve_type,
		current_attack_movement.enabled
	])

func _process_attack_movement(delta: float) -> void:
	"""每幀更新攻擊移動"""
	if not attack_movement_active or current_attack_movement == null:
		return
	
	# 等待起始延遲
	if attack_movement_timer < current_attack_movement.start_delay:
		attack_movement_timer += delta
		return
	
	var effective_time = attack_movement_timer - current_attack_movement.start_delay
	
	# 檢查是否超過持續時間
	if effective_time >= current_attack_movement.duration:
		attack_movement_active = false
		print("[Movement] ✓ 移動完成")
		return
	
	# 計算移動方向
	var move_direction: float = 1.0
	if current_attack_movement.use_facing_direction:
		move_direction = facing_direction
	if current_attack_movement.reverse_direction:
		move_direction *= -1.0
	
	# 獲取當前速度倍率（基於曲線）
	var speed_multiplier = current_attack_movement.get_speed_multiplier(effective_time)
	
	# 計算基礎速度（距離 / 持續時間）
	var base_speed = current_attack_movement.distance / current_attack_movement.duration
	
	# 應用速度倍率和方向
	var current_speed = base_speed * speed_multiplier * move_direction
	
	# 轉換為固定點速度
	if world:
		fixed_velocity.x = int(current_speed * world.SIMULATION_SCALE)
		
		# 調試輸出（每 10 幀輸出一次）
		if int(attack_movement_timer * 60) % 10 == 0:
			print("[Movement] time=%.2f, speed_mult=%.2f, velocity=%d" % [
				effective_time,
				speed_multiplier,
				fixed_velocity.x
			])
	
	attack_movement_timer += delta
