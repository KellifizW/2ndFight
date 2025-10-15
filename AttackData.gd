# AttackData.gd
extends Resource
class_name AttackData

@export var attack_name: String = ""  # 招式名稱，如 "st_mp"
@export var startup: float = 0.0      # 啟動時間（秒）
@export var active: float = 0.0       # 活躍時間（hitbox 出現時間）
@export var recovery: float = 0.0     # 恢復時間（剩餘時間）
@export var damage: float = 0.0       # 傷害值
@export var hitstun: float = 0.0      # 擊中硬直
@export var blockstun: float = 0.0    # 防禦硬直
