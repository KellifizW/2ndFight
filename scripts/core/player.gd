class_name Player extends Fighter

signal hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool)

@export var character_data: CharacterData      # 在角色場景中拖入對應的 .character.tres
@export var is_ai_controlled: bool = false
@export var corner_push_distance: float = 250.0
# Stage 2：`cancel_window_duration`（秒）已刪除 —— 取消窗口早已改為純
# Call Method 軌道驅動（CancelWindowHandler 的 open/close），沒有計時器讀它。
@export var skip_pushbox: bool = false
@export var attack_data: AttackData
@export var throw_data: ThrowData
@export var startup_logs: bool = false

var ATTACK_TABLE: Dictionary = {}
const _ATTACK_NAMES: Array = [
	"st_lp","st_mp","st_hp","st_lk","st_mk","st_hk",
	"cr_lp","cr_mp","cr_hp","cr_lk","cr_mk","cr_hk",
	"jump_lp","jump_mp","jump_hp","jump_lk","jump_mk","jump_hk",
]

# Stage 2：`powerkk_blockstun` 已刪除（零讀取；powerkk 的 blockstun 走招式數據）。

@onready var move_set = $MoveSet if has_node("MoveSet") else null
@onready var player_controller = $PlayerController if has_node("PlayerController") else null

# 新增 Handlers (Phase 1-4 重構)
@onready var shadow_sync_handler: ShadowSyncHandler = null
@onready var attack_movement_handler: AttackMovementHandler = null
@onready var cancel_window_handler: CancelWindowHandler = null
@onready var attack_executor: AttackExecutor = null
@onready var hit_response_handler: HitResponseHandler = null
@onready var throw_handler: ThrowHandler = null

# 新增：由 world.gd 動態生成時設定，決定這個角色是左邊還是右邊玩家
var seat: String = "player_a"  # "player_a" 或 "player_b"

# 角色唯一 ID（例如 "DAV" 或 "DEN"），用來判斷特殊招式
var character_id: String:
	get: return character_data.short_id if character_data else "UNKNOWN"

# Fireball 管理：追蹤當前活躍的 fireball 實例（同一時間只能有一個）
var active_fireball: Node = null

# ── 攻擊重複執行防護 (Attack Repetition Prevention) ──
# 【FIX】業界標準：防止同一攻擊在相鄰幀中重複執行
# 根本原因：reset_attack_state() 後，同一幀仍可被重新觸發
# 解決方案：鎖定上一次執行的攻擊，在新動畫完全開始前拒絕重複
var last_executed_attack: String = ""  # Track which attack was just executed (e.g., "st_hp")
var last_executed_attack_frame: int = -999  # Frame when it was executed
# 【修復】鎖定改為 1 物理幀（只防止真正的同幀重複執行）
# 原為 2 造成可感知的鎖定間隔（玩家進行快速連按時有明顯頓感）
var attack_execution_lock_frames: int = 1  # Minimum frames between same attack re-execution

# ── 狀態旗標 ─────────────────────
# Stage 2：`current_mode` 已刪除（只有 world.reset_players() 寫入，零讀取）。
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
	# 【FIX】記錄上次執行的攻擊及其幀數，用於防止同幀重複執行
	if attack_type != "none" and attack_type != "":
		var frames_elapsed = Engine.get_physics_frames() - last_executed_attack_frame
		last_executed_attack = attack_type
		last_executed_attack_frame = Engine.get_physics_frames()
	
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
	self.landing_lock_frames = 0
	self.landing_facing_lock = false
	self.update_facing_direction()
	# 获取当前真实的输入状态，保持蹲状态
	var input_data = get_input()
	_update_animation_state(0, input_data.crouch_pressed)

