extends ProgressBar
const DISPLAY_FPS: int = 60
# ── 變數宣告 ─────────────────────
var target_player: Node = null
var animation_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var animation_player: AnimationPlayer = null
var hitbox_shape: CollisionShape2D = null

var current_animation: String = ""
var last_animation: String = ""
var last_finished_animation: String = ""

var frame_data: Array[int] = []
var history_frame_data: Array[int] = []
var total_frames: int = 150
var current_frame: int = 0
var is_tracking: bool = false
var was_active: bool = false

var jump_frame_count: int = 0
var jump_to_attack_offset: int = 0
var is_jump_attack_active: bool = false
var is_airborne: bool = false

var reset_delay_timer: float = 0.0
var buffer_start_frame: int = 0
var white_frames_added: int = 0

# Knockfly 鏈
var knockfly_chain_active: bool = false
var knockfly_chain_completed: bool = false
var knockfly_total_frames: int = 0
var knockfly_knockfly_frames: int = 0
var knockfly_layground_frames: int = 0
var knockfly_wakeup_frames: int = 0

# Block/Hit 連續鏈
var block_hit_chain_active: bool = false
var block_hit_chain_type: int = -1  # 4=Block, 6=Hit

# 【新增】用來穩定追蹤 blockstun 的連續幀計數器
var blockstun_active_frames: int = 0

# 常數表
const TRACKED_ANIMS := [
	"st_mp","st_mk","jump_mp","jump_mk","powerkk","spnk","fireball","dp","super",
	"Dash","Backdash","block","cr_block",
	"Jump_F","Jump_B","Jump_V","hit","knockfly","layground","wakeup"
]
const ATTACK_ANIMS := ["st_mp","st_mk","jump_mp","jump_mk","powerkk","spnk","fireball","dp","super"]
const JUMP_ANIMS := ["Jump_F","Jump_B","Jump_V"]

@onready var frame_count_label: Label = $FrameCountLabel

# ── 初始化（Godot 4.5 正確寫法）─────────────────────
func _ready() -> void:
	max_value = total_frames
	value = 0
	
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.BLACK
	bg.border_color = Color.WHITE
	bg.border_width_left   = 2
	bg.border_width_right  = 2
	bg.border_width_top    = 2
	bg.border_width_bottom = 2
	
	add_theme_stylebox_override("background", bg)
	add_theme_stylebox_override("fill", StyleBoxFlat.new())  # 清空預設填滿
	visible = true
	
	if frame_count_label:
		frame_count_label.text = "Initializing..."
	else:
		push_error("FrameCountLabel not found!")

func initialize(p1: Node, _p2: Node) -> void:
	target_player = p1
	animation_tree = p1.get_node("AnimationTree")
	playback = animation_tree.get("parameters/playback") if animation_tree else null
	animation_player = p1.get_node("AnimationPlayer")
	hitbox_shape = p1.get_node("Hitbox/HitShape")
	
	if playback and not animation_tree.animation_finished.is_connected(_on_animation_finished):
		animation_tree.animation_finished.connect(_on_animation_finished)

# ── 主循環 ─────────────────────
func _process(delta: float) -> void:
	if not playback or not animation_player or not target_player or not hitbox_shape:
		return
	
	var flags := _get_player_flags()
	
	# 擴大 timer_driven 範圍：包含 block 動畫本身，確保全程使用逐幀計數
	var timer_driven: bool = flags.blocking or flags.hit or flags.knockfly or \
							flags.layground or flags.wakeup or \
							current_animation in ["block", "cr_block"]
	
	# Buffer 窗口
	if reset_delay_timer > 0:
		reset_delay_timer -= delta
		current_frame = buffer_start_frame + white_frames_added
		white_frames_added += 1
		_ensure_size(current_frame + 1)
		frame_data[current_frame] = 8
		value = min(current_frame + 1, total_frames)
		queue_redraw()
		if reset_delay_timer <= 0:
			reset_delay_timer = 0.0
	
	var anim_name := playback.get_current_node()
	var pos := playback.get_current_play_position()
	var on_floor: bool = target_player.is_on_floor() if target_player.has_method("is_on_floor") else false
	
	_update_airborne(anim_name, on_floor)
	
	if anim_name in TRACKED_ANIMS or timer_driven:
		_process_tracked(anim_name, pos, flags, timer_driven, on_floor)
	else:
		if is_tracking:
			reset_frame_bar()

