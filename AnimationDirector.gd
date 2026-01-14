class_name AnimationDirector extends Node

@onready var animation_tree: AnimationTree = $"../AnimationTree"
@onready var animation_state = animation_tree.get("parameters/playback") if animation_tree else null
@onready var animation_player: AnimationPlayer = $"../AnimationPlayer" if has_node("../AnimationPlayer") else null

var animation_conditions: Array = [
	"Walk", "cr_down", "cr_idle", "Dash", "Backdash",
	"st_mp", "st_mk", "cr_mp", "cr_mk",
	"Jump_F", "Jump_B", "Jump_V",
	"hit", "knockfly", "block", "cr_block",
	"powerkk", "spnk", "fireball",
	"jump_mp", "jump_mk", "landing", "wakeup", "super", "dp", "hdk", "layground"
]

signal animation_finished(anim_name: String)

# 所有需要動畫結束時重置的動畫名稱與對應處理
var anim_resets: Dictionary = {
	"layground": func(): _reset_layground_with_health_check(),
	"knockfly": func(): _reset_knockfly(),
	"st_mp": func(): _reset_ground_attack(),
	"st_mk": func(): _reset_ground_attack(),
	"cr_mp": func(): _reset_ground_attack(),
	"cr_mk": func(): _reset_ground_attack(),
	"jump_mp": func(): _reset_air_attack(),
	"jump_mk": func(): _reset_air_attack()
}

func _ready() -> void:
	if animation_tree:
		animation_tree.active = true
		animation_state.travel("Walk")
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

func update_animation_state(dir_x: float, crouch_input: bool) -> void:
	var parent = get_parent()
	var curr_state: String = animation_state.get_current_node() if animation_state else ""
	var on_floor: bool = parent.is_on_floor() if "is_on_floor" in parent else true
	var anim_dir: float = dir_x * parent.facing_direction if "facing_direction" in parent else 0.0
	var anim_jump_dir: float = parent.jump_dir * parent.facing_direction if "jump_dir" in parent and "facing_direction" in parent else 0.0
	
	var target_state: String = _compute_target_state(dir_x, crouch_input, on_floor, anim_jump_dir)
	
	# 血量歸零特殊處理
	var healthbar = parent.healthbar if "healthbar" in parent else null
	if healthbar and healthbar.current_health <= 0 and (parent.is_layground if "is_layground" in parent else false):
		target_state = "layground"
		animation_state.travel("layground")
		return
	
	_set_animation_conditions(target_state, on_floor, crouch_input)
	
	if curr_state != target_state:
		if not (target_state == "knockfly" and (parent.is_knockfly_animation_finished if "is_knockfly_animation_finished" in parent else false) and not on_floor):
			animation_state.travel(target_state)
	
	if target_state == "Walk":
		animation_tree.set("parameters/Walk/blend_position", anim_dir)
	
	if (parent.is_jumping if "is_jumping" in parent else false) and on_floor:
		parent.is_jumping = false