func reset_air_state() -> void:
	# 【重點】如果正在著地期間，不要修改landing狀態
	if self.is_landing and self.landing_lock_frames > 0:
		return
	
	if not self.is_on_floor():
		self.is_air_attacking = false
		self.is_attacking = false
		self.attack_type = "none"
		var air_input_data = get_input()
		self._update_animation_state(air_input_data.input_dir, air_input_data.crouch_pressed)
		return
	
	if self.is_on_floor():
		self.is_air_attacking = false
		self.has_air_attacked = false
		self.is_jumping = false
		self.just_jumped = false
		self.is_attacking = false
		self.attack_type = "none"
		if self.world:
			self.fixed_position.y = self.world.FLOOR_Y
			self.global_position = self.world.to_scaled_vector2(self.fixed_position)
		self.fixed_velocity.y = 0
		_enter_landing_state("AIR LANDING DEBUG")

func reset_special_state() -> void:
	var move_name = move_set.get_active_move_name() if move_set and move_set.has_method("get_active_move_name") else "UNKNOWN"
	var seat_str = seat if seat else "?"
	Debug.log("[RESET_SPECIAL] Move '%s' | Seat: %s" % [move_name, seat_str])
	
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
	# 🟢 【強化除錯】Call Method 觸發時加入詳細信息
	var debug_seat = seat if seat else "unknown"
	var anim_player = get_node_or_null("AnimationPlayer")
	var current_anim = anim_player.current_animation if anim_player else "none"
	
	Debug.log("[_spawn_fireball CALLED] Seat=%s | Current animation='%s' | is_spmove=%s | active_move=%s | frame=%d" % [
		debug_seat,
		current_anim,
		move_set.is_spmove if move_set else "?",
		move_set.current_move_state.active_move.name if (move_set and move_set.current_move_state.active_move) else "null",
		Engine.get_physics_frames()
	])
	
	# 通知 FrameBar call method 已被觸發
	var frame_bar = get_tree().get_first_node_in_group("frame_bar_" + debug_seat) if debug_seat else null
	if frame_bar and frame_bar.has_method("on_fireball_call_method_triggered"):
		frame_bar.on_fireball_call_method_triggered()
	
	if move_set and move_set.has_method("execute_fireball_spawn"):
		move_set.execute_fireball_spawn()
	else:
		Debug.log("[_spawn_fireball] ⚠️ MoveSet not found or doesn't have execute_fireball_spawn! (Seat=%s)" % debug_seat)

# ── 動畫重置分類（Phase 4 優化）──
const GROUND_ATTACK_ANIMS = ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
							  "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk"]
const AIR_ATTACK_ANIMS = ["jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk"]
const JUMP_ANIMS = ["jump_v", "Jump_V", "Jump_F", "Jump_B"]
const SPECIAL_ANIMS = ["fireball", "powerkk", "spnk", "dp", "hdk",
					   "fireballL", "fireballM", "fireballH",
					   "dpL", "dpM", "dpH"]

# ── 輸入輔助函數（取代 3 處重複的 6-button OR 檢查）──────────────────────────
static func _has_any_input(d: Dictionary) -> bool:
	return d.input_dir != 0 or d.crouch_pressed or d.jump_pressed \
		or d.st_lp_pressed or d.st_mp_pressed or d.st_hp_pressed \
		or d.st_lk_pressed or d.st_mk_pressed or d.st_hk_pressed \
		or d.spm1_pressed or d.spm2_pressed or d.dp_pressed

static func _has_attack_input(d: Dictionary) -> bool:
	return d.st_lp_pressed or d.st_mp_pressed or d.st_hp_pressed \
		or d.st_lk_pressed or d.st_mk_pressed or d.st_hk_pressed \
		or d.get("throw_pressed", false)

func _ready() -> void:
	for a in _ATTACK_NAMES:
		ATTACK_TABLE[a] = attack_data.get_attack(a)
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
		if startup_logs:
			Debug.log("[PLAYER READY] Connected animation_player.animation_finished to Player's handler | Seat: ", seat)
	
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

