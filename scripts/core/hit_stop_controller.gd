class_name HitStopController
extends Node

## 専門 Hitstop 管理器。
##
## 這不是全域時間停止（Engine.time_scale = 0），而是「角色動畫與視覺解耦」：
## - 角色動畫由 AnimationTree（狀態機）驅動 AnimationPlayer 播放。Godot 官方文件
##   明載：AnimationTree 接管後，AnimationPlayer 自身的播放屬性（含 speed_scale）
##   不會生效 —— 因此真正用來定格的是把 AnimationTree 的 callback_mode_process
##   切到 MANUAL：保持 active=true，狀態機節點身分、travel 目標與條件參數全部
##   保留，只是不再自動推進動畫時間。
## - AnimationPlayer / AnimatedSprite2D 的 speed_scale = 0 仍會一併設下，
##   覆蓋繞過 AnimationTree 直接播放的場合（例如 landing）。
## - 凍結開始時對每個凍結的 AnimationTree 做 advance(0)：把 take_hit() 已排定
##   的 travel（受擊 / 格擋動畫）以 delta=0 立即套用 —— 讓 hitstop 期間雙方
##   定格在「打中瞬間／受擊反應第 0 格」，而不是 hitstop 結束後才切進動畫。
## - 只在 Sprite / AnimatedSprite 的 offset / rotation 上做像素級微震動。
## - 不修改 CharacterBody2D 的 position / velocity，因此不影響 Hitbox / Hurtbox。
## - 背景、粒子特效、UI 全部維持正常時間運行。
## - 所有關鍵參數都是用 @export，可在編輯器直接調整。

signal hitstop_started
signal hitstop_finished

const LOG_TAG := "[HITSTOP]"

# ═══════════════════════════════════════════════════════════════════
# Hitstop 設定
# ═══════════════════════════════════════════════════════════════════
@export var enabled: bool = true
## 定格持續時間（物理幀；120 FPS 時 8 幀約 66ms）
@export_range(0, 60, 1, "or_greater") var hitstop_frames: int = 8
## 攻擊者動畫是否也要一起定格（近身打擊通常兩邊都停）
@export var freeze_attacker: bool = true
## 受擊者動畫是否要定格
@export var freeze_defender: bool = true
## 是否將 AnimationPlayer 的 speed_scale 設為 0（覆蓋繞過 AnimationTree 的直接播放）
@export var freeze_animation_player: bool = true
## 是否將 AnimatedSprite2D 的 speed_scale 設為 0（若角色直接使用 AnimatedSprite2D）
@export var freeze_animated_sprite: bool = true
## 是否把 AnimationTree 切到手動模式（MANUAL）凍結。
## 這才是 Tree 驅動動畫（本專案的標準配置）的真正定格開關；關閉的話
## AnimationTree 會繼續推進動畫，hitstop 將完全沒有「定格」的視覺效果。
@export var freeze_animation_tree: bool = true

# ═══════════════════════════════════════════════════════════════════
# 視覺微震動（Visual Jitter）
# ═══════════════════════════════════════════════════════════════════
@export_group("Visual Jitter")
@export var jitter_enabled: bool = true
@export_enum("Defender only", "Defender + Attacker", "Attacker only") var jitter_target: int = 1
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 開始一次 hitstop。回傳 true 代表成功開始，false 代表參數無效或已在進行中。
func begin_hitstop(attacker: Node, defender: Node) -> bool:
	if not enabled or is_active:
		return false
	if hitstop_frames <= 0:
		if debug_log:
			Debug.log("%s hitstop_frames <= 0，略過定格。" % LOG_TAG)
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
	remaining_frames = hitstop_frames

	if _defender:
		_register_actor(_defender, freeze_defender, _should_jitter(_defender))
	if _attacker:
		_register_actor(_attacker, freeze_attacker, _should_jitter(_attacker))

	# 防呆：若呼叫端沒有傳入攻擊者/受擊者（例如舊呼叫或暫態 null），
	# 直接凍結場景中所有 players，避免 hitstop 已啟動卻完全沒有定格。
	if _defender == null and _attacker == null:
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p != null:
				_register_actor(p, true, true)
		if debug_log:
			Debug.log("%s 未指定參與者，回退為凍結所有 players。" % LOG_TAG)
	elif _entries.is_empty():
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p != null:
				_register_actor(p, true, true)

	# ── 凍結開始：立刻把「打中瞬間／受擊反應」的姿勢套用到位 ──
	# take_hit() 只是把狀態機的 travel 排進佇列，真正換姿勢要等 AnimationTree
	# 下一次 process。若不在凍結時沖洗一次，sprite 會停在舊姿勢、直到 hitstop
	# 結束才切進受擊動畫 —— 這正是舊版「hitstop 完全沒有感覺」的成因之一。
	_apply_frozen_poses()

	if pause_frame_counter:
		_pause_frame_counter()

	_apply_jitter()

	if debug_log:
		Debug.log("%s 開始：frames=%d attacker=%s defender=%s" % [
			LOG_TAG, hitstop_frames,
			_attacker.name if _attacker else "none",
			_defender.name if _defender else "none",
		])

	emit_signal("hitstop_started")
	return true


## 每次物理幀：推進視覺微震動，並倒數剩餘幀數。
func _physics_process(_delta: float) -> void:
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

