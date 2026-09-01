@tool
class_name HitStopController
extends Node

## 専門 Hitstop 管理器。
##
## 這不是全域時間停止（Engine.time_scale = 0），而是「角色動畫與視覺解耦」：
## - 角色動畫由 AnimationTree（狀態機）驅動 AnimationPlayer 播放。Godot 官方文件
##   明載：AnimationTree 接管後，AnimationPlayer 自身的播放屬性（含 speed_scale）
##   不會生效 —— 因此真正用來定格的是把 AnimationTree 這個「節點」停止處理：
##   `AnimationTree.process_mode = PROCESS_MODE_DISABLED`。mixer 收不到
##   internal process 通知就不會推進動畫時間，姿勢原封不動停在最後套用的那一格；
##   `active` / `callback_mode_process` / 狀態機節點身分 / travel 目標 / 條件參數
##   全部保持不動，解凍時只要把 process_mode 放回去就能無縫續播。
##
##   【為什麼不用 callback_mode_process = MANUAL】（2026-09 攻擊者定格 BUG 根因）
##   Godot 的 `AnimationMixer::set_callback_mode_process()` 內部會做
##   `set_active(false)` → 改模式 → `set_active(true)`；而 `AnimationTree::_set_active()`
##   會把私有旗標 `started` 設為 true。下一次處理（就是我們的 advance(0)）時，
##   `_blend_pre_process()` 會以 `seeked = true, time = 0, is_external_seeking = false`
##   進入狀態機，命中 AnimationNodeStateMachinePlayback 的
##   「Check seek to 0 (means reset) by parent AnimationNode」分支 → `_start()` →
##   **整台狀態機被重啟回 Start 節點**。
##   受擊方剛好有 take_hit() 排好的 travel（hit / cr_hit / block），重啟後馬上被
##   travel 帶去受擊動畫，所以看不出異常；攻擊方沒有待處理的 travel，重啟後就掉回
##   Start → idle —— 這就是「打中瞬間攻擊者的動畫被重置成 idle 格」。
##   解凍時還原 callback_mode_process 會再觸發一次同樣的重啟，狀態機回到 idle 後
##   `is_attacking` 仍為 true，動畫層便再 travel 一次攻擊動畫 —— 這就是
##   「hitstop 結束後又把打擊動畫重播一次（甚至多次）」。
##   改用 process_mode 定格完全不碰 active，兩個症狀的根都被拔掉。
## - AnimationPlayer / AnimatedSprite2D 的 speed_scale = 0 仍會一併設下，
##   覆蓋繞過 AnimationTree 直接播放的場合（例如 landing）。
## - 凍結開始時只對「受擊方」的 AnimationTree 做 advance(0)：把 take_hit() 已排定
##   的 travel（受擊 / 格擋動畫）以 delta=0 立即套用 —— 讓 hitstop 期間受擊方
##   定格在「受擊反應第 0 格」，而不是 hitstop 結束後才切進動畫。
##   攻擊方**不沖洗**：它的 sprite 已經停在打中瞬間那一格，多推一次狀態機只會
##   有機會提前觸發轉場，沒有任何好處。
## - 只在「被擊中者／格擋者」的 Sprite / AnimatedSprite 的 offset / rotation 上做
##   像素級微震動；攻擊方只定格、不震動（jitter_target 預設 = Defender only）。
## - 不修改 CharacterBody2D 的 position / velocity，因此不影響 Hitbox / Hurtbox。
## - 背景、粒子特效、UI 全部維持正常時間運行。
## - 所有關鍵參數都是用 @export，可在編輯器直接調整。

signal hitstop_started
signal hitstop_finished

const LOG_TAG := "[HITSTOP]"

## `hitstop_frames` 的計量單位。
##
## 這是「編輯器不知道 hitstop_frames 到底是 60 還是 120 FPS」問題的正式答案：
## 引擎內部**永遠**以物理幀（project.godot: physics_ticks_per_second = 120）倒數，
## 但設計者可以選擇用自己習慣的單位輸入，由本控制器換算成物理幀。
enum HitstopUnit {
	PHYSICS_FRAMES_120FPS,  ## 物理幀（120 FPS，引擎原生單位）
	LOGIC_FRAMES_60FPS,     ## 邏輯幀（60 FPS，格鬥遊戲慣用的「幀數」）
	MILLISECONDS,           ## 毫秒
}