func get_throw_data() -> Dictionary:
	if throw_data:
		return throw_data.get_throw_data()
	return {}

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
	if is_attacking and attack_type in ["throw_enter", "throw_seq"]:
		return default_input.duplicate()
	# 被摔投期間禁止任何輸入（防止受害者在摔投期間生成攻擊）
	if "is_being_thrown" in self and self.is_being_thrown:
		return default_input.duplicate()
	if is_ai_controlled:
		var ai = $AIBehavior if has_node("AIBehavior") else null
		if ai and ai.has_method("get_ai_input"):
			var ai_input: Dictionary = default_input.duplicate()
			ai_input.merge(ai.get_ai_input(), true)
			return ai_input
		push_warning("[Player] %s is AI-controlled but AIBehavior input provider is unavailable" % seat)
		return default_input.duplicate()
	if player_controller:
		var data = player_controller.get_input_data()
		data.super_pressed = Input.is_key_pressed(KEY_P)
		data.merge(special_input_data, true)
		
		# 【NEW】Check for throw interrupt: if throw buffered while attacking regular move, cancel it
		# This handles the case where throw is detected AFTER st_lk started in the same frame
		if data.get("throw_pressed", false) and is_attacking and attack_type not in ["throw_enter", "throw_seq"]:
			Debug.log("[THROW INTERRUPT] Frame=%d Seat=%s | Throw detected while attacking '%s', will interrupt" % [
				Engine.get_physics_frames(), seat, attack_type
			])
			# Don't return yet - let Player decide in attack logic
		
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
	if hit_response_handler:
		hit_response_handler.process_multi_hit_overlaps()
	
	# ── 攻擊移動處理（必須在 super._physics_process 之前，確保速度在應用前被設置） ──
	if attack_movement_handler:
		attack_movement_handler.process_movement(delta)
	
	super._physics_process(delta)
	if not world: return

	# Handle air attack landing
	# 【重點】檢查是否已經由 LandingHandler 處理
	if is_air_attacking and is_on_floor() and not is_landing:
		is_air_attacking = false
		has_air_attacked = false
		is_jumping = false
		just_jumped = false
		is_attacking = false
		attack_type = "none"
		if world:
			fixed_position.y = world.FLOOR_Y
			global_position = world.to_scaled_vector2(fixed_position)
		fixed_velocity.y = 0
		_enter_landing_state("ON FLOOR LANDING DEBUG")

	var input_data = get_input()
	input_data.merge(special_input_data, true)

	if throw_handler:
		throw_handler.handle_throw(delta, input_data)

	# 移除：這段邏輯會在取消判定前清空按鈕，導致 attack_type 無法正確檢測
	# if input_data.spm2_pressed or input_data.dp_pressed or input_data.spm1_pressed or input_data.super_pressed:
	#     input_data.st_mp_pressed = false
	#     input_data.st_mk_pressed = false

	var is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup and not is_layground and not (is_landing and landing_lock_frames > Movement.LANDING_INTERRUPT_FRAMES)

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
	# 【DEBUG ATTACK LOCK】追蹤攻擊輸入清除的原因
	var _has_any_atk_input_pre_block = _has_attack_input(input_data)
	if is_attacking and animation_state.get_current_node() in ["st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk", "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk"]:
		if _has_any_atk_input_pre_block and not is_ai_controlled:
			var frames_held = Engine.get_physics_frames() - last_executed_attack_frame
			Debug.log("[LOCK_TRACE:IS_ATTACKING] F=%d Seat=%s | is_attacking=true anim_node='%s' attack_type='%s' | Input cleared (lock_frame=%d, held=%d physF=%.1f logicF)" % [
				Engine.get_physics_frames(), seat,
				animation_state.get_current_node(), attack_type,
				last_executed_attack_frame, frames_held, frames_held / 2.0
			])
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false
		input_data["throw_pressed"] = false  # 摔投不能從普通攻擊取消

	# 🟢 【DP修正】特殊招式必須無條件呼叫 process_move，否則 timer 倒數無法進行
	# DP 會跳起來，導致 is_valid_ground_state=false，如果檢查該條件就會跳過 process_move
	# 結果：timer 永遠不倒數，動畫無法自然完成，導致狀態永遠鎖定
	
	# DEBUG: Log AI special move input reception
	var has_special_input = input_data.get("spm2_pressed", false) or input_data.get("spm1_pressed", false) or input_data.get("dp_pressed", false)
	if is_ai_controlled and Engine.get_physics_frames() % 30 == 0 and has_special_input:
		Debug.log("[Player INPUT] Frame=%d Seat=%s spm2=%s spm1=%s dp=%s ground_state=%s" % [
			Engine.get_physics_frames(), seat, 
			input_data.get("spm2_pressed", false),
			input_data.get("spm1_pressed", false),
			input_data.get("dp_pressed", false),
			is_valid_ground_state
		])
	
	if move_set and move_set.is_spmove:
		# 特殊招式中：無條件呼叫 process_move
		if is_ai_controlled and Engine.get_physics_frames() % 30 == 0 and has_special_input:
			Debug.log("[Player PROCESS_MOVE] Frame=%d Seat=%s calling process_move(delta, input_data, true)" % [Engine.get_physics_frames(), seat])
		if move_set.process_move(delta, input_data, true):
			return
	elif move_set:
		if is_ai_controlled and Engine.get_physics_frames() % 30 == 0 and has_special_input:
			Debug.log("[Player PROCESS_MOVE] Frame=%d Seat=%s calling process_move(delta, input_data, %s)" % [Engine.get_physics_frames(), seat, is_valid_ground_state])
		if move_set.process_move(delta, input_data, is_valid_ground_state):
			return

	# 檢查取消窗口是否開啟
	var is_cancel_open = cancel_window_handler and cancel_window_handler.is_window_open
	var _has_any_atk_input_post_block = _has_attack_input(input_data)
	if is_cancel_open:
		if _has_any_atk_input_post_block and not is_ai_controlled:
			var frames_held = Engine.get_physics_frames() - last_executed_attack_frame
			Debug.log("[LOCK_TRACE:CANCEL_OPEN] F=%d Seat=%s | cancel_window OPEN | attack_type='%s' | Input cleared (lock_frame=%d, held=%d physF=%.1f logicF)" % [
				Engine.get_physics_frames(), seat, attack_type,
				last_executed_attack_frame, frames_held, frames_held / 2.0
			])
		input_data.st_lp_pressed = false
		input_data.st_mp_pressed = false
		input_data.st_hp_pressed = false
		input_data.st_lk_pressed = false
		input_data.st_mk_pressed = false
		input_data.st_hk_pressed = false

	# ── 地面攻擊執行（使用 AttackExecutor Handler）──
	var has_ground_attack_input := _has_attack_input(input_data)
	
	# 【DEBUG LOCK TRACE】當輸入通過所有清除保護後，追蹤最終狀態
	if not is_ai_controlled and (input_data.get("st_lp_pressed", false) or input_data.get("st_mp_pressed", false) or input_data.get("st_hp_pressed", false) or input_data.get("st_lk_pressed", false) or input_data.get("st_mk_pressed", false) or input_data.get("st_hk_pressed", false) or input_data.get("throw_pressed", false)):
		var frames_held = Engine.get_physics_frames() - last_executed_attack_frame
		Debug.log("[LOCK_TRACE:REACHED_EXEC] F=%d Seat=%s | st_lp=%s is_valid=%s is_attacking=%s anim='%s' | since_last: %d physF=%.1f logicF" % [
			Engine.get_physics_frames(), seat,
			input_data.get("st_lp_pressed", false), is_valid_ground_state, is_attacking,
			animation_state.get_current_node() if animation_state else "N/A",
			frames_held, frames_held / 2.0
		])
	elif not is_ai_controlled and has_ground_attack_input and not is_valid_ground_state:
		var frames_held2 = Engine.get_physics_frames() - last_executed_attack_frame
		var land_lock_val = landing_lock_frames if "landing_lock_frames" in self else -1
		Debug.log("[LOCK_TRACE:INVALID_STATE] F=%d Seat=%s | Input blocked by is_valid_ground_state=false | is_attacking=%s is_dashing=%s is_landing=%s land_lock=%df | since_last: %d physF=%.1f logicF" % [
			Engine.get_physics_frames(), seat,
			is_attacking, is_dashing, is_landing, land_lock_val,
			frames_held2, frames_held2 / 2.0
		])

	# 【著地攻擊取消】著地動畫可被攻擊指令取消（強制2幀後）
	if has_ground_attack_input and is_landing and _landing_forced_frames >= 2:
		is_landing = false
		landing_lock_frames = 0
		landing_facing_lock = false
		has_air_attacked = false
		# 重新計算 is_valid_ground_state（is_landing 已清除）
		is_valid_ground_state = is_on_floor() and not is_dashing and not is_backdashing and not is_jumping and not is_blocking and not is_knockfly and not is_wakeup and not is_layground

	if has_ground_attack_input and is_valid_ground_state:
		force_update_facing_direction()
		if attack_executor and attack_executor.try_execute_ground_attack(input_data, is_crouching):
			# 攻擊已執行，只有在沒有攻擊移動激活時才清零速度
			var has_active_movement = attack_movement_handler and attack_movement_handler.is_active()
			if not has_active_movement:
				fixed_velocity.x = 0
	
	# 【NEW】Throw can interrupt normal attacks (check separately)
	elif input_data.get("throw_pressed", false) and not is_crouching and is_attacking and attack_type not in ["throw_enter", "throw_seq"]:
		Debug.log("[THROW INTERRUPT EXECUTION] Frame=%d Seat=%s | Interrupting '%s' with throw" % [
			Engine.get_physics_frames(), seat, attack_type
		])
		if attack_executor:
			attack_executor.try_execute_ground_attack(input_data, is_crouching)

	# ── 空中攻擊執行（使用 AttackExecutor Handler）──
	var is_valid_air_state = not is_on_floor() and is_jumping and not is_air_attacking and not is_blocking and not is_knockfly and not is_hit and not is_wakeup and not has_air_attacked and not is_layground
	
	if is_valid_air_state and attack_executor:
		attack_executor.try_execute_air_attack(input_data)
	else:
		# 調試：顯示空中攻擊被阻擋的原因
		if attack_executor:
			attack_executor.debug_air_attack_blocked(input_data, self)

	# 【重點】landing_lock_frames 現在由 TimerHandler 管理，不在這裡遞減

	# Countdown wakeup timer (FRAME-BASED)
	if wakeup_timer > 0:
		wakeup_timer -= 1
		if wakeup_timer <= 0 and is_wakeup_locked:
			is_wakeup = false
			is_wakeup_locked = false
			is_landing = false
			attack_duration_timer = 0
			update_facing_direction()
	
	if not (landing_lock_frames > 0):
		_update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	var slowmo_controller = world.get_node_or_null("SlowMoController") if world else null
	var is_in_hitstop = slowmo_controller and slowmo_controller.is_hit_slowmo
	if is_in_hitstop and not _was_in_hitstop:
		var anim_name = animation_player.current_animation if animation_player else ""
		var anim_pos = animation_player.current_animation_position if animation_player else 0.0
	elif not is_in_hitstop and _was_in_hitstop:
		pass
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
		
		# 【新增詳細日誌】跳躍執行追蹤
		var frame_count = Engine.get_physics_frames()
		Debug.log("[JUMP EXEC] Frame=%d | Seat=%s | Pos(%.1f,%.1f) | Dir=%d | Vel.y=%d | jump_delay_timer=%d" % [
			frame_count, seat,
			global_position.x, global_position.y,
			input_data.input_dir,
			fixed_velocity.y,
			jump_delay_timer
		])
		
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
		# fireballL/M/H 各自播放獨立動畫（已在 dav.tscn 加入）
		if active_move_name in ["fireballL", "fireballM", "fireballH"]:
			return active_move_name
		if active_move_name in ["dpL", "dpM", "dpH"]:
			return active_move_name  # 🔴 FIX: return the variant directly (dpM/dpH/dpL), not "dp"
		if active_move_name in ["super", "powerkk", "dp", "spnk", "fireball"]:
			return active_move_name

	if is_blocking:
		return "cr_block" if is_crouch_blocking and crouch_input else "block"

	if is_landing and landing_lock_frames > 0:
		return "landing"

	# Air attack animation logic - only when actually in the air
	if not on_floor and (is_jumping or is_air_attacking):
		if is_air_attacking and attack_type in AIR_ATTACK_ANIMS:
			return attack_type
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
		# Set wakeup timer based on animation length (seconds → physics frames via Movement)
		if animation_player and animation_player.has_animation("wakeup"):
			var wakeup_duration = animation_player.get_animation("wakeup").length
			# Stage 1：秒→幀統一經唯一邊界 Movement.seconds_to_frames_nearest
			wakeup_timer = Movement.seconds_to_frames_nearest(wakeup_duration)
			Debug.log("[WAKEUP DEBUG] wakeup_duration: %.3fs -> wakeup_timer: %d frames @120 FPS physics" % [wakeup_duration, wakeup_timer])
		else:
			wakeup_timer = 60  # 1.0 second = 60 frames @60FPS logic = 120 frames @120 FPS physics
		animation_state.travel("wakeup")

