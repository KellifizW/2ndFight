extends Node2D

@onready var hit_label = $HitLabel
@onready var fps_label = $FPS
@onready var player1 = $Player1
@onready var player2 = $Player2
@onready var slowmo_controller = $SlowMoController
@onready var animation_label = $AnimationLabel

var initial_p1_pos: Vector2
var initial_p2_pos: Vector2
var slowmo_triggered: bool = false

func _ready():
	player1.hit_detected.connect(_on_hit_detected)
	player2.hit_detected.connect(_on_hit_detected)
	player1.block_detected.connect(_on_block_detected)
	player2.block_detected.connect(_on_block_detected)
	if not player1 or not player2:
		print("Warning: Player1 or Player2 node not found in world")
	if not slowmo_controller:
		print("Warning: SlowMoController node not found in world")
	if not animation_label:
		print("Warning: AnimationLabel node not found in world")
	
	# 儲存初始位置
	initial_p1_pos = player1.global_position
	initial_p2_pos = player2.global_position
	print("Debug: Initial positions stored - P1: %s, P2: %s" % [initial_p1_pos, initial_p2_pos])

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			reset_players()
		if event.keycode == KEY_M and not slowmo_triggered:
			slowmo_controller.request_slowmo_change()
			print("Debug: M key pressed, requesting slow motion change")

func _process(delta):
	fps_label.text = "FPS: %d" % (1.0 / delta)
	
	# 更新 AnimationLabel 顯示兩個角色的當前動畫
	if animation_label:
		var p1_anim = player1.animation_state.get_current_node() if player1.animation_state else "none"
		var p2_anim = player2.animation_state.get_current_node() if player2.animation_state else "none"
		animation_label.text = "P1: %s, P2: %s" % [p1_anim, p2_anim]
	
	# 檢查玩家血量以觸發慢動作
	if not slowmo_triggered:
		if (player1.healthbar and player1.healthbar.current_health <= 0) or \
		   (player2.healthbar and player2.healthbar.current_health <= 0):
			slowmo_controller.request_slowmo_change()
			slowmo_triggered = true
			print("Debug: Slow motion triggered due to player health <= 0")

# 新增：重置玩家動畫狀態的函數
func reset_player_animation(player: Node, target_state: String) -> void:
	var animation_tree = player.get_node_or_null("AnimationTree")
	var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
	var animation_player = player.get_node_or_null("AnimationPlayer")
	var move_set = player.get_node_or_null("MoveSet")
	var player_id = player.player_id if "player_id" in player else "p1"

	if not animation_tree or not animation_state or not animation_player:
		print("Warning: AnimationTree, animation_state, or animation_player not found for %s" % player.name)
		return
	
	# 停止 AnimationPlayer 以打斷當前動畫
	animation_player.stop()
	animation_player.clear_queue()
	animation_player.speed_scale = 1.0
	print("Debug: %s AnimationPlayer stopped and queue cleared" % player.name)
	
	# 禁用 AnimationTree 以清除狀態
	animation_tree.active = false
	
	# 設置動畫條件，與 player.gd 的邏輯一致
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
	
	# 重置 Walk 的混合位置
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", 0.0)
	
	# 重新啟用 AnimationTree 並切換到目標動畫
	animation_tree.active = true
	animation_state.travel(target_state)
	print("Debug: %s animation reset to %s" % [player.name, target_state])

func reset_players():
	# 重置位置
	player1.global_position = initial_p1_pos
	player2.global_position = initial_p2_pos
	
	# 重置血量並即時更新 UI
	for player in [player1, player2]:
		if player.healthbar:
			player.healthbar.current_health = 100.0
			if player.healthbar is ProgressBar:
				player.healthbar.value = 100.0
			else:
				player.healthbar.set("value", 100.0)
			print("Debug: %s health reset to 100.0" % player.name)
	
	# 重置狀態
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
		player.is_animation_finished = false
		player.hit_timer = 0.0
		player.block_timer = 0.0
		player.knockfly_timer = 0.0
		player.attack_timer = 0.0
		player.dash_timer = 0.0
		player.velocity = Vector2.ZERO
		player.current_mode = "ground_stand"
		player.attack_type = "none"
		player.update_facing_direction()
	
	# 重置特殊招式
	for player in [player1, player2]:
		if player.has_node("MoveSet"):
			player.get_node("MoveSet").stop_special_move()
	
	# 重置動畫到 Walk
	for player in [player1, player2]:
		reset_player_animation(player, "Walk")
	
	# 重置AI行為
	for player in [player1, player2]:
		if player.has_node("AIBehavior"):
			player.get_node("AIBehavior").current_state = "idle"
			player.get_node("AIBehavior").state_timer = 0.0
			player.get_node("AIBehavior").last_action_time = 0.0
	
	# 重置慢動作
	if slowmo_controller:
		slowmo_controller.exit_slowmo_animation()
		slowmo_triggered = false
		print("Debug: Slow motion reset during player reset")
	
	# 重置 AnimationLabel
	if animation_label:
		animation_label.text = "P1: Walk, P2: Walk"
	
	print("Debug: Players reset! Positions, health, animations, and slow motion restored.")

func _on_hit_detected(target: String, blockstun_duration: float, is_blocked: bool):
	if not is_blocked:
		hit_label.text = "Hits: " + target + " was hit!"
		print("Debug: %s was hit, updating HitLabel" % target)
	else:
		hit_label.text = target + " blocked! Blockstun: " + str(blockstun_duration)
		print("Debug: %s blocked with blockstun duration %s, updating HitLabel" % [target, blockstun_duration])

func _on_block_detected(target: String, block_type: String):
	if block_type == "proximity":
		hit_label.text = target + " blocked (proximity)!"
		print("Debug: %s triggered proximity block, updating HitLabel" % target)
