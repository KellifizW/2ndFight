extends Node2D

@onready var hit_label = $HitLabel
@onready var davis = $Davis
@onready var dennis = $Dennis

func _ready():
	davis.hit_detected.connect(_on_hit_detected)
	dennis.hit_detected.connect(_on_hit_detected)

func _physics_process(delta):
	var viewport_width = get_viewport_rect().size.x  # 獲取畫面寬度

	# 檢查 Davis 的邊界
	var davis_collider = davis.get_node("CollisionShape2D")
	var davis_width = davis_collider.shape.extents.x * 2 if davis_collider else 32
	if davis.position.x < davis_width / 2:
		davis.position.x = davis_width / 2
		if davis.velocity.x < 0:  # 只在向左移動時清 velocity，避免影響互推
			davis.velocity.x = 0
	elif davis.position.x > viewport_width - davis_width / 2:
		davis.position.x = viewport_width - davis_width / 2
		if davis.velocity.x > 0:  # 只在向右移動時清
			davis.velocity.x = 0

	# 檢查 Dennis 的邊界
	var dennis_collider = dennis.get_node("CollisionShape2D")
	var dennis_width = dennis_collider.shape.extents.x * 2 if dennis_collider else 32
	if dennis.position.x < dennis_width / 2:
		dennis.position.x = dennis_width / 2
		if dennis.velocity.x < 0:
			dennis.velocity.x = 0
	elif dennis.position.x > viewport_width - dennis_width / 2:
		dennis.position.x = viewport_width - dennis_width / 2
		if dennis.velocity.x > 0:
			dennis.velocity.x = 0

func _on_hit_detected(target: String):
	hit_label.text = "Hits: " + target + " was hit!"
