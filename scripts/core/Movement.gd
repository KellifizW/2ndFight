class_name Movement extends Node2D

@onready var player: Player = owner as Player

var healthbar: Node = null
var world: Node

@onready var animation_tree = $AnimationTree
@onready var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer if has_node("AnimationPlayer") else null
## 前衝煙霧的「生成點」（Marker2D）。
## 有這個節點的角色才會在前衝時噴煙 —— 沒放的角色（DAV / DEN）就沒有煙。
## 要給新角色加煙霧：在該角色場景裡拖一個同名 Marker2D 到腳下想要的位置，
## 不用改任何程式。位置寫在場景裡而不是寫死在程式裡，是因為每個角色的
## 原點/體型不同，這個偏移本來就該由美術調。
@onready var dash_smoke_point: Marker2D = $DashSmokePoint if has_node("DashSmokePoint") else null

# Handler instances
var input_handler: InputHandler
var animation_manager: AnimationManager
var dash_handler: DashHandler
var jump_handler: JumpHandler
var blocking_handler: BlockingHandler
var facing_handler: FacingHandler
var walk_handler: WalkHandler
var knockfly_handler: KnockflyHandler
var gravity_handler: GravityHandler
var timer_handler: TimerHandler
var landing_handler: LandingHandler

# ── 著地系統 ────────────────────────────
# 【Stage 1 時間域統一】landing 計時器改為 int 物理幀（120 Hz），
# 每個 _physics_process 遞減 1。舊版是 float 秒 `-= delta`，
# 在 hitstop（Engine.time_scale = 0.02）期間 delta 會被縮放，
# 導致著地鎖定時間隨 time_scale 漂移；改幀後與 time_scale 完全無關。
var is_landing: bool = false
var landing_lock_frames: int = 0  # 物理幀計數（由 TimerHandler 遞減）
var _landing_checkpoint_executed: bool = false  # 【新增】追蹤checkpoint是否已執行，防止重複執行
var _landing_forced_frames: int = 0  # 【新增】追蹤著地強制幀數，確保至少2幀

## 著地開始時的強制鎖定幀數（等價於舊值 2.0/60.0 秒）。
## checkpoint 在第 2 幀就會覆寫它，所以只在 checkpoint 未觸發時才用得到。
const LANDING_FORCED_LOCK_FRAMES: int = 5
## 著地被輸入中斷時剩餘的幀數（等價於舊的 0.001 秒魔數）。
## 不設 0 的原因：要留 1 幀讓 is_landing 在下一幀才解除，
## JumpHandler 才有機會在該幀處理跳躍延遲。
const LANDING_INTERRUPT_FRAMES: int = 1

# ── 基本狀態 ──────────────────────────────
@export var landing_duration: float = 0.2  # 秒（設計師調參用；經 seconds_to_lock_frames 轉幀）
@export var layground_duration: float = 0.2
var is_layground: bool = false
var layground_timer: int = 0  # Frame-based timer
var is_knockfly_animation_finished: bool = false

# ── 蹲姿 ──────────────────────────────────
var was_crouching_last_frame: bool = false
var is_crouching: bool = false
var was_hit_while_crouching: bool = false  # 記錄被擊中時是否處於蹲姿

# ── 跳躍 ──────────────────────────────────
var jump_vertical_speed: float = -2500.0
var jump_horizontal_speed: float = 470.0
var jump_dir: float = 0.0
var jump_delay_timer: int = 0  # Frame-based timer
var just_jumped: bool = false
var is_jumping: bool = false
@export var jump_delay_duration: float = 0.1

# ── 衝刺 ──────────────────────────────────
var is_dashing: bool = false
var is_backdashing: bool = false
var dash_speed: float = 2100.0
var backdash_speed: float = 1000.0
var dash_time: float = 0.35
var backdash_time: float = 0.35
var dash_timer: int = 0  # Frame-based timer
# Stage 1：這是「設計者秒數種子」，不是倒數計時器。double-tap 計數窗口位於
# PlayerController.double_tap_frames（物理幀）與 neutral_timer（DashHandler 由此種子換算）。
var double_tap_window_seconds: float = 0.3
var last_input_dir: int = 0
var pending_dash_dir: int = 0
var neutral_timer: int = 0  # Frame-based timer
# Dash deceleration variables
var dash_initial_speed: float = 0.0
var dash_total_time: float = 0.0

