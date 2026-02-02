extends Node2D

const TICKS_PER_SECOND: int = 60
const SIMULATION_SCALE: int = 1000
const WALL_LIMIT: int = 1280000
const STARTING_POSITION: int = 10000
const FLOOR_Y: int = 550000
const GRAVITY: int = 6200000
@export var arena_left: float = 0.0      # 舞台左邊界（像素）
@export var arena_right: float = 1600.0  # 舞台右邊界（像素）

@onready var position_label = $UI/PositionLabel
@export var bgm_max_volume_db: float = -6.0

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
@export var player_a_character: CharacterData
@export var player_b_character: CharacterData

# 動態生成的玩家
var player_a: Player
var player_b: Player

var initial_player_a_pos: Vector2
var initial_player_b_pos: Vector2

var slowmo_triggered: bool = false
var current_combo: int = 0
var combo_target: String = ""
var combo_reset_timer: float = 0.0
const COMBO_BUFFER: float = 0.2

# Hit Advantage
var hit_time: float = 0.0
var attacker: Node = null
var target_player: Node = null
var attacker_recover_time: float = 0.0
var target_recover_time: float = 0.0
var advantage_calculated: bool = false

# Block Advantage
var block_attacker: Node = null
var blocker: Node = null
var block_attack_recover_time: float = 0.0
var block_defend_recover_time: float = 0.0
var block_advantage_calculated: bool = false

var is_fading_out: bool = false
var is_bgm_enabled: bool = true

