## DAVMoveSet.gd
## DAV 角色專用招式設定。在 Inspector 只顯示 DAV 的招式欄位。
class_name DAVMoveSet extends MoveSet

# ============================================================
# DAV 招式資料 (Inspector 可直接拖入 .tres 編輯)
# ============================================================

@export_group("DAV 基礎招式")
@export var smd_powerkk: SpecialMoveData   ## 霸王腳
@export var smd_super: SpecialMoveData     ## 超必殺（百裂拳）

@export_group("DAV 升龍拳", "smd_dp")
@export var smd_dp: SpecialMoveData        ## 升龍拳（通用後備，通常不用）
@export var smd_dpL: SpecialMoveData       ## 升龍拳 L
@export var smd_dpM: SpecialMoveData       ## 升龍拳 M
@export var smd_dpH: SpecialMoveData       ## 升龍拳 H

@export_group("DAV 火球", "smd_fireball")
@export var smd_fireballL: SpecialMoveData ## 火球 L
@export var smd_fireballM: SpecialMoveData ## 火球 M
@export var smd_fireballH: SpecialMoveData ## 火球 H

@export_group("DAV 百裂拳", "smd_")
@export var smd_100p: SpecialMoveData      ## 百裂拳（多段連打）

@export_group("")  # 結束分組

# ============================================================
# 初始化招式庫（只載入 DAV 的招式）
# ============================================================

func _initialize_move_library() -> void:
	super._initialize_move_library()  # 登錄通用後備（fireball）
	var _md: MoveData

	# ── 基礎招式 ──────────────────────────────────────────
	_md = _load_smd(smd_powerkk, "res://data/specials/dav_powerkk.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		move_library["powerkk"] = MoveData.new(
			"powerkk", "DAV", 12.0, 600.0, 56.0, 150.0, 0.0, 0.0, false, false, 0.0, "special", false, "three_phase", 0.25, 0.2, 0.55, 0.0, 0.0, 0.0, 39, 23
		)

	_md = _load_smd(smd_super, "res://data/specials/dav_super.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		move_library["super"] = MoveData.new(
			"super", "DAV", 5.0, 200.0, 100.0, 0.0, 0.0, 0.0, true, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0,
			7400000.0, -2800.0, 20.0, 39, 23
		)

	# ── 升龍拳（dp generic fallback 常駐，讓 start_dp() 有基礎條目）──
	move_library["dp"] = MoveData.new(
		"dp", "DAV", 5.0, 100.0, 47.0, 40.0, 4.0, -2100.0, false, false, 7200000.0, "special", true, "none", 0.0, 0.0, 0.0,
		10000000.0, -3200.0, 20.0, 39, 23
	)
	_md = _load_smd(smd_dp, "res://data/specials/dav_dp.tres")
	if _md: move_library[_md.name] = _md

	for entry in [
		[smd_dpL, "res://data/specials/dav_dpL.tres"],
		[smd_dpM, "res://data/specials/dav_dpM.tres"],
		[smd_dpH, "res://data/specials/dav_dpH.tres"],
	]:
		_md = _load_smd(entry[0], entry[1])
		if _md: move_library[_md.name] = _md

	# ── 火球變體 ──────────────────────────────────────────
	for entry in [
		[smd_fireballL, "res://data/specials/dav_fireballL.tres"],
		[smd_fireballM, "res://data/specials/dav_fireballM.tres"],
		[smd_fireballH, "res://data/specials/dav_fireballH.tres"],
	]:
		_md = _load_smd(entry[0], entry[1])
		if _md: move_library[_md.name] = _md

	# ── 百裂拳 ────────────────────────────────────────────
	_md = _load_smd(smd_100p, "res://data/specials/dav_100p.tres")
	if _md: move_library[_md.name] = _md