# ═══════════════════════════════════════════════════════════════════
# Hitstop 設定
# ═══════════════════════════════════════════════════════════════════
@export var enabled: bool = true
## `hitstop_frames` 的單位。改這個不會改變已填的數字，只改變它的解讀方式；
## 換算結果即時顯示在下方唯讀的 `Hitstop Duration Readout`。
@export var hitstop_unit: HitstopUnit = HitstopUnit.PHYSICS_FRAMES_120FPS:
	set(value):
		hitstop_unit = value
		notify_property_list_changed()
## 定格持續時間。單位由上面的 `hitstop_unit` 決定（預設＝物理幀 @120 FPS，
## 即引擎每個 _physics_process 扣 1 的那個單位；8 物理幀 ≈ 66 ms）。
@export_range(0, 120, 1, "or_greater") var hitstop_frames: int = 8:
	set(value):
		hitstop_frames = max(0, value)
		notify_property_list_changed()
## 【唯讀】把上面的設定換算成三種單位一起顯示，避免再猜「這是 60 還是 120 FPS」。
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var hitstop_duration_readout: String = "":
	get:
		return describe_duration()
	set(_value):
		pass  # 唯讀顯示用，永遠由 describe_duration() 計算
## 攻擊者動畫是否也要一起定格（近身打擊通常兩邊都停）
@export var freeze_attacker: bool = true
## 受擊者動畫是否要定格
@export var freeze_defender: bool = true
## 是否將 AnimationPlayer 的 speed_scale 設為 0（覆蓋繞過 AnimationTree 的直接播放）
@export var freeze_animation_player: bool = true
## 是否將 AnimatedSprite2D 的 speed_scale 設為 0（若角色直接使用 AnimatedSprite2D）
@export var freeze_animated_sprite: bool = true
## 是否把 AnimationTree 節點停止處理（process_mode = DISABLED）來定格。
## 這才是 Tree 驅動動畫（本專案的標準配置）的真正定格開關；關閉的話
## AnimationTree 會繼續推進動畫，hitstop 將完全沒有「定格」的視覺效果。
## 【勿改回 callback_mode_process = MANUAL】那條路徑會 set_active(false/true)，
## 造成狀態機被重啟回 Start 節點（詳見檔頭說明）。
@export var freeze_animation_tree: bool = true

# ═══════════════════════════════════════════════════════════════════
# 視覺微震動（Visual Jitter）
# ═══════════════════════════════════════════════════════════════════
@export_group("Visual Jitter")
@export var jitter_enabled: bool = true
## 誰的 sprite 會震抖。
## 【設計約定】只有「被擊中者／格擋者」會震 —— 攻擊方只定格、不震動，
## 否則兩邊一起抖會分不出誰吃了這一下，打擊感反而變糊。
@export_enum("Defender only", "Defender + Attacker", "Attacker only") var jitter_target: int = 0
@export_range(0.0, 20.0, 0.1, "or_greater") var jitter_amplitude_x: float = 2.0
@export_range(0.0, 20.0, 0.1, "or_greater") var jitter_amplitude_y: float = 1.5
@export_range(0.0, 20.0, 0.1, "or_greater") var jitter_rotation_degrees: float = 0.0

# ═══════════════════════════════════════════════════════════════════
# 相容性 / 除錯
# ═══════════════════════════════════════════════════════════════════
@export_group("Compatibility / Debug")
## 是否在 hitstop 期間暫停 FrameCounter（保留舊版對全局幀計數器的行為）
@export var pause_frame_counter: bool = true
@export var debug_log: bool = false

# ═══════════════════════════════════════════════════════════════════
# 狀態
# ═══════════════════════════════════════════════════════════════════
var is_active: bool = false
var remaining_frames: int = 0

