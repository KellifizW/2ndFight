class_name PlayerController extends Node

@export var player_id: String = "p1"

# 新增：引用 ControlHistory 節點
var control_history = null
var special_moves = [
	{
		"state": "fireball",
		"sequence": [
			ControlHistory.MoveDirection.DOWN,
			ControlHistory.MoveDirection.DOWN_FORWARD,
			ControlHistory.MoveDirection.FORWARD,
			ControlHistory.SpecialMoveButton.ST_MP
		],
		"cursor": 0
	}
]

# 新增：緩衝窗口，防止 st_mp 立即覆蓋 spm2_pressed
var sequence_buffer_timer: float = 0.0
const SEQUENCE_BUFFER_DURATION: float = 0.2 # 增加到 0.2 秒
var pending_special_move: bool = false # 標記是否有待處理的特殊招式

func _ready():
	# 使用正確的路徑
	control_history = get_node("/root/World/ControlHistory")
	if not control_history:
		print("Error: ControlHistory node not found at /root/World/ControlHistory")
	else:
		print("Debug: ControlHistory node found at /root/World/ControlHistory")

func get_input_data() -> Dictionary:
	var suffix = "_p2" if player_id == "p2" else ""
	# 獲取原始輸入
	var move_right = Input.is_action_pressed("move_right" + suffix)
	var move_left = Input.is_action_pressed("move_left" + suffix)
	var move_up = Input.is_action_pressed("jump" + suffix)
	var move_down = Input.is_action_pressed("crouch" + suffix)
	
	# 計算水平方向 (dir_x)
	var dir_x: int = 0
	if move_right and not move_left:
		dir_x = 1
	elif move_left and not move_right:
		dir_x = -1
	
	# 計算垂直方向 (dir_y)
	var dir_y: int = 0
	if move_up and not move_down:
		dir_y = -1
	elif move_down and not move_up:
		dir_y = 1
	
	# 組合輸入：斜上和斜下處理
	var input_dir: int = dir_x
	var crouch_pressed: bool = dir_y > 0
	var jump_pressed: bool = dir_y < 0
	
	# 攻擊和特殊招式輸入
	var st_mp_pressed = Input.is_action_just_pressed("st_mp" + suffix)
	var st_mk_pressed = Input.is_action_just_pressed("st_mk" + suffix)
	var spm1_pressed = Input.is_action_just_pressed("spmove1" + suffix)
	var spm2_pressed = Input.is_action_just_pressed("spmove2" + suffix)
	
	# 新增：根據 facing_direction 映射方向
	var facing_direction = get_parent().facing_direction if "facing_direction" in get_parent() else 1.0
	var direction = ControlHistory.MoveDirection.NONE
	if dir_y > 0 and dir_x * facing_direction > 0:
		direction = ControlHistory.MoveDirection.DOWN_FORWARD
	elif dir_y > 0 and dir_x * facing_direction < 0:
		direction = ControlHistory.MoveDirection.DOWN_BACKWARD
	elif dir_y > 0:
		direction = ControlHistory.MoveDirection.DOWN
	elif dir_x * facing_direction > 0:
		direction = ControlHistory.MoveDirection.FORWARD
	elif dir_x * facing_direction < 0:
		direction = ControlHistory.MoveDirection.BACKWARD
	
	# 新增：記錄輸入快照
	var buttons = [st_mp_pressed] # 僅記錄 st_mp
	var player_id_num = 0 if player_id == "p1" else 1
	if control_history:
		control_history.poll_control(get_process_delta_time(), player_id_num, direction, buttons)
	
	# 新增：檢查特殊招式序列
	var sequence_completed = false
	if control_history:
		for move in special_moves:
			if control_history.has_special_move_been_executed(move, player_id_num, get_process_delta_time()):
				spm2_pressed = true
				st_mp_pressed = false
				sequence_completed = true
				sequence_buffer_timer = SEQUENCE_BUFFER_DURATION
				pending_special_move = true # 標記特殊招式待處理
				print("Debug: Fireball sequence completed for player %s" % player_id)
	
	# 新增：緩衝窗口內忽略 st_mp 輸入並保持 spm2_pressed
	if sequence_buffer_timer > 0:
		st_mp_pressed = false
		if pending_special_move:
			spm2_pressed = true # 保持 spm2_pressed 直到處理
		sequence_buffer_timer -= get_process_delta_time()
		if sequence_buffer_timer <= 0:
			pending_special_move = false # 重置特殊招式標記
			print("Debug: Sequence buffer window ended for player %s" % player_id)
	
	# 計算攻擊相關數據
	var move_set = get_parent().get_node("MoveSet") if get_parent().has_node("MoveSet") else null
	var attack_type = "st_mp" if st_mp_pressed else "st_mk" if st_mk_pressed else "none"
	var blockstun_duration = 0.4 if move_set and ((move_set.is_powerkk and player_id == "p1") or (move_set.is_spnk and player_id == "p2")) else 0.3 if move_set and move_set.is_fireball else 0.2
	var damage = move_set.get_special_damage() if move_set and (move_set.is_powerkk or move_set.is_spnk or move_set.is_fireball) else (10.0 if (st_mp_pressed or st_mk_pressed) else 0.0)
	
	# 僅在輸入變化時輸出調試訊息
	if spm2_pressed or st_mp_pressed or st_mk_pressed or spm1_pressed:
		print("Debug: Input for %s - spm2_pressed=%s, st_mp_pressed=%s, attack_type=%s" % [player_id, spm2_pressed, st_mp_pressed, attack_type])
	
	return {
		"input_dir": input_dir,
		"crouch_pressed": crouch_pressed,
		"jump_pressed": jump_pressed,
		"st_mp_pressed": st_mp_pressed,
		"st_mk_pressed": st_mk_pressed,
		"attack_type": attack_type,
		"blockstun_duration": blockstun_duration,
		"damage": damage,
		"spm1_pressed": spm1_pressed,
		"spm2_pressed": spm2_pressed
	}
