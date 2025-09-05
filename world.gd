extends Node2D

@onready var hit_label = $HitLabel
@onready var fps_label = $FPS
@onready var davis = $Davis
@onready var dennis = $Dennis

func _ready():
	davis.hit_detected.connect(_on_hit_detected)
	dennis.hit_detected.connect(_on_hit_detected)

func _on_hit_detected(target: String):
	hit_label.text = "Hits: " + target + " was hit!"

func _process(delta):
	fps_label.text = "FPS: %d" % (1.0 / delta)
