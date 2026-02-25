extends ProgressBar

const DISPLAY_FPS: int = 60
@export var startup_logs: bool = false

# ── 變數宣告 ─────────────────────
var target_player: Node = null      # 要追蹤的玩家（FrameBar 所屬玩家）
var opponent_player: Node = null    # 對手玩家（未來若需要對比用，目前可留空）
var animation_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var animation_player: AnimationPlayer = null
var hitbox_shape: CollisionShape2D = null
var display_frame_counter: int = 0

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

# 用來穩定追蹤 blockstun 的連續幀計數器
var blockstun_active_frames: int = 0

# ── 除錯用變數（hit / block 幀數追蹤） ─────────────────────
var _last_hitstun_frames: int = 0
var _hitstun_start_logged: bool = false
var _initial_hitstun_frames: int = 0  # 🟢 【新增】記錄初始 hitstun 值
var _last_block_timer: float = 0.0
var _blockstun_start_logged: bool = false

# 🟢 【新增】Hit stop 追蹤變數
var _is_in_hitstop: bool = false
var _hitstop_paused_counter: int = 0  # Hit stop 期間暫停的幀數
var _last_hitstop_state: bool = false

# 🟢 【新增】物理幀追蹤（防止 display_frame_counter 在每個渲染幀都遞增）
var _last_physics_frame: int = 0

# 🟢 【新增】Fireball Startup/Active 追蹤
var fireball_tracking_active: bool = false           # 是否正在追蹤 fireball
var fireball_call_method_triggered: bool = false    # Call method 是否已觸發
var fireball_startup_frame_count: int = 0           # Startup 的幀計數（call method 觸發時的 frame index）

var last_physics_frame_for_jump: int = 0  # 用來追蹤jump的物理幀

# 🟢 【新增】攻擊動畫完成追蹤（防止多餘幀遞增）
var animation_finished_locking: bool = false  # 防止動畫完成後再遞增幀數

# 🟢 【新增】Hit/Block/Knockfly 預期幀數追蹤（防止 display_frame_counter 溢出）
var expected_stun_frames: int = 0  # 預期的受擊/格擋幀數（邏輯幀）

# 🟢 【新增】攻擊動畫幀數追蹤（用於限制 display_frame_counter）
var current_attack_anim_name: String = ""           # 當前攻擊動畫名稱
var current_attack_expected_frames: int = 0         # 當前攻擊動畫的預期幀數（@60FPS）

# 常數表
const TRACKED_ANIMS := [
	# Standing attacks
	"st_lp","st_mp","st_hp","st_lk","st_mk","st_hk",
	# Crouching attacks
	"cr_lp","cr_mp","cr_hp","cr_lk","cr_mk","cr_hk",
	# Jump attacks
	"jump_lp","jump_mp","jump_hp","jump_lk","jump_mk","jump_hk",
	# Special moves
	"powerkk","spnk","fireball","dpL","dpM","dpH","super",
	# Movement
	"Dash","Backdash","block","cr_block",
	"Jump_F","Jump_B","Jump_V","hit","knockfly","layground","wakeup"
]
const ATTACK_ANIMS := [
	# Standing attacks
	"st_lp","st_mp","st_hp","st_lk","st_mk","st_hk",
	# Crouching attacks
	"cr_lp","cr_mp","cr_hp","cr_lk","cr_mk","cr_hk",
	# Jump attacks
	"jump_lp","jump_mp","jump_hp","jump_lk","jump_mk","jump_hk",
	# Special moves
	"powerkk","spnk","fireball","dpL","dpM","dpH","super"
]
const JUMP_ANIMS := ["Jump_F","Jump_B","Jump_V"]

@onready var frame_count_label: Label = $FrameCountLabel

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
	add_theme_stylebox_override("fill", StyleBoxFlat.new())
	visible = true
	
	if frame_count_label:
		frame_count_label.text = "Initializing..."
	else:
		push_error("FrameCountLabel not found!")

# 修改：只傳入要追蹤的目標玩家（對手可選傳入，未來擴充用）
func initialize(target: Node, opponent: Node = null) -> void:
	target_player = target
	opponent_player = opponent
	
	animation_tree = target.get_node("AnimationTree")
	playback = animation_tree.get("parameters/playback") if animation_tree else null
	animation_player = target.get_node("AnimationPlayer")
	hitbox_shape = target.get_node("Hitbox/HitShape")
	
	# 🟢 【新增】註冊到 group，讓 Player 可以找到這個 FrameBar
	if target.has_meta("player_seat"):
		var seat = target.get_meta("player_seat")
		add_to_group("frame_bar_" + seat)
		if startup_logs:
			print("[FRAMEBAR] 已註冊到 group: frame_bar_%s" % seat)
	
	if playback and not animation_tree.animation_finished.is_connected(_on_animation_finished):
		animation_tree.animation_finished.connect(_on_animation_finished)

