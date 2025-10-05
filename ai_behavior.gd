class_name AIBehavior extends Node

# 定義 AI 輸入類型，模擬 AIBrain.cs 的 AIInput，改為 Resource 以支持導出
class AIInput extends Resource:
	@export var direction: int = 0  # -1: left, 0: neutral, 1: right (相對於面向)
	@export var crouch: bool = false
	@export var jump: bool = false
	@export var attack: bool = false
	@export var spm1: bool = false
	@export var spm2: bool = false

# 定義 AI 動作，類似 AIAction
class AIAction extends Resource:
	@export var inputs: Array[Resource] = []  # AIInput Resource 陣列
	@export var auto_advance: bool = false  # 是否自動推進到下一個命令

# 定義 AI 條件，類似 AICondition
class AICondition extends Resource:
	@export var use_on_ground: bool = true
	@export var use_on_air: bool = false
	@export var distance: Vector2i = Vector2i(0, 0)  # x: 水平距離, y: 垂直距離 (以 SIMULATION_SCALE 單位)
	@export var probability: int = 5  # 0-10
	@export var action_mode: String = "neutral"  # "aggressive", "defensive", "neutral"
	@export var actions_list: Array[int] = []  # 動作索引陣列

# 定義 AI 動作包，類似 AIActionPack
class AIActionPack extends Resource:
	@export var horizontal_distance: int = 0  # 以 SIMULATION_SCALE 單位
	@export var conditions: Array[Resource] = []  # AICondition Resource 陣列

# 定義 AI 行為，類似 AIBehavior
@export_category("Behaviors")
@export var decision_rate_free: Vector2i = Vector2i(5, 15)  # 空閒時決策幀範圍
@export var decision_rate_busy: Vector2i = Vector2i(10, 20)  # 忙碌時決策幀範圍
@export var input_randomness: Vector2i = Vector2i(1, 3)  # 輸入隨機等待幀
@export var blocking_rate: int = 7  # 0-10，阻擋概率
@export var prediction_quality: int = 5  # 0-10，反擊預測品質
@export var low_health_threshold: float = 30.0  # 低血量門檻，切換模式

@export var actions: Array[Resource] = []  # AIAction Resource 陣列
@export var near_actions: Resource = AIActionPack.new()
@export var mid_actions: Resource = AIActionPack.new()
@export var far_actions: Resource = AIActionPack.new()
@export var distant_actions: Resource = AIActionPack.new()

@export var block_action: int = -1  # 阻擋動作索引 (遊戲中無 high/low 分類)

var ai_owner: Node  # 擁有者，通常是 Player
var opponent: Node  # 對手
var mode: String = "aggressive"  # "aggressive", "defensive"
var tick: int = 0
var tick_limit: int = 10
var input_tick: int = 0
var input_tick_limit: int = 1
var current_command_list: Array[int] = []
var current_command: int = 0
var current_input_index: int = 0
var can_advance: bool = false
var input_finished: bool = true
var blocking: bool = false
var ai_enabled: bool = false
var current_state: String = "idle"  # 新增：匹配 world.gd 重置邏輯
var state_timer: float = 0.0  # 新增：匹配 world.gd 重置邏輯
var last_action_time: float = 0.0  # 新增：匹配 world.gd 重置邏輯

func _ready():
	ai_owner = get_parent()
	if not ai_owner or not ai_owner is Fighter:
		print("Error: AIBehavior must be child of Fighter-derived node")
	opponent = get_opponent()
	if not opponent:
		print("Warning: Opponent not found for AIBehavior")
	print("Debug: AIBehavior initialized, ai_enabled=", ai_enabled)

func set_ai_enabled(enabled: bool):
	ai_enabled = enabled
	print("Debug: AI enabled set to ", ai_enabled)
	if not enabled:
		reset()

func get_opponent() -> Node:
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p != ai_owner:
			return p
	return null

func reset():
	current_command_list = []
	blocking = false
	current_command = 0
	current_input_index = 0
	can_advance = false
	input_finished = true
	current_state = "idle"  # 新增：重置狀態
	state_timer = 0.0  # 新增：重置計時器
	last_action_time = 0.0  # 新增：重置最後動作時間
	print("Debug: AI reset, current_command_list=", current_command_list)

