extends Node2D

@onready var hit_label = $HitLabel
@onready var davis = $Davis
@onready var dennis = $Dennis

func _ready():
	davis.hit_detected.connect(_on_hit_detected)
	dennis.hit_detected.connect(_on_hit_detected)

func _physics_process(delta):
	var viewport_width = get_viewport_rect().size.x  # 獲取畫面寬度，類似講稿的 GameViewport.width
	
	# 檢查 Davis 的邊界
	var davis_width = davis.get_node("Sprite2D").texture.get_width()  # 假設子節點為 Sprite2D
	if davis.position.x < 0:
		davis.position.x = 0  # 限制在左邊界
		if davis.has_method("reverse_direction"):  # 假設角色腳本有 reverse_direction 方法
			davis.reverse_direction()
	elif davis.position.x > viewport_width - davis_width:
		davis.position.x = viewport_width - davis_width  # 限制在右邊界
		if davis.has_method("reverse_direction"):
			davis.reverse_direction()
	
	# 檢查 Dennis 的邊界
	var dennis_width = dennis.get_node("Sprite2D").texture.get_width()
	if dennis.position.x < 0:
		dennis.position.x = 0
		if dennis.has_method("reverse_direction"):
			dennis.reverse_direction()
	elif dennis.position.x > viewport_width - dennis_width:
		dennis.position.x = viewport_width - dennis_width
		if dennis.has_method("reverse_direction"):
			dennis.reverse_direction()

func _on_hit_detected(target: String):
	hit_label.text = "Hits: " + target + " was hit!"
