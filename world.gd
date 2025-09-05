extends Node2D

@onready var hit_label = $HitLabel
@onready var FPS = $FPS
@onready var davis = $Davis
@onready var dennis = $Dennis

func _ready():
	davis.hit_detected.connect(_on_hit_detected)
	dennis.hit_detected.connect(_on_hit_detected)

func _physics_process(delta):
	var viewport_width = ProjectSettings.get_setting("display/window/size/viewport_width")  # 獲取邏輯寬度 320

	# 檢查 Davis 的邊界
	var davis_collision = davis.get_node("CollisionShape2D").shape as RectangleShape2D
	var davis_scale = davis.get_node("CollisionShape2D").scale
	var davis_width = davis_collision.size.x * davis_scale.x  # 考慮縮放後的碰撞寬度
	var davis_half_width = davis_width / 2.0  # 碰撞形狀的半寬
	if davis.position.x < davis_half_width:
		davis.position.x = davis_half_width  # 確保碰撞左邊緣不超出視口左邊
	elif davis.position.x > viewport_width - davis_half_width:
		davis.position.x = viewport_width - davis_half_width  # 確保碰撞右邊緣不超出視口右邊
	
	# 檢查 Dennis 的邊界
	var dennis_collision = dennis.get_node("CollisionShape2D").shape as RectangleShape2D
	var dennis_scale = dennis.get_node("CollisionShape2D").scale
	var dennis_width = dennis_collision.size.x * dennis_scale.x  # 考慮縮放後的碰撞寬度
	var dennis_half_width = dennis_width / 2.0  # 碰撞形狀的半寬
	if dennis.position.x < dennis_half_width:
		dennis.position.x = dennis_half_width
	elif dennis.position.x > viewport_width - dennis_half_width:
		dennis.position.x = viewport_width - dennis_half_width

func _on_hit_detected(target: String):
	hit_label.text = "Hits: " + target + " was hit!"
	
func _process(delta):
	FPS.text = "FPS: %d" % (1.0 / delta)