# ── 移動速度 ──────────────────────────────
var walk_speed: float = 360.0
var back_speed: float = 240.0

# ── 击飛物理 ──────────────────────────────
@export_group("Knockfly Physics")
@export var default_knockfly_gravity: float = 6000000.0
@export var default_knockfly_vertical_speed: float = -1000.0
@export var default_knockfly_horizontal_speed: float = 700.0
@export var default_air_friction: float = 200.0
@export var default_knockfly_duration: float = 0.4

var knockfly_gravity: float = 1700000.0
var knockfly_vertical_speed: float = -400.0
var knockfly_horizontal_speed: float = 6000.0
var air_friction: float = 200.0
var knockfly_duration_frames: int = 0  # 原始時長（物理幀），供 PushManager 速度曲線當分母
var knockfly_velocity_x: float = 0.0
var knockfly_accumulated_distance: float = 0.0
var knockfly_max_distance: float = 150.0
var is_knockfly: bool = false
var knockfly_frames: int = 0  # 剩餘物理幀，由 PushManager 每幀 -1（hitstop 期間凍結）
var just_thrown: bool = false
var is_being_thrown: bool = false

# ── 空中受擊 ──────────────────────────────
var is_air_hit_backjump: bool = false
var air_hit_backjump_timer: int = 0  # Frame-based timer
@export var air_hit_backjump_speed: float = 400.0
@export var air_hit_backjump_duration: float = 0.2
# Stage 2：`air_hit_backjump_up_speed` / `pending_jump_b_seek` /
# `is_air_hit_knockfly` 已刪除（零讀取或零寫入，且未被任何場景覆寫）。
# 其中 `is_air_hit_knockfly` 從未被設為 true，卻在 PushManager 裡選擇
# knockfly 速度曲線 —— 那條「線性衰減」分支自始不可達，實際永遠走二次衰減。

# ── 傷害與防禦 ────────────────────────────
var is_hit: bool = false
var hit_lock_frames: int = 0  # 舊 hit_timer 的幀制版；與 hitstun_frames 並行，由 PushManager 遞減
var is_blocking: bool = false
var block_lock_frames: int = 0  # 舊 block_timer 的幀制版；與 blockstun_frames 並行
var is_holding_back: bool = false
var is_crouch_blocking: bool = false
var is_proximity_blocking: bool = false
var is_opponent_proximity: bool = false
var block_type: String = "none"

# ── 推擠系統 ──────────────────────────────
@export_group("Push Parameters")
@export var block_push_distance: float = 250.0
@export var hit_push_distance: float = 250.0
@export var floor_snap_immunity_duration: float = 0.1

var knockback_start_time: float = 0.0  # Knockback開始時間（用於統計）
var hit_push_velocity: float = 0.0
var hit_push_initial_velocity: float = 0.0  # 初始knockback速度 (用於減速計算)

# ── Block Knockback 系統 ────────────────────────────────────────────────
# Stage 2：`initial_blockstun`（秒）與 `block_push_velocity` 這組 @deprecated
# 的秒制推擠變數已刪除 —— 兩者都只被寫入、從無讀取點（實際 block knockback
# 走 block_push_initial_velocity + block_knockback_frames 幀制路徑）。
# `block_push_frames` 保留：test_18 用它釘住「舊 block push 計時器仍是 int」。
var block_push_frames: int = 0  # @deprecated - 實際推擠用 block_knockback_frames

var block_push_initial_velocity: float = 0.0  # Block 推擊初始速度
var is_immune_to_floor_snap: bool = false
var floor_snap_immunity_timer: int = 0  # 物理幀（早已按幀遞減，型別從 float 對齊）