# Override parent's animation finished handler to use player_anim_resets
func _on_animation_player_finished(anim_name: String) -> void:
	"""動畫完成回調（Phase 4 優化：使用分類判斷）"""
	var seat_str = seat if seat else "?"
	var is_special_move = move_set and move_set.has_move_id(move_set.get_active_move_name()) if move_set else false
	var frames_since_last = Engine.get_physics_frames() - last_executed_attack_frame
	Debug.log("[✓ ANIM_FINISHED] '%s' | Seat: %s | F=%d | is_spmove=%s | is_attacking=%s | since_last=%d physF(%.1f logicF)" % [anim_name, seat_str, Engine.get_physics_frames(), is_special_move, is_attacking, frames_since_last, frames_since_last / 2.0])
	
	# 地面攻擊重置
	if anim_name in GROUND_ATTACK_ANIMS:
		Debug.log("  → Ground attack reset")
		reset_attack_state()
	# 空中攻擊重置
	elif anim_name in AIR_ATTACK_ANIMS:
		Debug.log("  → Air attack reset")
		reset_air_state()
	# 跳躍重置
	elif anim_name in JUMP_ANIMS:
		Debug.log("  → Jump reset")
		_reset_jump_state()
	# 特殊招式重置
	elif anim_name in SPECIAL_ANIMS:
		Debug.log("  → Special move reset")
		# 🟢 【DP自帶著地修正】DP/HDK/POWERKK自帶著地動畫，完成時視為著地完成
		if move_set and move_set.get_active_move_name() in ["dp", "dpL", "dpM", "dpH", "hdk", "powerkk"]:
			Debug.log("     (self-landing move)")
		reset_special_state()
	# 摔投重置
	elif anim_name in ["throw_enter", "throw_seq"]:
		Debug.log("  → Throw reset")
		reset_attack_state()
	# 著地重置
	elif anim_name == "landing":
		Debug.log("  → Landing reset")
		_reset_landing_anim()
	else:
		# 如果不在上述分類中，調用父類方法
		Debug.log("  → Parent handler")
		super._on_animation_player_finished(anim_name)

