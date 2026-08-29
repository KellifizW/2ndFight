extends Node2D

const TICKS_PER_SECOND: int = 120
const SIMULATION_SCALE: int = 1000
const WALL_LIMIT: int = 1280000
const STARTING_POSITION: int = 10000
const FLOOR_Y: int = 550000
const GRAVITY: int = 7400000
@export var arena_left: float = 0.0      # 舞台左邊界（像素）
@export var arena_right: float = 1600.0  # 舞台右邊界（像素）
@export var startup_logs: bool = false

@onready var position_label = $UI/PositionLabel
# BGM 最大音量（dB）。實際值取自 BGMPlayer 節點在編輯器設定的 volume_db，
# 於 _ready() 讀取，因此在編輯器調整 BGMPlayer 節點的 Volume Db 即可控制音量。
var bgm_max_volume_db: float = -6.0

# ============================================================
# 調試熱重載系統
# ============================================================
@export var enable_debug_hotkeys: bool = true  # 啟用調試按鍵
@export var debug_reload_key_hint: String = "Ctrl+R = 重新加載攻擊資料 | Ctrl+G = 重新加載 gravity"

# ============================================================
# AI 性能監視器選項（Phase 2 優化）
# ============================================================
@export var enable_performance_monitoring: bool = true  # 是否啟用性能監視器
@export var profiling_log_interval: float = 5.0  # 性能報告輸出間隔（秒）

@onready var hit_label = $UI/HitLabel
@onready var fps_label = $UI/FPS
@onready var slowmo_controller = $SlowMoController
@onready var animation_label = $UI/AnimationLabel
@onready var combo_label = $UI/ComboLabel
@onready var debug_label = $UI/DebugLabel if has_node("UI/DebugLabel") else null
@onready var p1_advantage_label = $UI/P1AdvantageLabel
@onready var p2_advantage_label = $UI/P2AdvantageLabel
@onready var frame_bar_p1 = $UI/FrameBarP1
@onready var frame_bar_p2 = $UI/FrameBarP2
@onready var bgm_player = $BGMPlayer if has_node("BGMPlayer") else null

# 選角用角色資源（在編輯器拖入 .character.tres）
# Inspector 顯示為 "Character A Character" / "Character B Character"（使用大寫 A/B）。
@export var character_a_character: CharacterData
@export var character_b_character: CharacterData

# 動態生成的玩家
var player_a: Player
var player_b: Player

var initial_player_a_pos: Vector2
var initial_player_b_pos: Vector2

var slowmo_triggered: bool = false
var current_combo: int = 0
var combo_target: String = ""
# Stage 1：連段標籤視窗改為 int 物理幀（每個 _physics_process -1）。
# 舊版是 float 秒 + `-= delta`：delta 受 Engine.time_scale 縮放，hitstop 期間
# 遞減速度只剩 2%，計數視窗被拉長最多 50×；幀制後與 time_scale 完全脫鉤。
var combo_reset_frames: int = 0
# 設計者秒數種子：只在命中訊號載入邊界經 Movement 轉換一次，不在遞減迴圈中出現。
const COMBO_BUFFER_SECONDS: float = 0.2

# Hit Advantage (改用幀計數器)
var hit_time: float = 0.0
var attacker: Node = null
var target_player: Node = null
var attacker_recover_frame: int = -1
var target_recover_frame: int = -1
var advantage_calculated: bool = false

# 🟢 【新增】攻擊幀數記錄（用於確定恢復時間）
var attack_start_frame: int = -1
var attack_duration_frames: int = 0
var hit_frame: int = -1
var hitstun_frames: int = 0

# Block Advantage (改用幀計數器)
var block_attacker: Node = null
var blocker: Node = null
var block_attack_recover_frame: int = -1
var block_defend_recover_frame: int = -1
var block_advantage_calculated: bool = false

# 幀計數器實例
var frame_counter: FrameCounter = null

var is_fading_out: bool = false
var is_bgm_enabled: bool = true
var _bgm_started: bool = false

