class_name HitStopManager
extends Node

## HitStopManager — 專門的 HitStop（受擊定格）管理器
##
## 業界標準做法（Street Fighter 6 / Guilty Gear -Strive- / Tekken 8）：
## Hitstop 不是全域時間停止（Engine.time_scale = 0 / get_tree().paused），
## 而是「角色動畫凍結 + Sprite 像素級微震抖（Frame Jitter）」。
##
## 本管理器只影響「角色節點」：
##
##   凍結（只限角色）：
##   - 動畫：AnimationPlayer / AnimationTree 的 speed_scale 設為 0
##     （停在全屏定格畫面，不推進、不觸發 Call Method 軌道）
##   - 物理：角色 fixed_position / fixed_velocity 停止積分 ——
##     由 Movement / Player / Fireball 依據 SlowMoController.is_hit_slowmo
##     早退實現。Hitbox / Hurtbox / Pushbox 完全不動，判定不受干擾。
##
##   不凍結（維持正常速度播放）：
##   - VFX 粒子 / 打擊火花（VFXImpact / VFXSmoke / 角色掛載的 GPUParticles）
##   - 音效、UI（計時器、血條、連段數、FrameBar 幀數據）
##   - 鏡頭
##
## 時長以「邏輯幀（60 FPS）」為單位，經 Movement.logic_frames_to_physics_frames
## 轉成物理幀倒數 —— 與 Engine.time_scale 完全無關，改參數即可調手感。
##
## 本節點放在 World/SlowMoController 之下，所有參數都是 @export：
## 在編輯器選取 World → SlowMoController → HitStopManager 即可調整。

signal hitstop_started(attack_type: String, is_blocked: bool)
signal hitstop_ended

# ── 定格時長（邏輯幀 @60 FPS）──────────────────────────────────────────
@export_group("HitStop Duration（邏輯幀 @60FPS）")
@export var light_hit_frames: int = 6    # 輕攻擊（*_lp / *_lk）
@export var medium_hit_frames: int = 8   # 中攻擊（*_mp / *_mk）
@export var heavy_hit_frames: int = 10   # 重攻擊（*_hp / *_hk）
@export var block_hit_frames: int = 4    # 格擋命中（比命中短，維持格擋節奏）
@export var special_hit_frames: int = 10 # 特殊招式 / 火球（powerkk / spnk / fireball...）

# ── 視覺微震抖（Frame Jitter）──────────────────────────────────────────
## 定格期間每個物理幀對角色視覺節點疊加隨機偏移（像素級抖動），
## 營造「肉體承受衝擊」的動能感；不修改 CharacterBody 物理座標。
@export_group("Jitter（像素微震抖）")
@export var jitter_enabled: bool = true
@export var jitter_amplitude: float = 2.0    # 水平最大偏移（像素）
@export var jitter_vertical_ratio: float = 0.4  # 垂直振幅 = 水平 × 此比例（避免角色「浮」）
@export var jitter_end_ratio: float = 0.2    # 振幅線性衰減終點（1.0 → 此值，衝擊感由強到弱）

var is_active: bool = false
var remaining_frames: int = 0  # 剩餘物理幀
var total_frames: int = 0      # 本次定格總物理幀

# 凍結期間的角色快照（key = instance_id）
var _frozen_players: Array[Node] = []
var _anim_speed_scale: Dictionary = {}  # id -> 凍結前的 AnimationPlayer.speed_scale
var _tree_speed_scale: Dictionary = {}  # id -> 凍結前的 AnimationTree.speed_scale
var _jitter_sprite: Dictionary = {}     # id -> 被 jitter 的視覺節點
var _sprite_base: Dictionary = {}       # id -> 凍結前的視覺節點 position


func _ready() -> void:
	add_to_group("hit_stop_manager")


func _physics_process(_delta: float) -> void:
	if not is_active:
		return
	_apply_jitter()
	remaining_frames -= 1
	if remaining_frames <= 0:
		_end_hitstop()


## 開始一次 hitstop。進行中的重複請求會被忽略（與舊版「避免重複觸發」一致）。
##
## attack_type: 攻擊型別（st_mp / jump_hk / powerkk / fireball...），用於選擇時長。
## is_blocked:  格擋命中用 block_hit_frames。
func request_hitstop(attack_type: String = "", is_blocked: bool = false) -> void:
	if is_active:
		Debug.log("[HITSTOP] request 被忽略（hitstop 進行中）")
		return
	var duration_logic_frames: int = _resolve_duration(attack_type, is_blocked)
	if duration_logic_frames <= 0:
		return
	total_frames = Movement.logic_frames_to_physics_frames(duration_logic_frames)
	remaining_frames = total_frames
	is_active = true
	_freeze_characters()
	Debug.log("[HITSTOP] 開始 | attack=%s blocked=%s | %d 邏輯幀 = %d 物理幀 | Engine.time_scale 未動（%s）" % [
		attack_type, is_blocked, duration_logic_frames, total_frames, Engine.time_scale])
	hitstop_started.emit(attack_type, is_blocked)


## 強制中斷並還原所有被凍結的角色（world reset_players 用）。
## 不發射 hitstop_ended —— reset 會自己清完所有遊戲狀態，
## 若再發信號會讓 Fighter 把「pending hit」套到剛重置完的角色上。
func hard_reset() -> void:
	is_active = false
	remaining_frames = 0
	total_frames = 0
	_restore_characters()