# ── 核心物理 ──────────────────────────────
var fixed_position: Vector2i = Vector2i.ZERO
var fixed_velocity: Vector2i = Vector2i.ZERO
var colbox_half_width: float = 0.0
var colbox_half_height: float = 0.0
var facing_direction: float = 1.0
var prev_position: Vector2 = Vector2()
var was_in_air: bool = false

# ── 狀態旗標 ──────────────────────────────
var is_attacking: bool = false
# Stage 2：`is_push_back` 及其計時器族（push_back_velocity / push_back_frames /
# initial_push_back_frames / push_back_timer）已刪除。
# 理由：全倉庫只有一處寫入且寫的是 `false`（PushManager 的過期分支），
# 沒有任何地方把它設為 true —— 也就是說那條「推開後減速」路徑自始至終
# 不可達，卻仍出現在 Dash/Jump/Walk/AI-dash 五條守衛條件裡當作假的互斥項。
# 移除後這些條件恆等（`not false` = true），行為一幀不變。
var landing_facing_lock: bool = false

# ── 動畫條件（已替換 Crouch 為 cr_down 和 cr_idle） ──
var animation_conditions: Array = [
	"Walk", "cr_down", "cr_idle", "Dash", "Backdash",
	"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
	"cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
	"Jump_F", "Jump_B", "Jump_V",
	"hit", "knockfly", "block", "cr_block",
	"powerkk", "spnk", "fireball", "100p",
	"jump_mp", "jump_mk", "landing", "wakeup", "super", "dp", "hdk", "layground"
]

var anim_resets: Dictionary = {
	"layground": func(): _reset_layground_with_health_check(),
	"knockfly": func(): _reset_knockfly(),
	"st_mp": func(): _reset_attack()
}

## 「這一幀玩家有沒有下任何可執行的指令」判定用的按鍵鍵名清單。
##
## 只列**動作**輸入（方向由 input_dir 另外判定）。三個著地路徑
## （LandingHandler、Player._enter_landing_state、TimerHandler checkpoint）
## 以前各自抄了一份 or 串，漏鍵就會出現「某個鍵中斷不了著地」的不一致；
## 現在全部走 has_actionable_input()，清單只有這一份。
const ACTIONABLE_INPUT_KEYS: Array = [
	"crouch_pressed",
	"jump_pressed",
	"st_lp_pressed", "st_mp_pressed", "st_hp_pressed",
	"st_lk_pressed", "st_mk_pressed", "st_hk_pressed",
	"spm1_pressed", "spm2_pressed", "spm3_pressed",
	"fireballL_pressed", "fireballM_pressed", "fireballH_pressed",
	"dp_pressed", "super_pressed",
	"dash_pressed", "backdash_pressed",
	"throw_pressed", "100p_pressed",
]

## 這一幀的輸入字典裡是否含有任何「可執行動作」的輸入（含方向）。
##
## 回傳型別明確為 bool：呼叫端可以安全地用 `var x: bool = ...`。
## 直接把 `input_data.get(...)` 串成 `or` 鏈會得到 Variant，
## GDScript 的靜態分析無法推導型別（`var x := (a or b)` 會編譯失敗：
## "Cannot infer the type of variable because the value doesn't have a set type"）。
static func has_actionable_input(input_data: Dictionary) -> bool:
	if int(input_data.get("input_dir", 0)) != 0:
		return true
	for key in ACTIONABLE_INPUT_KEYS:
		if bool(input_data.get(key, false)):
			return true
	return false

