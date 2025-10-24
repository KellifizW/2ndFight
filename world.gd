extends Node2D

const TICKS_PER_SECOND: int = 60
const SIMULATION_SCALE: int = 1000
const WALL_LIMIT: int = 24000
const STARTING_POSITION: int = 7500
const FLOOR_Y: int = 200000
const GRAVITY: int = 1800000

@onready var hit_label = $UI/HitLabel
@onready var fps_label = $UI/FPS
@onready var player1 = $Player1
@onready var player2 = $Player2
@onready var slowmo_controller = $SlowMoController
@onready var animation_label = $UI/AnimationLabel
@onready var combo_label = $UI/ComboLabel
@onready var debug_label = $UI/DebugLabel
@onready var p1_advantage_label = $UI/P1AdvantageLabel
@onready var p2_advantage_label = $UI/P2AdvantageLabel
@onready var frame_bar_p1 = $UI/FrameBarP1
@onready var frame_bar_p2 = $UI/FrameBarP2
@onready var bgm_player = $BGMPlayer if has_node("BGMPlayer") else null # 新增：背景音樂播放器

var initial_p1_pos: Vector2
var initial_p2_pos: Vector2
var slowmo_triggered: bool = false
var current_combo: int = 0
var combo_target: String = ""
var combo_reset_timer: float = 0.0
const COMBO_BUFFER: float = 0.2

# 用於計算優勢時間的變數（使用真實時間，避免 slowmo 影響）
var hit_time: float = 0.0
var attacker: Node = null
var target_player: Node = null
var attacker_recover_time: float = 0.0
var target_recover_time: float = 0.0
var advantage_calculated: bool = false

# 新增：背景音樂控制變數
var is_fading_out: bool = false

func _ready():
	add_to_group("world")
	print("Debug: World added to group 'world'. Group members: ", get_tree().get_nodes_in_group("world"))
	if not is_in_group("world"):
		print("Error: World failed to join 'world' group")
	player1.hit_detected.connect(_on_hit_detected)
	player2.hit_detected.connect(_on_hit_detected)
	player1.block_detected.connect(_on_block_detected)
	player2.block_detected.connect(_on_block_detected)
	if not player1 or not player2:
		print("Error: Player1 or Player2 node not found in world")
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
	
	# 新增：初始化背景音樂
	if bgm_player:
		bgm_player.volume_db = -80.0 # 初始無聲
		var tween = create_tween()
		tween.tween_property(bgm_player, "volume_db", 0.0, 1.0) # 3秒淡入到正常音量
		tween.play()
		print("Debug: BGM fade-in started at %s ms" % Time.get_ticks_msec())
	else:
		print("Warning: BGMPlayer node not found in world")

	initial_p1_pos = Vector2(190.0, float(FLOOR_Y) / SIMULATION_SCALE)
	initial_p2_pos = Vector2(290.0, float(FLOOR_Y) / SIMULATION_SCALE)
	player1.fixed_position = Vector2i(int(190.0 * SIMULATION_SCALE), FLOOR_Y)
	player2.fixed_position = Vector2i(int(290.0 * SIMULATION_SCALE), FLOOR_Y)
	player1.global_position = to_scaled_vector2(player1.fixed_position)
	player2.global_position = to_scaled_vector2(player2.fixed_position)
	print("Debug: Initial positions set - P1: %s, P2: %s" % [player1.global_position, player2.global_position])
	
	if frame_bar_p1:
		frame_bar_p1.initialize(player1, player2)
		frame_bar_p1.z_index = 10
		print("Debug: FrameBarP1 initialized at position: %s, z_index: %d" % [frame_bar_p1.position, frame_bar_p1.z_index])
	else:
		print("Error: FrameBarP1 not found in UI")
	
	if frame_bar_p2:
		frame_bar_p2.initialize(player2, player1)
		frame_bar_p2.z_index = 10
		print("Debug: FrameBarP2 initialized at position: %s, z_index: %d" % [frame_bar_p2.position, frame_bar_p2.z_index])
	else:
		print("Error: FrameBarP2 not found in UI")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			reset_players()
		if event.keycode == KEY_M and not slowmo_triggered:
			slowmo_controller.request_slowmo_change()
			print("Debug: M key pressed, requesting slow motion change at %s ms" % Time.get_ticks_msec())

