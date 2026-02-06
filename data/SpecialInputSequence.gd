# res://data/SpecialInputSequence.gd
class_name SpecialInputSequence extends Resource

@export var sequence_id: String = ""  # Should match special move id
@export var valid_inputs: Array = []  # Array[Array[Dictionary]]
@export var input_buffer: int = 10
@export var max_total_frames: int = 120
@export var absolute_direction: bool = false
