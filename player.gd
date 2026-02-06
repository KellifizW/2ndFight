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
	"jump_lp": attack_data.jump_lp,
	"jump_mp": attack_data.jump_mp,
	"jump_hp": attack_data.jump_hp,
	"jump_lk": attack_data.jump_lk,
	"jump_mk": attack_data.jump_mk,
	"jump_hk": attack_data.jump_hk,
}.duplicate(true)

@export var powerkk_blockstun: float = 0.3833

@onready var move_set = $MoveSet if has_node("MoveSet") else null
@onready var player_controller = $PlayerController if has_node("PlayerController") else null

# 新增 Handlers (Phase 1-4 重構)
@onready var shadow_sync_handler: ShadowSyncHandler = null
@onready var attack_movement_handler: AttackMovementHandler = null
@onready var cancel_window_handler: CancelWindowHandler = null
@onready var attack_executor: AttackExecutor = null
@onready var hit_response_handler: HitResponseHandler = null

# 新增：由 world.gd 動態生成時設定，決定這個角色是左邊還是右邊玩家
var seat: String = "player_a"  # "player_a" 或 "player_b"

# 角色唯一 ID（例如 "DAV" 或 "DEN"），用來判斷特殊招式
var character_id: String:
	get: return character_data.short_id if character_data else "UNKNOWN"

# Fireball 管理：追蹤當前活躍的 fireball 實例（同一時間只能有一個）
var active_fireball: Node = null

# ── 狀態旗標 ─────────────────────
var current_mode: String = "ground_stand"
var attack_type: String = "none"
var is_wakeup: bool = false
var is_wakeup_locked: bool = false
var is_air_attacking: bool = false
var is_special_moving: bool = false
var has_air_attacked: bool = false
var attack_duration_timer: int = 0  # Frame-based timer for attack duration
var attack_start_frame: int = -1  # 🟢 Frame when attack started (120 FPS physics frame)
var wakeup_timer: int = 0  # Frame-based timer for wakeup duration
var is_facing_locked: bool = false
var _was_in_hitstop: bool = false

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
	attack_duration_timer = 0
	attack_start_frame = -1  # 🟢 重置攻擊開始幀
	if cancel_window_handler:
		cancel_window_handler.reset()
	if attack_movement_handler:
		attack_movement_handler.stop_movement()
	update_facing_direction()
	# 获取当前真实的输入状态，保持蹲状态
	var input_data = get_input()
	_update_animation_state(0, input_data.crouch_pressed)

func reset_landing_state() -> void:
	# 【重點】如果在強制2幀期間，不要重置
	if self._landing_forced_frames < 2:
		return
	
	self.is_landing = false
	self.landing_lock_timer = 0
	self.landing_facing_lock = false
	self.update_facing_direction()
	# 获取当前真实的输入状态，保持蹲状态
	var input_data = get_input()
	_update_animation_state(0, input_data.crouch_pressed)

func reset_air_state() -> void:
	# 【重點】如果正在著地期間，不要修改landing狀態
	if self.is_landing and self.landing_lock_timer > 0:
		return
	
	if self.is_on_floor():
		self.is_air_attacking = false
		self.has_air_attacked = false
		var input_data = get_input()
		if (input_data.input_dir != 0 or input_data.crouch_pressed or input_data.jump_pressed
			or input_data.st_lp_pressed or input_data.st_mp_pressed or input_data.st_hp_pressed
			or input_data.st_lk_pressed or input_data.st_mk_pressed or input_data.st_hk_pressed
			or input_data.spm1_pressed or input_data.spm2_pressed or input_data.dp_pressed):
			self.is_landing = false
			self._update_animation_state(input_data.input_dir, input_data.crouch_pressed)
		else:
			self.is_landing = true
			# 轉換 landing_duration（秒）為幀數 @120 FPS (PHYSICS_FPS)
			self.landing_lock_timer = int(round(self.landing_duration * 120)) if "landing_duration" in self else 24
			print("[AIR LANDING DEBUG] is_landing set | duration: %.3fs -> timer: %d frames @120 FPS" % [self.landing_duration, self.landing_lock_timer])

func reset_special_state() -> void:
	var move_name = move_set.get_active_move_name() if move_set and move_set.has_method("get_active_move_name") else "UNKNOWN"
	var seat_str = seat if seat else "?"
	print("[RESET_SPECIAL] Move '%s' | Seat: %s" % [move_name, seat_str])
	
	if move_set and move_set.is_spmove:
		move_set.stop_special_move()
	is_facing_locked = false
	is_special_moving = false  # 🟢 【除錯修正】確保清除 is_special_moving
	
	force_update_facing_direction()
	
	# 获取当前真实的输入状态，保持蹲状态
	var input_data = get_input()
	_update_animation_state(0, input_data.crouch_pressed)