func _register_actor(node: Node, freeze_animation: bool, jitter: bool) -> void:
	debug_register_calls += 1
	var anim_player = node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var anim_tree = node.get_node_or_null("AnimationTree") as AnimationTree
	var anim_sprite = node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var sprite = node.get_node_or_null("Sprite2D") as Sprite2D

	# 先快照原本的動畫速度 / 狀態，再凍結動畫。快照必須在改動之前取得，
	# 否則 hitstop 結束時會把 speed_scale 還原成 0。
	var anim_player_speed: float = anim_player.speed_scale if anim_player else 1.0
	var anim_tree_process: int = anim_tree.callback_mode_process if anim_tree else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
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
		# 動畫實際由 AnimationTree 驅動：把 mixer 切到手動模式（MANUAL）才是真正的定格。
		# 刻意保持 active=true、不動狀態機內部 —— 節點身分、travel 目標與條件參數
		# 全部保留，只是不再自動推進；結束時還原本來的 process mode。
		# （單把 AnimationPlayer.speed_scale 設 0 對 Tree 驅動的播放無效，見檔頭說明。）
		if freeze_animation_tree:
			anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if freeze_animation and anim_player:
		# 覆蓋繞過 AnimationTree、直接用 AnimationPlayer 播放的場合（例如 landing）。
		# 只凍結「可見播放速度」，讓 hitstop 結束時能從凍結點無縫繼續。
		anim_player.speed_scale = 0.0
	if freeze_animation and anim_sprite:
		# Godot 4 的 AnimatedSprite2D 沒有 `playing` 屬性（Godot 3 遺留），
		# 凍結動畫請用 speed_scale = 0；恢復時再還原原本的 speed_scale。
		anim_sprite.speed_scale = 0.0

	var entry: Dictionary = {
		"node": node,
		"freeze": freeze_animation,
		"jitter": jitter,
		"anim_player": anim_player,
		"anim_tree": anim_tree,
		"anim_sprite": anim_sprite,
		"sprite": sprite,
		"anim_player_speed": anim_player_speed,
		"anim_tree_process": anim_tree_process,
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
## 以 delta=0 推進每個凍結的 AnimationTree 一次 —— 不推進任何動畫時間，只把
## 已排定的 travel / 切換套用到位：
## - 受擊者：take_hit() 已把狀態機推往 hit / cr_hit / block / knockfly，
##   沖洗後 sprite 立即停在受擊（或格擋）動畫的第 0 格。
## - 攻擊者：重新套用打中瞬間的當前姿勢（位置不動，只是確保定格）。
func _apply_frozen_poses() -> void:
	for entry in _entries:
		if not bool(entry.get("freeze", false)):
			continue
		var anim_tree = entry.get("anim_tree") as AnimationTree
		if anim_tree and anim_tree.active \
				and anim_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			# MANUAL 模式下 advance() 是唯一的推進入口（引擎的 _notification 會跳過
			# MANUAL 的 mixer）；delta = 0 代表「只套用、不前進」。
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
			anim_sprite.offset = base_anim_sprite_offset + Vector2(jitter_x, jitter_y)
			anim_sprite.rotation_degrees = base_anim_sprite_rotation + jitter_rot

		if sprite:
			var base_sprite_offset: Vector2 = entry.get("base_sprite_offset", Vector2.ZERO) as Vector2
			var base_sprite_rotation: float = entry.get("sprite_rotation", 0.0) as float
			sprite.offset = base_sprite_offset + Vector2(jitter_x, jitter_y)
			sprite.rotation_degrees = base_sprite_rotation + jitter_rot


func _finish() -> void:
	debug_finish_count += 1
	is_active = false
	remaining_frames = 0
	# 防呆：即使快照沒有成功保存，也要把所有 players 復原到正常狀態。
	_restore_all_players_defaults()
	_restore_entries()
	_resume_frame_counter()
	_entries.clear()
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
		# 防呆：快照遺失時若 tree 還停在凍結用的 MANUAL，退回場景預設的 IDLE。
		if anim_tree.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		anim_tree.active = true
	if anim_sprite:
		anim_sprite.speed_scale = 1.0
	if sprite:
		sprite.offset = Vector2.ZERO
		sprite.position = Vector2.ZERO
		sprite.rotation_degrees = 0.0


func _restore_entries() -> void:
	for entry in _entries:
		var anim_player = entry.get("anim_player") as AnimationPlayer
		var anim_sprite = entry.get("anim_sprite") as AnimatedSprite2D
		var sprite = entry.get("sprite") as Sprite2D

		if anim_player:
			# hitstop 期間速度被設為 0，結束時還原原本的播放速度。
			anim_player.speed_scale = float(entry.get("anim_player_speed", 1.0))
		if anim_sprite:
			anim_sprite.speed_scale = float(entry.get("anim_sprite_speed", 1.0))
			anim_sprite.frame = int(entry.get("anim_sprite_frame", 0))
			anim_sprite.offset = entry.get("anim_sprite_offset", Vector2.ZERO) as Vector2
			anim_sprite.position = entry.get("anim_sprite_position", Vector2.ZERO) as Vector2
			anim_sprite.rotation_degrees = float(entry.get("anim_sprite_rotation", 0.0))
		if sprite:
			sprite.offset = entry.get("sprite_offset", Vector2.ZERO) as Vector2
			sprite.position = entry.get("sprite_position", Vector2.ZERO) as Vector2
			sprite.rotation_degrees = float(entry.get("sprite_rotation", 0.0))

		# AnimationTree 在 hitstop 時被切到手動模式（MANUAL），結束時還原本來的
		# process mode，讓狀態機從凍結點無縫繼續（travel 目標與節點身分都沒丟過）。
		var anim_tree = entry.get("anim_tree") as AnimationTree
		if anim_tree:
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