func _process(delta):
	fps_label.text = "FPS: %d" % (1.0 / delta)
	
	if animation_label:
		var p1_anim = player1.animation_state.get_current_node() if player1.animation_state else "none"
		var p2_anim = player2.animation_state.get_current_node() if player2.animation_state else "none"
		animation_label.text = "P1: %s, P2: %s" % [p1_anim, p2_anim]
	
	# 修改：檢查玩家血量並觸發音樂淡出
	if not slowmo_triggered and not is_fading_out:
		if (player1.healthbar and player1.healthbar.current_health <= 0) or \
		   (player2.healthbar and player2.healthbar.current_health <= 0):
			slowmo_triggered = true
			if bgm_player:
				var tween = create_tween()
				tween.tween_property(bgm_player, "volume_db", -80.0, 2.0) # 2秒淡出到無聲
				tween.tween_callback(bgm_player.stop) # 淡出後停止播放
				tween.play()
				is_fading_out = true
				print("Debug: BGM fade-out started at %s ms due to player health <= 0" % Time.get_ticks_msec())
			slowmo_controller.request_slowmo_change()
			print("Debug: Slow motion triggered due to player health <= 0 at %s ms" % Time.get_ticks_msec())

func _physics_process(delta):
	if combo_reset_timer > 0:
		combo_reset_timer -= delta
		if combo_reset_timer <= 0:
			reset_combo()
	
	if attacker and target_player and not advantage_calculated:
		if attacker_recover_time == 0.0:
			var move_set = attacker.get_node_or_null("MoveSet")
			var animation_player = attacker.get_node_or_null("AnimationPlayer")
			var is_recovered = not attacker.is_attacking
			if move_set:
				is_recovered = is_recovered and not (move_set.is_special_moving or move_set.is_spmove)
			if animation_player and animation_player.is_playing():
				var current_anim = animation_player.current_animation
				if current_anim in ["powerkk", "spnk", "fireball"]:
					is_recovered = false
			if is_recovered:
				attacker_recover_time = Time.get_unix_time_from_system()
				print("Debug: Attacker %s recovered at %s" % [attacker.name, attacker_recover_time])
		
		if target_recover_time == 0.0 and not (target_player.is_hit or target_player.is_blocking):
			target_recover_time = Time.get_unix_time_from_system()
			print("Debug: Target %s recovered at %s" % [target_player.name, target_recover_time])
		
		if attacker_recover_time > 0 and target_recover_time > 0:
			var advantage_time = (target_recover_time - hit_time) - (attacker_recover_time - hit_time)
			var advantage_frames = int(advantage_time * TICKS_PER_SECOND)
			if attacker == player1:
				p1_advantage_label.text = "P1 Adv: " + ("+" if advantage_frames > 0 else "") + str(advantage_frames)
				p2_advantage_label.text = "P2 Adv: " + ("+" if -advantage_frames > 0 else "") + str(-advantage_frames)
			else:
				p1_advantage_label.text = "P1 Adv: " + ("+" if -advantage_frames > 0 else "") + str(-advantage_frames)
				p2_advantage_label.text = "P2 Adv: " + ("+" if advantage_frames > 0 else "") + str(advantage_frames)
			print("Debug: Advantage frames: %d (time diff: %.4f)" % [advantage_frames, advantage_time])
			advantage_calculated = true

func to_scaled_vector2(vector: Vector2i) -> Vector2:
	return Vector2(
		float(vector.x) / SIMULATION_SCALE,
		float(vector.y) / SIMULATION_SCALE
	)

func reset_player_animation(player: Node, target_state: String) -> void:
	var animation_tree = player.get_node_or_null("AnimationTree")
	var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
	var animation_player = player.get_node_or_null("AnimationPlayer")
	var move_set = player.get_node_or_null("MoveSet")
	var player_id = player.player_id if "player_id" in player else "p1"

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
		"powerkk": target_state == "powerkk" and player_id == "p1" and move_set and move_set.is_powerkk,
		"spnk": target_state == "spnk" and player_id == "p2" and move_set and move_set.is_spnk,
		"landing": target_state == "landing"
	}
	for condition in conditions:
		animation_tree.set("parameters/conditions/" + condition, conditions[condition])
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", 0.0)
	
	animation_tree.active = true
	animation_state.travel(target_state)
	print("Debug: %s animation reset to %s at %s ms" % [player.name, target_state, Time.get_ticks_msec()])