# 🔍 Debug counters for CI diagnostics (not gameplay behavior).
var debug_begin_count: int = 0
var debug_finish_count: int = 0
var debug_cancel_count: int = 0
var debug_register_calls: int = 0
var debug_attacker_name: String = "none"
var debug_defender_name: String = "none"
var debug_players_group_count: int = -1

var _attacker: Node = null
var _defender: Node = null
var _entries: Array = []
var _jitter_phase: int = 0
## 本次 hitstop 中被震動過的 sprite 的「原始 offset / rotation」（key = instance_id）。
## 用途：即使 _entries 快照遺失，收尾時也能把 sprite 放回原本的位置，
## 而不是硬設成 Vector2.ZERO（角色 sprite 本來就有 offset，例如 (0,-50)）。
## 每次 hitstop 結束／取消時清空，避免把過期的 offset 寫回新的動畫姿勢。
var _jitter_baselines: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════
# 單位換算 / 編輯器顯示
# ═══════════════════════════════════════════════════════════════════

## 引擎實際使用的定格長度（物理幀）。`_physics_process` 每幀扣 1 的就是它。
func get_hitstop_physics_frames() -> int:
	var ticks: float = float(Engine.physics_ticks_per_second)
	match hitstop_unit:
		HitstopUnit.LOGIC_FRAMES_60FPS:
			# Stage 1 約定：邏輯幀 → 物理幀只走 Movement 這唯一轉換點。
			return Movement.logic_frames_to_physics_frames(float(hitstop_frames))
		HitstopUnit.MILLISECONDS:
			return int(round(float(hitstop_frames) * ticks / 1000.0))
		_:
			return max(0, hitstop_frames)


## 三種單位一起講清楚，給編輯器唯讀欄位與 debug log 共用。
func describe_duration() -> String:
	var ticks: float = float(Engine.physics_ticks_per_second)
	if ticks <= 0.0:
		ticks = 120.0
	var phys: int = get_hitstop_physics_frames()
	var logic: float = float(phys) * 60.0 / ticks
	var ms: float = float(phys) * 1000.0 / ticks
	return "%d 物理幀 @%d FPS　=　%.1f 邏輯幀 @60 FPS　=　%.1f ms" % [
		phys, int(ticks), logic, ms
	]


func _validate_property(property: Dictionary) -> void:
	# 讓 Inspector 的數字欄位直接把單位寫在後面（suffix），不必再翻文件。
	if property.name == "hitstop_frames":
		var suffix := "物理幀 @120 FPS"
		match hitstop_unit:
			HitstopUnit.LOGIC_FRAMES_60FPS:
				suffix = "邏輯幀 @60 FPS"
			HitstopUnit.MILLISECONDS:
				suffix = "ms"
		property.hint = PROPERTY_HINT_RANGE
		property.hint_string = "0,120,1,or_greater,suffix:%s" % suffix


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 開始一次 hitstop。回傳 true 代表成功開始，false 代表參數無效或已在進行中。
func begin_hitstop(attacker: Node, defender: Node) -> bool:
	if not enabled or is_active:
		return false
	var duration_frames: int = get_hitstop_physics_frames()
	if duration_frames <= 0:
		if debug_log:
			Debug.log("%s 定格長度為 0（%s），略過定格。" % [LOG_TAG, describe_duration()])
		return false

	debug_begin_count += 1
	debug_register_calls = 0
	_attacker = attacker if is_instance_valid(attacker) else null
	_defender = defender if is_instance_valid(defender) else null
	debug_attacker_name = _attacker.name if _attacker else "none"
	debug_defender_name = _defender.name if _defender else "none"
	debug_players_group_count = get_tree().get_nodes_in_group("players").size() if get_tree() else -1
	_entries.clear()
	_jitter_phase = 0
	is_active = true
	remaining_frames = duration_frames

	if _defender:
		_register_actor(_defender, freeze_defender, _should_jitter(_defender), true)
	if _attacker:
		_register_actor(_attacker, freeze_attacker, _should_jitter(_attacker), false)

	# 防呆：若呼叫端沒有傳入攻擊者/受擊者（例如舊呼叫或暫態 null），
	# 直接凍結場景中所有 players，避免 hitstop 已啟動卻完全沒有定格。
	# 【注意】這條路徑分不出誰是受擊方，所以一律**不震動** ——
	# 寧可少一次震動，也不要讓攻擊方莫名其妙抖起來。
	if _defender == null and _attacker == null:
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p != null:
				_register_actor(p, true, false, true)
		if debug_log:
			Debug.log("%s 未指定參與者，回退為凍結所有 players（不震動）。" % LOG_TAG)
	elif _entries.is_empty():
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p != null:
				# 只有受擊方需要沖洗姿勢（把 take_hit 排定的 travel 立即套用）。
				_register_actor(p, true, _should_jitter(p), p == _defender)

	# ── 凍結開始：立刻把「受擊反應」的姿勢套用到位 ──
	# take_hit() 只是把狀態機的 travel 排進佇列，真正換姿勢要等 AnimationTree
	# 下一次 process。若不在凍結時沖洗一次，受擊方的 sprite 會停在舊姿勢、直到
	# hitstop 結束才切進受擊動畫 —— 這正是舊版「hitstop 完全沒有感覺」的成因之一。
	# 攻擊方不沖洗：它本來就已經停在打中瞬間的那一格。
	_apply_frozen_poses()

	if pause_frame_counter:
		_pause_frame_counter()

	_apply_jitter()

	if debug_log:
		Debug.log("%s 開始：%s attacker=%s defender=%s" % [
			LOG_TAG, describe_duration(),
			_attacker.name if _attacker else "none",
			_defender.name if _defender else "none",
		])

	emit_signal("hitstop_started")
	return true


