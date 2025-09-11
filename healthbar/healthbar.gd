extends ProgressBar

@export var max_health: float = 100.0
@export var target_node: NodePath  # 導出變數，用於指定角色節點
var current_health: float = max_health
var _target: Node  # 儲存角色節點的引用

func _ready():
	_target = get_node_or_null(target_node)
	if not _target:
		print("Warning: Target node not found for %s" % name)
	max_value = max_health  # 設置主血條的最大值
	$DamageBar.max_value = max_health  # 同步白色條的最大值
	value = current_health  # 初始化綠色條
	$DamageBar.value = current_health  # 初始化白色條
	$Timer.wait_time = 0.4  # 確認 Timer 延遲時間（你的 tscn 已設為 0.4）
	$Timer.one_shot = true  # 確認單次觸發

func take_damage(damage: float):
	current_health = max(0, current_health - damage)
	value = current_health  # 立即更新綠色條（主血條）
	if current_health < max_health:
		$Timer.start()  # 啟動 Timer，讓白色條延遲更新
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
	$DamageBar.value = current_health  # Timer 結束後，白色條追上當前血量