## 秒 → 物理幀數（Stage 1：landing / knockfly 等「舊 float 倒數」族的轉換邊界）。
##
## 為什麼是 floor(s * fps) + 1 而不是 round(s * fps)：
## 舊實作是 `timer = max(0, timer - delta)`，迴圈條件為 `timer > 0`，
## 也就是「要讓 timer 降到 0 需要幾次遞減」。0.2 秒 / (1/120) 數學上是 24，
## 但 24 次浮點相減後殘值為 5.2e-17 > 0，於是實際會多跑第 25 幀。
## 直接用 round() 會得到 24，讓著地整整短一幀 —— 正是「重構期間行為必須不變」
## 要防的漂移。floor()+1 精確重現舊的浮點格數（0.2→25、2/60→5、0.001→1）。
static func seconds_to_lock_frames(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	var fps: float = float(Engine.physics_ticks_per_second)
	return int(floor(seconds * fps)) + 1

## 秒 → 物理幀數，四捨五入版（Stage 1：設計者秒數「種子」的唯一轉換邊界）。
##
## 適用對象：本來就是 `int(round(sec * 120))` 種子、以每幀 -1 遞減的整數幀計時器
## （dash 0.35→42、跳躍延遲 0.1→12、double-tap 窗口 0.3→36、layground 0.2→24、
## wakeup、attack-movement 位移、空中受擊後跳 0.2→24）。
## 這些計時器從未用 `-= delta` 倒數，舊行為就是「四捨五入到最近幀」，
## 所以收攏時必須保持 round 語義 —— 改用 seconds_to_lock_frames 會無謂地多一幀
## （dash 42→43、double-tap 36→37）。
## 兩個函數分別對應兩族舊語義；全代碼不允許再出現第三種秒→幀算法。
static func seconds_to_frames_nearest(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	var fps: float = float(Engine.physics_ticks_per_second)
	return int(round(seconds * fps))

## 邏輯幀（60 FPS）→ 物理幀（Stage 1：全代碼唯一的邏輯↔物理轉換點）。
## 其他副本（Fighter.logic_frames_to_physics_frames、ThrowHandler._logic_...）
## 已全部收攏到這裡。幀比 120/60 = 2 在整數輸入下無捨入歧義。
static func logic_frames_to_physics_frames(logic_frames: float) -> int:
	if logic_frames <= 0.0:
		return 0
	var ratio: float = float(Engine.physics_ticks_per_second) / float(60.0)
	return int(round(logic_frames * ratio))

## Stage 1：把秒數 knockfly 時長轉成物理幀，並同步曲線分母。
## 轉換走 seconds_to_lock_frames，重現舊的 `timer -= delta` / `timer > 0` 格數。
func start_knockfly_timer(duration_seconds: float) -> void:
	knockfly_frames = seconds_to_lock_frames(duration_seconds)
	knockfly_duration_frames = knockfly_frames

func _reset_layground() -> void:
	is_layground = false
	is_knockfly = false
	is_knockfly_animation_finished = false
	_update_animation_state(0, false)

func _reset_knockfly() -> void:
	if is_on_floor():
		fixed_velocity = Vector2i.ZERO
		is_knockfly = false
		is_layground = true
		# 轉換 layground_duration（秒）為物理幀（唯一秒→幀邊界 Movement.seconds_to_frames_nearest）
		layground_timer = Movement.seconds_to_frames_nearest(layground_duration) if "layground_duration" in self else 24
		is_knockfly_animation_finished = false
		_update_animation_state(0, false)
	else:
		is_knockfly_animation_finished = true
		if animation_player:
			animation_player.stop()

func _reset_attack() -> void:
	is_attacking = false
	update_facing_direction()
	if has_node("Hitbox/HitShape"):
		$Hitbox/HitShape.disabled = true

func _apply_air_friction(friction_coeff: float, _delta: float) -> void:
	# Delegated to KnockflyHandler 【已改為 frame-based】
	knockfly_handler.apply_air_friction(friction_coeff)

## 在「發動前衝的那一瞬間的位置」生成一團地面煙霧。
##
## 【只有前衝呼叫它】landing / backdash 都不呼叫 —— 那些行動本來就不該有煙。
##
## 煙霧節點掛在 world 底下（不是角色底下），所以它不會跟著身體移動；
## 播完會自己 queue_free()，沒有觸發時畫面上什麼都沒有。
## 角色場景裡沒有 `DashSmokePoint` 這個 Marker2D 就直接不生成。
func spawn_dash_smoke() -> void:
	if dash_smoke_point == null or world == null:
		return
	VFXSmoke.spawn(world, dash_smoke_point.global_position, facing_direction)

## WOO's landing effect uses the same world-owned, one-shot VFX scene as dash
## smoke.  The character check keeps the effect exclusive to WOO even if a
## different character later gets a DashSmokePoint for dash tuning/tests.
func spawn_landing_smoke() -> void:
	if str(get("character_id")) != "WOO" or dash_smoke_point == null or world == null:
		return
	VFXSmoke.spawn_animation(world, dash_smoke_point.global_position, VFXSmoke.LANDING_ANIMATION, facing_direction)

func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	var retry_count: int = 0
	while not world and retry_count < 5:
		await get_tree().create_timer(0.1).timeout
		world = get_tree().get_first_node_in_group("world")
		retry_count += 1
	
	# Initialize handlers
	input_handler = InputHandler.new(self)
	animation_manager = AnimationManager.new(self)
	dash_handler = DashHandler.new(self)
	jump_handler = JumpHandler.new(self)
	blocking_handler = BlockingHandler.new(self)
	facing_handler = FacingHandler.new(self)
	walk_handler = WalkHandler.new(self)
	knockfly_handler = KnockflyHandler.new(self)
	gravity_handler = GravityHandler.new(self)
	timer_handler = TimerHandler.new(self)
	landing_handler = LandingHandler.new(self)
	
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	
	if has_node("Pushbox") and $Pushbox.shape is RectangleShape2D:
		var collision_scale: Vector2 = $Pushbox.scale
		colbox_half_width = $Pushbox.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = $Pushbox.shape.size.y * collision_scale.y / 2.0
	
	if has_node("Hurtbox"):
		$Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
		$Hurtbox.area_exited.connect(_on_hurtbox_area_exited)
	
	if animation_player:
		animation_player.speed_scale = 1.0
		animation_player.animation_finished.connect(_on_animation_player_finished)
	
	prev_position = global_position
	fixed_position = Vector2i(int(global_position.x * (world.SIMULATION_SCALE if world else 1000)), world.FLOOR_Y if world else 200000)
	update_facing_direction()
	knockfly_frames = 0
	knockfly_duration_frames = 0
	layground_timer = 0
	is_knockfly_animation_finished = false

func _physics_process(delta: float) -> void:
	var input_data: Dictionary = get_input()
	var input_dir: int = input_data["input_dir"]
	var crouch_pressed: bool = input_data["crouch_pressed"]
	var jump_pressed: bool = input_data["jump_pressed"]
	is_crouching = crouch_pressed
	
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_special_moving: bool = move_set.is_special_moving if move_set and "is_special_moving" in move_set else false
	
	var scale_factor: float = world.SIMULATION_SCALE if world else 1000.0
	var floor_y: int = world.FLOOR_Y if world else 200000
	
	# ── 蹲姿狀態檢測 ──
	# Stage 2：原本這裡有一段 if/else，兩個分支都只是把 `is_crouch_transition_played`
	# 設成 false（外加 `is_crouch_held = true`）。兩個旗標都沒有任何讀取點，
	# 整段等價於單獨更新 was_crouching_last_frame —— 而那才是真正被讀的東西
	# （AnimationManager 用它決定要不要 travel 到 cr_down）。
	was_crouching_last_frame = (is_on_floor() and crouch_pressed and not is_blocking)
	
	timer_handler.handle_timers(delta)
	
	# 【遊戲速度監視】每 120 物理幀輸出一次時間檢查點
	if get_physics_process_delta_time() > 0:
		var frame_time = get_physics_process_delta_time()
		if Engine.get_physics_frames() % 120 == 0 and name == "Player_A":
			var expected_time = Time.get_ticks_msec() / 1000.0
			Debug.vlog("[GAME SPEED] @%.2f秒 | Δt=%.5f(%.1f FPS) | Expected: 1/120" % [
				expected_time, frame_time, 1.0 / max(frame_time, 0.0001)
			])
	
	blocking_handler.handle_blocking(input_dir, is_special_moving)
	
	# 【關鍵修復】著地處理必須在 dash 之前，以清除 dash 相關狀態
	# 否則著地時的輸入會触發遺留的 pending_dash_dir
	landing_handler.handle_landing(input_data, floor_y, delta)
	
	# 🔴 【FIX】Check for AI direct dash request (dash_pressed flag)
	# AI cannot simulate complex double-tap pattern, so we allow direct trigger
	# 【關鍵】Only use dash_pressed/backdash_pressed for AI - human players use dash_handler's double-tap detection
	var has_dash_pressed = (player and player.is_ai_controlled and input_data.get("dash_pressed", false))
	var has_backdash_pressed = (player and player.is_ai_controlled and input_data.get("backdash_pressed", false))
	# Stage 2 切片 3：衝刺守衛收攏到 FighterState.can_dash（值等價，見 test_31）。
	# 注意：舊版的「AI 直接 backdash」分支缺少 `not is_crouching` 守衛，
	# 是前衝分支 / DashHandler 都不一致的真實 bug。為守 ground rule #2（行為一幀不變），
	# 這裡保留那條略寬鬆的舊守衛並在註解記下來，待日後 Stage 2 切片 4 統一修。
	var _ai_dash_can_dash: bool = FighterState.can_dash(self, is_special_moving)
	var _ai_backdash_can_dash: bool = is_on_floor() and not (is_landing and landing_lock_frames > 0) \
		and not is_attacking and not is_dashing and not is_backdashing and not is_special_moving \
		and not (is_hit or is_knockfly or is_blocking or is_layground)

	if has_dash_pressed and _ai_dash_can_dash:
		# AI wants to dash forward
		if input_dir * facing_direction > 0:
			# Same direction as facing - forward dash
			is_dashing = true
			dash_timer = Movement.seconds_to_frames_nearest(dash_time)
			dash_total_time = dash_timer
			dash_initial_speed = dash_speed * scale_factor * input_dir
			fixed_velocity.x = int(dash_initial_speed)
			# 前衝：在「發動的那個位置」生成一團煙（掛在 world，不跟著身體跑）。
			spawn_dash_smoke()
		else:
			# Opposite direction - backdash
			is_backdashing = true
			dash_timer = Movement.seconds_to_frames_nearest(backdash_time)
			dash_total_time = dash_timer
			dash_initial_speed = backdash_speed * scale_factor * input_dir
			fixed_velocity.x = int(dash_initial_speed)
			# 後衝刻意不生成煙霧：只有前衝才有（見 spawn_dash_smoke 說明）。
	elif has_backdash_pressed and _ai_backdash_can_dash:
		# AI wants to backdash
		is_backdashing = true
		dash_timer = Movement.seconds_to_frames_nearest(backdash_time)
		dash_total_time = dash_timer
		dash_initial_speed = backdash_speed * scale_factor * (-int(facing_direction))
		fixed_velocity.x = int(dash_initial_speed)
		# 後衝刻意不生成煙霧：只有前衝才有（見 spawn_dash_smoke 說明）。
	else:
		# Normal double-tap dash detection
		dash_handler.handle_dash(input_dir, scale_factor, is_special_moving)
	
	walk_handler.handle_walk(input_dir, scale_factor, is_special_moving)
	jump_handler.handle_jump(jump_pressed, input_dir, scale_factor, floor_y, is_special_moving)
	knockfly_handler.handle_knockfly_layground(delta, floor_y)
	gravity_handler.handle_gravity(delta, move_set)
	
	fixed_position += Vector2i(roundi(fixed_velocity.x * delta), roundi(fixed_velocity.y * delta))
	
	global_position = world.to_scaled_vector2(fixed_position) if world else Vector2(float(fixed_position.x) / 1000.0, float(fixed_position.y) / 1000.0)
	
	# 【新增調試】跳躍軌跡追蹤
	if is_jumping and Engine.get_physics_frames() % 5 == 0:
		var seat_name = player.seat if player and "seat" in player else "?"
		Debug.vlog("[JUMP TRAJECTORY] Frame=%d | Seat=%s | Y=%d | Vel.y=%d | jump_delay_timer=%d | on_floor=%s" % [
			Engine.get_physics_frames(),
			seat_name,
			fixed_position.y,
			fixed_velocity.y,
			jump_delay_timer,
			is_on_floor()
		])
	
	if just_jumped and fixed_velocity.y > 0:
		just_jumped = false
	
	if floor_snap_immunity_timer > 0:
		# 🔴 【關鍵修復】floor_snap_immunity_timer 是幀數，需轉换為幀數逅減 跟頭（不是 delta）
		floor_snap_immunity_timer -= 1
		if floor_snap_immunity_timer <= 0:
			is_immune_to_floor_snap = false
	
	var is_landing_state: bool = ("is_landing" in self and self.is_landing and "landing_lock_frames" in self and self.landing_lock_frames > 0)
	if not (is_attacking or landing_facing_lock or is_landing_state):
		update_facing_direction()
	if is_on_floor() and was_in_air and not is_landing_state and not is_special_moving and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	was_in_air = not is_on_floor()
	if is_on_floor() and prev_position.x != global_position.x and not is_special_moving and not is_landing_state and not is_jumping and not landing_facing_lock:
		update_facing_direction()
	
	prev_position = global_position
	
	if not ("landing_lock_frames" in self and self.landing_lock_frames > 0) and not is_layground:
		_update_animation_state(input_dir, crouch_pressed)
	
	post_physics_process(delta)

func _on_animation_player_finished(anim_name: String) -> void:
	if anim_name in anim_resets:
		anim_resets[anim_name].call()
	if anim_name == "cr_down":
		if animation_state:
			animation_state.travel("cr_idle")

func is_on_floor() -> bool:
	if jump_delay_timer > 0 or just_jumped:
		return false
	return fixed_position.y >= (world.FLOOR_Y if world else 200000)

func get_input() -> Dictionary:
	return input_handler.get_input()

func update_hitbox_position() -> void:
	pass

func post_physics_process(_delta: float) -> void:
	pass

func get_facing_multiplier() -> float:
	return facing_direction

func get_is_dashing() -> bool:
	return is_dashing

func get_is_backdashing() -> bool:
	return is_backdashing

func get_is_attacking() -> bool:
	return is_attacking

func get_is_hit() -> bool:
	return is_hit

func get_is_knockfly() -> bool:
	return is_knockfly

func _on_hurtbox_area_entered(area: Area2D) -> void:
	var player_seat = player.seat if player and "seat" in player else "?"
	
	# 檢測對手玩家的 Proximitybox
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = true
		return
	
	# 檢測 fireball 的 proximity area (Layer 8 = 128)
	if area.collision_layer & 128:  # Layer 8 檢測
		is_opponent_proximity = true
		return

func _on_hurtbox_area_exited(area: Area2D) -> void:
	var player_seat = player.seat if player and "seat" in player else "?"
	
	# 檢測對手玩家的 Proximitybox 離開
	if area.name == "Proximitybox" and area.get_parent().is_in_group("players") and area.get_parent() != self:
		is_opponent_proximity = false
		is_proximity_blocking = false
		return
	
	# 檢測 fireball 的 proximity area 離開 (Layer 8 = 128)
	if area.collision_layer & 128:
		is_opponent_proximity = false
		is_proximity_blocking = false
		return

func _set_facing(new_facing: float) -> void:
	facing_handler.set_facing(new_facing)

func update_facing_direction() -> void:
	facing_handler.update_facing_direction()

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	animation_manager.set_animation_conditions(target_state, on_floor, crouch_input)

func _compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	return animation_manager.compute_target_state(_dir_x, crouch_input, on_floor, anim_jump_dir)

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	animation_manager.update_animation_state(dir_x, crouch_input)

func _reset_layground_with_health_check() -> void:
	knockfly_handler.reset_layground_with_health_check()