func _ready() -> void:
	add_to_group("world")
	if startup_logs:
		Debug.log("Debug: World _ready() 開始執行")
	
	# ============================================================
	# 初始化 HitboxCache（新增）
	# ============================================================
	var hitbox_cache = HitboxCache.new()
	hitbox_cache.name = "HitboxCache"
	hitbox_cache.debug_mode = false
	add_child(hitbox_cache)
	hitbox_cache.add_to_group("hitbox_cache")
	if startup_logs:
		Debug.log("[WORLD] HitboxCache 已初始化")
	
	# ============================================================
	# 初始化 ResourcePreloadManager（特效預載系統）
	# ============================================================
	var resource_preloader = ResourcePreloadManager.new()
	resource_preloader.name = "ResourcePreloader"
	add_child(resource_preloader)
	resource_preloader.add_to_group("resource_preloader")
	if startup_logs:
		Debug.log("[WORLD] ResourcePreloadManager 已初始化")
	
	# ============================================================
	# 初始化 AI 性能監視器（Phase 2 優化）
	# ============================================================
	if enable_performance_monitoring:
		var profiler = AIPerformanceMonitor.new()
		profiler.enabled = true
		profiler.log_interval = profiling_log_interval
		profiler.show_realtime = false
		add_child(profiler)
		if startup_logs:
			Debug.log("[WORLD] ✓ AI 性能監視器已啟用 (每 %.1f 秒輸出一次報告，檢查 Console 標籤)" % profiling_log_interval)
	else:
		if startup_logs:
			Debug.log("[WORLD] ℹ️ AI 性能監視器已禁用 (在 Inspector 中設置 enable_performance_monitoring = True 以啟用)")
	
	# ============================================================
	# 🟢 【新增】初始化幀計數器（替代浮點時間戳）
	# ============================================================
	frame_counter = FrameCounter.new()
	frame_counter.name = "FrameCounter"
	add_child(frame_counter)
	if startup_logs:
		Debug.log("[WORLD] ✓ FrameCounter 已初始化 - 精確的幀級時間追蹤")
	
	# ============================================================
	# 🟢 【新增】初始化 Hit Stop 時機調試器
	# ============================================================
	var hitstop_debug = HitStopTimingDebugger.new()
	hitstop_debug.name = "HitStopTimingDebugger"
	hitstop_debug.enabled = true  # 設為 false 可關閉調試輸出
	hitstop_debug.detailed_logging = false  # 設為 true 可查看更詳細的日誌
	add_child(hitstop_debug)
	if startup_logs:
		Debug.log("[WORLD] ✓ HitStopTimingDebugger 已初始化 (詳細日誌: %s)" % hitstop_debug.detailed_logging)
	
	# 角色來源選擇：先用「選角畫面」的選擇（CharacterSelect 會設定 SelectedCharacters），
	# 如果沒有選角選擇（例如直接執行 world.tscn，或在編輯器把 Character A/B 拖入 Inspector），
	# 才能使用 world.tscn 上設定好的 Character A Character / Character B Character。
	# 注意：SelectedCharacters 只是 Autoload，角色必須在進入選角畫面後才被視為「已選擇」，
	# 不能用 autoload 的預設 DAV/DEN 覆蓋編輯器設定，否則在 Inspector 選 WOO 仍會載入 DAV。
	if SelectedCharacters != null and SelectedCharacters.p1_character != null and SelectedCharacters.p2_character != null:
		character_a_character = SelectedCharacters.p1_character
		character_b_character = SelectedCharacters.p2_character
		if startup_logs:
			Debug.log("從選角畫面成功載入角色：P1 = %s, P2 = %s" % [character_a_character.display_name, character_b_character.display_name])
	else:
		# 直接執行 world.tscn（測試用）：使用編輯器在世界節點 Inspector 拖入的角色
		if not character_a_character:
			push_error("錯誤：Character A 的 CharacterData 未指定！請從 CharacterSelect 進入，或在 World 節點的 Inspector 中拖入角色 .tres")
			return
		if not character_b_character:
			push_error("錯誤：Character B 的 CharacterData 未指定！請從 CharacterSelect 進入，或在 World 節點的 Inspector 中拖入角色 .tres")
			return
		if startup_logs:
			Debug.log("使用編輯器預設角色：P1 = %s, P2 = %s" % [character_a_character.display_name, character_b_character.display_name])
	
	# 安全檢查：確保兩個角色都有 PackedScene
	if not character_a_character.scene:
		push_error("錯誤：Player A 的 CharacterData.scene 為空！請確認 .character.tres 資源的 Scene 欄位已拖入角色場景（如 DAV.tscn）。")
		return
	if not character_b_character.scene:
		push_error("錯誤：Player B 的 CharacterData.scene 為空！請確認 .character.tres 資源的 Scene 欄位已拖入角色場景。")
		return
	
	# 生成玩家（順序很重要：先生成玩家，再連接信號）
	player_a = _spawn_player(character_a_character, Vector2(550.0, float(FLOOR_Y) / SIMULATION_SCALE), "player_a")
	player_b = _spawn_player(character_b_character, Vector2(1050.0, float(FLOOR_Y) / SIMULATION_SCALE), "player_b")
	if not player_a or not player_b:
		push_error("角色生成失敗！請檢查 CharacterData 和場景設定。")
		return
	
	# 預熱已生成角色內嵌的 VFX（groundsmoke、spawnfire 等），避免第一次觸發時卡頓。
	if resource_preloader and resource_preloader.has_method("warmup_character_vfx"):
		resource_preloader.warmup_character_vfx(player_a, player_a.character_id)
		resource_preloader.warmup_character_vfx(player_b, player_b.character_id)

	# 連接信號
	player_a.hit_detected.connect(_on_hit_detected)
	player_a.block_detected.connect(_on_block_detected)
	player_b.hit_detected.connect(_on_hit_detected)
	player_b.block_detected.connect(_on_block_detected)
	
	# 其餘初始化（保持不變）
	if not slowmo_controller:
		Debug.log("Warning: SlowMoController node not found in world")
	if not animation_label:
		Debug.log("Warning: AnimationLabel node not found in world")
	if not combo_label:
		Debug.log("Warning: ComboLabel node not found in world")
	else:
		combo_label.text = ""
	if debug_label:
		debug_label.text = ""
	if p1_advantage_label:
		p1_advantage_label.text = "P1 Adv: 0"
	if p2_advantage_label:
		p2_advantage_label.text = "P2 Adv: 0"
	else:
		Debug.log("Warning: Advantage labels not found in UI")
	if bgm_player:
		is_bgm_enabled = true
		# 以 BGMPlayer 節點在編輯器設定的 volume_db 作為 BGM 音量來源。
		# 舊版用 @export 的 bgm_max_volume_db 覆寫節點音量，導致在編輯器
		# 調整 BGMPlayer 節點的 Volume Db 完全無效。現在在覆寫成靜音前先記錄。
		bgm_max_volume_db = bgm_player.volume_db
		bgm_player.volume_db = -120.0
		# Web browsers block autoplay until a user gesture. The first key, mouse,
		# touch, or gamepad input starts the BGM from inside the input callback.
		if not OS.has_feature("web"):
			_start_bgm(1.0)
	else:
		Debug.log("Warning: BGMPlayer node not found in world")
	
	initial_player_a_pos = player_a.global_position
	initial_player_b_pos = player_b.global_position
	if startup_logs:
		Debug.log("Debug: Initial positions set - Player A: %s, Player B: %s" % [player_a.global_position, player_b.global_position])
	
	if frame_bar_p1:
		frame_bar_p1.initialize(player_a, player_b)
		frame_bar_p1.z_index = 10
	else:
		Debug.log("Error: FrameBarP1 not found in UI")
	if frame_bar_p2:
		frame_bar_p2.initialize(player_b, player_a)
		frame_bar_p2.z_index = 10
	else:
		Debug.log("Error: FrameBarP2 not found in UI")
	
	if position_label:
		position_label.text = "Player A: (0, 0)\nPlayer B: (0, 0)"
	else:
		Debug.log("Warning: PositionLabel not found in UI")

	_focus_web_canvas()
	
	$UI/CountdownTimer.countdown_finished.connect(_on_countdown_finished)
	
