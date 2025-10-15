extends Node2D

@onready var particles_1 = get_node_or_null("explode") if has_node("explode") else get_node_or_null("exp")
@onready var particles_2 = get_node_or_null("ring") if has_node("ring") else get_node_or_null("wave")

func _ready():
	# 確保粒子在實例化時開始播放
	if particles_1:
		particles_1.emitting = true
	if particles_2:
		particles_2.emitting = true
	print("Debug: VFX_impact initialized, particles emitting: %s, %s" % [particles_1.emitting if particles_1 else false, particles_2.emitting if particles_2 else false])

func _process(_delta):
	# 檢查兩個粒子系統是否都停止播放
	if (not particles_1 or not particles_1.emitting) and (not particles_2 or not particles_2.emitting):
		queue_free()
		print("Debug: VFX_impact particles finished, freeing node at position %s" % global_position)