# ── Fireball 生成方法（由動畫 Call Method 調用）──
func _spawn_fireball() -> void:
	# 🟢 【新增】通知 FrameBar call method 已被觸發
	var frame_bar = get_tree().get_first_node_in_group("frame_bar_" + seat) if seat else null
	if frame_bar and frame_bar.has_method("on_fireball_call_method_triggered"):
		frame_bar.on_fireball_call_method_triggered()
	
	if move_set and move_set.has_method("execute_fireball_spawn"):
		move_set.execute_fireball_spawn()

# ── 動畫重置分類（Phase 4 優化）──
const GROUND_ATTACK_ANIMS = ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
							  "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk"]
const AIR_ATTACK_ANIMS = ["jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk"]
const JUMP_ANIMS = ["jump_v", "Jump_V", "Jump_F", "Jump_B"]
const SPECIAL_ANIMS = ["fireball", "powerkk", "spnk", "dp", "hdk"]

func _ready() -> void:
	super._ready()
	world = get_tree().get_first_node_in_group("world")
	if has_node("Hitbox"):
		$Hitbox.area_entered.connect(_on_hitbox_area_entered)
	if animation_tree:
		animation_tree.animation_finished.connect(_on_animation_tree_finished)
		animation_tree.active = true
		animation_state.travel("Walk")
	
	# Reconnect animation_player to use Player's override
	if animation_player:
		# Get all connections
		var connections = animation_player.animation_finished.get_connections()
		for connection in connections:
			# Disconnect all existing connections to avoid duplicates
			animation_player.animation_finished.disconnect(connection["callable"])
		# Connect to Player's override
		animation_player.animation_finished.connect(_on_animation_player_finished)
		print("[PLAYER READY] Connected animation_player.animation_finished to Player's handler | Seat: ", seat)
	
	# 🟢 【新增】設置 metadata 讓 FrameBar 可以找到玩家的 seat
	set_meta("player_seat", seat)
	
	add_to_group("players")
	if player_controller:
		player_controller.player_seat = seat  # ← 這一行一定要加！
	hit_detected.connect(_on_hit_detected)
	skip_pushbox = false
	
	# 初始化 Handlers (Phase 1-2 重構)
	_initialize_handlers()
	
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

# Override take_hit to clear attack timer when getting hit
func take_hit(
	hitstun_duration: int = 18,
	blockstun_duration: int = 10,
	damage: float = 10.0,
	skip_push: bool = false,
	force_knockfly: bool = false,
	knockfly_params: Dictionary = {},
	knockback_distance: float = -1.0
) -> void:
	# Clear attack timer when getting hit
	attack_duration_timer = 0
	# Call parent implementation
	super.take_hit(hitstun_duration, blockstun_duration, damage, skip_push, force_knockfly, knockfly_params, knockback_distance)

