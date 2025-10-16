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
var frame_data: Array = []  # 儲存每幀的狀態（0=Startup, 1=Active, 2=Recovery, 3=Dash/Backdash, 4=Block, 5=Jump, 6=Hit, 7=Knockfly）
var total_frames: int = 180  # 總幀數（3秒 * 60 FPS）
var current_frame: int = 0
var is_tracking: bool = false
var was_active: bool = false  # 追蹤是否曾進入 Active 階段

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

func initialize(p1: Node, p2: Node):
	# 初始化玩家節點
	target_player = p1
	other_player = p2
	if target_player and target_player.has_node("AnimationTree"):
		animation_tree = target_player.get_node("AnimationTree")
		playback = animation_tree.get("parameters/playback") if animation_tree else null
		if playback and not animation_tree.animation_finished.is_connected(_on_animation_finished):
			animation_tree.animation_finished.connect(_on_animation_finished)
	if target_player and target_player.has_node("AnimationPlayer"):
		animation_player = target_player.get_node("AnimationPlayer")
	if target_player and target_player.has_node("Hitbox/HitShape"):
		hitbox_shape = target_player.get_node("Hitbox/HitShape")
	else:
		print("Warning: AnimationTree, playback, AnimationPlayer or Hitbox/HitShape not found for %s" % target_player.name)
	print("Debug: FrameBar initialized for %s, visible=%s" % [target_player.name if target_player else "null", visible])

func _process(delta):
	if not playback or not animation_player:
		return
	
	# 檢查當前動畫
	var anim_name = playback.get_current_node()
	print("Debug: Current anim for %s: %s, position: %s, hitbox shape=%s" % [target_player.name, anim_name, playback.get_current_play_position(), "null" if hitbox_shape == null or hitbox_shape.shape == null else "set"])
	
	# 監聽的動畫清單
	var tracked_animations = [
		"st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball",  # 攻擊動畫
		"Dash", "Backdash",  # Dash 動畫
		"block", "cr_block",  # 格擋動畫
		"Jump_F", "Jump_B", "Jump_V",  # 跳躍動畫
		"hit", "knockfly"  # 受擊和擊飛動畫
	]
	
	if anim_name in tracked_animations:
		# 檢查是否從跳躍動畫切換到跳躍攻擊
		var is_jump_to_attack = last_animation in ["Jump_F", "Jump_B", "Jump_V"] and anim_name in ["jump_mp", "jump_mk"]
		
		if (anim_name != last_animation or not is_tracking) and not is_jump_to_attack:
			# 新動畫開始或追蹤停止，重置進度條（除了跳躍到跳躍攻擊的情況）
			reset_frame_bar()
			current_animation = anim_name
			last_animation = anim_name
			is_tracking = true
			print("Debug: Tracking new animation %s for %s, was_active=%s, frame_data size=%d" % [anim_name, target_player.name, was_active, frame_data.size()])
		elif is_jump_to_attack:
			# 從跳躍到跳躍攻擊，保留 frame_data，不重置
			current_animation = anim_name
			last_animation = anim_name
			is_tracking = true
			was_active = false  # 重置攻擊狀態
			print("Debug: Transition from jump to attack %s for %s, keeping frame_data, size=%d" % [anim_name, target_player.name, frame_data.size()])
		
		# 計算當前幀
		var anim_position = playback.get_current_play_position()
		var anim_length = animation_player.get_animation(anim_name).length if animation_player.has_animation(anim_name) else 0.5
		current_frame = int(anim_position * 60)  # 轉換為幀數（60 FPS）
		
		# 確保不超過 180 幀
		if current_frame >= total_frames:
			current_frame = total_frames - 1
			is_tracking = false
		
		# 定義動畫階段
		var frame_state = 0  # 0=Startup, 1=Active, 2=Recovery, 3=Dash/Backdash, 4=Block, 5=Jump, 6=Hit, 7=Knockfly
		if anim_name in ["st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball"]:
			# 攻擊動畫邏輯
			if anim_name == "st_mp":
				if anim_position < 0.1333:  # 0-7 幀（0.1333秒）
					frame_state = 0  # Startup
				elif anim_position < 0.2:  # 8-11 幀（0.1333-0.2秒）
					frame_state = 1  # Active
					was_active = true
				else:  # 12-24 幀（0.2-0.4秒）
					frame_state = 2  # Recovery
			else:
				# 其他攻擊動畫
				if hitbox_shape and hitbox_shape.shape != null:
					frame_state = 1  # Active
					was_active = true
				elif was_active:
					frame_state = 2  # Recovery
				elif current_frame >= int(anim_length * 60):
					frame_state = 2  # Recovery
				else:
					frame_state = 0  # Startup
		elif anim_name in ["Dash", "Backdash"]:
			frame_state = 3  # Dash/Backdash（淺紅色）
		elif anim_name in ["block", "cr_block"]:
			frame_state = 4  # Block（綠色）
		elif anim_name in ["Jump_F", "Jump_B", "Jump_V"]:
			frame_state = 5  # Jump（粉紫色）
		elif anim_name == "hit":
			frame_state = 6  # Hit（橙色）
		elif anim_name == "knockfly":
			frame_state = 7  # Knockfly（紫色）
		
		# 儲存當前幀狀態
		if frame_data.size() <= current_frame:
			frame_data.resize(current_frame + 1)
		frame_data[current_frame] = frame_state
		
		# 更新進度條值
		value = current_frame + 1
		queue_redraw()  # 觸發自定義繪製
		print("Debug: FrameBar updated for %s, frame=%d, value=%d, state=%d, was_active=%s" % [target_player.name, current_frame, value, frame_state, was_active])
	else:
		# 非監聽動畫，保持當前進度條狀態（不重置）
		if is_tracking:
			is_tracking = false
			print("Debug: Stopped tracking for %s, animation=%s, keeping frame bar" % [target_player.name, anim_name])

