extends Node2D

@onready var particles_1 = $explode
@onready var particles_2 = $ring

func _ready():
	# 確保粒子在實例化時開始播放
	if particles_1:
		particles_1.emitting = true
	if particles_2:
		particles_2.emitting = true

func _process(_delta):
	# 檢查兩個粒子系統是否都停止播放
	if not particles_1.emitting and not particles_2.emitting:
		queue_free()
