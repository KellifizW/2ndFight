class_name AnimationController extends Node

# References
var movement_parent: Node
var animation_tree: AnimationTree
var animation_state: AnimationNodeStateMachinePlayback
var animation_player: AnimationPlayer
var sprite: Sprite2D
var world: Node

# Animation conditions list
var animation_conditions: Array = [
	"Walk", "cr_down", "cr_idle", "Dash", "Backdash",
	"st_mp", "st_mk", "cr_mp", "cr_mk",
	"Jump_F", "Jump_B", "Jump_V",
	"hit", "knockfly", "block", "cr_block",
	"powerkk", "spnk", "fireball",
	"jump_mp", "jump_mk", "landing", "wakeup", "super", "dp", "hdk", "layground"
]

var anim_resets: Dictionary = {}

func _ready() -> void:
	movement_parent = owner
	world = get_tree().get_first_node_in_group("world")
	
	animation_tree = get_node_or_null("../AnimationTree")
	animation_state = animation_tree.get("parameters/playback") if animation_tree else null
	sprite = get_node_or_null("../Sprite2D")
	animation_player = get_node_or_null("../AnimationPlayer")
	
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	
	if animation_player:
		animation_player.speed_scale = 1.0
		animation_player.animation_finished.connect(_on_animation_player_finished)
	
	# Setup reset functions
	anim_resets = {
		"layground": func(): _reset_layground_with_health_check(),
		"knockfly": func(): _reset_knockfly(),
		"st_mp": func(): _reset_attack()
	}

func _reset_layground() -> void:
	if "is_layground" in movement_parent:
		movement_parent.is_layground = false
	if "is_knockfly" in movement_parent:
		movement_parent.is_knockfly = false
	if "is_knockfly_animation_finished" in movement_parent:
		movement_parent.is_knockfly_animation_finished = false
	_update_animation_state(0, false)

func _reset_knockfly() -> void:
	if movement_parent.is_on_floor():
		if "fixed_velocity" in movement_parent:
			movement_parent.fixed_velocity = Vector2i.ZERO
		if "is_knockfly" in movement_parent:
			movement_parent.is_knockfly = false
		if "is_layground" in movement_parent:
			movement_parent.is_layground = true
		if "layground_timer" in movement_parent:
			movement_parent.layground_timer = movement_parent.layground_duration
		if "is_knockfly_animation_finished" in movement_parent:
			movement_parent.is_knockfly_animation_finished = false
		_update_animation_state(0, false)
	else:
		if "is_knockfly_animation_finished" in movement_parent:
			movement_parent.is_knockfly_animation_finished = true
		if animation_player:
			animation_player.stop()

func _reset_attack() -> void:
	if "is_attacking" in movement_parent:
		movement_parent.is_attacking = false
	movement_parent.update_facing_direction()
	if movement_parent.has_node("Hitbox/HitShape"):
		movement_parent.get_node("Hitbox/HitShape").disabled = true

func _reset_layground_with_health_check() -> void:
	var healthbar = movement_parent.healthbar if "healthbar" in movement_parent else null
	
	if healthbar and healthbar.current_health <= 0:
		if "is_layground" in movement_parent:
			movement_parent.is_layground = true
		if "is_knockfly" in movement_parent:
			movement_parent.is_knockfly = false
		if "is_knockfly_animation_finished" in movement_parent:
			movement_parent.is_knockfly_animation_finished = false
		return
	
	if "is_layground" in movement_parent:
		movement_parent.is_layground = false
	if "is_knockfly" in movement_parent:
		movement_parent.is_knockfly = false
	if "is_knockfly_animation_finished" in movement_parent:
		movement_parent.is_knockfly_animation_finished = false
	
	if "is_wakeup" in movement_parent:
		movement_parent.is_wakeup = true
		movement_parent.is_wakeup_locked = true
		if animation_state:
			animation_state.travel("wakeup")
	
	_update_animation_state(0, false)

func _on_animation_player_finished(anim_name: String) -> void:
	if anim_name in anim_resets:
		anim_resets[anim_name].call()
	if anim_name == "cr_down":
		if "is_crouch_transition_played" in movement_parent:
			movement_parent.is_crouch_transition_played = true
		if animation_state:
			animation_state.travel("cr_idle")

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	if not animation_tree:
		return
	
	for c in animation_conditions:
		var condition_value: bool = (target_state == c)
		if c == "Walk":
			condition_value = condition_value and on_floor and not crouch_input
		elif c == "cr_block":
			condition_value = condition_value and ("is_crouch_blocking" in movement_parent and movement_parent.is_crouch_blocking) and crouch_input
		animation_tree.set("parameters/conditions/" + c, condition_value)