func _ready() -> void:
	add_to_group("world")
	print("Debug: World _ready() 開始執行")
	
	# ============================================================
	# 初始化 HitboxCache（新增）
	# ============================================================
	var hitbox_cache = HitboxCache.new()
	hitbox_cache.name = "HitboxCache"
	hitbox_cache.debug_mode = true  # 啟用調試輸出
	add_child(hitbox_cache)
	hitbox_cache.add_to_group("hitbox_cache")
	print("[WORLD] HitboxCache 已初始化")
	
	# ============================================================
	# 初始化 ResourcePreloadManager（特效預載系統）
	# ============================================================
	var resource_preloader = ResourcePreloadManager.new()
	resource_preloader.name = "ResourcePreloader"
	add_child(resource_preloader)
	resource_preloader.add_to_group("resource_preloader")
	print("[WORLD] ResourcePreloadManager 已初始化")
	
	# ============================================================
	# 初始化 AI 性能監視器（Phase 2 優化）
	# ============================================================
	if enable_performance_monitoring:
		var profiler = AIPerformanceMonitor.new()
		profiler.enabled = true
		profiler.log_interval = profiling_log_interval
		profiler.show_realtime = false
		add_child(profiler)
		print("[WORLD] ✓ AI 性能監視器已啟用 (每 %.1f 秒輸出一次報告，檢查 Console 標籤)" % profiling_log_interval)
	else:
		print("[WORLD] ℹ️ AI 性能監視器已禁用 (在 Inspector 中設置 enable_performance_monitoring = True 以啟用)")
	
	# ============================================================
	# 🟢 【新增】初始化 Hit Stop 時機調試器
	# ============================================================
	var hitstop_debug = HitStopTimingDebugger.new()
	hitstop_debug.name = "HitStopTimingDebugger"
	hitstop_debug.enabled = true  # 設為 false 可關閉調試輸出
	hitstop_debug.detailed_logging = false  # 設為 true 可查看更詳細的日誌
	add_child(hitstop_debug)
	print("[WORLD] ✓ HitStopTimingDebugger 已初始化 (詳細日誌: %s)" % hitstop_debug.detailed_logging)
	
	# 關鍵修正：優先從選角畫面讀取角色（SelectedCharacters 是 Autoload 全局單例）
	if SelectedCharacters.p1_character != null and SelectedCharacters.p2_character != null:
		player_a_character = SelectedCharacters.p1_character
		player_b_character = SelectedCharacters.p2_character
		print("從選角畫面成功載入角色：P1 = %s, P2 = %s" % [player_a_character.display_name, player_b_character.display_name])
	else:
		# 如果直接執行 world.tscn（測試用），檢查編輯器是否有手動拖入角色
		if not player_a_character:
			push_error("錯誤：Player A 的 CharacterData 未指定！請從 CharacterSelect 進入，或在 World 節點的 Inspector 中拖入角色 .tres")
			return
		if not player_b_character:
			push_error("錯誤：Player B 的 CharacterData 未指定！請從 CharacterSelect 進入，或在 World 節點的 Inspector 中拖入角色 .tres")
			return
		print("使用編輯器預設角色：P1 = %s, P2 = %s" % [player_a_character.display_name, player_b_character.display_name])
	
	# 安全檢查：確保兩個角色都有 PackedScene
	if not player_a_character.scene:
		push_error("錯誤：Player A 的 CharacterData.scene 為空！請確認 .character.tres 資源的 Scene 欄位已拖入角色場景（如 DAV.tscn）。")
		return
	if not player_b_character.scene:
		push_error("錯誤：Player B 的 CharacterData.scene 為空！請確認 .character.tres 資源的 Scene 欄位已拖入角色場景。")
		return
	
	# 生成玩家（順序很重要：先生成玩家，再連接信號）
	player_a = _spawn_player(player_a_character, Vector2(550.0, float(FLOOR_Y) / SIMULATION_SCALE), "player_a")
	player_b = _spawn_player(player_b_character, Vector2(1050.0, float(FLOOR_Y) / SIMULATION_SCALE), "player_b")
	if not player_a or not player_b:
		push_error("角色生成失敗！請檢查 CharacterData 和場景設定。")
		return
	
	# 連接信號
	player_a.hit_detected.connect(_on_hit_detected)
	player_a.block_detected.connect(_on_block_detected)
	player_b.hit_detected.connect(_on_hit_detected)
	player_b.block_detected.connect(_on_block_detected)
	
	# 其餘初始化（保持不變）
	if not slowmo_controller:
		print("Warning: SlowMoController node not found in world")
	if not animation_label:
		print("Warning: AnimationLabel node not found in world")
	if not combo_label:
		print("Warning: ComboLabel node not found in world")
	else:
		combo_label.text = ""
	if debug_label:
		debug_label.text = ""
	if p1_advantage_label:
		p1_advantage_label.text = "P1 Adv: 0"
	if p2_advantage_label:
		p2_advantage_label.text = "P2 Adv: 0"
	else:
		print("Warning: Advantage labels not found in UI")
	if bgm_player:
		is_bgm_enabled = true
		bgm_player.volume_db = -80.0
		bgm_player.play()
		var tween = create_tween()
		tween.tween_property(bgm_player, "volume_db", bgm_max_volume_db, 1.0)
		tween.play()
		print("Debug: BGM fade-in started at %s ms" % Time.get_ticks_msec())
	else:
		print("Warning: BGMPlayer node not found in world")
	
	initial_player_a_pos = player_a.global_position
	initial_player_b_pos = player_b.global_position
	print("Debug: Initial positions set - Player A: %s, Player B: %s" % [player_a.global_position, player_b.global_position])
	
	if frame_bar_p1:
		frame_bar_p1.initialize(player_a, player_b)
		frame_bar_p1.z_index = 10
	else:
		print("Error: FrameBarP1 not found in UI")
	if frame_bar_p2:
		frame_bar_p2.initialize(player_b, player_a)
		frame_bar_p2.z_index = 10
	else:
		print("Error: FrameBarP2 not found in UI")
	
	if position_label:
		position_label.text = "Player A: (0, 0)\nPlayer B: (0, 0)"
	else:
		print("Warning: PositionLabel not found in UI")
	
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