func _reset_jump_state() -> void:
	"""跳躍動畫結束重置"""
	# 【重點】如果正在著地期間，不要修改landing狀態
	if is_landing and landing_lock_frames > 0:
		return
	
	if is_on_floor():
		is_jumping = false
		_enter_landing_state("AIR LANDING DEBUG")

func _reset_landing_anim() -> void:
	"""著地動畫結束重置"""
	# 【重點】如果在強制2幀期間，不要重置
	if _landing_forced_frames < 2:
		return

	# 【Stage 1 不變量】landing 狀態的唯一權威計時是 TimerHandler 的幀計數器
	# （每物理幀 -1，歸零時才清 is_landing）。landing 動畫（DAV/DEN 皆 0.2s）
	# 會在 lock 歸零前幾幀先播完：若在這裡提前清 is_landing，會留下
	# 「is_landing=false 但 landing_lock_frames>0」的殘留鎖 —— 不只凍結
	# _update_animation_state（它只看 lock>0），也讓著地時長取決於動畫
	# wall-clock 而非物理幀。動畫先播完時停在最後一幀，等 TimerHandler
	# 遞減到 0 時統一收尾（與輸入中斷著地的收尾路徑完全相同）。
	if is_landing and landing_lock_frames > 0:
		Debug.log("[LANDING_ANIM_EARLY_FINISH] lock=%df remains; TimerHandler will finish landing" % landing_lock_frames)
		return

	is_landing = false
	# 【重點】landing_lock_frames 由 TimerHandler 統一管理，不在這裡重置
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

