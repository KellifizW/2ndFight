extends ProgressBar

# 進度條監聽的目標玩家（P1 或 P2）
var target_player: Node = null
var other_player: Node = null
var animation_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var animation_player: AnimationPlayer = null
var hitbox_shape: CollisionShape2D = null
var current_animation: String = ""
var last_animation: String = ""
var last_finished_animation: String = ""  # 追蹤最後完成的動畫
var frame_data: Array = []  # 儲存當前動畫的幀狀態（0=Startup, 1=Active, 2=Recovery, 3=Dash/Backdash, 4=Block, 5=Jump, 6=Hit, 7=Knockfly, 8=Buffer/White）
var history_frame_data: Array = []  # 儲存所有歷史動畫的幀狀態
var total_frames: int = 90  # 總幀數（1.5秒 * 60 FPS）
var current_frame: int = 0
var is_tracking: bool = false
var was_active: bool = false  # 追蹤是否曾進入 Active 階段
var jump_frame_count: int = 0  # 記錄空中時間的幀數（從跳躍到著地）
var jump_to_attack_offset: int = 0  # 記錄跳躍到跳躍攻擊時的 frame_data 偏移量
var is_jump_attack_active: bool = false  # 標記是否處於跳躍攻擊狀態
var is_airborne: bool = false  # 標記角色是否在空中
var reset_delay_timer: float = 0.0  # 0.05s 時間窗口計時器
var buffer_start_frame: int = 0  # 記錄窗口開始的幀位置
var white_frames_added: int = 0  # 記錄添加的白色幀數

@onready var frame_count_label = $FrameCountLabel  # 引用場景中的 FrameCountLabel

func _ready():
	# 初始化進度條屬性
	max_value = total_frames
	value = 0
	# 設置背景為黑色，帶白色邊框
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color.BLACK
	bg_style.border_color = Color.WHITE
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	set("theme_override_styles/background", bg_style)
	# 禁用內建填充，改用自定義繪製
	set("theme_override_styles/fill", null)
	# 確保進度條可見
	visible = true
	
	# 檢查 FrameCountLabel 是否存在
	if frame_count_label:
		frame_count_label.text = "Initializing..."
		frame_count_label.visible = true
	else:
		push_error("Error: FrameCountLabel not found for %s. Please check scene setup." % name)
		return
	print("Debug: FrameBar initialized, FrameCountLabel found, visible=%s" % frame_count_label.visible)

func initialize(p1: Node, p2: Node):
	# 初始化玩家節點
	target_player = p1
	other_player = p2
	if target_player and target_player.has_node("AnimationTree"):
		animation_tree = target_player.get_node("AnimationTree")
		playback = animation_tree.get("parameters/playback") if animation_tree else null
		if playback:
			if not animation_tree.animation_finished.is_connected(_on_animation_finished):
				animation_tree.animation_finished.connect(_on_animation_finished)
				print("Debug: Connected animation_finished signal for %s" % target_player.name)
	else:
		push_error("Error: AnimationTree or playback not found for %s" % name)
	if target_player and target_player.has_node("AnimationPlayer"):
		animation_player = target_player.get_node("AnimationPlayer")
	else:
		push_error("Error: AnimationPlayer not found for %s" % name)
	if target_player and target_player.has_node("Hitbox/HitShape"):
		hitbox_shape = target_player.get_node("Hitbox/HitShape")
	else:
		push_error("Error: Hitbox/HitShape not found for %s" % name)
	print("Debug: FrameBar initialized for %s, visible=%s" % [target_player.name if target_player else "null", visible])

