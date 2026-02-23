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
			"powerkk", "DAV", 12.0, 600.0, 56.0, 150.0, 0.0, 0.0, false, false, 0.0, "special", false, "three_phase", 0.25, 0.2, 0.55, 0.0, 0.0, 0.0, 39, 23, false, []
		)

	_md = _load_smd(smd_super, "res://data/specials/dav_super.tres")
	if _md:
		move_library[_md.name] = _md
	else:
		move_library["super"] = MoveData.new(
			"super", "DAV", 5.0, 200.0, 100.0, 0.0, 0.0, 0.0, true, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0,
			7400000.0, -2800.0, 20.0, 39, 23, false, []
		)

	# ── 升龍拳（dp generic fallback 常駐，讓 start_dp() 有基礎條目）──
	move_library["dp"] = MoveData.new(
		"dp", "DAV", 5.0, 100.0, 47.0, 40.0, 4.0, -2100.0, false, false, 7200000.0, "special", true, "none", 0.0, 0.0, 0.0,
		10000000.0, -3200.0, 20.0, 39, 23, false, []
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
	if _md:
		# 🔴 調試：打印100p的多段信息
		print("[DAVMoveSet] 100p loaded: is_multi_hit=%s, hit_phases.size()=%d" % [_md.is_multi_hit, _md.hit_phases.size()])
		if _md.hit_phases.size() > 0:
			for i in _md.hit_phases.size():
				var hp = _md.hit_phases[i]
				if hp:
					print("  [Phase%d] frame=%d, damage=%.1f, hitstun=%d, knockback=%.1f" % [i, hp.frame, hp.damage, hp.hitstun, hp.knockback])
				else:
					print("  [Phase%d] NULL HitPhaseData!" % i)
		# ✅ 多段hit數據已修復（DAV.tscn中的4個phase補全了缺失字段）
		print("[DAVMoveSet] ✅ 100p多段hit數據完整，啟用多段模式")
		move_library[_md.name] = _md
	else:
		print("[DAVMoveSet] ⚠️  100p fallback: resource load failed, creating default")
		move_library["100p"] = MoveData.new(
			"100p", "DAV", 5.0, 100.0, 60.0, 0.0, 0.0, 0.0, false, false, 0.0, "special", false, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 18, 10, false, []
		)