func _compute_target_state(_dir_x: float, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	var parent = get_parent()
	
	if parent.is_hit if "is_hit" in parent else false:
		return "hit" if on_floor else "Jump_B"
	
	var move_set = parent.get_node_or_null("MoveSet")
	if parent.is_layground if "is_layground" in parent else false: return "layground"
	if parent.is_knockfly if "is_knockfly" in parent else false: return "knockfly"
	if "is_wakeup_locked" in parent and parent.is_wakeup_locked: return "wakeup"
	
	if move_set and move_set.is_spmove:
		if move_set.is_super: return "super"
		elif parent.character_id == "DAV" and move_set.is_powerkk: return "powerkk"
		elif parent.character_id == "DEN" and move_set.is_spnk: return "spnk"
		elif move_set.is_hdk: return "hdk"
		elif parent.character_id == "DAV" and move_set.is_dp: return "dp"
		elif move_set.is_fireball: return "fireball"
	
	if parent.is_proximity_blocking if "is_proximity_blocking" in parent else false:
		return "cr_block" if parent.is_crouching if "is_crouching" in parent else false else "block"
	if parent.is_blocking if "is_blocking" in parent else false:
		return "cr_block" if parent.is_crouch_blocking if "is_crouch_blocking" in parent else false and crouch_input else "block"
	
	if parent.is_attacking if "is_attacking" in parent else false:
		var atype = parent.attack_type if "attack_type" in parent else "none"
		if atype in ["st_mp", "st_mk", "cr_mp", "cr_mk", "super", "dp", "powerkk", "spnk", "fireball", "hdk"]:
			return atype
		return "Walk"
	
	if parent.is_dashing if "is_dashing" in parent else false: return "Dash"
	if parent.is_backdashing if "is_backdashing" in parent else false: return "Backdash"
	
	if crouch_input and on_floor and not (parent.is_blocking if "is_blocking" in parent else false):
		if not (parent.was_crouching_last_frame if "was_crouching_last_frame" in parent else false):
			animation_state.call_deferred("travel", "cr_down")
		return "cr_idle"
	
	if not on_floor and ((parent.is_jumping if "is_jumping" in parent else false) or (parent.is_air_attacking if "is_air_attacking" in parent else false)):
		if (parent.is_air_attacking if "is_air_attacking" in parent else false) and ((parent.has_air_attacked if "has_air_attacked" in parent else false) or parent.is_air_attacking):
			return parent.attack_type if "attack_type" in parent else "jump_mp"
		else:
			if anim_jump_dir > 0: return "Jump_F"
			elif anim_jump_dir < 0: return "Jump_B"
			else: return "Jump_V"
	
	return "Walk"

func _set_animation_conditions(target_state: String, on_floor: bool, crouch_input: bool) -> void:
	var parent = get_parent()
	for c in animation_conditions:
		var condition_value: bool = (target_state == c)
		if c == "Walk":
			condition_value = condition_value and on_floor and not crouch_input
		elif c == "cr_block":
			condition_value = condition_value and (parent.is_crouch_blocking if "is_crouch_blocking" in parent else false) and crouch_input
		animation_tree.set("parameters/conditions/" + c, condition_value)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name in anim_resets:
		anim_resets[anim_name].call()
	emit_signal("animation_finished", anim_name)
	if anim_name == "cr_down":
		get_parent().is_crouch_transition_played = true if "is_crouch_transition_played" in get_parent() else false
		animation_state.travel("cr_idle")

# 重置地面攻擊狀態
func _reset_ground_attack() -> void:
	var parent = get_parent()
	parent.is_attacking = false if "is_attacking" in parent else false
	if "update_facing_direction" in parent:
		parent.update_facing_direction()
	if parent.has_node("Hitbox/HitShape"):
		parent.get_node("Hitbox/HitShape").disabled = true
	update_animation_state(0, false)  # 強制切回 Walk

# 重置空中攻擊狀態（解決跳攻卡幀或無法播放）
func _reset_air_attack() -> void:
	var parent = get_parent()
	if "is_air_attacking" in parent:
		parent.is_air_attacking = false
	if "has_air_attacked" in parent:
		parent.has_air_attacked = false
	if "update_facing_direction" in parent:
		parent.update_facing_direction()
	update_animation_state(0, false)  # 強制切回 Jump_V 或 Walk

# 躺地重置
func _reset_layground_with_health_check() -> void:
	var parent = get_parent()
	print("Debug: layground reset triggered for %s. Checking health before wakeup transition." % parent.name)
	var player_healthbar = parent.healthbar if "healthbar" in parent else null
	if player_healthbar and player_healthbar.current_health <= 0:
		print("Debug: %s 血量已歸零，保持躺地狀態，不觸發 wakeup。" % parent.name)
		parent.is_layground = true if "is_layground" in parent else false
		parent.is_knockfly = false if "is_knockfly" in parent else false
		parent.is_knockfly_animation_finished = false if "is_knockfly_animation_finished" in parent else false
		return
	
	print("Debug: %s 血量仍有剩餘，允許 wakeup。" % parent.name)
	parent.is_layground = false if "is_layground" in parent else false
	parent.is_knockfly = false if "is_knockfly" in parent else false
	parent.is_knockfly_animation_finished = false if "is_knockfly_animation_finished" in parent else false
	
	if "is_wakeup" in parent and "is_wakeup_locked" in parent:
		parent.is_wakeup = true
		parent.is_wakeup_locked = true
		animation_state.travel("wakeup")
	
	update_animation_state(0, false)

# 擊飛重置
func _reset_knockfly() -> void:
	var parent = get_parent()
	if parent.is_on_floor() if "is_on_floor" in parent else false:
		parent.fixed_velocity = Vector2i.ZERO if "fixed_velocity" in parent else Vector2i.ZERO
		parent.is_knockfly = false if "is_knockfly" in parent else false
		parent.is_layground = true if "is_layground" in parent else false
		parent.layground_timer = parent.layground_duration if "layground_timer" in parent and "layground_duration" in parent else 0.2
		parent.is_knockfly_animation_finished = false if "is_knockfly_animation_finished" in parent else false
		update_animation_state(0, false)
	else:
		parent.is_knockfly_animation_finished = true if "is_knockfly_animation_finished" in parent else false
		if animation_player:
			animation_player.stop()