func _spawn_player(char_data: CharacterData, pos: Vector2, seat: String) -> Player:
	if not char_data or not char_data.scene:
		push_error("CharacterData 或場景遺失：%s" % char_data)
		return null
	
	var instance: Player = char_data.scene.instantiate()
	instance.global_position = pos
	instance.fixed_position = Vector2i(int(pos.x * SIMULATION_SCALE), FLOOR_Y)
	instance.seat = seat
	instance.character_data = char_data   # ← 這一行！關鍵！
	add_child(instance)
	return instance

# 其餘函式（_input, _process, _physics_process, advantage 計算, reset_players 等）保持原樣不變
# （為了節省篇幅這裡省略，但請保留你原本的所有程式碼）

func _start_bgm(fade_time: float = 1.0) -> void:
	if not bgm_player or not is_bgm_enabled or _bgm_started:
		return

	_bgm_started = true
	bgm_player.volume_db = -200.0
	bgm_player.play()
	var tween = create_tween()
	tween.tween_property(bgm_player, "volume_db", bgm_max_volume_db, fade_time)
	tween.play()
	if startup_logs:
		Debug.log("Debug: BGM fade-in started at %s ms" % Time.get_ticks_msec())

func _focus_web_canvas() -> void:
	if not OS.has_feature("web"):
		return
	if Engine.has_singleton("JavaScriptBridge"):
		JavaScriptBridge.eval("if (typeof Module !== 'undefined' && Module.canvas) { Module.canvas.tabIndex = 0; Module.canvas.focus(); }", true)

func _unlock_web_audio(event: InputEvent) -> void:
	if not OS.has_feature("web") or _bgm_started or not is_bgm_enabled:
		return
	if not bgm_player:
		return

	var user_gesture: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
	)
	if user_gesture:
		_focus_web_canvas()
		_start_bgm()