# ── 核心邏輯 ─────────────────────
func _process_tracked(anim_name: String, pos: float, flags: Dictionary, timer_driven: bool, on_floor: bool) -> void:
	var jump_to_attack := last_animation in JUMP_ANIMS and anim_name in ["jump_mp","jump_mk"]
	var knockfly_chain := knockfly_chain_active and anim_name in ["knockfly","layground","wakeup"]
	
	if anim_name == "knockfly" and not knockfly_chain_active:
		knockfly_chain_active = true
	
	_handle_block_hit_chain(flags)
	
	var need_new := (anim_name != last_animation or not is_tracking) and \
					not jump_to_attack and not knockfly_chain and not block_hit_chain_active
	
	if need_new:
		_start_new_animation(anim_name)
	elif knockfly_chain or jump_to_attack:
		current_animation = anim_name
		last_animation = anim_name
		is_tracking = true
		if jump_to_attack and jump_to_attack_offset == 0:
			jump_to_attack_offset = frame_data.size()
	
	if is_airborne:
		jump_frame_count += 1
	
	# 【關鍵】更新 blockstun 持續計數器
	if anim_name in ["block", "cr_block"]:
		blockstun_active_frames += 1
	else:
		blockstun_active_frames = 0
	
	current_frame = _calc_frame(anim_name, pos, timer_driven, knockfly_chain)
	_ensure_size(current_frame + 1)
	
	var state := _get_state(anim_name, flags, on_floor)
	if state != -1:
		frame_data[current_frame] = state
		value = min(current_frame + 1, total_frames)
		queue_redraw()
		update_frame_count_label(anim_name)

# ── 輔助函式 ─────────────────────
func _get_player_flags() -> Dictionary:
	return {
		blocking = target_player.is_blocking if target_player.has_signal("is_blocking") else false,
		hit = ("is_hit" in target_player and target_player.is_hit) or \
	 (target_player.has_method("is_in_hitstun") and target_player.is_in_hitstun()),
		knockfly = target_player.is_knockfly if "is_knockfly" in target_player else false,
		layground = target_player.is_layground if "is_layground" in target_player else false,
		wakeup = target_player.is_wakeup_locked if "is_wakeup_locked" in target_player else false
	}

func _update_airborne(anim_name: String, on_floor: bool) -> void:
	if anim_name in JUMP_ANIMS and not is_airborne:
		is_airborne = true
		jump_frame_count = 0
	if is_airborne and (on_floor or anim_name == "landing"):
		is_airborne = false
		is_tracking = false

func _ensure_size(size: int) -> void:
	if frame_data.size() < size:
		frame_data.resize(size)

func _calc_frame(anim_name: String, pos: float, timer_driven: bool, knockfly_chain: bool) -> int:
	if timer_driven or knockfly_chain or block_hit_chain_active:
		return frame_data.size()
	if is_jump_attack_active:
		return min(jump_to_attack_offset + int(pos * DISPLAY_FPS), total_frames - 1)
	if anim_name in JUMP_ANIMS:
		return jump_frame_count
	return min(int(pos * DISPLAY_FPS), total_frames - 1)

func _get_state(anim_name: String, flags: Dictionary, on_floor: bool) -> int:
	# 【核心修復】blockstun 優先用動畫 + 連續幀確認，絕對穩定
	if anim_name in ["block", "cr_block"] and blockstun_active_frames > 0:
		return 4
	if flags.blocking:
		return 4
	if flags.hit:
		return 6
	if flags.knockfly:
		return 7
	if flags.layground:
		return 9
	if flags.wakeup:
		return 10
	
	if anim_name in ATTACK_ANIMS:
		if hitbox_shape.disabled or hitbox_shape.shape == null:
			return 0 if not was_active else 2
		was_active = true
		return 1
	if anim_name in ["Dash","Backdash"]:
		return 3
	if anim_name in JUMP_ANIMS:
		return 5
	if anim_name == "hit":
		return 6
	if anim_name == "knockfly":
		return 7
	if anim_name == "layground":
		return 9
	if anim_name == "wakeup":
		return 10
	if anim_name == "dp" and not on_floor:
		return 2
	return -1

func _handle_block_hit_chain(flags: Dictionary) -> void:
	var type := 4 if flags.blocking else (6 if flags.hit else -1)
	if type != -1:
		if not block_hit_chain_active or block_hit_chain_type != type:
			_start_new_block_hit_chain(type)
	else:
		block_hit_chain_active = false
		block_hit_chain_type = -1

func _start_new_block_hit_chain(type: int) -> void:
	block_hit_chain_active = true
	block_hit_chain_type = type
	history_frame_data.clear()
	frame_data.clear()
	current_frame = 0
	was_active = false
	is_tracking = true
	reset_delay_timer = 0.0
	white_frames_added = 0
	buffer_start_frame = 0
	blockstun_active_frames = 0  # 重置

