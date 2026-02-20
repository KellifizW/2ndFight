# res://data/HitPhaseData.gd
class_name HitPhaseData extends Resource

@export_group("Phase Timing")
@export var frame: int = 0  # Logic frames at 60 FPS

@export_group("Phase Combat")
@export var damage: float = 0.0
@export var hitstun: int = 0
@export var blockstun: int = 0
@export var knockback: float = 0.0

@export_group("Phase Knockfly")
@export var force_knockfly: bool = false
@export var knockfly_gravity: float = 0.0
@export var knockfly_vertical_speed: float = 0.0
@export var knockfly_horizontal_speed: float = 0.0