# ── 主循環 ─────────────────────
func _process(delta: float) -> void:
	if not playback or not animation_player or not target_player or not hitbox_shape:
		return
	
	# 🟢 【新增】檢查是否在 hit stop 期間
	var world = get_tree().get_first_node_in_group("world")
	var slowmo_controller = world.get_node_or_null("SlowMoController") if world else null
	_is_in_hitstop = slowmo_controller and slowmo_controller.is_hit_slowmo
	
	# 🟢 【新增】Hit stop 狀態變化檢測與調試
	if _is_in_hitstop and not _last_hitstop_state:
		print("[FRAMEBAR] %s - Hit stop 開始，暫停幀數計算" % target_player.name)
		_last_hitstop_state = true
	elif not _is_in_hitstop and _last_hitstop_state:
		print("[FRAMEBAR] %s - Hit stop 結束，恢復幀數計算（暫停了 %d 次更新）" % [
			target_player.name, _hitstop_paused_counter
		])
		_hitstop_paused_counter = 0
		_last_hitstop_state = false
	
	# 🟢 【修正】Hit stop 期間跳過幀數更新，但仍保持視覺更新
	if _is_in_hitstop:
		_hitstop_paused_counter += 1
		# 保持 UI 更新但不計數新幀
		queue_redraw()
		return
	
	# ── 除錯：hitstun（固定幀數）追蹤 ─────────────────────
	if target_player.has_method("is_in_hitstun"):
		var cur_frames = target_player.hitstun_frames if "hitstun_frames" in target_player else 0
		if cur_frames > 0 and not _hitstun_start_logged:
			_initial_hitstun_frames = cur_frames  # 🟢 【新增】記錄初始值
			var display_frames: int = int(round(cur_frames / 2.0))
			var real_seconds: float = cur_frames / float(Engine.physics_ticks_per_second)
			print("[HITSTUN] %s 進入 hitstun → %d 物理幀 (%d 顯示幀 / %.3f秒)" % [
				target_player.name, cur_frames, display_frames, real_seconds
			])
			_hitstun_start_logged = true
		elif cur_frames <= 0 and _hitstun_start_logged:
			# 🟢 【修正】使用初始值計算總耗時
			var hitstun_total_frames = _initial_hitstun_frames
			var display_frames: int = int(round(hitstun_total_frames / 2.0))
			var real_seconds: float = hitstun_total_frames / float(Engine.physics_ticks_per_second)
			print("[HITSTUN] %s hitstun 結束，共 %d 物理幀 (%d 顯示幀 / %.3f秒)" % [
				target_player.name, hitstun_total_frames, display_frames, real_seconds
			])
			_hitstun_start_logged = false
		_last_hitstun_frames = cur_frames
	
	# ── 除錯：blockstun（舊版 timer）追蹤 ─────────────────────
	if "block_timer" in target_player:
		var cur_timer = target_player.block_timer
		if cur_timer > 0 and not _blockstun_start_logged:
			print("[BLOCKSTUN] %s 進入 blockstun → %.3f秒 (約 %d 幀)" % [
				target_player.name, cur_timer, int(cur_timer * Engine.physics_ticks_per_second)
			])
			_blockstun_start_logged = true
		elif cur_timer <= 0 and _blockstun_start_logged:
			print("[BLOCKSTUN] %s blockstun 結束" % target_player.name)
			_blockstun_start_logged = false
		_last_block_timer = cur_timer
	
	var flags := _get_player_flags()
	var timer_driven: bool = flags.blocking or flags.hit or flags.knockfly or \
							flags.layground or flags.wakeup or \
							current_animation in ["block", "cr_block"]
	
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
			# 🟢 【修改】不清空資料，只停止追蹤，保持顯示
			is_tracking = false

