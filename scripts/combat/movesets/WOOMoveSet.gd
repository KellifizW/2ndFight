## WOOMoveSet.gd
## WOO 角色專用招式設定。在 Inspector 只顯示 WOO 的招式欄位。
class_name WOOMoveSet extends MoveSet

# ============================================================
# WOO 招式資料 (Inspector 可直接拖入 .tres 編輯)
# ============================================================

@export_group("WOO 特殊招式")
@export var smd_214K: SpecialMoveData   ## 214K（214 後半圈 + 任意腳：輕/中/重腳皆可）
@export var smd_623K: SpecialMoveData   ## 623K（623 升龍系 + 任意腳：輕/中/重腳皆可）

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

	# ── 623K（623 + 任意腳）──────────────────────────────
	_md = _load_smd(smd_623K, "res://data/specials/woo_623K.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		move_library["623K"] = MoveData.new(
			"623K", "WOO", 10.0, 120.0, 0.0, 0.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 24, 14, false, []
		)
