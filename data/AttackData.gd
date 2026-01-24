# res://data/AttackData.gd
class_name AttackData extends Resource

# ── st_lp ──
@export var st_lp_damage: float = 6.0
@export var st_lp_hitstun: float = 0.30
@export var st_lp_blockstun: float = 0.200
@export var st_lp_knockback: float = 150.0

# ── st_mp ──
@export var st_mp_damage: float = 10.0
@export var st_mp_hitstun: float = 0.40
@export var st_mp_blockstun: float = 0.267
@export var st_mp_knockback: float = 250.0

# ── st_hp ──
@export var st_hp_damage: float = 14.0
@export var st_hp_hitstun: float = 0.55
@export var st_hp_blockstun: float = 0.333
@export var st_hp_knockback: float = 350.0

# ── st_lk ──
@export var st_lk_damage: float = 7.0
@export var st_lk_hitstun: float = 0.50
@export var st_lk_blockstun: float = 0.233
@export var st_lk_knockback: float = 200.0

# ── st_mk ──
@export var st_mk_damage: float = 9.0
@export var st_mk_hitstun: float = 0.65
@export var st_mk_blockstun: float = 0.300
@export var st_mk_knockback: float = 280.0

# ── st_hk ──
@export var st_hk_damage: float = 12.0
@export var st_hk_hitstun: float = 0.75
@export var st_hk_blockstun: float = 0.367
@export var st_hk_knockback: float = 400.0

# ── cr_lp ──
@export var cr_lp_damage: float = 5.0
@export var cr_lp_hitstun: float = 0.25
@export var cr_lp_blockstun: float = 0.167
@export var cr_lp_knockback: float = 120.0

# ── cr_mp ──
@export var cr_mp_damage: float = 8.0
@export var cr_mp_hitstun: float = 0.35
@export var cr_mp_blockstun: float = 0.233
@export var cr_mp_knockback: float = 180.0

# ── cr_hp ──
@export var cr_hp_damage: float = 12.0
@export var cr_hp_hitstun: float = 0.50
@export var cr_hp_blockstun: float = 0.300
@export var cr_hp_knockback: float = 300.0

# ── cr_lk ──
@export var cr_lk_damage: float = 6.5
@export var cr_lk_hitstun: float = 0.40
@export var cr_lk_blockstun: float = 0.200
@export var cr_lk_knockback: float = 150.0

# ── cr_mk ──
@export var cr_mk_damage: float = 9.0
@export var cr_mk_hitstun: float = 0.50
@export var cr_mk_blockstun: float = 0.267
@export var cr_mk_knockback: float = 200.0

# ── cr_hk ──
@export var cr_hk_damage: float = 11.0
@export var cr_hk_hitstun: float = 0.65
@export var cr_hk_blockstun: float = 0.333
@export var cr_hk_knockback: float = 350.0

# ── jump_mp ──
@export var jump_mp_damage: float = 8.0
@export var jump_mp_hitstun: float = 0.40
@export var jump_mp_blockstun: float = 0.267
@export var jump_mp_knockback: float = 220.0

# ── jump_mk ──
@export var jump_mk_damage: float = 9.0
@export var jump_mk_hitstun: float = 0.50
@export var jump_mk_blockstun: float = 0.300
@export var jump_mk_knockback: float = 260.0

# Dictionary accessors for code compatibility
var st_lp: Dictionary:
	get: return { "damage": st_lp_damage, "hitstun": st_lp_hitstun, "blockstun": st_lp_blockstun, "knockback": st_lp_knockback }
var st_mp: Dictionary:
	get: return { "damage": st_mp_damage, "hitstun": st_mp_hitstun, "blockstun": st_mp_blockstun, "knockback": st_mp_knockback }
var st_hp: Dictionary:
	get: return { "damage": st_hp_damage, "hitstun": st_hp_hitstun, "blockstun": st_hp_blockstun, "knockback": st_hp_knockback }
var st_lk: Dictionary:
	get: return { "damage": st_lk_damage, "hitstun": st_lk_hitstun, "blockstun": st_lk_blockstun, "knockback": st_lk_knockback }
var st_mk: Dictionary:
	get: return { "damage": st_mk_damage, "hitstun": st_mk_hitstun, "blockstun": st_mk_blockstun, "knockback": st_mk_knockback }
var st_hk: Dictionary:
	get: return { "damage": st_hk_damage, "hitstun": st_hk_hitstun, "blockstun": st_hk_blockstun, "knockback": st_hk_knockback }
var cr_lp: Dictionary:
	get: return { "damage": cr_lp_damage, "hitstun": cr_lp_hitstun, "blockstun": cr_lp_blockstun, "knockback": cr_lp_knockback }
var cr_mp: Dictionary:
	get: return { "damage": cr_mp_damage, "hitstun": cr_mp_hitstun, "blockstun": cr_mp_blockstun, "knockback": cr_mp_knockback }
var cr_hp: Dictionary:
	get: return { "damage": cr_hp_damage, "hitstun": cr_hp_hitstun, "blockstun": cr_hp_blockstun, "knockback": cr_hp_knockback }
var cr_lk: Dictionary:
	get: return { "damage": cr_lk_damage, "hitstun": cr_lk_hitstun, "blockstun": cr_lk_blockstun, "knockback": cr_lk_knockback }
var cr_mk: Dictionary:
	get: return { "damage": cr_mk_damage, "hitstun": cr_mk_hitstun, "blockstun": cr_mk_blockstun, "knockback": cr_mk_knockback }
var cr_hk: Dictionary:
	get: return { "damage": cr_hk_damage, "hitstun": cr_hk_hitstun, "blockstun": cr_hk_blockstun, "knockback": cr_hk_knockback }
var jump_mp: Dictionary:
	get: return { "damage": jump_mp_damage, "hitstun": jump_mp_hitstun, "blockstun": jump_mp_blockstun, "knockback": jump_mp_knockback }
var jump_mk: Dictionary:
	get: return { "damage": jump_mk_damage, "hitstun": jump_mk_hitstun, "blockstun": jump_mk_blockstun, "knockback": jump_mk_knockback }