## 為摔投中斷特別設計的停止攻擊函式
func stop_attack_for_throw() -> void:
	# 【THROW INTERRUPT】停止當前攻擊以準備摔投
	# 用於摔投偵測時立即中斷st_lp/st_lk等攻擊
	stop_attack()

func get_facing_multiplier() -> float:
	return super.get_facing_multiplier()

func update_facing_direction() -> void:
	if is_facing_locked: return
	super.update_facing_direction()

## 進入著地狀態（Stage 1：統一原本散落在三處的相同 8 行 pattern）。
##
## 原本 player.gd 有三段一字不差的複製：空中重置、on-floor 分支、跳躍動畫結束。
## 任何一處漏改都會造成著地行為不一致 —— 這正是 Stage 1 要消滅的耦合。
## LandingHandler._handle_normal_landing 另有一份變體（多了 neutral_timer 等重置），
## 保持獨立，因為它額外負責清 pending_dash_dir 與播放粒子。
##
## debug_tag 只影響 log 前綴，不影響行為。
func _enter_landing_state(debug_tag: String) -> void:
	var input_data = get_input()
	is_landing = true
	landing_lock_frames = LANDING_FORCED_LOCK_FRAMES
	landing_facing_lock = false
	_landing_checkpoint_executed = false
	_landing_forced_frames = 0
	# 【面向規則】與 LandingHandler._handle_normal_landing 一致：
	# 著地「開始」不翻面。cross-up 後的翻面統一由 TimerHandler 在
	# landing_lock_frames 歸零（著地動畫播完）那一刻執行。
	# 這裡原本的 force_update_facing_direction() 會繞過所有鎖，
	# 造成「還沒完成著地就轉身」。
	Debug.log("[%s] is_landing set | forced lock: %df" % [debug_tag, landing_lock_frames])
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func force_update_facing_direction() -> void:
	if facing_handler:
		facing_handler.update_facing_direction(true)