# ── 核心邏輯 ─────────────────────
func _process_tracked(anim_name: String, pos: float, flags: Dictionary, timer_driven: bool, on_floor: bool) -> void:
	# Jump attacks: all jump punch/kick variations
	const JUMP_ATTACK_ANIMS := ["jump_lp","jump_mp","jump_hp","jump_lk","jump_mk","jump_hk"]
	var jump_to_attack := last_animation in JUMP_ANIMS and anim_name in JUMP_ATTACK_ANIMS
	var knockfly_chain := knockfly_chain_active and anim_name in ["knockfly","layground","wakeup"]
	
	if anim_name == "knockfly" and not knockfly_chain_active:
		knockfly_chain_active = true
		display_frame_counter = 0
		history_frame_data.clear()
		frame_data.clear()
		current_frame = 0
		is_tracking = true
	
	# 🟢 【新增】當進入 "hit" 動畫時，重置 display_frame_counter 並記錄預期幀數
	if anim_name == "hit" and last_animation != "hit" and timer_driven:
		display_frame_counter = 0
		last_animation = "hit"  # 🔴 【關鍵】更新 last_animation，防止每幀都重置
		
		# 🟢 【新增】記錄預期的 hitstun 幀數（邏輯幀）用於防護
		if "hitstun_frames" in target_player:
			var hitstun_physics_frames = target_player.hitstun_frames
			expected_stun_frames = int(hitstun_physics_frames / 2.0)  # 轉換為邏輯幀
			print("[FRAMEBAR] %s - 進入 hit 動畫，重置 display_frame_counter，預期 hitstun: %d 邏輯幀 (%d 物理幀)" % [
				target_player.name, expected_stun_frames, hitstun_physics_frames
			])
		else:
			expected_stun_frames = 0
			print("[FRAMEBAR] %s - 進入 hit 動畫，重置 display_frame_counter 為 0" % target_player.name)
	
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
		# 🟢 【修改】只在物理幀更新時增加 jump_frame_count（而非每個渲染幀）
		var current_physics_frame: int = Engine.get_physics_frames()
		if current_physics_frame != last_physics_frame_for_jump:
			jump_frame_count += 1
			last_physics_frame_for_jump = current_physics_frame
	
	if anim_name in ["block", "cr_block"]:
		blockstun_active_frames += 1
	else:
		blockstun_active_frames = 0
	
	current_frame = _calc_frame(anim_name, pos, timer_driven, knockfly_chain)
	# 🟢 【修正】current_frame 現在是 1-indexed；資料寫入 frame_data[current_frame - 1]
	_ensure_size(current_frame)
	
	var state := _get_state(anim_name, flags, on_floor, pos)
	if state != -1:
		frame_data[current_frame - 1] = state
	
	# 🟢 【除錯】每幀記錄 FrameBar 狀態（攻擊動畫 / timer 驅動）
	if anim_name in ATTACK_ANIMS or timer_driven:
		const STATE_NAMES := {0: "S(Startup)", 1: "A(Active)", 2: "R(Recovery)",
			4: "B(Block)", 5: "J(Jump)", 6: "H(Hit)", 7: "K(Knockfly)",
			8: "W(White)", 9: "L(Layground)", 10: "WK(Wakeup)"}
		var state_label: String = STATE_NAMES.get(state, "?("+str(state)+")")
		var raw_pos_frame: int = int(pos * DISPLAY_FPS)
		print("[FRAMEBAR RECORD] %s | anim='%s' pos=%.4f raw_pos_frame=%d → current_frame=%d state=%s | frame_data.size=%d" % [
			target_player.name, anim_name, pos, raw_pos_frame, current_frame, state_label, frame_data.size()
		])
	
	if timer_driven or knockfly_chain or block_hit_chain_active:
		# 🟢 【修正】只在每個物理幀增加一次 display_frame_counter（防止渲染幀率導致快速遞增）
		# 🟢 【新增】檢查動畫是否已完成，完成後停止遞增（防止多餘幀）
		var current_physics_frame: int = Engine.get_physics_frames()
		if current_physics_frame != _last_physics_frame and not animation_finished_locking:
			var old_counter = display_frame_counter  # 🟢 【修改】提前聲明 old_counter
			
			# 🟢 【防護】檢查是否已達到預期的幀數上限
			var should_increment = true
			
			# 如果是 hit 動畫且有預期幀數，檢查是否已達到上限
			if anim_name == "hit" and expected_stun_frames > 0:
				var max_display_frames = expected_stun_frames * 2  # expected_stun_frames @60FPS = × 2 @120FPS
				if display_frame_counter >= max_display_frames:
					should_increment = false
					# ...debug print removed...
			
			# 如果是攻擊動畫且有預期幀數，檢查是否已達到上限
			elif current_attack_anim_name in ATTACK_ANIMS and current_attack_expected_frames > 0:
				var max_display_frames = current_attack_expected_frames * 2
				if display_frame_counter >= max_display_frames:
					should_increment = false
			
			if should_increment:
				display_frame_counter += 1
				_last_physics_frame = current_physics_frame
			
			# 🟢 【新增】調試信息：重要的幀數遞增（僅在關鍵狀態變化時輸出）
			if old_counter == 0 or (flags.hit and old_counter % 10 == 0) or (flags.blocking and old_counter % 10 == 0):
				print("[FRAMEBAR COUNTER] %s - display_frame_counter: %d → %d (anim: %s, state: %d, timer_driven: %s)" % [
					target_player.name, old_counter, display_frame_counter, anim_name, state, timer_driven
				])
	
	# 🟢 【修正】current_frame 已是 1-indexed，不需再 +1
	value = min(current_frame, total_frames)
	queue_redraw()
	update_frame_count_label(anim_name)

