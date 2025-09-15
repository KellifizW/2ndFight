extends Node2D

@onready var hit_label = $HitLabel
@onready var fps_label = $FPS
@onready var player1 = $Player1
@onready var player2 = $Player2

func _ready():
	player1.hit_detected.connect(_on_hit_detected)
	player2.hit_detected.connect(_on_hit_detected)
	player1.block_detected.connect(_on_block_detected)
	player2.block_detected.connect(_on_block_detected)
	if not player1 or not player2:
		print("Warning: Player1 or Player2 node not found in world")

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