func _input(event: InputEvent) -> void:
	if OS.has_feature("web") and (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	):
		_focus_web_canvas()

	_unlock_web_audio(event)
	if event is InputEventKey and event.pressed:
		# 調試熱鍵
		if enable_debug_hotkeys:
			if event.keycode == KEY_R and Input.is_key_pressed(KEY_CTRL):
				# Ctrl+R = 重新加載攻擊資料
				reload_attack_data()
				return
			if event.keycode == KEY_G and Input.is_key_pressed(KEY_CTRL):
				# Ctrl+G = 重新加載物理參數
				reload_physics_params()
				return
		
		# 遊戲控制（保持原有功能）
		if event.keycode == KEY_R:
			reset_players()
		if Input.is_action_just_pressed("slowmo_toggle") and not slowmo_triggered:
			slowmo_controller.request_slowmo_change()
			Debug.log("Debug: slowmo_toggle pressed, requesting slow motion change at %s ms" % Time.get_ticks_msec())
		if Input.is_action_just_pressed("toggle_bgm"):
			toggle_bgm()
			Debug.log("Debug: toggle_bgm action triggered, BGM state: %s at %s ms" % [is_bgm_enabled, Time.get_ticks_msec()])
			
func _process(delta: float) -> void:
	fps_label.text = "FPS: %d" % (1.0 / delta)
	
	if animation_label and player_a and player_b:
		var a_anim = player_a.animation_state.get_current_node() if player_a.animation_state else "none"
		var b_anim = player_b.animation_state.get_current_node() if player_b.animation_state else "none"
		animation_label.text = "Player A: %s, Player B: %s" % [a_anim, b_anim]
	
	# 修正：安全檢查 healthbar 是否存在，並在 player 生成後才可能有值
	if not slowmo_triggered and not is_fading_out and is_bgm_enabled and player_a and player_b:
		var a_defeated: bool = player_a.healthbar != null and player_a.healthbar.current_health <= 0
		var b_defeated: bool = player_b.healthbar != null and player_b.healthbar.current_health <= 0
		if a_defeated or b_defeated:
			slowmo_triggered = true
			if bgm_player:
				var tween = create_tween()
				tween.tween_property(bgm_player, "volume_db", -120.0, 2.0)
				tween.tween_callback(bgm_player.stop)
				tween.play()
				is_fading_out = true
				is_bgm_enabled = false
				Debug.log("Debug: BGM fade-out started at %s ms due to player health <= 0" % Time.get_ticks_msec())
			slowmo_controller.request_slowmo_change()
			Debug.log("Debug: Slow motion triggered due to player health <= 0 at %s ms" % Time.get_ticks_msec())
	
	if position_label and player_a and player_b:
		var a_pos = player_a.global_position
		var b_pos = player_b.global_position
		position_label.text = "Player A: (%d, %d)\nPlayer B: (%d, %d)" % [
			int(a_pos.x), int(a_pos.y),
			int(b_pos.x), int(b_pos.y)
		]

func _physics_process(_delta: float) -> void:
	if combo_reset_frames > 0:
		# Stage 1：每個物理幀固定 -1（不再用 delta，hitstop 不影響計數）
		combo_reset_frames -= 1
		if combo_reset_frames <= 0:
			reset_combo()
	
	if attacker and target_player and not advantage_calculated:
		_calculate_hit_advantage()
	
	if block_attacker and blocker and not block_advantage_calculated:
		_calculate_block_advantage()

# （以下函式保持不變，只修正了血量檢查部分）
func _calculate_hit_advantage() -> void:
	# 🟢 【改進】使用確定的幀數計算，避免狀態檢查和轉換誤差
	if not frame_counter or hit_frame == -1:
		return
	
	# 🟢 【第1步】計算被擊者恢復時間（基於確定的 hitstun_frames）
	if target_recover_frame == -1:
		# 直接使用 target_player.hitstun_frames（物理幀，已是確定值）
		if is_instance_valid(target_player) and "hitstun_frames" in target_player and target_player.hitstun_frames > 0:
			# ✅ 兩個都是物理幀，直接相加（無轉換誤差）
			target_recover_frame = hit_frame + target_player.hitstun_frames
		else:
			# 備用方案（不應到達）
			var fallback_hitstun = int(hitstun_frames * frame_counter.FPS_RATIO) if hitstun_frames > 0 else 26
			target_recover_frame = hit_frame + fallback_hitstun
	if attacker_recover_frame == -1 and is_instance_valid(attacker):
		# 🟢 【修復】使用攻擊開始幀 + 完整動畫時長（而非「當前幀 + 剩餘timer」）
		# 根本原因：hit stop 期間會凍結 FrameCounter，導致「當前幀 + timer」計算出錯
		# 正確做法：攻擊的持續時間是確定的，不會因 hit stop 而改變
		
		if "attack_start_frame" in attacker and attack_start_frame != -1 and attack_duration_frames > 0:
			# ✅ 最精確方式：attack_start_frame + 完整動畫時長（不受 hit stop 影響）
			attacker_recover_frame = attack_start_frame + attack_duration_frames

		elif "is_attacking" in attacker and not attacker.is_attacking:
			# 備用：攻擊已結束，記錄當前幀
			attacker_recover_frame = frame_counter.get_current_frame()

		else:
			# 備用：未知狀態
			pass
	
	# 🟢 【第3步】計算優勢（都確認恢復時）
	if attacker_recover_frame != -1 and target_recover_frame != -1 and not advantage_calculated:
		# 物理幀計算（都是 120 FPS，直接計算）
		var physics_advantage_frames = target_recover_frame - attacker_recover_frame
		
		# 邏輯幀計算（轉換為 60 FPS）
		# 🟢 【修復】使用 int() 舍入（向下）而非 round()
		# 理由：當 advantage = 4.5 邏輯幀時，應取 4（還需等待直到第5幀）
		var logic_advantage_frames = int(float(physics_advantage_frames) / frame_counter.FPS_RATIO)
		
		# 秒數計算（基於邏輯幀）
		var advantage_seconds = frame_counter.logic_frames_to_seconds(logic_advantage_frames)
		
		_update_advantage_labels(attacker, logic_advantage_frames, false, advantage_seconds)
		advantage_calculated = true

