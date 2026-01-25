# res://data/AttackData.gd
class_name AttackData extends Resource

# ── st_lp ──
@export var st_lp_damage: float = 6.0
@export var st_lp_hitstun: float = 0.30
@export var st_lp_blockstun: float = 0.200
@export var st_lp_knockback: float = 150.0
@export var st_lp_movement: AttackMovement = null

# ── st_mp ──
@export var st_mp_damage: float = 10.0
@export var st_mp_hitstun: float = 0.40
@export var st_mp_blockstun: float = 0.267
@export var st_mp_knockback: float = 250.0
@export var st_mp_movement: AttackMovement = null

# ── st_hp ──
@export var st_hp_damage: float = 14.0
@export var st_hp_hitstun: float = 0.55
@export var st_hp_blockstun: float = 0.333
@export var st_hp_knockback: float = 350.0
@export var st_hp_movement: AttackMovement = null

# ── st_lk ──
@export var st_lk_damage: float = 7.0
@export var st_lk_hitstun: float = 0.50
@export var st_lk_blockstun: float = 0.233
@export var st_lk_knockback: float = 200.0
@export var st_lk_movement: AttackMovement = null

# ── st_mk ──
@export var st_mk_damage: float = 9.0
@export var st_mk_hitstun: float = 0.65
@export var st_mk_blockstun: float = 0.300
@export var st_mk_knockback: float = 280.0
@export var st_mk_movement: AttackMovement = null

# ── st_hk ──
@export var st_hk_damage: float = 12.0
@export var st_hk_hitstun: float = 0.75
@export var st_hk_blockstun: float = 0.367
@export var st_hk_knockback: float = 400.0
@export var st_hk_movement: AttackMovement = null

# ── cr_lp ──
@export var cr_lp_damage: float = 5.0
@export var cr_lp_hitstun: float = 0.25
@export var cr_lp_blockstun: float = 0.167
@export var cr_lp_knockback: float = 120.0
@export var cr_lp_movement: AttackMovement = null

# ── cr_mp ──
@export var cr_mp_damage: float = 8.0
@export var cr_mp_hitstun: float = 0.35
@export var cr_mp_blockstun: float = 0.233
@export var cr_mp_knockback: float = 180.0
@export var cr_mp_movement: AttackMovement = null

# ── cr_hp ──
@export var cr_hp_damage: float = 12.0
@export var cr_hp_hitstun: float = 0.50
@export var cr_hp_blockstun: float = 0.300
@export var cr_hp_knockback: float = 300.0
@export var cr_hp_movement: AttackMovement = null

# ── cr_lk ──
@export var cr_lk_damage: float = 6.5
@export var cr_lk_hitstun: float = 0.40
@export var cr_lk_blockstun: float = 0.200
@export var cr_lk_knockback: float = 150.0
@export var cr_lk_movement: AttackMovement = null

# ── cr_mk ──
@export var cr_mk_damage: float = 9.0
@export var cr_mk_hitstun: float = 0.50
@export var cr_mk_blockstun: float = 0.267
@export var cr_mk_knockback: float = 200.0
@export var cr_mk_movement: AttackMovement = null

# ── cr_hk ──
@export var cr_hk_damage: float = 11.0
@export var cr_hk_hitstun: float = 0.65
@export var cr_hk_blockstun: float = 0.333
@export var cr_hk_knockback: float = 350.0
@export var cr_hk_movement: AttackMovement = null

# ── jump_lp ──
@export var jump_lp_damage: float = 6.0
@export var jump_lp_hitstun: float = 0.30
@export var jump_lp_blockstun: float = 0.200
@export var jump_lp_knockback: float = 180.0

# ── jump_mp ──
@export var jump_mp_damage: float = 8.0
@export var jump_mp_hitstun: float = 0.40
@export var jump_mp_blockstun: float = 0.267
@export var jump_mp_knockback: float = 220.0

# ── jump_hp ──
@export var jump_hp_damage: float = 12.0
@export var jump_hp_hitstun: float = 0.50
@export var jump_hp_blockstun: float = 0.333
@export var jump_hp_knockback: float = 320.0

# ── jump_lk ──
@export var jump_lk_damage: float = 7.0
@export var jump_lk_hitstun: float = 0.40
@export var jump_lk_blockstun: float = 0.233
@export var jump_lk_knockback: float = 200.0

