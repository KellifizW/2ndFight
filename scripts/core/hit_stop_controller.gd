class_name HitStopController
extends Node

## 専門 Hitstop 管理器。
##
## 這不是全域時間停止（Engine.time_scale = 0），而是「角色動畫與視覺解耦」：
## - 只暫停參與打擊的角色的 AnimationPlayer / AnimatedSprite2D。
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
## 是否將 AnimationPlayer 的 speed_scale 設為 0
@export var freeze_animation_player: bool = true
## 是否將 AnimatedSprite2D 的 speed_scale 設為 0（若角色直接使用 AnimatedSprite2D）
@export var freeze_animated_sprite: bool = true

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

var _attacker: Node = null
var _defender: Node = null
var _entries: Array[Dictionary] = []
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

	_attacker = attacker if is_instance_valid(attacker) else null
	_defender = defender if is_instance_valid(defender) else null
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
	is_active = false
	remaining_frames = 0
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
	var anim_player = node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var anim_tree = node.get_node_or_null("AnimationTree") as AnimationTree
	var anim_sprite = node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var sprite = node.get_node_or_null("Sprite2D") as Sprite2D

	var entry: Dictionary = {
		"node": node,
		"freeze": freeze_animation,
		"jitter": jitter,
		"anim_player": anim_player,
		"anim_tree": anim_tree,
		"anim_sprite": anim_sprite,
		"sprite": sprite,
		"anim_player_speed": anim_player.speed_scale if anim_player else 1.0,
		"anim_tree_active": anim_tree.active if anim_tree else true,
		"anim_sprite_speed": anim_sprite.speed_scale if anim_sprite else 1.0,
		"anim_sprite_playing": anim_sprite.playing if anim_sprite else false,
		"anim_sprite_frame": anim_sprite.frame if anim_sprite else 0,
		"anim_sprite_offset": anim_sprite.offset if anim_sprite else Vector2.ZERO,
		"anim_sprite_position": anim_sprite.position if anim_sprite else Vector2.ZERO,
		"anim_sprite_rotation": anim_sprite.rotation_degrees if anim_sprite else 0.0,
		"sprite_offset": sprite.offset if sprite else Vector2.ZERO,
		"sprite_position": sprite.position if sprite else Vector2.ZERO,
		"sprite_rotation": sprite.rotation_degrees if sprite else 0.0,
		"base_anim_sprite_offset": anim_sprite.offset if anim_sprite else Vector2.ZERO,
		"base_sprite_offset": sprite.offset if sprite else Vector2.ZERO,
	}

	if freeze_animation and anim_player:
		# 透過 AnimationTree 播放時 AnimationPlayer.speed_scale 通常會被忽略，
		# 但對直接播放 AnimationPlayer 的狀態（如 landing）仍然有效。
		anim_player.speed_scale = 0.0
	if freeze_animation and anim_tree:
		# AnimationTree 是 StateMachine root，active=false 才能真正凍結狀態機與播放。
		anim_tree.active = false
	if freeze_animation and anim_sprite:
		anim_sprite.speed_scale = 0.0
		anim_sprite.playing = false

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
	is_active = false
	remaining_frames = 0
	_restore_entries()
	_resume_frame_counter()
	_entries.clear()
	_attacker = null
	_defender = null

	if debug_log:
		Debug.log("%s 結束。" % LOG_TAG)

	emit_signal("hitstop_finished")


func _restore_entries() -> void:
	for entry in _entries:
		var anim_player = entry.get("anim_player") as AnimationPlayer
		var anim_sprite = entry.get("anim_sprite") as AnimatedSprite2D
		var sprite = entry.get("sprite") as Sprite2D

		if anim_player:
			anim_player.speed_scale = float(entry.get("anim_player_speed", 1.0))
		if anim_sprite:
			anim_sprite.speed_scale = float(entry.get("anim_sprite_speed", 1.0))
			anim_sprite.playing = bool(entry.get("anim_sprite_playing", false))
			anim_sprite.frame = int(entry.get("anim_sprite_frame", 0))
			anim_sprite.offset = entry.get("anim_sprite_offset", Vector2.ZERO) as Vector2
			anim_sprite.position = entry.get("anim_sprite_position", Vector2.ZERO) as Vector2
			anim_sprite.rotation_degrees = float(entry.get("anim_sprite_rotation", 0.0))
		if sprite:
			sprite.offset = entry.get("sprite_offset", Vector2.ZERO) as Vector2
			sprite.position = entry.get("sprite_position", Vector2.ZERO) as Vector2
			sprite.rotation_degrees = float(entry.get("sprite_rotation", 0.0))

		# AnimationTree 在 hitstop 時被設為 inactive，結束時還原為快照值。
		var anim_tree = entry.get("anim_tree") as AnimationTree
		if anim_tree:
			anim_tree.active = bool(entry.get("anim_tree_active", true))


func _pause_frame_counter() -> void:
	var frame_counter = get_tree().get_first_node_in_group("frame_counter") if get_tree() else null
	if frame_counter and frame_counter.has_method("pause"):
		frame_counter.pause()


func _resume_frame_counter() -> void:
	var frame_counter = get_tree().get_first_node_in_group("frame_counter") if get_tree() else null
	if frame_counter and frame_counter.has_method("resume"):
		frame_counter.resume()
