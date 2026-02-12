# res://data/SpecialMoveData.gd
class_name SpecialMoveData extends Resource

# ============================================================
# ACCELERATION CURVE TYPE
# ============================================================
enum AccelerationCurve {
	NONE,           # 恆定速度（無加速度變化）
	ACCELERATE,     # 從靜止開始加速（漸進型）
	DECELERATE,     # 從最高速開始減速（衝刺型）
	THREE_PHASE     # 三階段：靜止 → 爆發加速 → 減速（複雜型，如Ken的Super）
}

# ============================================================
# CORE IDENTIFIERS
# ============================================================
@export_group("基本設定")
@export var move_id: String = ""
@export var character_requirement: String = "*"  ## 角色限定："DAV", "DEN", 或 "*"（通用）

# ============================================================
# COMBAT STATS (Frame-based at 60 FPS)
# ============================================================
@export_group("戰鬥數值")
@export var damage: float = 0.0  ## 招式傷害值
@export var knockback: float = 0.0  ## 普通擊退距離（像素）
@export var hitstun_frames: int = 18  ## 命中硬直時間（邏輯幀數 @ 60 FPS）
@export var blockstun_frames: int = 10  ## 格擋硬直時間（邏輯幀數 @ 60 FPS）

# ============================================================
# KNOCKFLY CONTROL (NEW!)
# ============================================================
@export_group("擊飛控制", "knockfly_")
@export var knockfly_force_enable: bool = false  ## ✅ 【新增】無論傷害多少，強制令對手進入Knockfly狀態
@export var knockfly_gravity: float = 0.0  ## 擊飛時的重力（正值向下）
@export var knockfly_vertical_speed: float = 0.0  ## 擊飛初始垂直速度（負值向上）
@export var knockfly_horizontal_speed: float = 0.0  ## 擊飛水平速度

# ============================================================
# TIMING AND MOVEMENT (Frame-based at 60 FPS)
# ============================================================
@export_group("時間與移動")
@export var duration_frames: int = 0  ## 招式持續時間（邏輯幀數）。**設為0時自動使用動畫長度**
@export var move_distance: float = 0.0  ## 角色移動距離（像素）
@export var trajectory_delay_frames: int = 0  ## ✅ 【新增】招式軌跡開始前的延遲時間（邏輯幀數），用於"蓄力後爆發"的招式

# ============================================================
# ACCELERATION CURVE
# ============================================================
@export_group("加速度曲線")
@export var acceleration_curve: AccelerationCurve = AccelerationCurve.NONE  ## ✅ 【改為選單式】加速度類型
@export var stationary_ratio: float = 0.0  ## 三階段模式：靜止階段佔比（0.0-1.0）
@export var acceleration_ratio: float = 0.0  ## 三階段模式：加速階段佔比（0.0-1.0）
@export var deceleration_ratio: float = 0.0  ## 三階段模式：減速階段佔比（0.0-1.0）

# ============================================================
# CASTER JUMP SYSTEM (NEW!)
# ============================================================
@export_group("出招者跳躍", "caster_jump_")
@export var caster_jump_enabled: bool = false  ## ✅ 【新增】此招式是否令出招者飛到空中（如升龍拳）
@export var caster_jump_delay_frames: int = 0  ## 跳躍延遲時間（邏輯幀數），用於"助跑後起跳"
@export var caster_jump_vertical_speed: float = 0.0  ## ✅ 【修正】跳躍初始垂直速度（負值向上，取代舊的jump_speed）
@export var caster_jump_gravity: float = 0.0  ## ✅ 【新增】跳躍時的重力（正值向下）

# ============================================================
# SPECIAL BEHAVIOR
# ============================================================
@export_group("特殊行為")
@export var is_freeze: bool = false  ## 時間凍結效果（如超必殺開場畫面凍結）
@export var is_projectile: bool = false  ## 是否生成飛行道具（如火球），而非移動角色本身
@export var gravity: float = 0.0  ## 角色移動時的重力（用於拋物線軌跡）
@export var sound_type: String = "special"  ## 音效類型："special" 或 "fireball"
@export var penetrable: bool = false  ## 飛行道具是否可穿透對手

# ============================================================
# PROJECTILE PARAMETERS
# ============================================================
@export_group("飛行道具參數", "projectile_")
@export var projectile_speed: float = 0.0  ## 飛行道具速度（像素/秒）

# ============================================================
# DEPRECATED (Kept for backward compatibility)
# ============================================================
# @deprecated Use caster_jump_vertical_speed instead
var jump_delay_frames: int:
	get: return caster_jump_delay_frames
	set(value): caster_jump_delay_frames = value

# @deprecated Use caster_jump_vertical_speed instead
var jump_speed: float:
	get: return caster_jump_vertical_speed
	set(value): caster_jump_vertical_speed = value