# ── 輔助函式 ─────────────────────
func _get_player_flags() -> Dictionary:
	return {
		blocking = "is_blocking" in target_player and target_player.is_blocking,
		hit = ("is_hit" in target_player and target_player.is_hit) or \
			  (target_player.has_method("is_in_hitstun") and target_player.is_in_hitstun()),
		knockfly = "is_knockfly" in target_player and target_player.is_knockfly,
		layground = "is_layground" in target_player and target_player.is_layground,
		wakeup = "is_wakeup_locked" in target_player and target_player.is_wakeup_locked
	}

func _update_airborne(anim_name: String, on_floor: bool) -> void:
	if anim_name in JUMP_ANIMS and not is_airborne:
		is_airborne = true
		jump_frame_count = 0
		last_physics_frame_for_jump = Engine.get_physics_frames()
	if is_airborne and (on_floor or anim_name == "landing"):
		is_airborne = false
		# 🟢 【修改】著陸時不清空 is_tracking，讓跳躍顯示保持
		# is_tracking = false

func _ensure_size(min_size: int) -> void:
	if frame_data.size() < min_size:
		frame_data.resize(min_size)

func _calc_frame(anim_name: String, pos: float, timer_driven: bool, knockfly_chain: bool) -> int:
	# 🟢 【修正】所有分支加 +1，使 current_frame 改為 1-indexed（動畫第0格 → 顯示第1格）
	if timer_driven or knockfly_chain or block_hit_chain_active:
		return int(display_frame_counter / 2.0) + 1
	if is_jump_attack_active:
		return min(jump_to_attack_offset + int(pos * DISPLAY_FPS) + 1, total_frames)
	# 🟢 【修改】跳躍使用 jump_frame_count（已按物理幀計算）
	if anim_name in JUMP_ANIMS:
		return int(jump_frame_count / 2.0) + 1  # 按60FPS轉換幀
	return min(int(pos * DISPLAY_FPS) + 1, total_frames)

func _get_state(anim_name: String, flags: Dictionary, on_floor: bool, pos: float) -> int:
	if anim_name in ["block", "cr_block"] and blockstun_active_frames > 0:
		return 4
	if flags.blocking: return 4
	if flags.hit: return 6
	if flags.knockfly: return 7
	if flags.layground: return 9
	if flags.wakeup: return 10
	
	# 🟢 【新增】Fireball 特殊處理 - 區分 startup 和 active
	# 只有在主動追蹤 fireball 時才更新狀態
	if anim_name == "fireball" and fireball_tracking_active:
		if not fireball_call_method_triggered:
			# Call method 尚未觸發，全部是 startup（藍色）
			return 0
		elif current_frame <= fireball_startup_frame_count:
			# Startup 階段（call method 前）- 使用藍色（0）
			return 0
		else:
			# Active 階段（call method 後）- 使用紅色（1）
			return 1
	
	# 🟢 【修正】DP (dpL/dpM/dpH) 只依據 hitshape disabled 軌道來判定 S/A/R
	if anim_name in ["dpL", "dpM", "dpH"]:
		var track_state := _get_attack_state_from_hitbox_track(anim_name, pos)
		if track_state != -1:
			return track_state

	if anim_name in ATTACK_ANIMS:
		# 🟢 【修正】只檢查 hitbox_shape 是否存在且 enabled，不檢查 shape 屬性
		if not hitbox_shape or hitbox_shape.disabled:
			return 0 if not was_active else 2
		else:
			if not was_active:
				was_active = true
				for i in range(frame_data.size()):
					if frame_data[i] == -1:
						frame_data[i] = 0
			return 1
	
	if anim_name in ["Dash","Backdash"]: return 3
	if anim_name in JUMP_ANIMS: return 5
	if anim_name == "hit": return 6
	if anim_name == "knockfly": return 7
	if anim_name == "layground": return 9
	if anim_name == "wakeup": return 10
	return -1

