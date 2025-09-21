extends Camera2D

@export var zoom_factor:float = 40
@export var min_zoom:float = 0.8
var players = []

func _ready():
	players += [$"../Player1" , $"../Player2"]
	
func move():
	var ave:Vector2
	for s in players:
		ave += s.position
	ave/=players.size()
	position = ave

func zooming():
	var longest_dist:float = 1000
	for i in players:
		for j in players:
			if i==j: continue
			var dist:float = (i.global_position-j.global_position).length_squared()
			longest_dist = max(longest_dist, dist)
	var z = max(min_zoom, zoom_factor/sqrt(longest_dist))
	zoom = Vector2(z, z)
	
func _process(delta):
	move()
	zooming()