func _start_new_animation(anim_name: String) -> void:
	was_active = false
	if reset_delay_timer > 0 and anim_name != last_finished_animation:
		var elapsed := 0.05 - reset_delay_timer
		var add: int = max(1, int(elapsed * 60))
		for _i in add:
			current_frame = buffer_start_frame + white_frames_added
			white_frames_added += 1
			_ensure_size(current_frame + 1)
			frame_data[current_frame] = 8
		reset_delay_timer = 0.0
	else:
		history_frame_data.clear()
		frame_data.clear()
		current_frame = 0
		reset_delay_timer = 0.0
		white_frames_added = 0
		buffer_start_frame = 0
		if not is_airborne:
			jump_frame_count = 0
	
	current_animation = anim_name
	last_animation = anim_name
	is_tracking = true
	is_jump_attack_active = false
	jump_to_attack_offset = 0
	last_finished_animation = ""
	blockstun_active_frames = 0  # 重置

# ── 繪製（Godot 4.5）─────────────────────
func _draw() -> void:
	var w := size.x / float(total_frames)
	draw_rect(Rect2(0, 0, size.x, size.y), Color.BLACK, true)
	
	for i in min(history_frame_data.size(), total_frames):
		_draw_frame(i, history_frame_data[i], w)
	for i in min(frame_data.size(), total_frames):
		_draw_frame(i, frame_data[i], w)

func _draw_frame(i: int, state: int, w: float) -> void:
	if state == -1: return
	const COLORS := [
		Color.BLUE, Color.RED, Color.YELLOW, Color.PINK, Color.GREEN,
		Color(1.0, 0.5, 1.0), Color.ORANGE, Color.PURPLE, Color.WHITE,
		Color(0.3, 0.3, 0.3), Color(0.7, 0.9, 1.0)
	]
	draw_rect(Rect2(i * w, 0, w, size.y), COLORS[state], true)

# ── 重置與 Label ─────────────────────
func reset_frame_bar() -> void:
	value = 0
	current_frame = 0
	if frame_data.size() > 0:
		history_frame_data.append_array(frame_data)
	frame_data.clear()
	is_tracking = true
	was_active = false
	jump_frame_count = 0 if not is_airborne else jump_frame_count
	jump_to_attack_offset = 0
	is_jump_attack_active = false
	knockfly_chain_active = false
	block_hit_chain_active = false
	blockstun_active_frames = 0  # 重置
	queue_redraw()

func update_frame_count_label(anim_name: String) -> void:
	if not frame_count_label: return
	
	var counts := {"S":0,"A":0,"R":0,"J":0,"H":0,"B":0,"K":0,"L":0,"W":0}
	for s in frame_data:
		if s == 8: continue
		match s:
			0: counts.S += 1
			1: counts.A += 1
			2: counts.R += 1
			5: counts.J += 1
			6: counts.H += 1
			4: counts.B += 1
			7: counts.K += 1
			9: counts.L += 1
			10: counts.W += 1
	
	var text := "%s: " % anim_name
	if knockfly_chain_completed:
		text += "K:%dF L:%dF W:%dF Total:%dF" % [counts.K, counts.L, counts.W, knockfly_total_frames]
	elif anim_name in ATTACK_ANIMS:
		text += "S:%d A:%d R:%d Total:%dF" % [counts.S, counts.A, counts.R, frame_data.size()]
	else:
		text += "%dF" % frame_data.size()
	frame_count_label.text = text

# ── 動畫結束 ─────────────────────
func _on_animation_finished(anim_name: String) -> void:
	if anim_name == last_finished_animation or anim_name not in TRACKED_ANIMS:
		return
	last_finished_animation = anim_name
	buffer_start_frame = frame_data.size()
	_ensure_size(frame_data.size() + 1)
	frame_data[frame_data.size() - 1] = 8
	queue_redraw()
	
	if anim_name == "wakeup" and knockfly_chain_active:
		knockfly_chain_completed = true
		knockfly_total_frames = frame_data.size()
		for s in frame_data:
			if s == 7: knockfly_knockfly_frames += 1
			elif s == 9: knockfly_layground_frames += 1
			elif s == 10: knockfly_wakeup_frames += 1
		knockfly_chain_active = false
	
	reset_delay_timer = 0.05
	var len := animation_player.get_animation(anim_name).length if animation_player.has_animation(anim_name) else 0.5
	var frames := int(len * DISPLAY_FPS)
	if anim_name in ["jump_mp","jump_mk"] and last_animation in JUMP_ANIMS:
		frames += jump_frame_count
	
	var fill := 2
	if anim_name in ["Dash","Backdash"]: fill = 3
	elif anim_name in ["block","cr_block"]: fill = 4
	elif anim_name in JUMP_ANIMS: fill = 5
	elif anim_name == "hit": fill = 6
	elif anim_name == "knockfly": fill = 7
	elif anim_name == "layground": fill = 9
	elif anim_name == "wakeup": fill = 10
	
	for i in range(current_frame + 1, min(frames, total_frames)):
		_ensure_size(i + 1)
		frame_data[i] = fill
	
	value = min(frames, total_frames)
	queue_redraw()
	update_frame_count_label(anim_name)
