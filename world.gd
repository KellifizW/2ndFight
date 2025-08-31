extends Node2D

@onready var hit_label = $HitLabel

func _ready():
	$Davis.hit_detected.connect(_on_hit_detected)
	$Dennis.hit_detected.connect(_on_hit_detected)

func _on_hit_detected(target: String):
	hit_label.text = "Hits: " + target + " was hit!"
