extends Node2D

var particle_nodes: Array = []

func _ready():
	# 抓取所有子節點，並過濾出 GPUParticles2D 類型
	for child in get_children():
		if child is GPUParticles2D:
			particle_nodes.append(child)
			child.emitting = true

func _process(_delta):
	# 檢查所有粒子是否都停止播放
	var all_stopped = true
	for particle in particle_nodes:
		if particle.emitting:
			all_stopped = false
			break
	
	if all_stopped and not particle_nodes.is_empty():
		queue_free()
		print("Debug: VFX_impact all particles finished, freeing node at position %s" % global_position)