func _process(delta):
	if not playback or not animation_player or not target_player or not hitbox_shape:
		return
	
	# 處理重置延遲計時器 (時間窗口)
	if reset_delay_timer > 0:
		reset_delay_timer -= delta
		current_frame = buffer_start_frame + white_frames_added
		current_frame += 1
		white_frames_added += 1
		if current_frame >= total_frames:
			current_frame = total_frames - 1
		if current_frame >= frame_data.size():
			frame_data.resize(current_frame + 1)
		frame_data[current_frame] = 8  # 白色窗口 state
		value = min(current_frame + 1, total_frames)
		queue_redraw()
		update_frame_count_label(current_animation)  # 實時更新標籤
		if reset_delay_timer <= 0:
			print("Debug: Buffer window ended for %s, total white frames added=%d, frame_data size=%d" % [target_player.name, white_frames_added, frame_data.size()])
	
	# 檢查當前動畫
	var anim_name = playback.get_current_node()
	var anim_position = playback.get_current_play_position()
	var anim_length = animation_player.get_animation(anim_name).length if animation_player.has_animation(anim_name) else 0.5
	var total_anim_frames = int(anim_length * 60)
	var is_on_floor = target_player.is_on_floor() if target_player.has_method("is_on_floor") else false

	# 檢查是否進入空中狀態
	if anim_name in ["Jump_F", "Jump_B", "Jump_V"] and not is_airborne:
		is_airborne = true
		jump_frame_count = 0
		print("Debug: Entered airborne state for %s" % target_player.name)
	
	# 檢查是否結束空中狀態
	if is_airborne and (anim_name == "landing" or is_on_floor):
		is_airborne = false
		if last_animation in ["Jump_F", "Jump_B", "Jump_V", "jump_mp", "jump_mk"]:
			update_frame_count_label(last_animation)  # 只顯示跳躍動畫的資料
			is_tracking = false
		print("Debug: Exited airborne state for %s, jump_frame_count=%d, is_on_floor=%s" % [target_player.name, jump_frame_count, is_on_floor])
	
	# 監聽的動畫清單（已加入 dp 與 super）
	var tracked_animations = [
		"st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball",
		"dp", "super",
		"Dash", "Backdash",
		"block", "cr_block",
		"Jump_F", "Jump_B", "Jump_V",
		"hit", "knockfly"
	]
	
	if anim_name in tracked_animations:
		var is_jump_to_attack = last_animation in ["Jump_F", "Jump_B", "Jump_V"] and anim_name in ["jump_mp", "jump_mk"]
		
		if (anim_name != last_animation or not is_tracking) and not is_jump_to_attack:
			was_active = false
			if reset_delay_timer > 0 and anim_name != last_finished_animation:
				var elapsed = 0.05 - reset_delay_timer
				var add_white = max(1, int(elapsed * 60))
				for i in range(add_white):
					current_frame = buffer_start_frame + white_frames_added
					white_frames_added += 1
					if current_frame >= frame_data.size():
						frame_data.resize(current_frame + 1)
					frame_data[current_frame] = 8
				reset_delay_timer = 0.0
				current_animation = anim_name
				last_animation = anim_name
				is_tracking = true
				is_jump_attack_active = false
				if not is_airborne:
					jump_frame_count = 0
				print("Debug: New animation %s in buffer window for %s, added %d white frames, frame_data size=%d" % [anim_name, target_player.name, add_white, frame_data.size()])
			else:
				history_frame_data.clear()
				frame_data.clear()
				current_frame = 0
				current_animation = anim_name
				last_animation = anim_name
				is_tracking = true
				is_jump_attack_active = false
				if not is_airborne:
					jump_frame_count = 0
				reset_delay_timer = 0.0
				white_frames_added = 0
				buffer_start_frame = 0
				print("Debug: New animation %s for %s, cleared all data, frame_data size=%d" % [anim_name, target_player.name, frame_data.size()])
			last_finished_animation = ""
		elif is_jump_to_attack:
			current_animation = anim_name
			last_animation = anim_name
			is_tracking = true
			is_jump_attack_active = true
			was_active = false
			if jump_to_attack_offset == 0:
				jump_to_attack_offset = frame_data.size()
			print("Debug: Transition from jump to attack %s for %s, keeping frame_data, size=%d, offset=%d" % [anim_name, target_player.name, frame_data.size(), jump_to_attack_offset])
		
		# 更新空中幀數
		if is_airborne:
			jump_frame_count += 1
		
		# 計算當前幀
		if is_jump_attack_active:
			current_frame = jump_to_attack_offset + int(anim_position * 60)
			if current_frame >= total_frames:
				current_frame = total_frames - 1
			print("Debug: Jump attack active, current_frame=%d, anim_position=%s, offset=%d" % [current_frame, anim_position, jump_to_attack_offset])
		else:
			if anim_name in ["Jump_F", "Jump_B", "Jump_V"]:
				current_frame = jump_frame_count
				if current_frame >= total_frames:
					current_frame = total_frames - 1
			else:
				current_frame = int(anim_position * 60)
				if current_frame >= total_frames:
					current_frame = total_frames - 1
		
		# 確保 frame_data 足夠長
		if current_frame >= frame_data.size():
			frame_data.resize(current_frame + 1)
		
		# 根據動畫類型設定 state（僅 DP 空中改 Recovery）
		var state: int = -1
		if anim_name in ["st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball", "dp", "super"]:
			if hitbox_shape.shape == null or hitbox_shape.disabled:
				if not was_active:
					state = 0  # Startup
				else:
					state = 2  # Recovery
			else:
				state = 1  # Active
				was_active = true
		elif anim_name in ["Dash", "Backdash"]:
			state = 3
		elif anim_name in ["block", "cr_block"]:
			state = 4
		elif anim_name in ["Jump_F", "Jump_B", "Jump_V"]:
			state = 5
		elif anim_name == "hit":
			state = 6
		elif anim_name == "knockfly":
			state = 7
		
		# === DP 空中強制 Recovery（僅此一改） ===
		if anim_name == "dp" and not is_on_floor:
			state = 2
		
		if state != -1:
			frame_data[current_frame] = state
			value = min(current_frame + 1, total_frames)
			queue_redraw()
			update_frame_count_label(anim_name)  # 實時更新標籤
	else:
		if is_tracking:
			reset_frame_bar()