func _input(event) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			reset_players()
		if Input.is_action_just_pressed("slowmo_toggle") and not slowmo_triggered:
			slowmo_controller.request_slowmo_change()
			print("Debug: slowmo_toggle pressed, requesting slow motion change at %s ms" % Time.get_ticks_msec())
		if Input.is_action_just_pressed("toggle_bgm"):
			toggle_bgm()
			print("Debug: toggle_bgm action triggered, BGM state: %s at %s ms" % [is_bgm_enabled, Time.get_ticks_msec()])
			
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
				tween.tween_property(bgm_player, "volume_db", -80.0, 2.0)
				tween.tween_callback(bgm_player.stop)
				tween.play()
				is_fading_out = true
				is_bgm_enabled = false
				print("Debug: BGM fade-out started at %s ms due to player health <= 0" % Time.get_ticks_msec())
			slowmo_controller.request_slowmo_change()
			print("Debug: Slow motion triggered due to player health <= 0 at %s ms" % Time.get_ticks_msec())
	
	if position_label and player_a and player_b:
		var a_pos = player_a.global_position
		var b_pos = player_b.global_position
		position_label.text = "Player A: (%d, %d)\nPlayer B: (%d, %d)" % [
			int(a_pos.x), int(a_pos.y),
			int(b_pos.x), int(b_pos.y)
		]

func _physics_process(delta: float) -> void:
	if combo_reset_timer > 0:
		combo_reset_timer -= delta
		if combo_reset_timer <= 0:
			reset_combo()
	
	if attacker and target_player and not advantage_calculated:
		_calculate_hit_advantage()
	
	if block_attacker and blocker and not block_advantage_calculated:
		_calculate_block_advantage()

# （以下函式保持不變，只修正了血量檢查部分）
func _calculate_hit_advantage() -> void:
	if attacker_recover_time == 0.0 and is_instance_valid(attacker) and not attacker.is_attacking:
		var move_set = attacker.get_node_or_null("MoveSet")
		var recovered = true
		if move_set:
			recovered = not (move_set.is_special_moving or move_set.is_spmove)
		if recovered:
			attacker_recover_time = Time.get_unix_time_from_system()
			print("Debug: Attacker %s recovered at %.3f" % [attacker.name, attacker_recover_time])
	
	if target_recover_time == 0.0 and is_instance_valid(target_player):
		var still_in_hitstun := false
		if target_player.has_method("is_in_hitstun"):
			still_in_hitstun = target_player.is_in_hitstun()
		elif "is_hit" in target_player:
			still_in_hitstun = target_player.is_hit
		
		if not still_in_hitstun and not target_player.is_blocking:
			target_recover_time = Time.get_unix_time_from_system()
			print("Debug: Target %s recovered at %.3f" % [target_player.name, target_recover_time])
			
			if attacker_recover_time > 0.0:
				var adv_sec = target_recover_time - attacker_recover_time
				var adv_frames = int(round(adv_sec * 60.0))
				_update_advantage_labels(attacker, adv_frames)
				advantage_calculated = true

func _calculate_block_advantage() -> void:
	var valid = is_instance_valid(block_attacker) and is_instance_valid(blocker)
	if not valid: return
	
	if block_attack_recover_time == 0.0 and not block_attacker.is_attacking:
		var move_set = block_attacker.get_node_or_null("MoveSet")
		var recovered = true
		if move_set:
			recovered = not (move_set.is_special_moving or move_set.is_spmove)
		if recovered:
			block_attack_recover_time = Time.get_unix_time_from_system()
	
	if block_defend_recover_time == 0.0:
		var recovered = false
		if blocker.has_method("is_in_blockstun"):
			recovered = not blocker.is_in_blockstun()
		elif "block_timer" in blocker and blocker.block_timer <= 0.0:
			recovered = true
		else:
			var anim = blocker.animation_state.get_current_node() if blocker.animation_state else ""
			recovered = anim not in ["block", "cr_block"]
		
		if recovered:
			block_defend_recover_time = Time.get_unix_time_from_system()
	
	if block_attack_recover_time > 0.0 and block_defend_recover_time > 0.0:
		var advantage_sec = block_defend_recover_time - block_attack_recover_time
		var advantage_frames = int(round(advantage_sec * 60.0))
		_update_advantage_labels(block_attacker, advantage_frames, true)
		block_advantage_calculated = true