func _get_attack_state_from_hitbox_track(anim_name: String, pos: float) -> int:
	if not animation_player:
		return -1
	var eval_pos = _get_anim_position(anim_name, pos)
	var anim = animation_player.get_animation(anim_name)
	if not anim:
		return -1
	var track_path := NodePath("Hitbox/HitShape:disabled")
	var track_idx = anim.find_track(track_path, Animation.TYPE_VALUE)
	if track_idx == -1:
		return -1
	var key_count = anim.track_get_key_count(track_idx)
	if key_count == 0:
		return -1
	var last_value = null
	var had_active = false
	for i in range(key_count):
		var key_time = anim.track_get_key_time(track_idx, i)
		if key_time > eval_pos:
			break
		var key_value = anim.track_get_key_value(track_idx, i)
		last_value = key_value
		if key_value == false:
			had_active = true
	if last_value == null:
		return -1
	if last_value == false:
		return 1  # Active
	return 2 if had_active else 0

func _get_anim_position(anim_name: String, fallback_pos: float) -> float:
	if animation_player and animation_player.current_animation == anim_name:
		return animation_player.current_animation_position
	return fallback_pos

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
	display_frame_counter = 0
	was_active = false
	is_tracking = true
	reset_delay_timer = 0.0
	white_frames_added = 0
	buffer_start_frame = 0
	blockstun_active_frames = 0

func _start_new_animation(anim_name: String) -> void:
	was_active = false
	# 🟢 【修改】只有在明確不同的動畫(非延續狀態)時才清空舊資料
	# 這樣可以讓完成的狀態顯示保持，直到下一個新狀態開始
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
		# 🟢 【修改】保存前一個狀態到歷史，而不是直接清空
		if frame_data.size() > 0 and anim_name in ATTACK_ANIMS:
			print("[FRAMEBAR NEW ANIM] %s - saving old '%s' to history | frame_data.size()=%d" % [target_player.name, last_animation, frame_data.size()])
		
		if frame_data.size() > 0:
			history_frame_data.clear()
			history_frame_data.append_array(frame_data)
		
		frame_data.clear()
		current_frame = 0
		reset_delay_timer = 0.0
		white_frames_added = 0
		buffer_start_frame = 0
		display_frame_counter = 0  # 🟢 【新增】重置display_frame_counter
		animation_finished_locking = false  # 🟢 【新增】解鎖，允許新動畫遞增幀數
		expected_stun_frames = 0  # 🟢 【新增】重置預期幀數
		if not is_airborne:
			jump_frame_count = 0
		
		# 🟢 【新增】如果開始新攻擊動畫，記錄預期幀數
		if anim_name in ATTACK_ANIMS and "animation_player" in target_player:
			current_attack_anim_name = anim_name
			if target_player.animation_player.has_animation(anim_name):
				var anim_length = target_player.animation_player.get_animation(anim_name).length
				current_attack_expected_frames = int(round(anim_length * 60))
				print("[FRAMEBAR NEW ANIM START] %s - starting '%s' animation | expected: %dF | display_frame_counter reset to 0" % [target_player.name, anim_name, current_attack_expected_frames])
			else:
				current_attack_expected_frames = 0
		else:
			current_attack_anim_name = ""
			current_attack_expected_frames = 0
	
	# 🟢 【修改】開始新動畫時重置追蹤狀態
	if anim_name == "fireball":
		fireball_tracking_active = true
		fireball_call_method_triggered = false
		fireball_startup_frame_count = 0
		print("[FRAMEBAR] %s - 開始追蹤 fireball 動畫，舊資料已保存到歷史" % target_player.name)
	else:
		# 當離開 fireball 動畫時，停止追蹤但保持顯示
		if fireball_tracking_active and anim_name != last_animation:
			print("[FRAMEBAR] %s - 結束 fireball 追蹤 (Startup:%d)，進度條將保持顯示" % [
				target_player.name, fireball_startup_frame_count
			])
			fireball_tracking_active = false
			fireball_call_method_triggered = false
	
	current_animation = anim_name
	last_animation = anim_name
	is_tracking = true
	is_jump_attack_active = false
	jump_to_attack_offset = 0
	last_finished_animation = ""
	blockstun_active_frames = 0