func _draw():
	var bar_width = size.x
	var bar_height = size.y
	var frame_width = bar_width / total_frames
	
	# 繪製背景（黑色）
	var bg_rect = Rect2(0, 0, bar_width, bar_height)
	draw_rect(bg_rect, Color.BLACK, true)
	
	# 繪製歷史動畫
	for i in range(min(history_frame_data.size(), total_frames)):
		var color = Color.BLACK
		if history_frame_data[i] != null:
			match history_frame_data[i]:
				0: color = Color.BLUE
				1: color = Color.RED
				2: color = Color.YELLOW
				3: color = Color.PINK
				4: color = Color.GREEN
				5: color = Color(1.0, 0.5, 1.0)
				6: color = Color.ORANGE
				7: color = Color.PURPLE
				8: color = Color.WHITE
			var rect = Rect2(i * frame_width, 0, frame_width, bar_height)
			draw_rect(rect, color, true)
	
	# 繪製當前動畫
	for i in range(min(frame_data.size(), total_frames)):
		var color = Color.BLACK
		if frame_data[i] != null:
			match frame_data[i]:
				0: color = Color.BLUE
				1: color = Color.RED
				2: color = Color.YELLOW
				3: color = Color.PINK
				4: color = Color.GREEN
				5: color = Color(1.0, 0.5, 1.0)
				6: color = Color.ORANGE
				7: color = Color.PURPLE
				8: color = Color.WHITE
			var rect = Rect2(i * frame_width, 0, frame_width, bar_height)
			draw_rect(rect, color, true)

func reset_frame_bar():
	value = 0
	current_frame = 0
	if frame_data.size() > 0:
		history_frame_data.append_array(frame_data)
	frame_data.clear()
	is_tracking = true
	was_active = false
	if not is_airborne:
		jump_frame_count = 0
	jump_to_attack_offset = 0
	is_jump_attack_active = false
	queue_redraw()

func update_frame_count_label(anim_name: String):
	if not frame_count_label:
		push_error("Error: FrameCountLabel not found for %s during update" % name)
		return
	
	var tracked_animations = [
		"st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball",
		"dp", "super",
		"Dash", "Backdash", "block", "cr_block", "Jump_F", "Jump_B", "Jump_V",
		"hit", "knockfly", "landing"
	]
	if anim_name not in tracked_animations:
		return
	
	var anim_length = animation_player.get_animation(anim_name).length if animation_player.has_animation(anim_name) else 0.5
	var total_anim_frames = int(anim_length * 60)
	
	var is_jump_attack = anim_name in ["jump_mp", "jump_mk"] and last_animation in ["Jump_F", "Jump_B", "Jump_V"]
	if is_jump_attack:
		total_anim_frames += jump_frame_count
	
	var stage_counts = {
		"Startup": 0,
		"Active": 0,
		"Recovery": 0,
		"Dash": 0,
		"Backdash": 0,
		"Block": 0,
		"Cr_Block": 0,
		"Jump": 0,
		"Hit": 0,
		"Knockfly": 0
	}
	for frame_state in frame_data:
		if frame_state != null and frame_state != 8:
			match frame_state:
				0: stage_counts["Startup"] += 1
				1: stage_counts["Active"] += 1
				2: stage_counts["Recovery"] += 1
				3: 
					if anim_name == "Dash":
						stage_counts["Dash"] += 1
					elif anim_name == "Backdash":
						stage_counts["Backdash"] += 1
				4:
					if anim_name == "block":
						stage_counts["Block"] += 1
					elif anim_name == "cr_block":
						stage_counts["Cr_Block"] += 1
				5: stage_counts["Jump"] += 1
				6: stage_counts["Hit"] += 1
				7: stage_counts["Knockfly"] += 1
	
	var label_text = anim_name + ": "
	if anim_name == "landing":
		label_text += "Jump: %dF Total: %dF" % [jump_frame_count, jump_frame_count]
	elif anim_name in ["st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball", "dp", "super"]:
		var stages = []
		if is_jump_attack and stage_counts["Jump"] > 0:
			stages.append("Jump: %dF" % stage_counts["Jump"])
		if stage_counts["Startup"] > 0:
			stages.append("Startup: %dF" % stage_counts["Startup"])
		else:
			stages.append("Startup: 0F")
		if stage_counts["Active"] > 0:
			stages.append("Active: %dF" % stage_counts["Active"])
		else:
			stages.append("Active: 0F")
		if stage_counts["Recovery"] > 0:
			stages.append("Recovery: %dF" % stage_counts["Recovery"])
		else:
			stages.append("Recovery: 0F")
		label_text += " ".join(stages)
		label_text += " Total: %dF" % total_anim_frames
	else:
		var stage_name = "Dash" if anim_name == "Dash" else \
						"Backdash" if anim_name == "Backdash" else \
						"Block" if anim_name == "block" else \
						"Cr_Block" if anim_name == "cr_block" else \
						"Jump" if anim_name in ["Jump_F", "Jump_B", "Jump_V"] else \
						"Hit" if anim_name == "hit" else \
						"Knockfly" if anim_name == "knockfly" else anim_name
		label_text += "%s: %dF Total: %dF" % [stage_name, stage_counts[stage_name] if stage_counts[stage_name] > 0 else total_anim_frames, total_anim_frames]
	
	frame_count_label.text = label_text