func _calculate_block_advantage() -> void:
	var valid = is_instance_valid(block_attacker) and is_instance_valid(blocker)
	if not valid: return
	
	if block_attack_recover_frame == -1 and not block_attacker.is_attacking and frame_counter:
		var move_set = block_attacker.get_node_or_null("MoveSet")
		var recovered = true
		if move_set:
			recovered = not (move_set.is_special_moving or move_set.is_spmove)
		if recovered:
			block_attack_recover_frame = frame_counter.get_current_frame()  # ✅ 記錄幀數
	
	if block_defend_recover_frame == -1 and frame_counter:
		var recovered = false
		if blocker.has_method("is_in_blockstun"):
			recovered = not blocker.is_in_blockstun()
		elif "block_lock_frames" in blocker and blocker.block_lock_frames <= 0:
			recovered = true
		else:
			var anim = blocker.animation_state.get_current_node() if blocker.animation_state else ""
			recovered = anim not in ["block", "cr_block"]
		
		if recovered:
			block_defend_recover_frame = frame_counter.get_current_frame()  # ✅ 記錄幀數
	
	if block_attack_recover_frame != -1 and block_defend_recover_frame != -1 and frame_counter:
		var physics_advantage_frames = block_defend_recover_frame - block_attack_recover_frame  # 120 FPS 物理幀
		var logic_advantage_frames = frame_counter.get_logic_frame_difference(block_attack_recover_frame, block_defend_recover_frame)  # ✅ 轉換為 60 FPS 邏輯幀
		var advantage_seconds = frame_counter.logic_frames_to_seconds(logic_advantage_frames)  # ✅ 基於 60 FPS 計算秒數
		_update_advantage_labels(block_attacker, logic_advantage_frames, true, advantage_seconds)
		block_advantage_calculated = true

func _update_advantage_labels(attacker_node: Node, advantage_frames: int, is_block: bool = false, real_seconds: float = 0.0) -> void:
	# 計算各玩家的優勢幀數
	# 正數 = 有利（可以更早繼續進攻）
	# 負數 = 不利（被打會更晚恢復，在防守時受罰）
	var a_frames = 0
	var b_frames = 0
	
	if attacker_node == player_a:
		# P1 是攻擊者
		a_frames = advantage_frames
		b_frames = -advantage_frames
	else:
		# P2 是攻擊者
		b_frames = advantage_frames
		a_frames = -advantage_frames
	
	# 計算秒數
	# 如果有傳入真實秒數，則使用真實秒數（精確值）
	# 否則從幀數計算（向後相容）
	var a_seconds: float
	var b_seconds: float
	if real_seconds != 0.0:
		# 使用真實讀取的秒數（精確）
		a_seconds = real_seconds
		b_seconds = -real_seconds
	else:
		# 從幀數計算（舊方法，精度會損失）
		a_seconds = a_frames / 60.0
		b_seconds = b_frames / 60.0
	
	# 格式化顯示文本：幀數 + 秒數
	# 注意：支持正數（有利）和負數（不利）
	var a_text = "P1 Adv: "
	var b_text = "P2 Adv: "
	
	# 格式化幀數字符串 - 明確顯示正負號
	var a_frames_str: String
	if a_frames > 0:
		a_frames_str = "+%d" % a_frames
	elif a_frames < 0:
		a_frames_str = "%d" % a_frames  # 負號會自動包含
	else:
		a_frames_str = "0"
	
	var b_frames_str: String
	if b_frames > 0:
		b_frames_str = "+%d" % b_frames
	elif b_frames < 0:
		b_frames_str = "%d" % b_frames  # 負號會自動包含
	else:
		b_frames_str = "0"
	
	# 格式化秒數字符串 - 使用絕對值以保持符號一致
	var a_seconds_str: String
	if a_frames != 0:
		if a_frames > 0:
			a_seconds_str = "+%.3fs" % a_seconds
		else:
			a_seconds_str = "%.3fs" % a_seconds  # 負號會自動包含
	else:
		a_seconds_str = "0.000s"
	
	var b_seconds_str: String
	if b_frames != 0:
		if b_frames > 0:
			b_seconds_str = "+%.3fs" % b_seconds
		else:
			b_seconds_str = "%.3fs" % b_seconds  # 負號會自動包含
	else:
		b_seconds_str = "0.000s"
	
	a_text += "%sF (%s)" % [a_frames_str, a_seconds_str]
	b_text += "%sF (%s)" % [b_frames_str, b_seconds_str]
	
	if p1_advantage_label:
		p1_advantage_label.text = a_text
	if p2_advantage_label:
		p2_advantage_label.text = b_text
	
	var type = "Block" if is_block else "Hit"
	var advantage_str: String
	if advantage_frames > 0:
		advantage_str = "+%d" % advantage_frames
	elif advantage_frames < 0:
		advantage_str = "%d" % advantage_frames
	else:
		advantage_str = "0"
	
	var advantage_sec_str: String
	if advantage_frames > 0:
		advantage_sec_str = "+%.3fs" % (advantage_frames / 60.0)
	elif advantage_frames < 0:
		advantage_sec_str = "%.3fs" % (advantage_frames / 60.0)
	else:
		advantage_sec_str = "0.000s"
	
	var attacker_name = attacker_node.name if attacker_node else StringName("Unknown")

