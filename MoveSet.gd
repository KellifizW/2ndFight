# filename: MoveSet.gd
class_name MoveSet extends Node

# 招式相關變數
var is_powerkk: bool = false
var is_spnk: bool = false
var powerkk_time: float = 0.933
var spnk_time: float = 1.2
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var powerkk_damage: float = 20.0
var spnk_damage: float = 20.0
var powerkk_move_distance: float = 70.0  # powerkk 總移動距離
var spnk_move_distance: float = 60.0     # spnk 總移動距離
@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if not is_valid_state:
		return false
	
	var player_id = parent.player_id if "player_id" in parent else "p1"
	
	if input_data.spm1_pressed:
		if player_id == "p1" and not is_powerkk:
			is_powerkk = true
			powerkk_timer = powerkk_time
			parent.current_damage = powerkk_damage
			parent.velocity.x = 0
			parent.update_facing_direction()
			animation_player.play("powerkk")
			hitbox.disabled = false
			print("Debug: Powerkk triggered for %s, current_damage set to %s" % [parent.name, powerkk_damage])
			return true
		elif player_id == "p2" and not is_spnk:
			is_spnk = true
			spnk_timer = spnk_time
			parent.current_damage = spnk_damage
			parent.velocity.x = 0
			parent.update_facing_direction()
			animation_player.play("spnk")
			hitbox.disabled = false
			print("Debug: Spnk triggered for %s, current_damage set to %s" % [parent.name, spnk_damage])
			return true
	
	if is_powerkk:
		parent.velocity.x = 0
		var move_speed = (powerkk_move_distance / powerkk_time) * parent.facing_direction
		parent.global_position.x += move_speed * delta
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			is_powerkk = false
			hitbox.disabled = true
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
			parent.update_facing_direction()
			print("Debug: Powerkk ended for %s, final position: %s, facing_direction=%s" % [parent.name, parent.global_position, parent.facing_direction])
		return true

	if is_spnk:
		parent.velocity.x = 0
		var move_speed = (spnk_move_distance / spnk_time) * parent.facing_direction
		parent.global_position.x += move_speed * delta
		spnk_timer -= delta
		print("Debug: Spnk active, facing_direction=%s, sprite.scale.x=%s, parent.scale.x=%s" % [parent.facing_direction, sprite.scale.x, parent.scale.x])
		if spnk_timer <= 0:
			is_spnk = false
			hitbox.disabled = true
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
			parent.update_facing_direction()
			print("Debug: Spnk ended, sprite.scale.x=%s, facing_direction=%s, parent.scale.x=%s" % [sprite.scale.x, parent.facing_direction, parent.scale.x])
		return true
	
	return false

func get_special_damage() -> float:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p1" and is_powerkk:
		return powerkk_damage
	elif player_id == "p2" and is_spnk:
		return spnk_damage
	return 0.0