func reset_players():
	player1.global_position = initial_p1_pos
	player2.global_position = initial_p2_pos
	player1.fixed_position = Vector2i(int(initial_p1_pos.x * SIMULATION_SCALE), FLOOR_Y)
	player2.fixed_position = Vector2i(int(initial_p2_pos.x * SIMULATION_SCALE), FLOOR_Y)
	player1.global_position = to_scaled_vector2(player1.fixed_position)
	player2.global_position = to_scaled_vector2(player2.fixed_position)
	
	for player in [player1, player2]:
		if player.healthbar:
			player.healthbar.current_health = 100.0
			if player.healthbar is ProgressBar:
				player.healthbar.value = 100.0
			else:
				player.healthbar.set("value", 100.0)
			print("Debug: %s health reset to 100.0 at %s ms" % [player.name, Time.get_ticks_msec()])
	
	for player in [player1, player2]:
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
		player.dash_timer = 0.0
		player.velocity = Vector2.ZERO
		player.current_mode = "ground_stand"
		player.attack_type = "none"
		player.update_facing_direction()
	
	for player in [player1, player2]:
		if player.has_node("MoveSet"):
			player.get_node("MoveSet").stop_special_move()
	
	for player in [player1, player2]:
		reset_player_animation(player, "Walk")
	
	for player in [player1, player2]:
		if player.has_node("AIBehavior"):
			player.get_node("AIBehavior").current_state = "idle"
			player.get_node("AIBehavior").state_timer = 0.0
			player.get_node("AIBehavior").last_action_time = 0.0
	
	if slowmo_controller:
		slowmo_controller.exit_slowmo_animation()
		slowmo_controller.is_hit_slowmo = false
		slowmo_triggered = false
		Engine.time_scale = slowmo_controller.normal_time_scale
		print("Debug: Slow motion and hit slowmo states reset, time_scale=%s at %s ms" % [Engine.time_scale, Time.get_ticks_msec()])
	
	# 新增：重置背景音樂
	if bgm_player:
		bgm_player.volume_db = -80.0
		bgm_player.play()
		var tween = create_tween()
		tween.tween_property(bgm_player, "volume_db", 0.0, 3.0)
		tween.play()
		is_fading_out = false
		print("Debug: BGM reset and fade-in started at %s ms" % Time.get_ticks_msec())
	
	if animation_label:
		animation_label.text = "P1: Walk, P2: Walk"
	
	reset_combo()
	
	if debug_label:
		debug_label.text = ""
	
	hit_time = 0.0
	attacker = null
	target_player = null
	attacker_recover_time = 0.0
	target_recover_time = 0.0
	advantage_calculated = false
	if p1_advantage_label:
		p1_advantage_label.text = "P1 Adv: 0"
	if p2_advantage_label:
		p2_advantage_label.text = "P2 Adv: 0"
	
	if frame_bar_p1:
		frame_bar_p1.reset_frame_bar()
	if frame_bar_p2:
		frame_bar_p2.reset_frame_bar()
	
	print("Debug: Players reset! Positions, health, animations, frame bars, and slow motion restored at %s ms" % Time.get_ticks_msec())

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	var hit_time_ms = Time.get_ticks_msec()
	if not is_blocked:
		hit_label.text = "Hits: " + target + " was hit!"
		print("Debug: %s was hit at %s ms, updating HitLabel, stun_duration=%s" % [target, hit_time_ms, stun_duration])
		
		if was_in_stun and combo_target == target and current_combo > 0:
			current_combo += 1
		else:
			current_combo = 1
			combo_target = target
		combo_reset_timer = stun_duration + COMBO_BUFFER
		update_combo_label()
	else:
		hit_label.text = target + " blocked! Stun: " + str(stun_duration)
		print("Debug: %s blocked at %s ms with stun duration %s, updating HitLabel" % [target, hit_time_ms, stun_duration])
		reset_combo()
	
	hit_time = Time.get_unix_time_from_system()
	attacker = player1 if target == "Player2" else player2
	target_player = player2 if target == "Player2" else player1
	attacker_recover_time = 0.0
	target_recover_time = 0.0
	advantage_calculated = false
	print("Debug: Hit detected at %s ms, attacker=%s, target=%s, requesting slowmo" % [hit_time_ms, attacker.name, target_player.name])

func _on_block_detected(target: String, block_type: String):
	var block_time_ms = Time.get_ticks_msec()
	if block_type == "proximity":
		hit_label.text = target + " blocked (proximity)!"
		print("Debug: %s triggered proximity block at %s ms, updating HitLabel" % [target, block_time_ms])
	reset_combo()

func update_combo_label():
	if current_combo >= 2:
		combo_label.text = str(current_combo) + " Hit !"
	else:
		combo_label.text = ""

func reset_combo():
	current_combo = 0
	combo_target = ""
	update_combo_label()