func get_ai_input() -> Dictionary:
	print("Debug: get_ai_input called, ai_enabled=", ai_enabled)
	if not ai_enabled:
		print("Debug: AI disabled, returning default input")
		return {
			"input_dir": 0,
			"crouch_pressed": false,
			"jump_pressed": false,
			"attack_pressed": false,
			"attack_type": "none",
			"blockstun_duration": 0.2,
			"damage": 0.0,
			"spm1_pressed": false,
			"spm2_pressed": false
		}
	
	select_command()
	update_command()
	
	var ai_input_inst = generate_input()
	var result = {
		"input_dir": ai_input_inst.direction,
		"crouch_pressed": ai_input_inst.crouch,
		"jump_pressed": ai_input_inst.jump,
		"attack_pressed": ai_input_inst.attack,
		"attack_type": "attack" if ai_input_inst.attack else "none",
		"blockstun_duration": 0.2,  # 預設值，根據動作調整若需要
		"damage": 10.0 if ai_input_inst.attack else 0.0,  # 預設攻擊傷害
		"spm1_pressed": ai_input_inst.spm1,
		"spm2_pressed": ai_input_inst.spm2
	}
	print("Debug: get_ai_input returning ", result)
	return result

func select_command():
	print("Debug: select_command called, ai_owner state: is_hit=", ai_owner.is_hit, ", is_knockfly=", ai_owner.is_knockfly, ", is_wakeup=", ai_owner.is_wakeup)
	if ai_owner.is_hit or ai_owner.is_knockfly or ai_owner.is_wakeup:
		print("Debug: AI in invalid state, skipping command selection")
		return
	
	if current_command > 0 or (current_input_index > 0 and not can_advance):
		print("Debug: Command in progress, resetting. current_command=", current_command, ", current_input_index=", current_input_index)
		reset()
	
	var move_ended = (current_command == 0 or current_command >= current_command_list.size()) and current_input_index == 0
	if not move_ended:
		print("Debug: Move not ended, tick reset, current_command=", current_command, ", current_input_index=", current_input_index)
		tick = 0
		return
	
	# 如果忙碌，重置
	if ai_owner.is_attacking or ai_owner.is_special_moving or ai_owner.is_blocking:
		print("Debug: AI busy (attacking=", ai_owner.is_attacking, ", special_moving=", ai_owner.is_special_moving, ", blocking=", ai_owner.is_blocking, "), resetting")
		reset()
		tick = 0
		return
	
	# 如果被近距離阻擋，嘗試阻擋
	if ai_owner.has_node("Proximitybox") and ai_owner.get_node("Proximitybox").monitoring:
		print("Debug: Proximitybox detected, blocking=", blocking, ", block_action=", block_action)
		if not blocking:
			reset()
			var rnd = randi() % 10
			if rnd < blocking_rate and block_action >= 0:
				current_command_list = [block_action]
				print("Debug: Block action selected, current_command_list=", current_command_list)
			else:
				print("Debug: Block not triggered, rnd=", rnd, ", blocking_rate=", blocking_rate)
			blocking = true
		tick = 0
		input_tick = 0
		return
	
	# 推進決策 tick
	tick += 1
	if tick <= tick_limit:
		print("Debug: Waiting for tick limit, tick=", tick, ", tick_limit=", tick_limit)
		return
	else:
		tick_limit = update_decision_rate()
		tick = 0
		print("Debug: Tick limit reached, new tick_limit=", tick_limit)
	
	# 儲存先前值
	var previous_command_list = current_command_list.duplicate()
	var previous_command = current_command
	var previous_input_index = current_input_index
	
	reset()
	
	# 計算距離 (使用 fixed_position)
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		print("Debug: World node not found, skipping command selection")
		return
	var distance = Vector2i(
		abs(ai_owner.fixed_position.x - opponent.fixed_position.x),
		abs(ai_owner.fixed_position.y - opponent.fixed_position.y)
	)
	print("Debug: Distance to opponent: x=", distance.x, ", y=", distance.y)
	
	# 根據距離選擇動作包
	var selected_pack: AIActionPack = near_actions
	if distance.x > near_actions.horizontal_distance and distance.x <= mid_actions.horizontal_distance:
		selected_pack = mid_actions
		print("Debug: Selected mid_actions, horizontal_distance=", mid_actions.horizontal_distance)
	elif distance.x > mid_actions.horizontal_distance and distance.x <= far_actions.horizontal_distance:
		selected_pack = far_actions
		print("Debug: Selected far_actions, horizontal_distance=", far_actions.horizontal_distance)
	elif distance.x > far_actions.horizontal_distance:
		selected_pack = distant_actions
		print("Debug: Selected distant_actions, horizontal_distance=", distant_actions.horizontal_distance)
	else:
		print("Debug: Selected near_actions, horizontal_distance=", near_actions.horizontal_distance)
	
	# 根據健康切換模式
	var healthbar = ai_owner.healthbar if "healthbar" in ai_owner else null
	if healthbar and healthbar.current_health < low_health_threshold:
		mode = "defensive"
		print("Debug: Mode switched to defensive, current_health=", healthbar.current_health)
	else:
		mode = "aggressive"
		print("Debug: Mode set to aggressive, current_health=", healthbar.current_health if healthbar else "N/A")
	
	# 選擇命令
	if selected_pack.conditions.size() == 0:
		print("Debug: No conditions in selected_pack, skipping command selection")
		return
	if selected_pack.conditions.size() == 1:
		current_command_list = selected_pack.conditions[0].actions_list.duplicate()
		print("Debug: Single condition, selected actions_list=", current_command_list)
	else:
		var prev_dist_x = 0
		var prev_dist_y = 0
		for cond in selected_pack.conditions:
			# 檢查表面
			var correct_surface = (cond.use_on_ground and ai_owner.is_on_floor()) or \
								  (cond.use_on_air and not ai_owner.is_on_floor()) or \
								  (cond.use_on_ground and cond.use_on_air)
			if not correct_surface:
				print("Debug: Condition skipped, correct_surface=", correct_surface, ", use_on_ground=", cond.use_on_ground, ", use_on_air=", cond.use_on_air, ", is_on_floor=", ai_owner.is_on_floor())
				continue
			
			# 檢查距離
			var is_same_x = cond.distance.x == prev_dist_x
			var ignore_y = cond.distance.y == 0
			var check_far = (is_same_x or distance.x > prev_dist_x) and (ignore_y or distance.y >= prev_dist_y)
			var check_close = distance.x <= cond.distance.x and (ignore_y or distance.y <= cond.distance.y)
			if not check_far or not check_close:
				print("Debug: Condition skipped, distance check failed: distance.x=", distance.x, ", cond.distance.x=", cond.distance.x, ", distance.y=", distance.y, ", cond.distance.y=", cond.distance.y)
				continue
			
			# 隨機選擇
			var prob = variable_probability(cond)
			var rnd = randi() % 10
			if rnd > prob - 1:
				print("Debug: Condition skipped, probability check failed: rnd=", rnd, ", prob=", prob)
				continue
			
			current_command_list = cond.actions_list.duplicate()
			prev_dist_x = cond.distance.x
			prev_dist_y = cond.distance.y
			print("Debug: Condition selected, actions_list=", current_command_list)
	
	if current_command_list.is_empty():
		print("Debug: No valid command list selected")
	
	# 如果新命令與先前相同，繼續
	if compare_commands(current_command_list, previous_command_list):
		current_command = previous_command
		current_input_index = previous_input_index
		print("Debug: Restored previous command, current_command=", current_command, ", current_input_index=", current_input_index)
	
	input_tick = 0
	input_tick_limit = set_input_random_wait_time()
	print("Debug: Input tick reset, input_tick_limit=", input_tick_limit)

