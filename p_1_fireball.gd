extends Area2D

var speed = 300.0
var direction = 1

@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer

func _ready():
	if sprite == null:
		print("Error: Sprite2D node not found in Fireball!")
	else:
		sprite.flip_h = direction < 0
	if animation_player == null:
		print("Error: AnimationPlayer node not found in Fireball!")
	else:
		animation_player.play("idle")
	monitoring = true
	monitorable = true
	print("Fireball initialized, collision_layer: ", collision_layer, " collision_mask: ", collision_mask)
	print("Fireball monitoring: ", monitoring, " monitorable: ", monitorable)

func _physics_process(delta):
	position.x += speed * direction * delta
	if position.x > 2000 or position.x < -2000:
		print("Fireball out of bounds, destroying at position: ", position.x)
		queue_free()