func to_scaled_vector2(vector: Vector2i) -> Vector2:
	return Vector2(float(vector.x) / SIMULATION_SCALE, float(vector.y) / SIMULATION_SCALE)

# ============================================================
# 🔥 熱重載系統 - 即時套用編輯器數值變更
# ============================================================
func reload_attack_data() -> void:
	"""重新加載攻擊資料（Ctrl+R）"""
	if not player_a or not player_b:
		Debug.log("❌ 無法熱重載：玩家尚未初始化")
		return
	
	var reload_count = 0
	Debug.log("\n🔄 [HOT RELOAD] 開始重新加載攻擊資料...")
	
	for player in [player_a, player_b]:
		if player.has_method("reload_attack_data"):
			player.reload_attack_data()
			reload_count += 1
			Debug.log("  ✅ %s 攻擊資料已重新加載" % player.seat)
		else:
			Debug.log("  ⚠️  %s 無 reload_attack_data() 方法" % player.seat)
	
	Debug.log("✨ 熱重載完成: %d 個玩家的攻擊資料已更新\n" % reload_count)

func reload_physics_params() -> void:
	"""重新加載物理參數（Ctrl+G）"""
	if not player_a or not player_b:
		Debug.log("❌ 無法熱重載：玩家尚未初始化")
		return
	
	Debug.log("\n🔄 [HOT RELOAD] 開始重新加載物理參數...")
	
	for player in [player_a, player_b]:
		if player.has_method("reload_physics_params"):
			player.reload_physics_params()
			Debug.log("  ✅ %s 物理參數已重新加載" % player.seat)
		else:
			Debug.log("  ⚠️  %s 無 reload_physics_params() 方法" % player.seat)
	
	Debug.log("✨ 物理參數熱重載完成\n")

func reset_player_animation(player: Node, target_state: String) -> void:
	var animation_tree = player.get_node_or_null("AnimationTree")
	var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
	var animation_player = player.get_node_or_null("AnimationPlayer")
	var move_set = player.get_node_or_null("MoveSet")
	
	if not animation_tree or not animation_state or not animation_player:
		Debug.log("Warning: AnimationTree, animation_state, or animation_player not found for %s" % player.name)
		return
	
	animation_player.stop()
	animation_player.clear_queue()
	animation_player.speed_scale = 1.0
	Debug.log("Debug: %s AnimationPlayer stopped and queue cleared at %s ms" % [player.name, Time.get_ticks_msec()])
	
	animation_tree.active = false
	
	var conditions = {
		"Walk": target_state == "Walk",
		"Crouch": target_state == "Crouch",
		"Dash": false,
		"Backdash": false,
		"st_mp": target_state == "st_mp",
		"Jump_F": target_state == "Jump_F",
		"Jump_B": target_state == "Jump_B",
		"Jump_V": target_state == "Jump_V",
		"hit": target_state == "hit",
		"knockfly": target_state == "knockfly",
		"block": target_state == "block",
		"cr_block": target_state == "cr_block",
		"powerkk": target_state == "powerkk" and player.character_id == "DAV" and move_set and move_set.is_move_active("powerkk"),
		"spnk": target_state == "spnk" and player.character_id == "DEN" and move_set and move_set.is_move_active("spnk"),
		"landing": target_state == "landing"
	}
	for condition in conditions:
		animation_tree.set("parameters/conditions/" + condition, conditions[condition])
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", 0.0)
	
	animation_tree.active = true
	animation_state.travel(target_state)
	Debug.log("Debug: %s animation reset to %s at %s ms" % [player.name, target_state, Time.get_ticks_msec()])

