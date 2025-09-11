extends Node2D

@onready var hit_label = $HitLabel
@onready var fps_label = $FPS
@onready var davis = $Davis
@onready var dennis = $Dennis

func _ready():
	davis.hit_detected.connect(_on_hit_detected)
	dennis.hit_detected.connect(_on_hit_detected)
	davis.block_detected.connect(_on_block_detected)
	dennis.block_detected.connect(_on_block_detected)
	if not davis or not dennis:
		print("Warning: Davis or Dennis node not found in world")

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

func _process(delta):
	fps_label.text = "FPS: %d" % (1.0 / delta)
