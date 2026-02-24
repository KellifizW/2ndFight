# res://data/AttackData.gd
class_name AttackData extends Resource

# ═══════════════════════════════════════════════════════════════════════════
# 🟢 幀數優先格式（Inspector 直接輸入幀數 @60FPS 邏輯幀）
# 例: st_lp_hitstun_frames = 30 → 30 邏輯幀 = 0.5 秒
# ═══════════════════════════════════════════════════════════════════════════
const LOGIC_FPS: int = 60  # 邏輯/顯示幀率（資源中的幀數基準）

# ── st_lp ──
@export var st_lp_damage: float = 3.0
@export var st_lp_hitstun_frames: int = 14      # 14 幀 = 0.233 秒
@export var st_lp_blockstun_frames: int = 12    # 12 幀 = 0.20 秒
@export var st_lp_knockback: float = 60.0
@export var st_lp_movement: AttackMovement = null

# ── st_mp ──
@export var st_mp_damage: float = 6.0
@export var st_mp_hitstun_frames: int = 24      # 24 幀 = 0.40 秒
@export var st_mp_blockstun_frames: int = 16    # 16 幀 = 0.267 秒
@export var st_mp_knockback: float = 120.0
@export var st_mp_movement: AttackMovement = null

# ── st_hp ──
@export var st_hp_damage: float = 9.0
@export var st_hp_hitstun_frames: int = 33      # 33 幀 = 0.55 秒
@export var st_hp_blockstun_frames: int = 20    # 20 幀 = 0.333 秒
@export var st_hp_knockback: float = 130.0
@export var st_hp_movement: AttackMovement = null

# ── st_lk ──
@export var st_lk_damage: float = 3.0
@export var st_lk_hitstun_frames: int = 30      # 30 幀 = 0.50 秒
@export var st_lk_blockstun_frames: int = 14    # 14 幀 = 0.233 秒
@export var st_lk_knockback: float = 130.0
@export var st_lk_movement: AttackMovement = null

# ── st_mk ──
@export var st_mk_damage: float = 6.0
@export var st_mk_hitstun_frames: int = 33      # 33 幀 = 0.55 秒
@export var st_mk_blockstun_frames: int = 18    # 18 幀 = 0.30 秒
@export var st_mk_knockback: float = 130.0
@export var st_mk_movement: AttackMovement = null

# ── st_hk ──
@export var st_hk_damage: float = 9.0
@export var st_hk_hitstun_frames: int = 20      # 20 幀 = 0.333 秒
@export var st_hk_blockstun_frames: int = 22    # 22 幀 = 0.367 秒
@export var st_hk_knockback: float = 110.0
@export var st_hk_movement: AttackMovement = null

# ── cr_lp ──
@export var cr_lp_damage: float = 2.0
@export var cr_lp_hitstun_frames: int = 15      # 15 幀 = 0.25 秒
@export var cr_lp_blockstun_frames: int = 10    # 10 幀 = 0.167 秒
@export var cr_lp_knockback: float = 70.0
@export var cr_lp_movement: AttackMovement = null

# ── cr_mp ──
@export var cr_mp_damage: float = 6.0
@export var cr_mp_hitstun_frames: int = 21      # 21 幀 = 0.35 秒
@export var cr_mp_blockstun_frames: int = 14    # 14 幀 = 0.233 秒
@export var cr_mp_knockback: float = 80.0
@export var cr_mp_movement: AttackMovement = null

# ── cr_hp ──
@export var cr_hp_damage: float = 9.0
@export var cr_hp_hitstun_frames: int = 30      # 30 幀 = 0.50 秒
@export var cr_hp_blockstun_frames: int = 18    # 18 幀 = 0.30 秒
@export var cr_hp_knockback: float = 80.0
@export var cr_hp_movement: AttackMovement = null

# ── cr_lk ──
@export var cr_lk_damage: float = 2.0
@export var cr_lk_hitstun_frames: int = 15      # 15 幀 = 0.25 秒
@export var cr_lk_blockstun_frames: int = 12    # 12 幀 = 0.20 秒
@export var cr_lk_knockback: float = 100.0
@export var cr_lk_movement: AttackMovement = null

# ── cr_mk ──
@export var cr_mk_damage: float = 6.0
@export var cr_mk_hitstun_frames: int = 30      # 30 幀 = 0.50 秒
@export var cr_mk_blockstun_frames: int = 16    # 16 幀 = 0.267 秒
@export var cr_mk_knockback: float = 140.0
@export var cr_mk_movement: AttackMovement = null

# ── cr_hk ──
@export var cr_hk_damage: float = 9.0
@export var cr_hk_hitstun_frames: int = 39      # 39 幀 = 0.65 秒
@export var cr_hk_blockstun_frames: int = 20    # 20 幀 = 0.333 秒
@export var cr_hk_knockback: float = 150.0
@export var cr_hk_movement: AttackMovement = null

# ── jump_lp ──
@export var jump_lp_damage: float = 3.0
@export var jump_lp_hitstun_frames: int = 18    # 18 幀 = 0.30 秒
@export var jump_lp_blockstun_frames: int = 12  # 12 幀 = 0.20 秒
@export var jump_lp_knockback: float = 80.0

# ── jump_mp ──
@export var jump_mp_damage: float = 6.0
@export var jump_mp_hitstun_frames: int = 24    # 24 幀 = 0.40 秒
@export var jump_mp_blockstun_frames: int = 16  # 16 幀 = 0.267 秒
@export var jump_mp_knockback: float = 110.0

# ── jump_hp ──
@export var jump_hp_damage: float = 9.0
@export var jump_hp_hitstun_frames: int = 30    # 30 幀 = 0.50 秒
@export var jump_hp_blockstun_frames: int = 20  # 20 幀 = 0.333 秒
@export var jump_hp_knockback: float = 120.0

# ── jump_lk ──
@export var jump_lk_damage: float = 2.0
@export var jump_lk_hitstun_frames: int = 24    # 24 幀 = 0.40 秒
@export var jump_lk_blockstun_frames: int = 14  # 14 幀 = 0.233 秒
@export var jump_lk_knockback: float = 60.0

# ── jump_mk ──
@export var jump_mk_damage: float = 5.0
@export var jump_mk_hitstun_frames: int = 30    # 30 幀 = 0.50 秒
@export var jump_mk_blockstun_frames: int = 18  # 18 幀 = 0.30 秒
@export var jump_mk_knockback: float = 60.0

# ── jump_hk ──
@export var jump_hk_damage: float = 9.0
@export var jump_hk_hitstun_frames: int = 36    # 36 幀 = 0.60 秒
@export var jump_hk_blockstun_frames: int = 22  # 22 幀 = 0.367 秒
@export var jump_hk_knockback: float = 70.0

# ═══════════════════════════════════════════════════════════════════════════
# 🟢 單一入口：取代 18 個獨立的 Dictionary getter 屬性
# jump_* 攻擊不含 movement 鍵（保持原有合約）
# ═══════════════════════════════════════════════════════════════════════════
func get_attack(attack_name: String) -> Dictionary:
	var d := {
		"damage":    get(attack_name + "_damage"),
		"hitstun":   get(attack_name + "_hitstun_frames"),
		"blockstun": get(attack_name + "_blockstun_frames"),
		"knockback": get(attack_name + "_knockback"),
	}
	if not attack_name.begins_with("jump_"):
		d["movement"] = get(attack_name + "_movement")
	return d

func frames_to_seconds(frames: int) -> float:
	return float(frames) / float(LOGIC_FPS)
