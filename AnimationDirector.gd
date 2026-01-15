class_name AnimationDirector extends Node

@onready var animation_tree: AnimationTree = get_parent().get_node("AnimationTree") if get_parent().has_node("AnimationTree") else null
@onready var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
@onready var animation_player: AnimationPlayer = get_parent().get_node("AnimationPlayer") if get_parent().has_node("AnimationPlayer") else null

# 從原版抽出的動畫條件陣列（保持一致）
var animation_conditions: Array = [
	"Walk", "cr_down", "cr_idle", "Dash", "Backdash",
	"st_mp", "st_mk", "cr_mp", "cr_mk",
	"Jump_F", "Jump_B", "Jump_V",
	"hit", "knockfly", "block", "cr_block",
	"powerkk", "spnk", "fireball",
	"jump_mp", "jump_mk", "landing", "wakeup", "super", "dp", "hdk", "layground"
]

# 信號：當動畫完成時發出，讓 Player.gd 或其他監聽
signal animation_finished(anim_name: String)

func _ready() -> void:
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	else:
		print("Error: AnimationTree not found in parent.")
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_player_finished)
	else:
		print("Error: AnimationPlayer not found in parent.")

# 主要方法：更新動畫狀態
func update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var movement = get_parent()  # Parent 是 Movement / Player
	if not movement or not animation_state:
		return
	
	var curr_state: String = animation_state.get_current_node()
	var on_floor: bool = movement.is_on_floor()
	var anim_dir: float = dir_x * movement.facing_direction
	var anim_jump_dir: float = movement.jump_dir * movement.facing_direction
	var target_state: String = _compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	# 檢查攻擊動畫是否自然結束（避免卡在攻擊狀態）
	if movement.is_attacking and (curr_state.to_lower().contains("_mp") or curr_state.to_lower().contains("_mk")):
		var position = animation_state.get_current_play_position()
		var length = animation_state.get_current_length()
		if position >= length - 0.01:
			_reset_attack()
	
	# 健康檢查（血量歸零強制 layground）
	var healthbar = get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % get_parent().name) if get_tree().get_first_node_in_group("ui") else null
	if healthbar and healthbar.current_health <= 0 and movement.is_layground:
		target_state = "layground"
		animation_state.travel("layground")
		return
	
	# 落地時額外處理跳躍動畫
	if target_state == "Walk" and not on_floor and movement.is_jumping:
		target_state = "Jump_F" if anim_jump_dir > 0 else ("Jump_B" if anim_jump_dir < 0 else "Jump_V")
	
	_set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		if not (target_state == "knockfly" and movement.is_knockfly_animation_finished and not on_floor):
			animation_state.travel(target_state)
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
	# 落地重置跳躍狀態
	if movement.is_jumping and on_floor:
		movement.is_jumping = false

# 計算目標狀態
func _compute_target_state(dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	var movement = get_parent()
	var move_set = movement.get_node("MoveSet") if movement.has_node("MoveSet") else null
	var player = get_parent()
	
	if movement.is_hit:
		return "hit" if on_floor else "Jump_B"
	if movement.is_layground: return "layground"
	if movement.is_knockfly: return "knockfly"
	if "is_wakeup_locked" in movement and movement.is_wakeup_locked: return "wakeup"
	
	if move_set and move_set.is_spmove:
		if move_set.is_super: return "super"
		elif player and move_set.is_powerkk and player.character_id == "DAV": return "powerkk"
		elif player and move_set.is_spnk and player.character_id == "DEN": return "spnk"
		elif move_set.is_hdk: return "hdk"
		elif player and move_set.is_dp and player.character_id == "DAV": return "dp"
		elif move_set.is_fireball: return "fireball"
	
	if movement.is_proximity_blocking:
		return "cr_block" if movement.is_crouching else "block"
	if movement.is_blocking:
		return "cr_block" if movement.is_crouch_blocking and crouch_input else "block"
	
	if movement.is_attacking:
		var atype = movement.get("attack_type") if "attack_type" in movement else "none"
		if atype in ["st_mp", "st_mk", "cr_mp", "cr_mk", "super", "dp", "powerkk", "spnk", "fireball", "hdk"]:
			return atype
		return "Walk"
	
	if movement.is_dashing: return "Dash"
	if movement.is_backdashing: return "Backdash"
	
	if crouch_input and on_floor and not movement.is_blocking:
		if not movement.was_crouching_last_frame:
			animation_state.call_deferred("travel", "cr_down")
		return "cr_idle"
	
	if not on_floor and (movement.is_jumping or ("is_air_attacking" in movement and movement.is_air_attacking)):
		if "is_air_attacking" in movement and (movement.is_air_attacking or ("has_air_attacked" in movement and movement.has_air_attacked)):
			return movement.get("attack_type") if "attack_type" in movement else "jump_mp"
		else:
			if anim_jump_dir > 0: return "Jump_F"
			elif anim_jump_dir < 0: return "Jump_B"
			else: return "Jump_V"
	
	return "Walk"

# 設定動畫條件
func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	var movement = get_parent()
	for c in animation_conditions:
		var condition_value: bool = (target_state == c)
		if c == "Walk":
			condition_value = condition_value and on_floor and not crouch_input
		elif c == "cr_block":
			condition_value = condition_value and movement.is_crouch_blocking and crouch_input
		animation_tree.set("parameters/conditions/" + c, condition_value)

# 動畫播放器結束時處理
func _on_animation_player_finished(anim_name: String) -> void:
	emit_signal("animation_finished", anim_name)
	var movement = get_parent()
	
	if anim_name == "cr_down":
		movement.is_crouch_transition_played = true
		animation_state.travel("cr_idle")
	
	if anim_name == "layground":
		_reset_layground_with_health_check()
	elif anim_name == "knockfly":
		_reset_knockfly()
	elif anim_name.to_lower() in ["st_mp", "st_mk", "cr_mp", "cr_mk", "super", "dp", "powerkk", "spnk", "fireball", "hdk"]:
		_reset_attack()

# 重置相關狀態
func _reset_layground_with_health_check() -> void:
	var movement = get_parent()
	var player_healthbar = movement.healthbar
	if player_healthbar and player_healthbar.current_health <= 0:
		movement.is_layground = true
		movement.is_knockfly = false
		movement.is_knockfly_animation_finished = false
		return
	
	movement.is_layground = false
	movement.is_knockfly = false
	movement.is_knockfly_animation_finished = false
	
	if "is_wakeup" in movement and "is_wakeup_locked" in movement:
		movement.is_wakeup = true
		movement.is_wakeup_locked = true
	
	animation_state.travel("wakeup")
	update_animation_state(0, false)

func _reset_knockfly() -> void:
	var movement = get_parent()
	if movement.is_on_floor():
		movement.fixed_velocity = Vector2i.ZERO
		movement.is_knockfly = false
		movement.is_layground = true
		movement.layground_timer = movement.layground_duration
		movement.is_knockfly_animation_finished = false
		update_animation_state(0, false)
	else:
		movement.is_knockfly_animation_finished = true
		if animation_player:
			animation_player.stop()

func _reset_attack() -> void:
	var movement = get_parent()
	movement.is_attacking = false
	movement.update_facing_direction()
	if movement.has_node("Hitbox/HitShape"):
		movement.get_node("Hitbox/HitShape").disabled = true
	animation_state.travel("Walk")
	update_animation_state(0, false)