func _physics_process(delta: float) -> void:
	if has_node("InputManager"):
		$InputManager.update_input()
	
	# ── 攻擊移動處理（必須在 super._physics_process 之前，確保速度在應用前被設置） ──
	if attack_movement_handler:
		attack_movement_handler.process_movement(delta)
	
	super._physics_process(delta)
	if not world: return

	# Handle air attack landing
	# 【重點】檢查是否已經由 LandingHandler 處理
	if is_air_attacking and is_on_floor() and not is_landing:
		is_air_attacking = false
		is_attacking = false
		var air_input_data = get_input()
		if not (air_input_data.input_dir != 0 or air_input_data.crouch_pressed or air_input_data.jump_pressed):
			is_landing = true
			# 轉換 landing_duration（秒）為幀數 @120 FPS (PHYSICS_FPS)
			landing_lock_timer = int(round(landing_duration * 120)) if "landing_duration" in self else 24
			print("[ON FLOOR LANDING DEBUG] Landing triggered | duration: %.3fs -> timer: %d frames @120 FPS" % [landing_duration, landing_lock_timer])
			animation_state.travel("landing")
		else:
			is_landing = false
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
	if is_attacking and cancel_window_handler:
		var input_move = input_data.get("attack_type", "none")
		if cancel_window_handler.check_cancel(input_move, attack_type):
			stop_attack()

	# 在取消判定之後才清空按鈕輸入，避免影響特殊招檢測
	if is_attacking and animation_state.get_current_node() in ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk", "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk"]:
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false

	# 🟢 【DP修正】特殊招式必須無條件呼叫 process_move，否則 timer 倒數無法進行
	# DP 會跳起來，導致 is_valid_ground_state=false，如果檢查該條件就會跳過 process_move
	# 結果：timer 永遠不倒數，動畫無法自然完成，導致狀態永遠鎖定
	if move_set and move_set.is_spmove:
		# 特殊招式中：無條件呼叫 process_move
		if move_set.process_move(delta, input_data, true):
			return
	elif move_set and move_set.process_move(delta, input_data, is_valid_ground_state):
		return

	# 檢查取消窗口是否開啟
	var is_cancel_open = cancel_window_handler and cancel_window_handler.is_window_open
	if is_cancel_open:
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false

	# ── 地面攻擊執行（使用 AttackExecutor Handler）──
	if (input_data.st_lp_pressed or input_data.st_mp_pressed or input_data.st_hp_pressed or input_data.st_lk_pressed or input_data.st_mk_pressed or input_data.st_hk_pressed) and is_valid_ground_state:
		force_update_facing_direction()
		if attack_executor and attack_executor.try_execute_ground_attack(input_data, is_crouching):
			# 攻擊已執行，只有在沒有攻擊移動激活時才清零速度
			var has_active_movement = attack_movement_handler and attack_movement_handler.is_active()
			if not is_push_back and not has_active_movement:
				fixed_velocity.x = 0

	# ── 空中攻擊執行（使用 AttackExecutor Handler）──
	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup and not has_air_attacked and not is_layground
	
	if is_valid_air_state and attack_executor:
		attack_executor.try_execute_air_attack(input_data)
	else:
		# 調試：顯示空中攻擊被阻擋的原因
		if attack_executor:
			attack_executor.debug_air_attack_blocked(input_data, self)

	# 【重點】landing_lock_timer 現在由 TimerHandler 管理，不在這裡遞減
			landing_facing_lock = false
			has_air_attacked = false
			update_facing_direction()
			_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
		elif landing_lock_timer <= 0 and is_landing:
			is_landing = false
			has_air_attacked = false
			landing_facing_lock = false

	# Countdown wakeup timer (FRAME-BASED)
	if wakeup_timer > 0:
		wakeup_timer -= 1
		if wakeup_timer <= 0 and is_wakeup_locked:
			is_wakeup = false
			is_wakeup_locked = false
			is_landing = false
			attack_duration_timer = 0
			update_facing_direction()
	
	if not (landing_lock_timer > 0):
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	var slowmo_controller = world.get_node_or_null("SlowMoController") if world else null
	var is_in_hitstop = slowmo_controller and slowmo_controller.is_hit_slowmo
	if is_in_hitstop and not _was_in_hitstop:
		var anim_name = animation_player.current_animation if animation_player else ""
		var anim_pos = animation_player.current_animation_position if animation_player else 0.0
		print("[HITSTOP PAUSE] Seat=%s attack=%s timer=%d anim=%s pos=%.3f" % [seat, attack_type, attack_duration_timer, anim_name, anim_pos])
	elif not is_in_hitstop and _was_in_hitstop:
		print("[HITSTOP RESUME] Seat=%s attack=%s timer=%d" % [seat, attack_type, attack_duration_timer])
	_was_in_hitstop = is_in_hitstop
	
	# Countdown attack duration timer (FRAME-BASED, only when actually attacking)
	if is_attacking and attack_duration_timer > 0 and not is_in_hitstop:
		attack_duration_timer -= 1
		if attack_duration_timer <= 0:
			reset_attack_state()

func _physics_process_jump(_delta: float) -> void:
	var input_data = get_input()
	if input_data.jump_pressed and is_on_floor() and not is_dashing and not is_backdashing and not is_attacking and not is_hit and not is_knockfly and not is_blocking and not is_layground:
		# Consume the buffered jump input
		if player_controller and player_controller.has_method("consume_button_input"):
			player_controller.consume_button_input("jump")
		
		is_jumping = true
		has_air_attacked = false
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
		# 地面受擊：根據受擊時的姿勢選擇動畫
		if on_floor:
			return "cr_hit" if was_hit_while_crouching else "hit"
		return "Jump_B"

	if move_set and move_set.is_spmove:
		var active_move_name = move_set.get_active_move_name()
		if active_move_name in ["super", "powerkk", "dp", "spnk", "fireball"]:
			return active_move_name

	if is_blocking:
		return "cr_block" if is_crouch_blocking and crouch_input else "block"

	if is_landing and landing_lock_timer > 0:
		return "landing"

	# Air attack animation logic - only when actually in the air
	if not on_floor and (is_jumping or is_air_attacking):
		if is_air_attacking:
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
		# Set wakeup timer based on animation length (converted to frame count @60FPS - LOGIC_FPS)
		if animation_player and animation_player.has_animation("wakeup"):
			var wakeup_duration = animation_player.get_animation("wakeup").length
			# 🔴 【關鍵修復】wakeup_timer 需轉換爲 ×120 幀數（120 FPS 物理中逅減）
			wakeup_timer = int(round(wakeup_duration * 120))
			print("[WAKEUP DEBUG] wakeup_duration: %.3fs -> wakeup_timer: %d frames @120 FPS physics" % [wakeup_duration, wakeup_timer])
		else:
			wakeup_timer = 60  # 1.0 second = 60 frames @60FPS logic = 120 frames @120 FPS physics
		animation_state.travel("wakeup")

