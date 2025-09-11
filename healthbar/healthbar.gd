extends ProgressBar

@export var max_health: float = 100.0
@export var target_node: NodePath # 導出變數，用於指定角色節點
var current_health: float = max_health
var _target: Node # 儲存角色節點的引用

func _ready():
	_target = get_node_or_null(target_node)
	if not _target:
		print("Warning: Target node not found for %s" % name)
	value = current_health
	max_value = max_health
	update_health_bar()

func take_damage(damage: float):
	current_health = max(0, current_health - damage)
	update_health_bar()
	if current_health <= 0:
		if _target:
			print("Debug: %s is defeated!" % _target.name)
		else:
			print("Debug: %s is defeated! (No target assigned)" % name)

func update_health_bar():
	value = current_health
	$DamageBar.value = current_health
	if current_health < max_health:
		$Timer.start()
		if _target:
			print("Debug: Health updated to %s for %s" % [current_health, _target.name])
		else:
			print("Debug: Health updated to %s for %s" % [current_health, name])

func _on_timer_timeout():
	$DamageBar.value = current_health
