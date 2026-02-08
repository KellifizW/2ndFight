# res://data/ThrowData.gd
class_name ThrowData extends Resource

# ═══════════════════════════════════════════════════════════════════════════
# 摔投（Throw/Grab）數據資源
# 每個角色可以有自己的 throw_data.tres 資源，控制摔投的所有參數
# ═══════════════════════════════════════════════════════════════════════════

const LOGIC_FPS: int = 60  # 邏輯/顯示幀率（資源中的幀數基準）

# ── 基本傷害和眩暈 ──
@export var throw_damage: float = 8.0
@export var throw_hitstun_frames: int = 36      # 36 幀 @60FPS = 0.60 秒 (物理幀 = 72 @120FPS)
@export var throw_blockstun_frames: int = 18    # 18 幀 @60FPS = 0.30 秒

# ── 推擊距離 ──
@export var throw_knockback_horizontal: float = 120.0  # 水平推力（像素/幀，未缩放）

# ── 被摔投者的速度參數 ──
@export var throw_launch_vertical_speed: float = -1000.0  # 垂直速度（像素/幀，負數=向上）
@export var throw_launch_horizontal_speed: float = 0.0    # 追加水平速度（可選）

# ── 被摔投者的重力參數 ──
@export var throw_gravity: float = 6000000.0  # 被摔投時的重力（固定點單位）

# ── 摔投動畫參數 ──
@export var throw_enter_duration: int = 30        # throw_enter 動畫幀數 @60FPS = 0.501秒 = 60幀 @120FPS
@export var throw_seq_duration: int = 60          # throw_seq 動畫幀數 @60FPS = 1.002秒 = 120幀 @120FPS

# ── 位置控制參數 ──
@export_group("Position Control")
@export var pivot_offset_x: float = 50.0          # 對手水平偏移（像素，相對攻擊者）
@export var pivot_offset_y: float = -30.0         # 對手垂直偏移（像素，負值=向上）
@export var hold_duration_frames: int = 30        # 持有對手的幀數 @60FPS（HOLD 階段長度）

# ── 自訂重力參數 ──
@export_group("Launch Physics")
@export var use_custom_gravity: bool = false      # 是否使用自訂重力（false=使用預設）
@export var custom_throw_gravity: int = 0         # 自訂重力值（固定點單位，use_custom_gravity=true 時生效）

# ── 連打逃脫參數 ──
@export_group("Escape Mechanism")
@export var allow_escape: bool = true             # 是否允許逃脫
@export var escape_window_end_frame: int = 15     # 逃脫窗口結束幀 @60FPS（從抓取開始計算）
@export var escape_mash_threshold: int = 8        # 逃脫所需按鍵次數（連打檢測）

# ── 多段摔投支援（選配）──
@export_group("Multi-Hit Throw (Optional)")
@export var is_multi_hit: bool = false            # 是否為多段摔投
@export var release_phases: Array[Dictionary] = []  # 多段釋放點：[{frame: int, damage: float, knockback: Vector2}]

func _to_string() -> String:
	return "ThrowData(damage=%.1f, hitstun=%d, launch_speed=%.1f, gravity=%.0f, pivot=(%.1f,%.1f))" % [
		throw_damage, throw_hitstun_frames, throw_launch_vertical_speed, throw_gravity,
		pivot_offset_x, pivot_offset_y
	]

# 返回摔投數據字典（供代碼調用）
func get_throw_data() -> Dictionary:
	return {
		"damage": throw_damage,
		"hitstun": throw_hitstun_frames,
		"blockstun": throw_blockstun_frames,
		"knockback": throw_knockback_horizontal,
		"launch_vertical_speed": throw_launch_vertical_speed,
		"launch_horizontal_speed": throw_launch_horizontal_speed,
		"gravity": throw_gravity if not use_custom_gravity else custom_throw_gravity,
		"pivot_offset_x": pivot_offset_x,
		"pivot_offset_y": pivot_offset_y,
		"hold_duration_frames": hold_duration_frames,
		"escape_window_end_frame": escape_window_end_frame,
		"escape_mash_threshold": escape_mash_threshold,
		"allow_escape": allow_escape,
		"is_multi_hit": is_multi_hit,
		"release_phases": release_phases,
	}
