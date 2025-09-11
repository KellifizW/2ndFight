extends ProgressBar

@export var max_health: float = 100.0
var current_health: float = max_health

func _ready():
	value = current_health
	max_value = max_health
	update_health_bar()

func take_damage(damage: float):
	current_health = max(0, current_health - damage)
	update_health_bar()
	if current_health <= 0:
		print("Debug: %s is defeated!" % get_parent().name)

func update_health_bar():
	value = current_health
	$DamageBar.value = current_health
	if current_health < max_health:
		$Timer.start()
		print("Debug: Health updated to %s for %s" % [current_health, get_parent().name])

func _on_timer_timeout():
	$DamageBar.value = current_health