## 每次物理幀：推進視覺微震動，並倒數剩餘幀數。
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool 腳本：編輯器內不跑遊戲邏輯
	if not is_active:
		return
	_apply_jitter()
	remaining_frames -= 1
	if remaining_frames <= 0:
		_finish()


## 立即取消（用於 reset / 離開場景）。不會發射 hitstop_finished，
## 因為這不是一次正常的 hitstop 結束。
func cancel() -> void:
	if not is_active:
		return
	debug_cancel_count += 1
	is_active = false
	remaining_frames = 0
	# 防呆：即使快照沒有成功保存，也要把所有 players 復原到正常狀態。
	_restore_all_players_defaults()
	_restore_entries()
	_resume_frame_counter()
	_entries.clear()
	_jitter_baselines.clear()
	_attacker = null
	_defender = null
	if debug_log:
		Debug.log("%s 已被取消。" % LOG_TAG)


## 強制清除（reset 時也要把任何殘留快照救回）。
func reset() -> void:
	cancel()


# ═══════════════════════════════════════════════════════════════════
# 內部實作
# ═══════════════════════════════════════════════════════════════════

func _register_actor(node: Node, freeze_animation: bool, jitter: bool, flush_pose: bool = false) -> void:
	debug_register_calls += 1
	var anim_player = node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var anim_tree = node.get_node_or_null("AnimationTree") as AnimationTree
	var anim_sprite = node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var sprite = node.get_node_or_null("Sprite2D") as Sprite2D

	# 先快照原本的動畫速度 / 狀態，再凍結動畫。快照必須在改動之前取得，
	# 否則 hitstop 結束時會把 speed_scale 還原成 0。
	var anim_player_speed: float = anim_player.speed_scale if anim_player else 1.0
	var anim_tree_process: int = anim_tree.callback_mode_process if anim_tree else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	var anim_tree_process_mode: int = anim_tree.process_mode if anim_tree else Node.PROCESS_MODE_INHERIT
	var anim_tree_active: bool = anim_tree.active if anim_tree else true
	var anim_sprite_speed: float = anim_sprite.speed_scale if anim_sprite else 1.0
	var anim_sprite_frame: int = anim_sprite.frame if anim_sprite else 0
	var anim_sprite_offset: Vector2 = anim_sprite.offset if anim_sprite else Vector2.ZERO
	var anim_sprite_position: Vector2 = anim_sprite.position if anim_sprite else Vector2.ZERO
	var anim_sprite_rotation: float = anim_sprite.rotation_degrees if anim_sprite else 0.0
	var sprite_offset: Vector2 = sprite.offset if sprite else Vector2.ZERO
	var sprite_position: Vector2 = sprite.position if sprite else Vector2.ZERO
	var sprite_rotation: float = sprite.rotation_degrees if sprite else 0.0

	# 凍結動畫。放在 Dictionary/Array 記錄之前，確保即使後續記錄失敗動畫仍然停住。
	if freeze_animation and anim_tree:
		# 動畫實際由 AnimationTree 驅動：讓 AnimationTree 這個節點停止處理才是真正的定格。
		# 刻意不碰 active / callback_mode_process —— 那兩個 setter 都會經過
		# set_active(false→true)，把 mixer 的 `started` 旗標打開，下一次處理就會以
		# 「seek 到 0」進入狀態機，導致整台狀態機重啟回 Start 節點（＝攻擊者掉回 idle）。
		# process_mode 只影響「這個節點收不收得到 process 通知」，狀態機內部完全不動，
		# 解凍時把 process_mode 放回去即可從凍結點無縫續播。
		# （單把 AnimationPlayer.speed_scale 設 0 對 Tree 驅動的播放無效，見檔頭說明。）
		if freeze_animation_tree:
			anim_tree.process_mode = Node.PROCESS_MODE_DISABLED
	if freeze_animation and freeze_animation_player and anim_player:
		# 覆蓋繞過 AnimationTree、直接用 AnimationPlayer 播放的場合（例如 landing）。
		# 只凍結「可見播放速度」，讓 hitstop 結束時能從凍結點無縫繼續。
		anim_player.speed_scale = 0.0
	if freeze_animation and freeze_animated_sprite and anim_sprite:
		# Godot 4 的 AnimatedSprite2D 沒有 `playing` 屬性（Godot 3 遺留），
		# 凍結動畫請用 speed_scale = 0；恢復時再還原原本的 speed_scale。
		anim_sprite.speed_scale = 0.0

	var entry: Dictionary = {
		"node": node,
		"freeze": freeze_animation,
		"jitter": jitter,
		"flush_pose": flush_pose,
		"anim_player": anim_player,
		"anim_tree": anim_tree,
		"anim_sprite": anim_sprite,
		"sprite": sprite,
		"anim_player_speed": anim_player_speed,
		"anim_tree_process": anim_tree_process,
		"anim_tree_process_mode": anim_tree_process_mode,
		"anim_tree_active": anim_tree_active,
		"anim_sprite_speed": anim_sprite_speed,
		"anim_sprite_frame": anim_sprite_frame,
		"anim_sprite_offset": anim_sprite_offset,
		"anim_sprite_position": anim_sprite_position,
		"anim_sprite_rotation": anim_sprite_rotation,
		"sprite_offset": sprite_offset,
		"sprite_position": sprite_position,
		"sprite_rotation": sprite_rotation,
		"base_anim_sprite_offset": anim_sprite_offset,
		"base_sprite_offset": sprite_offset,
	}

	_entries.append(entry)