func _on_animation_finished(anim_name: String):
	var tracked_animations = [
		"st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball",
		"dp", "super",
		"Dash", "Backdash",
		"block", "cr_block",
		"Jump_F", "Jump_B", "Jump_V",
		"hit", "knockfly"
	]
	if anim_name in tracked_animations and anim_name != last_finished_animation:
		last_finished_animation = anim_name
		buffer_start_frame = frame_data.size()
		white_frames_added = 0
		if frame_data.size() > 0:
			current_frame = frame_data.size() - 1
			frame_data[current_frame] = 8
			white_frames_added += 1
			queue_redraw()
			print("Debug: Immediate white frame added at end of %s for %s, current_frame=%d" % [anim_name, target_player.name, current_frame])
		reset_delay_timer = 0.05
		var anim_length = animation_player.get_animation(anim_name).length if animation_player.has_animation(anim_name) else 0.5
		var total_anim_frames = int(anim_length * 60)
		var is_jump_attack = anim_name in ["jump_mp", "jump_mk"] and last_animation in ["Jump_F", "Jump_B", "Jump_V"]
		if is_jump_attack:
			total_anim_frames += jump_frame_count
		var display_frames = min(total_anim_frames, total_frames)
		if total_anim_frames > total_frames:
			var extra_frames = total_anim_frames - total_frames
			for i in range(min(extra_frames, total_frames)):
				if frame_data.size() <= i:
					frame_data.resize(i + 1)
				if anim_name in ["st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball", "dp", "super"]:
					frame_data[i] = 2
				elif anim_name in ["Dash", "Backdash"]:
					frame_data[i] = 3
				elif anim_name in ["block", "cr_block"]:
					frame_data[i] = 4
				elif anim_name in ["Jump_F", "Jump_B", "Jump_V"]:
					frame_data[i] = 5
				elif anim_name == "hit":
					frame_data[i] = 6
				elif anim_name == "knockfly":
					frame_data[i] = 7
			display_frames = total_frames
		else:
			for i in range(current_frame + 1, display_frames):
				if frame_data.size() <= i:
					frame_data.resize(i + 1)
				if anim_name in ["st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball", "dp", "super"]:
					frame_data[i] = 2
				elif anim_name in ["Dash", "Backdash"]:
					frame_data[i] = 3
				elif anim_name in ["block", "cr_block"]:
					frame_data[i] = 4
				elif anim_name in ["Jump_F", "Jump_B", "Jump_V"]:
					frame_data[i] = 5
				elif anim_name == "hit":
					frame_data[i] = 6
				elif anim_name == "knockfly":
					frame_data[i] = 7
		value = display_frames
		queue_redraw()
		update_frame_count_label(anim_name)
		print("Debug: Animation %s finished for %s, total frames=%d, display frames=%d, jump_frame_count=%d, is_airborne=%s" % [anim_name, target_player.name, total_anim_frames, display_frames, jump_frame_count, is_airborne])