# Override parent's animation finished handler to use player_anim_resets
func _on_animation_player_finished(anim_name: String) -> void:
	"""動畫完成回調（Phase 4 優化：使用分類判斷）"""
	var seat_str = seat if seat else "?"
	var is_special_move = move_set and move_set.get_active_move_name() in move_set.move_library if move_set else false
	print("[✓ ANIM_FINISHED] '%s' | Seat: %s | is_spmove=%s | is_attacking=%s" % [anim_name, seat_str, is_special_move, is_attacking])
	
	# 地面攻擊重置
	if anim_name in GROUND_ATTACK_ANIMS:
		print("  → Ground attack reset")
		reset_attack_state()
	# 空中攻擊重置
	elif anim_name in AIR_ATTACK_ANIMS:
		print("  → Air attack reset")
		reset_air_state()
	# 跳躍重置
	elif anim_name in JUMP_ANIMS:
		print("  → Jump reset")
		_reset_jump_state()
	# 特殊招式重置
	elif anim_name in SPECIAL_ANIMS:
		print("  → Special move reset")
		# 🟢 【DP自帶著地修正】DP/HDK/POWERKK自帶著地動畫，完成時視為著地完成
		if move_set and move_set.get_active_move_name() in ["dp", "hdk", "powerkk"]:
			print("     (self-landing move)")
		reset_special_state()
	# 著地重置
	elif anim_name == "landing":
		print("  → Landing reset")
		_reset_landing_anim()
	else:
		# 如果不在上述分類中，調用父類方法
		print("  → Parent handler")
		super._on_animation_player_finished(anim_name)

func _reset_jump_state() -> void:
	"""跳躍動畫結束重置"""
	# 【重點】如果正在著地期間，不要修改landing狀態
	if is_landing and landing_lock_timer > 0:
		return
	
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
			landing_lock_timer = int(round(landing_duration * 120)) if "landing_duration" in self else int(24)
			print("[AIR LANDING DEBUG] is_landing set | duration: %.3fs -> timer: %d frames @120 FPS" % [landing_duration, landing_lock_timer])

func _reset_landing_anim() -> void:
	"""著地動畫結束重置"""
	# 【重點】如果在強制2幀期間，不要重置
	if _landing_forced_frames < 2:
		return
	
	is_landing = false
	# 【重點】landing_lock_timer 由 TimerHandler 統一管理，不在這裡重置
	has_air_attacked = false
	var input_data = get_input()
	_update_animation_state(0, input_data.crouch_pressed)

# ── 擊中處理（Phase 4：委派給 HitResponseHandler）─────────────────────
func _on_hitbox_area_entered(area: Area2D) -> void:
	"""Hitbox 碰撞處理（委派給 HitResponseHandler）"""
	if hit_response_handler:
		hit_response_handler.handle_hitbox_collision(area)

func _on_hit_detected(_target: String, _stun_duration: float, _is_blocked: bool, _was_in_stun: bool) -> void:
	# 擊中確認取消（Hit-Confirm Cancel）：只有在擊中對手時才真正開啟取消窗口
	if cancel_window_handler:
		cancel_window_handler.on_hit_confirm()

# ═══════════════════════════════════════════════════════════
# 取消窗口系統（純 Call Method Track - Option 1）
# ═══════════════════════════════════════════════════════════
# 這些方法會被 AnimationPlayer 的 Call Method Track 調用
# open_cancel_window 時開啟，close_cancel_window 時關閉，不需要 timer

# 準備取消窗口（由動畫軌道調用，等待擊中確認）
# allowed_moves: 允許取消成的招式陣列，例如 ["powerkk", "fireball"]
func _open_cancel_window(allowed_moves: Array = []) -> void:
	# 由動畫軌道調用，委派給 CancelWindowHandler
	if cancel_window_handler:
		cancel_window_handler.open_window(allowed_moves)