func _should_jitter(actor: Node) -> bool:
	if not jitter_enabled:
		return false
	match jitter_target:
		0:
			return actor == _defender
		1:
			return actor == _defender or actor == _attacker
		2:
			return actor == _attacker
	return false


## 凍結開始時的一次性「姿勢沖洗」：
## 以 delta=0 推進**受擊方**的 AnimationTree 一次 —— 不推進任何動畫時間，只把
## 已排定的 travel / 切換套用到位：
## - 受擊者：take_hit() 已把狀態機推往 hit / cr_hit / block / knockfly，
##   沖洗後 sprite 立即停在受擊（或格擋）動畫的第 0 格。
## - 攻擊者：**不沖洗**。它的 sprite 已經停在打中瞬間那一格，再推一次狀態機
##   只會多跑一輪轉場判定（例如 At End 轉場提早成立），有害無益。
func _apply_frozen_poses() -> void:
	for entry in _entries:
		if not bool(entry.get("freeze", false)):
			continue
		if not bool(entry.get("flush_pose", false)):
			continue
		var anim_tree = entry.get("anim_tree") as AnimationTree
		if anim_tree and anim_tree.active:
			# 節點已被 process_mode = DISABLED 停掉，引擎不會再自動處理它；
			# advance() 是手動推進的唯一入口，delta = 0 代表「只套用、不前進」。
			anim_tree.advance(0.0)