func _draw():
	# 自定義繪製進度條，顯示不同顏色
	var bar_width = size.x
	var bar_height = size.y
	var frame_width = bar_width / float(total_frames)
	
	# 繪製每幀的顏色
	for i in range(min(frame_data.size(), total_frames)):
		var color = Color.BLACK
		match frame_data[i]:
			0:  # Startup
				color = Color.BLUE
			1:  # Active
				color = Color.RED
			2:  # Recovery
				color = Color.YELLOW
			3:  # Dash/Backdash
				color = Color.PINK
			4:  # Block
				color = Color.GREEN
			5:  # Jump
				color = Color(1.0, 0.5, 1.0)  # 粉紫色
			6:  # Hit
				color = Color.ORANGE
			7:  # Knockfly
				color = Color.PURPLE
		var rect = Rect2(i * frame_width, 0, frame_width, bar_height)
		draw_rect(rect, color, true)
	
	print("Debug: FrameBar redrawn for %s, frame_data size=%d, current_animation=%s" % [target_player.name, frame_data.size(), current_animation])

func reset_frame_bar():
	# 重置進度條
	value = 0
	current_frame = 0
	frame_data.clear()
	is_tracking = true
	was_active = false  # 重置 Active 狀態
	queue_redraw()
	print("Debug: FrameBar reset for %s, was_active=%s" % [target_player.name, was_active])

func _on_animation_finished(anim_name: String):
	var tracked_animations = [
		"st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball",
		"Dash", "Backdash", "block", "cr_block", "Jump_F", "Jump_B", "Jump_V",
		"hit", "knockfly"
	]
	if anim_name in tracked_animations:
		# 動畫結束，停止追蹤但保留進度條
		is_tracking = false
		var anim_length = animation_player.get_animation(anim_name).length if animation_player.has_animation(anim_name) else 0.5
		var total_anim_frames = int(anim_length * 60)
		if total_anim_frames > current_frame:
			for i in range(current_frame + 1, min(total_anim_frames, total_frames)):
				if frame_data.size() <= i:
					frame_data.resize(i + 1)
				# 為非攻擊動畫保持對應狀態
				if anim_name in ["st_mp", "st_mk", "jump_mp", "jump_mk", "powerkk", "spnk", "fireball"]:
					frame_data[i] = 2  # Recovery
				elif anim_name in ["Dash", "Backdash"]:
					frame_data[i] = 3  # Dash/Backdash
				elif anim_name in ["block", "cr_block"]:
					frame_data[i] = 4  # Block
				elif anim_name in ["Jump_F", "Jump_B", "Jump_V"]:
					frame_data[i] = 5  # Jump
				elif anim_name == "hit":
					frame_data[i] = 6  # Hitr
				elif anim_name == "knockfly":
					frame_data[i] = 7  # Knockfly
			value = min(total_anim_frames, total_frames)
			queue_redraw()
		print("Debug: Animation %s finished for %s, total frames=%d" % [anim_name, target_player.name, value])
