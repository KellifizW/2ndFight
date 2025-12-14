# Healthbar.gd  （改寫為 TextureProgressBar 版）
extends TextureProgressBar   # ← 唯一需要改的繼承類別

@export var max_health: float = 100.0
@export var target_node: NodePath  # 仍然保留，讓你可以在編輯器拖角色進來
var current_health: float = max_health
var _target: Node

func _ready():
	_target = get_node_or_null(target_node)
	if not _target:
		print("Warning: Target node not found for %s" % name)
	
	# 以下全部改用 TextureProgressBar 的屬性
	max_value = max_health
	$DamageBar.max_value = max_health         # DamageBar 也必須是 TextureProgressBar
	value = current_health                     # 主條（你設的黃橘紅漸層）
	$DamageBar.value = current_health          # 白色延遲條
	$Timer.wait_time = 0.4
	$Timer.one_shot = true

func take_damage(damage: float):
	current_health = max(0, current_health - damage)
	
	value = current_health                     # 立即掉血（主條）
	
	if current_health < max_health:
		$Timer.start()                         # 啟動延遲讓白色條追上
	
	if current_health <= 0:
		if _target:
			print("Debug: %s is defeated!" % _target.name)
		else:
			print("Debug: %s is defeated! (No target assigned)" % name)
	
	if _target:
		print("Debug: Health updated to %s for %s" % [current_health, _target.name])
	else:
		print("Debug: Health updated to %s for %s" % [current_health, name])

func _on_timer_timeout():
	$DamageBar.value = current_health          # 白色條緩慢追上