func _apply_jitter() -> void:
	if _entries.is_empty():
		return

	_jitter_phase += 1
	var phase: int = _jitter_phase

	# 刻意使用確定性震動：X 每幀換向，Y 以 4 幀為週期換向。
	# 這讓 hitstop 期間的抖動穩定且易於遊戲測試，同時避免畫面死寂。
	var x_sign: float = 1.0 if phase % 2 == 1 else -1.0
	var y_sign: float = 1.0 if (phase % 4) < 2 else -1.0
	var rot_sign: float = 1.0 if (phase % 4) < 2 else -1.0

	var jitter_x: float = x_sign * jitter_amplitude_x
	var jitter_y: float = y_sign * jitter_amplitude_y
	var jitter_rot: float = rot_sign * jitter_rotation_degrees

	for entry in _entries:
		if not bool(entry.get("jitter", false)):
			continue

		var anim_sprite = entry.get("anim_sprite") as AnimatedSprite2D
		var sprite = entry.get("sprite") as Sprite2D

		if anim_sprite:
			var base_anim_sprite_offset: Vector2 = entry.get("base_anim_sprite_offset", Vector2.ZERO) as Vector2
			var base_anim_sprite_rotation: float = entry.get("anim_sprite_rotation", 0.0) as float
			_remember_jitter_baseline(anim_sprite, base_anim_sprite_offset, base_anim_sprite_rotation)
			anim_sprite.offset = base_anim_sprite_offset + Vector2(jitter_x, jitter_y)
			anim_sprite.rotation_degrees = base_anim_sprite_rotation + jitter_rot

		if sprite:
			var base_sprite_offset: Vector2 = entry.get("base_sprite_offset", Vector2.ZERO) as Vector2
			var base_sprite_rotation: float = entry.get("sprite_rotation", 0.0) as float
			_remember_jitter_baseline(sprite, base_sprite_offset, base_sprite_rotation)
			sprite.offset = base_sprite_offset + Vector2(jitter_x, jitter_y)
			sprite.rotation_degrees = base_sprite_rotation + jitter_rot


## 記住某個 sprite 沒被震動前的 offset / rotation（只記第一次）。
func _remember_jitter_baseline(node: Node2D, offset: Vector2, rotation_deg: float) -> void:
	var key: int = node.get_instance_id()
	if not _jitter_baselines.has(key):
		_jitter_baselines[key] = {"offset": offset, "rotation": rotation_deg}


func _finish() -> void:
	debug_finish_count += 1
	is_active = false
	remaining_frames = 0
	# 防呆：即使快照沒有成功保存，也要把所有 players 復原到正常狀態。
	_restore_all_players_defaults()
	_restore_entries()
	_resume_frame_counter()
	_entries.clear()
	_jitter_baselines.clear()
	_attacker = null
	_defender = null

	if debug_log:
		Debug.log("%s 結束。" % LOG_TAG)

	emit_signal("hitstop_finished")


func _restore_all_players_defaults() -> void:
	# 先恢復記錄中的攻擊者/受擊者（即使 _entries 沒成功保存也要恢復）。
	_restore_actor_defaults(_attacker)
	_restore_actor_defaults(_defender)

	var tree := get_tree()
	if tree == null:
		return
	for player in tree.get_nodes_in_group("players"):
		_restore_actor_defaults(player)


