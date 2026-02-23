## DENMoveSet.gd
## DEN 角色專用招式設定。在 Inspector 只顯示 DEN 的招式欄位。
class_name DENMoveSet extends MoveSet

# ============================================================
# DEN 招式資料 (Inspector 可直接拖入 .tres 編輯)
# ============================================================

@export_group("DEN 基礎招式")
@export var smd_spnk: SpecialMoveData   ## 旋風腿
@export var smd_hdk: SpecialMoveData    ## 飛腳踢

@export_group("DEN 火球", "smd_fireball")
@export var smd_fireball: SpecialMoveData  ## 火球（DEN）

@export_group("")  # 結束分組

# ============================================================
# 初始化招式庫（只載入 DEN 的招式）
# ============================================================

func _initialize_move_library() -> void:
	super._initialize_move_library()  # 登錄通用後備（fireball）
	var _md: MoveData

	_md = _load_smd(smd_spnk, "res://data/specials/den_spnk.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		move_library["spnk"] = MoveData.new(
			"spnk", "DEN", 12.0, 280.0, 72.0, 250.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 27, 23
		)

	_md = _load_smd(smd_hdk, "res://data/specials/den_hdk.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		move_library["hdk"] = MoveData.new(
			"hdk", "DEN", 3.0, 290.0, 66.0, 200.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 27, 23
		)

	_md = _load_smd(smd_fireball, "res://data/specials/den_fireball.tres")
	if _md: move_library[_md.name] = _md