func update_decision_rate() -> int:
	var rate = randi_range(decision_rate_free.x, decision_rate_free.y) if not (ai_owner.is_attacking or ai_owner.is_special_moving) else randi_range(decision_rate_busy.x, decision_rate_busy.y)
	print("Debug: Decision rate updated, rate=", rate, ", is_busy=", ai_owner.is_attacking or ai_owner.is_special_moving)
	return rate

func set_input_random_wait_time() -> int:
	var wait = randi_range(input_randomness.x, input_randomness.y)
	print("Debug: Input random wait time set to ", wait)
	return wait

func variable_probability(cond: AICondition) -> int:
	var prob = cond.probability
	match mode:
		"aggressive":
			match cond.action_mode:
				"aggressive": prob += 1
				"defensive": prob -= 2
		"defensive":
			match cond.action_mode:
				"aggressive": prob -= 2
				"defensive": prob += 1
	prob = clamp(prob, 0, 10)
	print("Debug: Probability calculated for mode=", mode, ", action_mode=", cond.action_mode, ", prob=", prob)
	return prob

func compare_commands(c1: Array[int], c2: Array[int]) -> bool:
	if c1.size() != c2.size():
		print("Debug: Command lists differ in size, c1=", c1.size(), ", c2=", c2.size())
		return false
	for i in range(c1.size()):
		if c1[i] != c2[i]:
			print("Debug: Command lists differ at index ", i, ": c1=", c1[i], ", c2=", c2[i])
			return false
	print("Debug: Command lists are identical")
	return true