func _restore_actor_defaults(player: Node) -> void:
	if not is_instance_valid(player):
		return
	var anim_player := player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var anim_tree := player.get_node_or_null("AnimationTree") as AnimationTree
	var anim_sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var sprite := player.get_node_or_null("Sprite2D") as Sprite2D
	if anim_player:
		anim_player.speed_scale = 1.0
	if anim_tree:
		# 防呆：快照遺失時若 tree 還停在凍結用的狀態，退回場景預設。
		if anim_tree.process_mode == Node.PROCESS_MODE_DISABLED:
			anim_tree.process_mode = Node.PROCESS_MODE_INHERIT
		# 舊版（MANUAL 定格）留下的殘留狀態也一併救回。
		if anim_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		anim_tree.active = true
	if anim_sprite:
		anim_sprite.speed_scale = 1.0
		_restore_jitter_baseline(anim_sprite)
	if sprite:
		# 【修正】不能硬設成 Vector2.ZERO —— 角色場景本來就替 sprite 設了 offset
		# （WOO 的 AnimatedSprite2D offset = (0,-50)）。只把「我們震過的」放回原位。
		_restore_jitter_baseline(sprite)


## 把某個曾被震動的 sprite 放回它被震動前的 offset / rotation。
func _restore_jitter_baseline(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	var key: int = node.get_instance_id()
	if not _jitter_baselines.has(key):
		return
	var base: Dictionary = _jitter_baselines[key]
	node.set("offset", base.get("offset", Vector2.ZERO))
	node.rotation_degrees = float(base.get("rotation", 0.0))


func _restore_entries() -> void:
	for entry in _entries:
		var anim_player = entry.get("anim_player") as AnimationPlayer
		var anim_sprite = entry.get("anim_sprite") as AnimatedSprite2D
		var sprite = entry.get("sprite") as Sprite2D

		if anim_player:
			# hitstop 期間速度被設為 0，結束時還原原本的播放速度。
			anim_player.speed_scale = float(entry.get("anim_player_speed", 1.0))
		# 【只還原我們動過的東西】speed_scale 與震動用的 offset / rotation。
		# 舊版連 `frame` / `position` 也一併還原 —— 但那兩個是動畫軌道在寫的，
		# 快照又是在「沖洗受擊姿勢之前」取的，於是 hitstop 結束的那一幀會把
		# 受擊者的 sprite 倒回被打前的格數，閃一下才被動畫改回來。
		if anim_sprite:
			anim_sprite.speed_scale = float(entry.get("anim_sprite_speed", 1.0))
			if bool(entry.get("jitter", false)):
				anim_sprite.offset = entry.get("base_anim_sprite_offset", Vector2.ZERO) as Vector2
				anim_sprite.rotation_degrees = float(entry.get("anim_sprite_rotation", 0.0))
		if sprite and bool(entry.get("jitter", false)):
			sprite.offset = entry.get("base_sprite_offset", Vector2.ZERO) as Vector2
			sprite.rotation_degrees = float(entry.get("sprite_rotation", 0.0))

		# AnimationTree 在 hitstop 期間被 process_mode = DISABLED 停住，結束時把
		# process_mode 放回原值即可從凍結點無縫繼續（active / callback_mode_process /
		# 狀態機節點身分 / travel 目標都沒被動過，因此不會有「重啟回 Start」的重播）。
		var anim_tree = entry.get("anim_tree") as AnimationTree
		if anim_tree:
			anim_tree.process_mode = int(entry.get(
				"anim_tree_process_mode", Node.PROCESS_MODE_INHERIT))
			# 相容舊快照：只有在真的被改過時才寫回（setter 相同值會提前 return，
			# 不會觸發 set_active(false→true)）。
			anim_tree.callback_mode_process = int(entry.get(
				"anim_tree_process", AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE))
			anim_tree.active = true


func _pause_frame_counter() -> void:
	var frame_counter = get_tree().get_first_node_in_group("frame_counter") if get_tree() else null
	if frame_counter and frame_counter.has_method("pause"):
		frame_counter.pause()


func _resume_frame_counter() -> void:
	var frame_counter = get_tree().get_first_node_in_group("frame_counter") if get_tree() else null
	if frame_counter and frame_counter.has_method("resume"):
		frame_counter.resume()