# 關閉取消窗口（由動畫軌道調用）
func _close_cancel_window() -> void:
	# 由動畫軌道調用，委派給 CancelWindowHandler
	if cancel_window_handler:
		cancel_window_handler.close_window()

# ═══════════════════════════════════════════════════════════

func stop_attack() -> void:
	is_attacking = false
	attack_type = "none"
	if cancel_window_handler:
		cancel_window_handler.reset()
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

# _process 已移除 - 陰影同步由 ShadowSyncHandler 處理

# ══════════════════════════════════════════════════════════════════
# ── 攻擊移動系統 ─────────────────────
# ══════════════════════════════════════════════════════════════════

func _execute_attack(attack_name: String) -> void:
	"""統一的攻擊執行函式，處理傷害設置、狀態變更和移動啟動"""
	print("[EXECUTE_ATTACK] attack_name: ", attack_name, " | Seat: ", seat)
	if not attack_name in ATTACK_TABLE:
		print("[EXECUTE_ATTACK] NOT in ATTACK_TABLE")
		return
	
	current_damage = ATTACK_TABLE[attack_name].damage
	is_attacking = true
	attack_type = attack_name
	
	# 🟢 【新增】記錄攻擊開始幀（用於精確計算優勢）
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter:
		attack_start_frame = frame_counter.get_current_frame()
		print("[EXECUTE_ATTACK] 記錄攻擊開始幀：%d (120 FPS 物理幀)" % attack_start_frame)
	else:
		attack_start_frame = -1
	
	# Get animation duration and set timer (convert to frames @120 FPS PHYSICS - multiply by 2 since 120/60=2)
	if animation_player and animation_player.has_animation(attack_name):
		var anim_length = animation_player.get_animation(attack_name).length
		# 🔴 【關鍵修復】attack_duration_timer 應按 120 FPS 物理幀計算
		# 邏輯：動畫時長（秒）× 60 FPS（邏輯幀）× 2（物理幀轉換係數）= 對應的物理幀數
		attack_duration_timer = int(round(anim_length * 60 * 2))
		print("[EXECUTE_ATTACK] Set attack_duration_timer=%d frames for %s (duration: %.3fs @60 FPS logic = %d @120 FPS physics)" % [int(round(anim_length * 60)), attack_name, anim_length, attack_duration_timer])
	else:
		# Default: 0.5 seconds @ 60 FPS = 30 frames → × 2 = 60 frames @ 120 FPS
		attack_duration_timer = 60
		print("[EXECUTE_ATTACK] Animation not found, using default timer=60 frames (@120 FPS physics)")
	
	print("[EXECUTE_ATTACK] Set is_attacking=true, attack_type=", attack_name)
	
	# Immediately switch to attack animation
	if animation_state:
		animation_state.travel(attack_name)
		print("[EXECUTE_ATTACK] Switched animation to: ", attack_name)
	
	# 啟動攻擊移動（如果有設定）
	if attack_movement_handler:
		attack_movement_handler.start_movement(attack_name, ATTACK_TABLE)

# ══════════════════════════════════════════════════════════════════
# ── Handler 初始化 (Phase 1-2 重構) ──
# ══════════════════════════════════════════════════════════════════

func _initialize_handlers() -> void:
	"""初始化所有 Handlers (Phase 1-3)"""
	# Phase 1: ShadowSyncHandler
	var shadow_handler = ShadowSyncHandler.new()
	shadow_handler.name = "ShadowSyncHandler"
	add_child(shadow_handler)
	shadow_sync_handler = shadow_handler
	
	# Phase 2: AttackMovementHandler
	var movement_handler = AttackMovementHandler.new()
	movement_handler.name = "AttackMovementHandler"
	add_child(movement_handler)
	attack_movement_handler = movement_handler
	
	# Phase 2: CancelWindowHandler
	var cancel_handler = CancelWindowHandler.new()
	cancel_handler.name = "CancelWindowHandler"
	add_child(cancel_handler)
	cancel_window_handler = cancel_handler
	
	# Phase 3: AttackExecutor
	var executor = AttackExecutor.new(self)
	executor.name = "AttackExecutor"
	add_child(executor)
	attack_executor = executor
	
	# Phase 4: HitResponseHandler
	var hit_handler = HitResponseHandler.new(self)
	hit_handler.name = "HitResponseHandler"
	add_child(hit_handler)
	hit_response_handler = hit_handler
	
	print("[Player] Handlers 初始化完成 (Phase 1-4) | Seat: ", seat)
