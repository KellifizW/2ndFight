# res://scripts/combat/base/AttackBase.gd
class_name AttackBase extends Node

# ── 所有普通攻擊共用參數（未來在子類中直接在 Inspector 調整） ──────────────────
@export var attack_id: String = "st_mp"                  # 攻擊唯一 ID，用於動畫與取消判斷
@export var animation_name: String = ""                 # 動畫名稱，留空則自動使用 attack_id
@export var damage: float = 10.0
@export var hitstun: float = 0.35
@export var blockstun: float = 0.267
@export var startup_frames: int = 8                      # 啟動幀（可轉換成秒）
@export var active_frames: int = 4                       # 活躍幀（Hitbox 開啟時間）
@export var recovery_frames: int = 12                    # 恢復幀
@export var cancelable_into: Array[String] = []          # 可取消進哪些特殊招，例如 ["powerkk"]

# ── 內部狀態（不需要在 Inspector 調整） ─────────────────────────────────────────────
var frame_counter: int = 0
var is_executing: bool = false
var parent_player: Player  # 會在 _ready 自動取得

func _ready() -> void:
	parent_player = get_parent() as Player
	if not parent_player:
		push_error("AttackBase 必須作為 Player 的子節點！")
	if animation_name.is_empty():
		animation_name = attack_id

# ── 檢查此攻擊在當前狀態是否可輸入（由 AttackController 呼叫） ─────────────────────
func can_execute(input_data: Dictionary, current_state: String) -> bool:
	# 子類可覆寫此函數來定義更複雜的輸入條件
	# 預設只檢查是否正在執行其他攻擊
	return not is_executing and not parent_player.is_attacking

# ── 開始執行攻擊（由 AttackController 呼叫） ───────────────────────────────────────
func execute() -> void:
	if is_executing:
		return
	is_executing = true
	frame_counter = 0
	parent_player.is_attacking = true
	parent_player.attack_type = attack_id
	parent_player.current_damage = damage
	parent_player.animation_player.play(animation_name)
	Debug.log("[AttackBase] 執行普通攻擊：", attack_id)

# ── 每幀更新（由 AttackController 在 _physics_process 呼叫） ─────────────────────────
func update(delta: float) -> void:
	if not is_executing:
		return
	frame_counter += 1
	
	# 啟動階段 → 還沒出招
	if frame_counter < startup_frames:
		return
	
	# 活躍階段 → 開啟 Hitbox（這裡簡化，實際 Hitbox 控制可另外做）
	if frame_counter == startup_frames:
		if parent_player.has_node("Hitbox/HitShape"):
			parent_player.get_node("Hitbox/HitShape").disabled = false
	
	# 活躍結束 → 關閉 Hitbox
	if frame_counter >= startup_frames + active_frames:
		if parent_player.has_node("Hitbox/HitShape"):
			parent_player.get_node("Hitbox/HitShape").disabled = true
	
	# 完全結束
	if frame_counter >= startup_frames + active_frames + recovery_frames:
		finish_attack()

# ── 攻擊結束 ─────────────────────────────────────────────────────────────────────
func finish_attack() -> void:
	is_executing = false
	frame_counter = 0
	parent_player.is_attacking = false
	parent_player.attack_type = "none"
	if parent_player.has_node("Hitbox/HitShape"):
		parent_player.get_node("Hitbox/HitShape").disabled = true

# ── 可被子類覆寫：檢查是否可以取消進特殊招 ───────────────────────────────────────
func can_cancel_into(special_id: String) -> bool:
	return special_id in cancelable_into and frame_counter <= startup_frames + active_frames
