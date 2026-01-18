# res://scripts/combat/base/SpecialMoveBase.gd
class_name SpecialMoveBase extends Node

@export var move_id: String = "powerkk"
@export var character_requirement: String = "*"  # "DAV"、"DEN" 或 "*"（所有角色）
@export var animation_name: String = ""
@export var damage: float = 12.0
@export var duration_seconds: float = 0.933
@export var move_distance: float = 300.0          # 前衝距離（像素）
@export var has_jump: bool = false
@export var jump_delay_seconds: float = 0.0
@export var jump_vertical_speed: float = 0.0
@export var freeze_time: float = 0.0              # 畫面凍結時間（超必殺用）
@export var is_projectile: bool = false
@export var projectile_scene: PackedScene         # 火球專用

var is_executing: bool = false
var timer: float = 0.0
var jump_timer: float = 0.0
var parent_player: Player

func _ready() -> void:
	parent_player = get_parent() as Player
	if not parent_player:
		push_error("SpecialMoveBase 必須作為 Player 的子節點！")
	if animation_name.is_empty():
		animation_name = move_id

func can_execute() -> bool:
	return not is_executing and not parent_player.is_attacking and not parent_player.get_node("MoveSet").is_spmove

func execute() -> void:
	if is_executing or not can_execute():
		return
	is_executing = true
	timer = duration_seconds
	jump_timer = jump_delay_seconds
	parent_player.is_attacking = true
	parent_player.attack_type = move_id
	parent_player.current_damage = damage
	
	# Use the new MoveSet API to start the special move
	var move_set = parent_player.get_node("MoveSet")
	# Instead of directly setting is_spmove, we call the appropriate start function
	if move_id == "powerkk":
		move_set.start_powerkk()
	elif move_id == "spnk":
		move_set.start_spnk()
	elif move_id == "super":
		move_set.start_super()
	elif move_id == "dp":
		move_set.start_dp()
	elif move_id == "hdk":
		move_set.start_hdk()
	elif move_id == "fireball":
		move_set.start_fireball()
	else:
		push_error("Unknown move_id: %s" % move_id)
		return
	
	# Freeze if needed
	if freeze_time > 0:
		var tween = create_tween().set_ignore_time_scale(true)
		Engine.time_scale = 0.0
		tween.tween_interval(freeze_time)
		tween.tween_property(Engine, "time_scale", 1.0, 0.1)
	
	print("[SpecialMoveBase] 執行特殊招：", move_id)

func update(delta: float) -> void:
	if not is_executing:
		return
	
	timer -= delta
	if has_jump:
		jump_timer -= delta
		if jump_timer <= 0 and jump_timer > -delta and not parent_player.is_jumping:
			var world = get_tree().get_first_node_in_group("world")
			parent_player.fixed_velocity.y = int(jump_vertical_speed * world.SIMULATION_SCALE)
			parent_player.is_jumping = true
			parent_player.fixed_position.y = world.FLOOR_Y - 1
	
	if timer <= 0:
		finish_move()

func finish_move() -> void:
	is_executing = false
	parent_player.is_attacking = false
	parent_player.attack_type = "none"
	parent_player.fixed_velocity.x = 0
	parent_player.get_node("MoveSet").stop_special_move()
	parent_player.force_update_facing_direction()

# 火球專用生成（子類可呼叫）
func spawn_projectile() -> void:
	if not is_projectile or not projectile_scene:
		return
	var world = get_tree().get_first_node_in_group("world")
	var fb = projectile_scene.instantiate()
	fb.direction = parent_player.facing_direction
	fb.global_position = parent_player.global_position + Vector2(40 * parent_player.facing_direction, -40)
	get_tree().current_scene.add_child(fb)