# ── 繪製 ─────────────────────
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
	# 🟢 【修改】保持顯示舊資料，不清空。新動畫會自動清空
	is_tracking = false
	was_active = false
	# 只重置跟蹤狀態，不清空 frame_data
	# value = 0
	# current_frame = 0
	# frame_data.clear()
	queue_redraw()

# 🟢 【新增】Call method 觸發回調（由 Player._spawn_fireball() 調用）
func on_fireball_call_method_triggered() -> void:
	if fireball_tracking_active and not fireball_call_method_triggered:
		fireball_call_method_triggered = true
		fireball_startup_frame_count = current_frame
		print("[FRAMEBAR FIREBALL] %s - Call method 已觸發！Startup 幀數: %d" % [
			target_player.name, fireball_startup_frame_count
		])

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
	# 🟢 【新增】Hit 動畫特殊顯示 - 限制顯示幀數
	elif anim_name == "hit" and expected_stun_frames > 0:
		var display_frames = min(frame_data.size(), expected_stun_frames)
		text += "H:%dF (hitstun: %dF)" % [display_frames, expected_stun_frames]
	# 🟢 【新增】Fireball 特殊顯示 - 展示 S(startup) A(active) R(recovery)
	elif anim_name == "fireball":
		if fireball_call_method_triggered and fireball_startup_frame_count > 0:
			# Call method 已觸發，計算 startup/active/recovery
			var startup_frames = fireball_startup_frame_count
			var total_animated = frame_data.size()
			var active_frames = total_animated - startup_frames
			var recovery_frames = 0  # 由於 active 很短，recovery 就是剩下的
			
			text += "S:%d A:%d R:%d Total:%dF" % [startup_frames, active_frames, recovery_frames, total_animated]
		else:
			# Call method 尚未觸發
			text += "S:0 A:%d R:0 (等待 call method...)" % frame_data.size()
	elif anim_name in ATTACK_ANIMS:
		# 🟢 【修正】S 顯示值 = counts.S + 1（當有 Active 幀時）
		# 原因：frame_data 是 0-indexed，但顯示是 1-indexed。
		# "4F startup" 的格鬥遊戲慣例 = 第一個 Active 幀在顯示第4格。
		# counts.S = 3 個 Startup 格（0-indexed），加 1 = 4（1-indexed Active 起始幀號）
		var s_display = counts.S + (1 if counts.A > 0 else 0)
		# 🟢 【修正】Total 優先使用動畫預期幀數，避免因最後一個渲染幀未被捕捉而少一格
		var display_frames: int
		if current_attack_expected_frames > 0:
			display_frames = current_attack_expected_frames
		else:
			display_frames = frame_data.size()
		text += "S:%d A:%d R:%d Total:%dF" % [s_display, counts.A, counts.R, display_frames]
	else:
		text += "%dF" % frame_data.size()
	frame_count_label.text = text

# ── 動畫結束 ─────────────────────
func _on_animation_finished(anim_name: String) -> void:
	if anim_name == last_finished_animation or anim_name not in TRACKED_ANIMS:
		return
	last_finished_animation = anim_name
	
	if anim_name in ATTACK_ANIMS:
		was_active = false
		# 🟢 【新增】加鎖防止動畫完成後記錄多餘的幀
		animation_finished_locking = true
		# 保持顯示，直到下一個新狀態開始
		print("[FRAMEBAR ATTACK FINISH] %s - animation '%s' finished | display_frame_counter=%d (@120FPS) → %dF (@60FPS) | frame_data.size()=%d" % [
			target_player.name, anim_name, display_frame_counter, int(display_frame_counter / 2.0), frame_data.size()
		])
		if "attack_duration_timer" in target_player:
			print("[FRAMEBAR ATTACK FINISH DETAIL] attack_duration_timer: %d | Expected: %d" % [
				target_player.attack_duration_timer, display_frame_counter
			])
	
	if anim_name == "wakeup" and knockfly_chain_active:
		knockfly_chain_completed = true
		knockfly_total_frames = frame_data.size()
		for s in frame_data:
			if s == 7: knockfly_knockfly_frames += 1
			elif s == 9: knockfly_layground_frames += 1
			elif s == 10: knockfly_wakeup_frames += 1
		knockfly_chain_active = false
	
	update_frame_count_label(anim_name)
	queue_redraw()