func reset_players() -> void:
	if not player_a or not player_b:
		return
	
	player_a.global_position = initial_player_a_pos
	player_b.global_position = initial_player_b_pos
	player_a.fixed_position = Vector2i(int(initial_player_a_pos.x * SIMULATION_SCALE), FLOOR_Y)
	player_b.fixed_position = Vector2i(int(initial_player_b_pos.x * SIMULATION_SCALE), FLOOR_Y)
	player_a.global_position = to_scaled_vector2(player_a.fixed_position)
	player_b.global_position = to_scaled_vector2(player_b.fixed_position)
	
	for player in [player_a, player_b]:
		if player.healthbar != null:
			player.healthbar.current_health = 100.0
			Debug.log("Debug: %s health reset to 100.0 at %s ms" % [player.name, Time.get_ticks_msec()])
	
	for player in [player_a, player_b]:
		player.is_hit = false
		player.is_knockfly = false
		player.is_blocking = false
		player.is_attacking = false
		player.is_dashing = false
		player.is_backdashing = false
		player.is_jumping = false
		player.is_crouching = false
		player.is_landing = false
		# 【同上】is_landing 被清除時 landing_lock_frames 必須一起歸零，
		# 否則殘留鎖會凍結 _update_animation_state 最多 25 幀
		player.landing_lock_frames = 0
		player.is_wakeup = false
		player.is_wakeup_locked = false
		player.hit_lock_frames = 0
		player.block_lock_frames = 0
		player.knockfly_frames = 0
		player.knockfly_duration_frames = 0
		player.block_push_frames = 0
		player.attack_type = "none"
		player.update_facing_direction()
	
	for player in [player_a, player_b]:
		if player.has_node("MoveSet"):
			player.get_node("MoveSet").stop_special_move()
	
	for player in [player_a, player_b]:
		reset_player_animation(player, "Walk")
	
	# Reset AI behavior (no state properties in new AI system)
	for player in [player_a, player_b]:
		if player.has_node("AIBehavior"):
			var ai_behavior = player.get_node("AIBehavior")
			# Reset commitment and decision timers（Stage 1：物理幀計數，0 = 立即解除）
			ai_behavior.commitment_frames = 0
			ai_behavior.decision_cooldown_frames = 0
			ai_behavior.current_committed_action = ""
			ai_behavior.committed_input = {}
	
	if slowmo_controller:
		slowmo_controller.exit_slowmo_animation()
		slowmo_controller.is_hit_slowmo = false
		slowmo_triggered = false
		Engine.time_scale = slowmo_controller.normal_time_scale
		Debug.log("Debug: Slow motion and hit slowmo states reset, time_scale=%s at %s ms" % [Engine.time_scale, Time.get_ticks_msec()])
	
	if bgm_player:
		bgm_player.stop()
		if is_bgm_enabled:
			bgm_player.volume_db = -120.0
			bgm_player.play()
			var tween = create_tween()
			tween.tween_property(bgm_player, "volume_db", bgm_max_volume_db, 3.0)
			tween.play()
			Debug.log("Debug: BGM reset and fade-in started at %s ms" % Time.get_ticks_msec())
		else:
			bgm_player.volume_db = -120.0
			Debug.log("Debug: BGM reset but kept off at %s ms" % Time.get_ticks_msec())
		is_fading_out = false
	
	if animation_label:
		animation_label.text = "Player A: Walk, Player B: Walk"
	
	reset_combo()
	if debug_label:
		debug_label.text = ""
	
	hit_time = 0.0
	attacker = null
	target_player = null
	attacker_recover_frame = -1
	target_recover_frame = -1
	advantage_calculated = false
	attack_start_frame = -1
	attack_duration_frames = 0
	hit_frame = -1
	hitstun_frames = 0
	block_attacker = null
	blocker = null
	block_attack_recover_frame = -1
	block_defend_recover_frame = -1
	block_advantage_calculated = false
	
	if p1_advantage_label:
		p1_advantage_label.text = "P1 Adv: 0"
	if p2_advantage_label:
		p2_advantage_label.text = "P2 Adv: 0"
	
	# 重置優勢計算（改用幀計數器）
	attacker_recover_frame = -1
	target_recover_frame = -1
	block_attack_recover_frame = -1
	block_defend_recover_frame = -1
	advantage_calculated = false
	block_advantage_calculated = false
	
	# 重置幀計數器
	if frame_counter:
		frame_counter.reset()
	
	if frame_bar_p1:
		frame_bar_p1.reset_frame_bar()
	if frame_bar_p2:
		frame_bar_p2.reset_frame_bar()
	
	Debug.log("[WORLD] ✓ 玩家重置完成 - 位置、血量、動畫、幀條、優勢已恢復 | FrameCounter 重置至 0")

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool) -> void:
	var hit_time_ms = Time.get_ticks_msec()
	
	if not is_blocked:
		hit_label.text = "Hits: " + target + " was hit!"
		
		if was_in_stun and combo_target == target and current_combo > 0:
			current_combo += 1
		else:
			current_combo = 1
			combo_target = target
		# hit_detected 傳入的是 60 FPS 邏輯幀（hitstun/blockstun）。Stage 1：
		# 在訊號載入邊界一次性轉成物理幀窗口 = stun×2 + 0.2s 緩衝（lock 式 +1），
		# 24 邏輯幀 → 48+25=73 物理幀。舊秒制曾把 24 誤當 24 秒或依赖 delta，皆已不存在。
		combo_reset_frames = Movement.logic_frames_to_physics_frames(stun_duration) \
			+ Movement.seconds_to_lock_frames(COMBO_BUFFER_SECONDS)
		update_combo_label()
		
		attacker = player_a if target == player_b.name else player_b
		target_player = player_b if target == player_b.name else player_a
		
		# 🟢 【改進】實時追蹤 advantage，記錄當前被擊時的相關信息
		if attacker and target_player and frame_counter:
			# 🟢 【修復】記錄攻擊開始幀（來自 player.gd）
			if "attack_start_frame" in attacker:
				attack_start_frame = attacker.attack_start_frame
			else:
				attack_start_frame = -1
			
			# 記錄當前被擊時的幀數（120 FPS 物理幀）
			hit_frame = frame_counter.get_current_frame()
			
			# 🟢 【關鍵】直接取得被擊者的 hitstun_frames（已是物理幀，來自 take_hit()）
			if "hitstun_frames" in target_player:
				hitstun_frames = target_player.hitstun_frames  # ✅ 物理幀，直接使用
				Debug.log("[HIT DETECTION] 被擊者 %s 進入 %d 物理幀 hitstun (%.1f 邏輯幀)" % [
					target_player.name, hitstun_frames, hitstun_frames / frame_counter.FPS_RATIO
				])
			else:
				# 備用：轉換信號的 stun_duration（邏輯幀）→ 物理幀（唯一邊界）
				hitstun_frames = Movement.logic_frames_to_physics_frames(stun_duration)
			
			# 🟢 【修復】記錄攻擊的完整持續時間（物理幀）
			# 用於在 _calculate_hit_advantage() 中準確計算恢復時間
			attack_duration_frames = 0
			if "animation_player" in attacker and "attack_type" in attacker:
				var anim_player = attacker.animation_player
				var attack_type = attacker.attack_type
				if anim_player and anim_player.has_animation(attack_type):
					var anim_length = anim_player.get_animation(attack_type).length
					attack_duration_frames = Movement.seconds_to_frames_nearest(anim_length)

		
		attacker_recover_frame = -1
		target_recover_frame = -1
		advantage_calculated = false
		
		block_attacker = null
		blocker = null
		block_attack_recover_frame = -1
		block_defend_recover_frame = -1
		block_advantage_calculated = false
		
	else:
		hit_label.text = target + " blocked!"
		Debug.log("Debug: %s blocked at %s ms" % [target, hit_time_ms])
		reset_combo()
		
		block_attacker = player_a if target == player_b.name else player_b
		blocker = player_b if target == player_b.name else player_a
		block_attack_recover_frame = -1
		block_defend_recover_frame = -1
		block_advantage_calculated = false
		
		attacker = null
		target_player = null
		advantage_calculated = true
	
	var attacker_name: String = str(attacker.name) if attacker else "none"
	var target_name: String = str(target_player.name) if target_player else "none"

