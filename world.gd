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

func _on_hit_detected(target: String):
	if not get_node(target).is_blocking:  # 僅在未格擋時顯示被擊中
		hit_label.text = "Hits: " + target + " was hit!"
		print("Debug: %s was hit, updating HitLabel" % target)

func _on_block_detected(target: String):
	hit_label.text = target + " blocked!"
	print("Debug: %s blocked, updating HitLabel" % target)

func _process(delta):
	fps_label.text = "FPS: %d" % (1.0 / delta)