# _process 已移除 - 陰影同步由 ShadowSyncHandler 處理

# ══════════════════════════════════════════════════════════════════
# ── 攻擊移動系統 ─────────────────────
# ══════════════════════════════════════════════════════════════════

func _execute_attack(attack_name: String) -> void:
	"""統一的攻擊執行函式，處理傷害設置、狀態變更和移動啟動"""
	Debug.log("[EXECUTE_ATTACK] attack_name: ", attack_name, " | Seat: ", seat)
	
	# 【FIX】攻擊去重防護：防止同一攻擊在相鄰幀中重複執行（業界標準）
	# 根本原因：reset_attack_state()後同一幀可能再次觸發相同按鍵
	# 如果上一幀剛剛執行了這個攻擊，拒絕這一幀的重複執行
	var current_frame = Engine.get_physics_frames()
	var frames_since_last_exec = current_frame - last_executed_attack_frame
	var is_same_attack_repeat = (last_executed_attack == attack_name and frames_since_last_exec < attack_execution_lock_frames)
	
	if is_same_attack_repeat:
		Debug.log("[LOCK_TRACE:DEDUP] F=%d Seat=%s | Rejecting '%s' - last exec %d physF ago (%.1f logicF), lock=%d physF (%.1f logicF)" % [
			current_frame, seat, attack_name,
			frames_since_last_exec, frames_since_last_exec / 2.0,
			attack_execution_lock_frames, attack_execution_lock_frames / 2.0
		])
		return  # 拒絕執行，直到鎖定期結束
	
	var is_throw_attack = attack_name in ["throw_enter", "throw_seq"]
	if not is_throw_attack and not attack_name in ATTACK_TABLE:
		Debug.log("[EXECUTE_ATTACK] NOT in ATTACK_TABLE")
		return
	
	if not is_throw_attack:
		current_damage = ATTACK_TABLE[attack_name].damage
	else:
		current_damage = 0.0
	is_attacking = true
	attack_type = attack_name
	if is_throw_attack and throw_handler:
		throw_handler.try_initiate_throw({})
	
	# 🟢 【新增】記錄攻擊開始幀（用於精確計算優勢）
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter:
		attack_start_frame = frame_counter.get_current_frame()
		Debug.log("[EXECUTE_ATTACK] 記錄攻擊開始幀：%d (120 FPS 物理幀)" % attack_start_frame)
	else:
		attack_start_frame = -1
	
	# Get animation duration and set timer (convert to frames @120 FPS PHYSICS - multiply by 2 since 120/60=2)
	if animation_player and animation_player.has_animation(attack_name):
		var anim_length = animation_player.get_animation(attack_name).length
		# 🔴 【關鍵修復】attack_duration_timer 應按 120 FPS 物理幀計算
		# 邏輯：動畫時長（秒）× 60 FPS（邏輯幀）× 2（物理幀轉換係數）= 對應的物理幀數
		attack_duration_timer = int(round(anim_length * 60 * 2))
		Debug.log("[EXECUTE_ATTACK] Set attack_duration_timer=%d frames for %s (duration: %.3fs @60 FPS logic = %d @120 FPS physics)" % [int(round(anim_length * 60)), attack_name, anim_length, attack_duration_timer])
	else:
		# Default: 0.5 seconds @ 60 FPS = 30 frames → × 2 = 60 frames @ 120 FPS
		attack_duration_timer = 60
		Debug.log("[EXECUTE_ATTACK] Animation not found, using default timer=60 frames (@120 FPS physics)")
	
	Debug.log("[EXECUTE_ATTACK] Set is_attacking=true, attack_type=", attack_name)
	
	# Immediately switch to attack animation
	if animation_state:
		animation_state.travel(attack_name)
		Debug.log("[EXECUTE_ATTACK] Switched animation to: ", attack_name)
	
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

	# Phase 5: ThrowHandler
	var handler_throw = ThrowHandler.new()
	handler_throw.name = "ThrowHandler"
	add_child(handler_throw)
	throw_handler = handler_throw
	throw_handler.set_player(self)
	
	if startup_logs:
		Debug.log("[Player] Handlers 初始化完成 (Phase 1-5) | Seat: ", seat)
