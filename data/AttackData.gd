# res://data/AttackData.gd
class_name AttackData extends Resource

# ── st_mp ──
@export var st_mp_damage: float = 10.0
@export var st_mp_hitstun: float = 0.40
@export var st_mp_blockstun: float = 0.267
@export var st_mp_knockback: float = 250.0

# ── st_mk ──
@export var st_mk_damage: float = 9.0
@export var st_mk_hitstun: float = 0.65
@export var st_mk_blockstun: float = 0.300
@export var st_mk_knockback: float = 280.0

# ── cr_mp ──
@export var cr_mp_damage: float = 8.0
@export var cr_mp_hitstun: float = 0.35
@export var cr_mp_blockstun: float = 0.233
@export var cr_mp_knockback: float = 180.0

# ── cr_mk ──
@export var cr_mk_damage: float = 9.0
@export var cr_mk_hitstun: float = 0.50
@export var cr_mk_blockstun: float = 0.267
@export var cr_mk_knockback: float = 200.0

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
var st_mp: Dictionary:
	get: return { "damage": st_mp_damage, "hitstun": st_mp_hitstun, "blockstun": st_mp_blockstun, "knockback": st_mp_knockback }
var st_mk: Dictionary:
	get: return { "damage": st_mk_damage, "hitstun": st_mk_hitstun, "blockstun": st_mk_blockstun, "knockback": st_mk_knockback }
var cr_mp: Dictionary:
	get: return { "damage": cr_mp_damage, "hitstun": cr_mp_hitstun, "blockstun": cr_mp_blockstun, "knockback": cr_mp_knockback }
var cr_mk: Dictionary:
	get: return { "damage": cr_mk_damage, "hitstun": cr_mk_hitstun, "blockstun": cr_mk_blockstun, "knockback": cr_mk_knockback }
var jump_mp: Dictionary:
	get: return { "damage": jump_mp_damage, "hitstun": jump_mp_hitstun, "blockstun": jump_mp_blockstun, "knockback": jump_mp_knockback }
var jump_mk: Dictionary:
	get: return { "damage": jump_mk_damage, "hitstun": jump_mk_hitstun, "blockstun": jump_mk_blockstun, "knockback": jump_mk_knockback }