func _update_advantage_labels(attacker_node: Node, advantage_frames: int, is_block: bool = false) -> void:
	var a_frames = 0
	var b_frames = 0
	
	if attacker_node == player_a:
		a_frames = advantage_frames
		b_frames = -advantage_frames
	else:
		b_frames = advantage_frames
		a_frames = -advantage_frames
	
	var a_text = "P1 Adv: "
	var b_text = "P2 Adv: "
	
	a_text += ("+%d" % a_frames) if a_frames > 0 else str(a_frames)
	b_text += ("+%d" % b_frames) if b_frames > 0 else str(b_frames)
	
	if p1_advantage_label:
		p1_advantage_label.text = a_text
	if p2_advantage_label:
		p2_advantage_label.text = b_text
	
	var type = "Block" if is_block else "Hit"
	var advantage_str = "+%d" % advantage_frames if advantage_frames > 0 else str(advantage_frames)
	print("[ADVANTAGE] %s → 攻擊者優勢 %sF → Player A: %s / Player B: %s" % [
		type,
		advantage_str,
		a_text, b_text
	])

func to_scaled_vector2(vector: Vector2i) -> Vector2:
	return Vector2(float(vector.x) / SIMULATION_SCALE, float(vector.y) / SIMULATION_SCALE)

func reset_player_animation(player: Node, target_state: String) -> void:
	var animation_tree = player.get_node_or_null("AnimationTree")
	var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
	var animation_player = player.get_node_or_null("AnimationPlayer")
	var move_set = player.get_node_or_null("MoveSet")
	
	if not animation_tree or not animation_state or not animation_player:
		print("Warning: AnimationTree, animation_state, or animation_player not found for %s" % player.name)
		return
	
	animation_player.stop()
	animation_player.clear_queue()
	animation_player.speed_scale = 1.0
	print("Debug: %s AnimationPlayer stopped and queue cleared at %s ms" % [player.name, Time.get_ticks_msec()])
	
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
	print("Debug: %s animation reset to %s at %s ms" % [player.name, target_state, Time.get_ticks_msec()])

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
			print("Debug: %s health reset to 100.0 at %s ms" % [player.name, Time.get_ticks_msec()])
	
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
		player.is_wakeup = false
		player.is_wakeup_locked = false
		player.hit_timer = 0.0
		player.block_timer = 0.0
		player.knockfly_timer = 0.0
		player.current_mode = "ground_stand"
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
			# Reset commitment and decision timers
			ai_behavior.commitment_timer = 0.0
			ai_behavior.decision_cooldown = 0.0
			ai_behavior.current_committed_action = ""
			ai_behavior.committed_input = {}
	
	if slowmo_controller:
		slowmo_controller.exit_slowmo_animation()
		slowmo_controller.is_hit_slowmo = false
		slowmo_triggered = false
		Engine.time_scale = slowmo_controller.normal_time_scale
		print("Debug: Slow motion and hit slowmo states reset, time_scale=%s at %s ms" % [Engine.time_scale, Time.get_ticks_msec()])
	
	if bgm_player:
		bgm_player.stop()
		if is_bgm_enabled:
			bgm_player.volume_db = -80.0
			bgm_player.play()
			var tween = create_tween()
			tween.tween_property(bgm_player, "volume_db", bgm_max_volume_db, 3.0)
			tween.play()
			print("Debug: BGM reset and fade-in started at %s ms" % Time.get_ticks_msec())
		else:
			bgm_player.volume_db = -80.0
			print("Debug: BGM reset but kept off at %s ms" % Time.get_ticks_msec())
		is_fading_out = false
	
	if animation_label:
		animation_label.text = "Player A: Walk, Player B: Walk"
	
	reset_combo()
	if debug_label:
		debug_label.text = ""
	
	hit_time = 0.0
	attacker = null
	target_player = null
	attacker_recover_time = 0.0
	target_recover_time = 0.0
	advantage_calculated = false
	block_attacker = null
	blocker = null
	block_attack_recover_time = 0.0
	block_defend_recover_time = 0.0
	block_advantage_calculated = false
	
	if p1_advantage_label:
		p1_advantage_label.text = "P1 Adv: 0"
	if p2_advantage_label:
		p2_advantage_label.text = "P2 Adv: 0"
	
	if frame_bar_p1:
		frame_bar_p1.reset_frame_bar()
	if frame_bar_p2:
		frame_bar_p2.reset_frame_bar()
	
	print("Debug: Players reset! Positions, health, animations, frame bars, and advantages restored at %s ms" % Time.get_ticks_msec())

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool) -> void:
	var hit_time_ms = Time.get_ticks_msec()
	
	if not is_blocked:
		hit_label.text = "Hits: " + target + " was hit!"
		print("Debug: %s was hit at %s ms, stun_duration=%s" % [target, hit_time_ms, stun_duration])
		
		if was_in_stun and combo_target == target and current_combo > 0:
			current_combo += 1
		else:
			current_combo = 1
			combo_target = target
		combo_reset_timer = stun_duration + COMBO_BUFFER
		update_combo_label()
		
		attacker = player_a if target == player_b.name else player_b
		target_player = player_b if target == player_b.name else player_a
		attacker_recover_time = 0.0
		target_recover_time = 0.0
		advantage_calculated = false
		
		block_attacker = null
		blocker = null
		block_attack_recover_time = 0.0
		block_defend_recover_time = 0.0
		block_advantage_calculated = false
		
	else:
		hit_label.text = target + " blocked!"
		print("Debug: %s blocked at %s ms" % [target, hit_time_ms])
		reset_combo()
		
		block_attacker = player_a if target == player_b.name else player_b
		blocker = player_b if target == player_b.name else player_a
		block_attack_recover_time = 0.0
		block_defend_recover_time = 0.0
		block_advantage_calculated = false
		
		attacker = null
		target_player = null
		advantage_calculated = true
	
	var attacker_name: String = attacker.name if attacker else "none"
	var target_name: String = target_player.name if target_player else "none"
	print("Debug: Hit detected at %s ms, attacker=%s, target=%s" % [hit_time_ms, attacker_name, target_name])

func _on_block_detected(target: String, block_type: String) -> void:
	var block_time_ms = Time.get_ticks_msec()
	if block_type == "proximity":
		hit_label.text = target + " blocked (proximity)!"
		print("Debug: %s triggered proximity block at %s ms" % [target, block_time_ms])
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
		print("Warning: BGMPlayer node not found, cannot toggle BGM")
		return
	
	is_fading_out = true
	var tween = create_tween()
	
	if is_bgm_enabled:
		tween.tween_property(bgm_player, "volume_db", -80.0, 1.0)
		tween.tween_callback(bgm_player.stop)
		is_bgm_enabled = false
		print("Debug: BGM fading out and stopping at %s ms" % Time.get_ticks_msec())
	else:
		bgm_player.play()
		tween.tween_property(bgm_player, "volume_db", bgm_max_volume_db, 1.0)
		is_bgm_enabled = true
		print("Debug: BGM playing and fading in at %s ms" % Time.get_ticks_msec())
	
	tween.tween_callback(func(): is_fading_out = false)
	tween.play()

func _on_countdown_finished() -> void:
	print("對戰時間結束")
