# res://data/SpecialMoveData.gd
class_name SpecialMoveData extends Resource

# Move identification
@export var move_name: String = "powerkk"
@export var character_requirement: String = "DAV"  # "DAV", "DEN", or "*"

# Core properties
@export var damage: float = 12.0
@export var knockback: float = 300.0
@export var duration: float = 0.933
@export var move_distance: float = 300.0

# Jump properties
@export var jump_delay: float = 0.0
@export var jump_speed: float = 0.0

# Special effects
@export var is_freeze: bool = false
@export var freeze_duration: float = 0.3
@export var is_projectile: bool = false
@export var gravity: float = 0.0
@export var penetrable: bool = false

# Sound
@export var sound_type: String = "special"  # "special" or "fireball"

# Knockfly properties (for moves like DP)
@export var knockfly_gravity: float = 0.0
@export var knockfly_vertical_speed: float = 0.0
@export var knockfly_horizontal_speed: float = 0.0

# Constructor for programmatic creation
func _init(p_move_name = "powerkk", p_character = "DAV", p_damage = 12.0, p_knockback = 300.0, 
	p_duration = 0.933, p_move_distance = 300.0, p_jump_delay = 0.0, p_jump_speed = 0.0,
	p_is_freeze = false, p_freeze_duration = 0.3, p_is_projectile = false, p_gravity = 0.0,
	p_penetrable = false, p_sound_type = "special", p_knockfly_gravity = 0.0, 
	p_knockfly_vertical_speed = 0.0, p_knockfly_horizontal_speed = 0.0) -> void:
	move_name = p_move_name
	character_requirement = p_character
	damage = p_damage
	knockback = p_knockback
	duration = p_duration
	move_distance = p_move_distance
	jump_delay = p_jump_delay
	jump_speed = p_jump_speed
	is_freeze = p_is_freeze
	freeze_duration = p_freeze_duration
	is_projectile = p_is_projectile
	gravity = p_gravity
	penetrable = p_penetrable
	sound_type = p_sound_type
	knockfly_gravity = p_knockfly_gravity
	knockfly_vertical_speed = p_knockfly_vertical_speed
	knockfly_horizontal_speed = p_knockfly_horizontal_speed
func to_dict() -> Dictionary:
	return {
		"name": move_name,
		"character_requirement": character_requirement,
		"damage": damage,
		"knockback": knockback,
		"duration": duration,
		"move_distance": move_distance,
		"jump_delay": jump_delay,
		"jump_speed": jump_speed,
		"is_freeze": is_freeze,
		"freeze_duration": freeze_duration,
		"is_projectile": is_projectile,
		"gravity": gravity,
		"penetrable": penetrable,
		"sound_type": sound_type,
		"knockfly_gravity": knockfly_gravity,
		"knockfly_vertical_speed": knockfly_vertical_speed,
		"knockfly_horizontal_speed": knockfly_horizontal_speed
	}