# ── jump_mk ──
@export var jump_mk_damage: float = 9.0
@export var jump_mk_hitstun: float = 0.50
@export var jump_mk_blockstun: float = 0.300
@export var jump_mk_knockback: float = 260.0

# ── jump_hk ──
@export var jump_hk_damage: float = 11.0
@export var jump_hk_hitstun: float = 0.60
@export var jump_hk_blockstun: float = 0.367
@export var jump_hk_knockback: float = 380.0

# Dictionary accessors for code compatibility
var st_lp: Dictionary:
	get: return { "damage": st_lp_damage, "hitstun": st_lp_hitstun, "blockstun": st_lp_blockstun, "knockback": st_lp_knockback, "movement": st_lp_movement }
var st_mp: Dictionary:
	get: return { "damage": st_mp_damage, "hitstun": st_mp_hitstun, "blockstun": st_mp_blockstun, "knockback": st_mp_knockback, "movement": st_mp_movement }
var st_hp: Dictionary:
	get: return { "damage": st_hp_damage, "hitstun": st_hp_hitstun, "blockstun": st_hp_blockstun, "knockback": st_hp_knockback, "movement": st_hp_movement }
var st_lk: Dictionary:
	get: return { "damage": st_lk_damage, "hitstun": st_lk_hitstun, "blockstun": st_lk_blockstun, "knockback": st_lk_knockback, "movement": st_lk_movement }
var st_mk: Dictionary:
	get: return { "damage": st_mk_damage, "hitstun": st_mk_hitstun, "blockstun": st_mk_blockstun, "knockback": st_mk_knockback, "movement": st_mk_movement }
var st_hk: Dictionary:
	get: return { "damage": st_hk_damage, "hitstun": st_hk_hitstun, "blockstun": st_hk_blockstun, "knockback": st_hk_knockback, "movement": st_hk_movement }
var cr_lp: Dictionary:
	get: return { "damage": cr_lp_damage, "hitstun": cr_lp_hitstun, "blockstun": cr_lp_blockstun, "knockback": cr_lp_knockback, "movement": cr_lp_movement }
var cr_mp: Dictionary:
	get: return { "damage": cr_mp_damage, "hitstun": cr_mp_hitstun, "blockstun": cr_mp_blockstun, "knockback": cr_mp_knockback, "movement": cr_mp_movement }
var cr_hp: Dictionary:
	get: return { "damage": cr_hp_damage, "hitstun": cr_hp_hitstun, "blockstun": cr_hp_blockstun, "knockback": cr_hp_knockback, "movement": cr_hp_movement }
var cr_lk: Dictionary:
	get: return { "damage": cr_lk_damage, "hitstun": cr_lk_hitstun, "blockstun": cr_lk_blockstun, "knockback": cr_lk_knockback, "movement": cr_lk_movement }
var cr_mk: Dictionary:
	get: return { "damage": cr_mk_damage, "hitstun": cr_mk_hitstun, "blockstun": cr_mk_blockstun, "knockback": cr_mk_knockback, "movement": cr_mk_movement }
var cr_hk: Dictionary:
	get: return { "damage": cr_hk_damage, "hitstun": cr_hk_hitstun, "blockstun": cr_hk_blockstun, "knockback": cr_hk_knockback, "movement": cr_hk_movement }
var jump_lp: Dictionary:
	get: return { "damage": jump_lp_damage, "hitstun": jump_lp_hitstun, "blockstun": jump_lp_blockstun, "knockback": jump_lp_knockback }
var jump_mp: Dictionary:
	get: return { "damage": jump_mp_damage, "hitstun": jump_mp_hitstun, "blockstun": jump_mp_blockstun, "knockback": jump_mp_knockback }
var jump_hp: Dictionary:
	get: return { "damage": jump_hp_damage, "hitstun": jump_hp_hitstun, "blockstun": jump_hp_blockstun, "knockback": jump_hp_knockback }
var jump_lk: Dictionary:
	get: return { "damage": jump_lk_damage, "hitstun": jump_lk_hitstun, "blockstun": jump_lk_blockstun, "knockback": jump_lk_knockback }
var jump_mk: Dictionary:
	get: return { "damage": jump_mk_damage, "hitstun": jump_mk_hitstun, "blockstun": jump_mk_blockstun, "knockback": jump_mk_knockback }
var jump_hk: Dictionary:
	get: return { "damage": jump_hk_damage, "hitstun": jump_hk_hitstun, "blockstun": jump_hk_blockstun, "knockback": jump_hk_knockback }
