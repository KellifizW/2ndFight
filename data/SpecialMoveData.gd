# res://data/SpecialMoveData.gd
class_name SpecialMoveData extends Resource

# Core identifiers
@export var move_id: String = ""
@export var character_requirement: String = "*"  # "DAV", "DEN", or "*"

# Combat stats (frame-based at 60 FPS)
@export var damage: float = 0.0
@export var knockback: float = 0.0
@export var hitstun_frames: int = 18
@export var blockstun_frames: int = 10

# Timing and movement (frame-based at 60 FPS)
@export var duration_frames: int = 0
@export var move_distance: float = 0.0
@export var jump_delay_frames: int = 0
@export var jump_speed: float = 0.0

# Special behavior
@export var is_freeze: bool = false
@export var is_projectile: bool = false
@export var gravity: float = 0.0
@export var sound_type: String = "special"  # "special" or "fireball"
@export var penetrable: bool = false

# Acceleration curve
@export var acceleration_curve: String = "none"  # "none", "decelerate", "accelerate", "three_phase"
@export var stationary_ratio: float = 0.0
@export var acceleration_ratio: float = 0.0
@export var deceleration_ratio: float = 0.0

# Knockfly parameters
@export var knockfly_gravity: float = 0.0
@export var knockfly_vertical_speed: float = 0.0
@export var knockfly_horizontal_speed: float = 0.0

# Projectile parameters
@export var projectile_speed: float = 0.0
