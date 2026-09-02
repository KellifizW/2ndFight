## WOOMoveSet.gd
## WOO 角色專用招式設定。在 Inspector 只顯示 WOO 的招式欄位。
class_name WOOMoveSet extends MoveSet

# ============================================================
# WOO 招式資料 (Inspector 可直接拖入 .tres 編輯)
# ============================================================

@export_group("WOO 特殊招式")
@export var smd_214K: SpecialMoveData   ## 214K（214 後半圈 + 任意腳：輕/中/重腳皆可）
@export var smd_623K: SpecialMoveData   ## 623K（623 升龍系 + 任意腳：輕/中/重腳皆可）

@export_group("WOO 火球", "smd_fireball")
@export var smd_fireball: SpecialMoveData  ## 火球（WOO，236 + 任意拳，投射物使用 WOO_fireball.tscn）

@export_group("")  # 結束分組

# ============================================================
# 初始化招式庫（只載入 WOO 的招式）
# ============================================================

func _initialize_move_library() -> void:
	super._initialize_move_library()  # 登錄通用後備（fireball）
	var _md: MoveData

	# ── 214K（214 + 任意腳）──────────────────────────────
	_md = _load_smd(smd_214K, "res://data/specials/woo_214K.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		# 後備：duration 0 = 自動同步動畫長度（見 MoveSet._start_special）
		move_library["214K"] = MoveData.new(
			"214K", "WOO", 8.0, 80.0, 0.0, 0.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 20, 12, false, []
		)

	# ── 623K（623 + 任意腳，升空飛踢）────────────────────
	_md = _load_smd(smd_623K, "res://data/specials/woo_623K.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		# 後備：duration 0 = 自動同步動畫；jump_delay/jump_speed 對應 caster jump
		var _fallback_623k = MoveData.new(
			"623K", "WOO", 30.0, 200.0, 0.0, 300.0, 6.0, -1500.0, false, false, 6000000.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 24, 14, false, []
		)
		_fallback_623k.caster_jump_enabled = true
		move_library["623K"] = _fallback_623k

	# ── 火球（236 + 任意拳）──────────────────────────────
	# WOO 的火球與 DAV/DEN 走同一條路徑：動畫 Call Method _spawn_fireball
	# → execute_fireball_spawn() → ResourcePreloader 取出 WOO_fireball.tscn。
	_md = _load_smd(smd_fireball, "res://data/specials/woo_fireball.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		# 後備：duration 0 = 自動同步動畫長度（見 MoveSet._start_special）
		var _fallback_fireball = MoveData.new(
			"fireball", "WOO", 10.0, 80.0, 0.0, 0.0, 0.0, 0.0, false, true, 0.0, "FireballCallPlayer", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 24, 14, false, []
		)
		_fallback_fireball.projectile_speed = 800.0
		move_library["fireball"] = _fallback_fireball