func update_command():
	print("Debug: update_command called, current_command_list=", current_command_list, ", current_command=", current_command)
	if current_command_list.is_empty() or current_command >= current_command_list.size():
		print("Debug: Invalid command list or index, skipping")
		return
	
	var curr = current_command_list[current_command]
	if curr < 0 or curr >= actions.size():
		print("Debug: Invalid action index: curr=", curr, ", actions.size()=", actions.size())
		return
	
	input_tick += 1
	input_finished = current_input_index >= (actions[curr] as AIAction).inputs.size() - 1
	print("Debug: input_tick=", input_tick, ", input_finished=", input_finished, ", current_input_index=", current_input_index, ", inputs_size=", (actions[curr] as AIAction).inputs.size())
	
	if input_tick <= input_tick_limit:
		print("Debug: Waiting for input tick limit, input_tick=", input_tick, ", input_tick_limit=", input_tick_limit)
		return
	else:
		input_tick_limit = set_input_random_wait_time()
		input_tick = 0
	
	current_input_index += 1
	current_input_index = clamp(current_input_index, 0, (actions[curr] as AIAction).inputs.size() - 1)
	print("Debug: Advanced to input_index=", current_input_index)
	
	if input_finished and (can_advance or (actions[curr] as AIAction).auto_advance) and current_command < current_command_list.size():
		current_command += 1
		current_input_index = 0
		can_advance = false
		print("Debug: Advanced to next command, current_command=", current_command)

func generate_input() -> AIInput:
	var ai_input_inst = AIInput.new()
	print("Debug: generate_input called, current_command=", current_command, ", current_input_index=", current_input_index)
	if current_command >= current_command_list.size() or current_input_index >= (actions[current_command_list[current_command]] as AIAction).inputs.size():
		print("Debug: Invalid command or input index, returning default AIInput")
		return ai_input_inst
	
	var input_data = (actions[current_command_list[current_command]] as AIAction).inputs[current_input_index] as AIInput
	
	# 根據面向調整方向
	var side = 1 if ai_owner.facing_direction > 0 else -1  # facing_direction 為 1 或 -1
	ai_input_inst.direction = input_data.direction * side
	ai_input_inst.crouch = input_data.crouch
	ai_input_inst.jump = input_data.jump
	ai_input_inst.attack = input_data.attack
	ai_input_inst.spm1 = input_data.spm1
	ai_input_inst.spm2 = input_data.spm2
	
	print("Debug: Generated AIInput: direction=", ai_input_inst.direction, ", crouch=", ai_input_inst.crouch, ", jump=", ai_input_inst.jump, ", attack=", ai_input_inst.attack, ", spm1=", ai_input_inst.spm1, ", spm2=", ai_input_inst.spm2)
	return ai_input_inst