func _compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	if "is_layground" in movement_parent and movement_parent.is_layground:
		return "layground"
	if "is_knockfly" in movement_parent and movement_parent.is_knockfly:
		return "knockfly"
	if "is_wakeup_locked" in movement_parent and movement_parent.is_wakeup_locked:
		return "wakeup"
	if "is_hit" in movement_parent and movement_parent.is_hit:
		if not on_floor and ("is_air_hit_backjump" in movement_parent and movement_parent.is_air_hit_backjump):
			return "Jump_B"
		return "hit" if on_floor else "Jump_B"

	var move_set = movement_parent.get_node_or_null("MoveSet")
	
	if move_set and move_set.is_spmove:
		if move_set.is_super: return "super"
		elif move_set.is_hdk: return "hdk"
		elif move_set.is_powerkk and "character_id" in movement_parent and movement_parent.character_id == "DAV": return "powerkk"
		elif move_set.is_spnk and "character_id" in movement_parent and movement_parent.character_id == "DEN": return "spnk"
		elif move_set.is_dp and "character_id" in movement_parent and movement_parent.character_id == "DAV": return "dp"
		elif move_set.is_fireball: return "fireball"
	
	if "is_proximity_blocking" in movement_parent and movement_parent.is_proximity_blocking:
		return "cr_block" if ("is_crouching" in movement_parent and movement_parent.is_crouching) else "block"
	if "is_blocking" in movement_parent and movement_parent.is_blocking:
		return "cr_block" if ("is_crouch_blocking" in movement_parent and movement_parent.is_crouch_blocking and crouch_input) else "block"
	
	if "is_attacking" in movement_parent and movement_parent.is_attacking:
		var atype = movement_parent.attack_type if "attack_type" in movement_parent else "none"
		if atype in ["st_mp", "st_mk", "cr_mp", "cr_mk", "super", "dp", "powerkk", "spnk", "fireball", "hdk"]:
			return atype
		return "Walk"
	
	if "is_dashing" in movement_parent and movement_parent.is_dashing:
		return "Dash"
	if "is_backdashing" in movement_parent and movement_parent.is_backdashing:
		return "Backdash"
	
	if crouch_input and on_floor and not ("is_blocking" in movement_parent and movement_parent.is_blocking):
		if "was_crouching_last_frame" in movement_parent and not movement_parent.was_crouching_last_frame:
			if animation_state:
				animation_state.call_deferred("travel", "cr_down")
		return "cr_idle"
	
	if not on_floor and ("is_jumping" in movement_parent and movement_parent.is_jumping or ("is_air_attacking" in movement_parent and movement_parent.is_air_attacking)):
		if "is_air_attacking" in movement_parent and (movement_parent.is_air_attacking or ("has_air_attacked" in movement_parent and movement_parent.has_air_attacked)):
			return movement_parent.attack_type if "attack_type" in movement_parent else "jump_mp"
		else:
			return "Jump_F" if anim_jump_dir > 0 else ("Jump_B" if anim_jump_dir < 0 else "Jump_V")
	
	return "Walk"

func _update_animation_state(dir_x: float, crouch_input: bool) -> void:
	if not animation_state:
		return
	
	var curr_state: String = animation_state.get_current_node() if animation_state else StringName()
	var on_floor: bool = movement_parent.is_on_floor()
	var anim_dir: float = dir_x * (movement_parent.facing_direction if "facing_direction" in movement_parent else 1.0)
	var jump_dir = movement_parent.jump_dir if "jump_dir" in movement_parent else 0
	var anim_jump_dir: float = jump_dir * (movement_parent.facing_direction if "facing_direction" in movement_parent else 1.0)
	var target_state: String = _compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	# Health check for layground state
	var healthbar = movement_parent.healthbar if "healthbar" in movement_parent else null
	if healthbar and healthbar.current_health <= 0 and ("is_layground" in movement_parent and movement_parent.is_layground):
		target_state = "layground"
		animation_state.travel("layground")
		return
	
	if target_state == "Walk" and not on_floor and ("is_jumping" in movement_parent and movement_parent.is_jumping):
		target_state = "Jump_F" if anim_jump_dir > 0 else ("Jump_B" if anim_jump_dir < 0 else "Jump_V")
	
	_set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		var _is_knockfly_finished = ("is_knockfly_animation_finished" in movement_parent and movement_parent.is_knockfly_animation_finished)
		if not (target_state == "knockfly" and _is_knockfly_finished and not on_floor):
			animation_state.travel(target_state)
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
	if "is_jumping" in movement_parent and movement_parent.is_jumping and on_floor:
		movement_parent.is_jumping = false