# ═══════════════════════════════════════════════════════════════════════
# 內部實作
# ═══════════════════════════════════════════════════════════════════════

func _end_hitstop() -> void:
	is_active = false
	remaining_frames = 0
	_restore_characters()
	Debug.log("[HITSTOP] 結束 | 動畫/物理還原；VFX/粒子/UI 全程未凍結")
	hitstop_ended.emit()


## 凍結所有角色：動畫 speed_scale=0 + 記錄 jitter 基準點。
func _freeze_characters() -> void:
	_frozen_players.clear()
	_anim_speed_scale.clear()
	_tree_speed_scale.clear()
	_jitter_sprite.clear()
	_sprite_base.clear()
	if get_tree() == null:
		return
	for player in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(player):
			_freeze_player(player)


func _freeze_player(player: Node) -> void:
	_frozen_players.append(player)
	var id: int = player.get_instance_id()

	# 1) 動畫凍結：AnimationTree 狀態機與 AnimationPlayer 直接播放（如 landing）
	#    都要停。speed_scale=0 → 軌道停在當前定格畫面，Call Method 也不會觸發。
	var animation_player = player.get_node_or_null("AnimationPlayer")
	if animation_player:
		_anim_speed_scale[id] = animation_player.speed_scale
		animation_player.speed_scale = 0.0
	var animation_tree = player.get_node_or_null("AnimationTree")
	if animation_tree:
		_tree_speed_scale[id] = animation_tree.speed_scale
		animation_tree.speed_scale = 0.0

	# 2) 記錄 jitter 基準點。只動「視覺節點」的 position：
	#    - 不碰 CharacterBody 的物理座標，Hitbox / Hurtbox / Pushbox 完全不受影響。
	#    - 目前角色場景的可見 sprite 是 AnimatedSprite2D，所有動畫軌道只寫
	#      frame / offset / scale / rotation，從不寫 position，
	#      所以 position 可以被 jitter 安全疊加（不會被動畫覆寫）。
	#    - Sprite2D 作為 fallback（未來角色若改用 Sprite2D 渲染也能工作；
	#      其 position 有動畫軌道時 jitter 會被覆寫、不可見，但不會破遊戲）。
	for sprite_name in ["AnimatedSprite2D", "Sprite2D"]:
		var sprite = player.get_node_or_null(sprite_name)
		if sprite:
			_jitter_sprite[id] = sprite
			_sprite_base[id] = sprite.position
			break


## 每個物理幀對被凍結角色疊加隨機微震抖（振幅由強到弱線性衰減）。
func _apply_jitter() -> void:
	if not jitter_enabled or _frozen_players.is_empty():
		return
	var progress: float = 0.0
	if total_frames > 0:
		progress = 1.0 - float(remaining_frames) / float(total_frames)
	var scale: float = lerpf(1.0, jitter_end_ratio, progress)
	var amp: float = jitter_amplitude * scale
	var amp_y: float = amp * jitter_vertical_ratio
	for player in _frozen_players:
		if not is_instance_valid(player):
			continue
		var id: int = player.get_instance_id()
		if not _jitter_sprite.has(id) or not _sprite_base.has(id):
			continue
		var sprite = _jitter_sprite[id]
		if sprite == null or not is_instance_valid(sprite):
			continue
		var base: Vector2 = _sprite_base[id]
		sprite.position = Vector2(
			base.x + randf_range(-amp, amp),
			base.y + randf_range(-amp_y, amp_y)
		)


## 還原所有被凍結的角色：動畫速度歸位 + sprite 偏移歸零。
func _restore_characters() -> void:
	for player in _frozen_players:
		if not is_instance_valid(player):
			continue
		var id: int = player.get_instance_id()
		var animation_player = player.get_node_or_null("AnimationPlayer")
		if animation_player and _anim_speed_scale.has(id):
			animation_player.speed_scale = _anim_speed_scale[id]
		var animation_tree = player.get_node_or_null("AnimationTree")
		if animation_tree and _tree_speed_scale.has(id):
			animation_tree.speed_scale = _tree_speed_scale[id]
		var sprite = _jitter_sprite.get(id)
		if sprite != null and is_instance_valid(sprite) and _sprite_base.has(id):
			sprite.position = _sprite_base[id]
	_frozen_players.clear()
	_anim_speed_scale.clear()
	_tree_speed_scale.clear()
	_jitter_sprite.clear()
	_sprite_base.clear()


## 依攻擊型別決定定格時長（邏輯幀）。
func _resolve_duration(attack_type: String, is_blocked: bool) -> int:
	if is_blocked:
		return block_hit_frames
	var t: String = attack_type.to_lower()
	if t.ends_with("_lp") or t.ends_with("_lk"):
		return light_hit_frames
	if t.ends_with("_mp") or t.ends_with("_mk"):
		return medium_hit_frames
	if t.ends_with("_hp") or t.ends_with("_hk"):
		return heavy_hit_frames
	if t.begins_with("st_") or t.begins_with("cr_") or t.begins_with("jump_"):
		# 普通攻擊的未識別型別（例如新增招式）：以中攻擊為基準
		return medium_hit_frames
	# 特殊招式（powerkk / spnk / dp / hdk / fireball / super...）
	return special_hit_frames