func _on_block_detected(target: String, block_type: String) -> void:
	var block_time_ms = Time.get_ticks_msec()
	if block_type == "proximity":
		hit_label.text = target + " blocked (proximity)!"
		Debug.log("Debug: %s triggered proximity block at %s ms" % [target, block_time_ms])
	reset_combo()

func update_combo_label() -> void:
	if current_combo >= 2:
		combo_label.text = str(current_combo) + " Hit !"
	else:
		combo_label.text = ""

func reset_combo() -> void:
	current_combo = 0
	combo_target = ""
	update_combo_label()

func toggle_bgm() -> void:
	if not bgm_player:
		Debug.log("Warning: BGMPlayer node not found, cannot toggle BGM")
		return
	
	is_fading_out = true
	var tween = create_tween()
	
	if is_bgm_enabled:
		tween.tween_property(bgm_player, "volume_db", -120.0, 1.0)
		tween.tween_callback(bgm_player.stop)
		is_bgm_enabled = false
		Debug.log("Debug: BGM fading out and stopping at %s ms" % Time.get_ticks_msec())
	else:
		bgm_player.play()
		tween.tween_property(bgm_player, "volume_db", bgm_max_volume_db, 1.0)
		is_bgm_enabled = true
		Debug.log("Debug: BGM playing and fading in at %s ms" % Time.get_ticks_msec())
	
	tween.tween_callback(func(): is_fading_out = false)
	tween.play()

func _on_countdown_finished() -> void:
	Debug.log("對戰時間結束")
