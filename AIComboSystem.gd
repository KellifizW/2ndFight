class_name AIComboSystem extends Node

var combo_database: Dictionary = {
	"light_punish": {
		"moves": ["st_mp", "st_mp", "fireball"],
		"conditions": {"distance_max": 75},
		"damage": 35.0
	},
	"medium_punish": {
		"moves": ["st_mk", "powerkk"],
		"conditions": {"distance_max": 95},
		"damage": 42.0
	},
	"close_combo": {
		"moves": ["cr_mp", "st_mk"],
		"conditions": {"distance_max": 70},
		"damage": 28.0
	},
}

var current_combo: Array = []
var combo_step: int = 0
var combo_timer: float = 0.0
var combo_timeout: float = 0.5  # 連段超時時間

func _process(delta: float) -> void:
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			reset_combo()

func get_available_combos(ai_player: Player, opponent: Player) -> Array[String]:
	var available: Array[String] = []
	for combo_id in combo_database.keys():
		if can_execute_combo(combo_id, ai_player, opponent):
			available.append(combo_id)
	return available

func can_execute_combo(combo_id: String, ai_player: Player, opponent: Player) -> bool:
	var combo = combo_database.get(combo_id, {})
	var conditions = combo.get("conditions", {})
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	
	if conditions.has("distance_max") and distance > conditions["distance_max"]:
		return false
	
	# 檢查對手是否在硬直或受創狀態
	if not (opponent.is_hit or opponent.is_knockfly or opponent.is_blocking):
		# 如果對手沒有處於可懲罰狀態，只允許在近距離執行
		if distance > 80:
			return false
	
	return true

func start_combo(combo_id: String) -> void:
	var combo = combo_database.get(combo_id, {})
	current_combo = combo.get("moves", [])
	combo_step = 0
	combo_timer = combo_timeout

func get_next_combo_move() -> String:
	if combo_step >= current_combo.size():
		return ""
	var move = current_combo[combo_step]
	combo_step += 1
	combo_timer = combo_timeout  # 重置超時計時器
	return move

func is_executing_combo() -> bool:
	return combo_step > 0 and combo_step < current_combo.size() and combo_timer > 0

func reset_combo() -> void:
	current_combo = []
	combo_step = 0
	combo_timer = 0.0

func advance_combo() -> void:
	"""在成功執行招式後呼叫，推進到下一步"""
	if is_executing_combo():
		combo_timer = combo_timeout
