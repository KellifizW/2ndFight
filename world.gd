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

var initial_p1_pos: Vector2
var initial_p2_pos: Vector2
var slowmo_triggered: bool = false
var current_combo: int = 0
var combo_target: String = ""
var combo_reset_timer: float = 0.0
const COMBO_BUFFER: float = 0.2

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
	
	initial_p1_pos = Vector2(190.0, float(FLOOR_Y) / SIMULATION_SCALE)
	initial_p2_pos = Vector2(290.0, float(FLOOR_Y) / SIMULATION_SCALE)
	player1.fixed_position = Vector2i(int(190.0 * SIMULATION_SCALE), FLOOR_Y)
	player2.fixed_position = Vector2i(int(290.0 * SIMULATION_SCALE), FLOOR_Y)
	player1.global_position = to_scaled_vector2(player1.fixed_position)
	player2.global_position = to_scaled_vector2(player2.fixed_position)
	print("Debug: Initial positions set - P1: %s, P2: %s" % [player1.global_position, player2.global_position])

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			reset_players()
		if event.keycode == KEY_M and not slowmo_triggered:
			slowmo_controller.request_slowmo_change()
			print("Debug: M key pressed, requesting slow motion change")

func _process(delta):
	fps_label.text = "FPS: %d" % (1.0 / delta)
	
	if animation_label:
		var p1_anim = player1.animation_state.get_current_node() if player1.animation_state else "none"
		var p2_anim = player2.animation_state.get_current_node() if player2.animation_state else "none"
		animation_label.text = "P1: %s, P2: %s" % [p1_anim, p2_anim]
	
	if not slowmo_triggered:
		if (player1.healthbar and player1.healthbar.current_health <= 0) or \
		   (player2.healthbar and player2.healthbar.current_health <= 0):
			slowmo_controller.request_slowmo_change()
			slowmo_triggered = true
			print("Debug: Slow motion triggered due to player health <= 0")

func _physics_process(delta):
	if combo_reset_timer > 0:
		combo_reset_timer -= delta
		if combo_reset_timer <= 0:
			reset_combo()

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
	print("Debug: %s AnimationPlayer stopped and queue cleared" % player.name)
	
	animation_tree.active = false
	
	var conditions = {
		"Walk": target_state == "Walk",
		"Crouch": target_state == "Crouch",
		"Dash": false,
		"Backdash": false,
		"St_mp": target_state == "St_mp",
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
	print("Debug: %s animation reset to %s" % [player.name, target_state])

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
			print("Debug: %s health reset to 100.0" % player.name)
	
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
		print("Debug: Slow motion and hit slowmo states reset, time_scale=%s" % Engine.time_scale)
	
	if animation_label:
		animation_label.text = "P1: Walk, P2: Walk"
	
	reset_combo()
	
	if debug_label:
		debug_label.text = ""
	
	print("Debug: Players reset! Positions, health, animations, and slow motion restored.")

func _on_hit_detected(target: String, stun_duration: float, is_blocked: bool, was_in_stun: bool):
	if not is_blocked:
		hit_label.text = "Hits: " + target + " was hit!"
		print("Debug: %s was hit, updating HitLabel" % target)
		
		if was_in_stun and combo_target == target and current_combo > 0:
			current_combo += 1
		else:
			current_combo = 1
			combo_target = target
		combo_reset_timer = stun_duration + COMBO_BUFFER
		update_combo_label()
	else:
		hit_label.text = target + " blocked! Stun: " + str(stun_duration)
		print("Debug: %s blocked with stun duration %s, updating HitLabel" % [target, stun_duration])
		reset_combo()

func _on_block_detected(target: String, block_type: String):
	if block_type == "proximity":
		hit_label.text = target + " blocked (proximity)!"
		print("Debug: %s triggered proximity block, updating HitLabel" % target)
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
