extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2 切片 6：動畫判定鏈的唯一定義（FighterState.animation_for）必須與
## **它取代的兩份舊抄本合成後實際生效的鏈**逐幀等價。
##
## 為什麼需要這個用例：
## 切片 6 之前這條「這一幀該播哪個動畫」的優先序有兩份抄本 ——
##   1. Player._compute_target_state()（攔截頭段，其餘 super 下去）
##   2. AnimationManager.compute_target_state()（把同樣八段又寫一次，
##      順序還不同，後面才接尾段）
## 因為所有角色場景掛的都是 player.gd，抄本 2 的頭段實機不可達，
## 兩份從來沒被同步過。切片 6 把**合成後實際生效**的順序搬進
## FighterState.animation_for()，刪掉兩份抄本。
##
## 本用例把舊的合成鏈**原樣重寫在這裡**當對照組，每幀比對新舊。
## （尾段裡與頭段重複的那八段不重寫：頭段已經 return，走不到它們；
##   「它們不可達」這個結論由 ci/verify_animation_chain.py 連同不可達分支
##   一起窮舉證明，不是本用例假設出來的。）對照組刻意保留舊寫法，不要「順手優化」成呼叫
## FighterState，否則這個用例會變成自己跟自己比。
##
## Python 暴力窮舉（ci/verify_animation_chain.py，18,874,368 組合）已先證明
## 0 分岔；本用例在引擎內逐幀釘住真實可達的旗標軌跡，並要求觀察到足夠多
## 種不同的動畫（避免「整場都是 Walk」的假綠）。

const RANDOM_FRAMES: int = 600
const SEED: int = 20260903

const AIR_ATTACK_ANIMS: Array = [
	"jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk",
]
const GROUND_ATTACK_ANIMS: Array = [
	"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
	"cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
	"throw_enter", "throw_seq",
]

var _samples: int = 0
var _mismatches: Array = []
var _observed: Dictionary = {}

func run() -> bool:
	await await_frames(10)
	# 距離拉近（沿用 test_26 的布景）：讓 hit / block / knockfly / landing
	# 這些高優先段真的出現在樣本裡，而不是整場都在尾段。
	teleport_x(p1, 520.0)
	teleport_x(p2, 700.0)
	await await_frames(5)

	# ── 階段 1：確定性覆蓋幾個關鍵段落 ──────────────────────────────
	# 蹲下（cr_idle，尾段第 14 段 + cr_down 副作用）
	Input.action_press("crouch")
	for i in 8:
		await await_frames(1)
		_sample(p1, i)
		_sample(p2, i)
	Input.action_release("crouch")
	await await_frames(5)

	# 跳躍（Jump_*，第 8 段）
	await tap("jump")
	for i in 60:
		await await_frames(1)
		_sample(p1, 100 + i)
		_sample(p2, 100 + i)
	# 著地（landing，第 7 段）
	var me = p1
	await wait_until(func(): return me.is_on_floor() and not me.is_jumping, 240)
	for i in 20:
		await await_frames(1)
		_sample(p1, 200 + i)
		_sample(p2, 200 + i)

	# 命中對手（hit / block，第 4 / 6 段）
	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")
	for i in 120:
		await await_frames(1)
		_sample(p1, 300 + i)
		_sample(p2, 300 + i)

	# ── 階段 2：600 幀固定種子隨機輸入 ─────────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var actions: Array = [
		"move_left", "move_right", "jump", "crouch",
		"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
		"spmove1", "spmove2", "spmove3",
	]
	var p2_actions: Array = [
		"move_left_p2", "move_right_p2", "jump_p2", "crouch_p2",
		"st_lp_p2", "st_mp_p2", "st_hp_p2", "st_lk_p2", "st_mk_p2", "st_hk_p2",
	]
	var held: Dictionary = {}

	for frame in RANDOM_FRAMES:
		if frame % 5 == 0:
			for action in held.keys():
				Input.action_release(action)
			held.clear()
			var n: int = rng.randi_range(0, 3)
			for i in n:
				var a: String = actions[rng.randi_range(0, actions.size() - 1)]
				if not held.has(a):
					Input.action_press(a)
					held[a] = true
			var b: String = p2_actions[rng.randi_range(0, p2_actions.size() - 1)]
			if not held.has(b):
				Input.action_press(b)
				held[b] = true

		await await_frames(1)
		_sample(p1, 1000 + frame)
		_sample(p2, 1000 + frame)

	for action in held.keys():
		Input.action_release(action)

	check(_mismatches.is_empty(),
		"動畫鏈與舊合成鏈分岔：%s" % " | ".join(_mismatches))

	# 覆蓋度：必須真的觀察到多種動畫，否則「逐幀相等」只是在比對常數。
	var names: Array = _observed.keys()
	names.sort()
	print("      動畫覆蓋（%d 樣本）: %s" % [_samples, ", ".join(names)])
	check(names.size() >= 5,
		"樣本內至少要出現 5 種不同動畫（實際 %d 種：%s），否則比對不具意義"
			% [names.size(), ", ".join(names)])
	check(_observed.has("Walk"), "樣本內應出現 Walk（尾段預設）")
	var saw_airborne: bool = _observed.has("Jump_V") or _observed.has("Jump_F") \
		or _observed.has("Jump_B")
	check(saw_airborne, "樣本內應出現 Jump_* （第 8 段：空中族）")

	return not has_failures()

## 逐幀比對：舊合成鏈（原樣搬運）vs FighterState.animation_for()。
func _sample(fighter: Node, frame: int) -> void:
	_samples += 1
	var on_floor: bool = bool(fighter.is_on_floor())
	var crouch_input: bool = bool(fighter.is_crouching)
	# 動畫層實際餵進來的 anim_jump_dir = jump_dir × facing_direction。
	var anim_jump_dir: float = float(fighter.jump_dir) * float(fighter.facing_direction)

	var legacy: String = _legacy_chain(fighter, crouch_input, on_floor, anim_jump_dir)
	var unified: String = FighterState.animation_for(
		fighter, crouch_input, on_floor, anim_jump_dir)

	_observed[unified] = true

	if legacy != unified and _mismatches.size() < 8:
		_mismatches.append("frame %d %s: legacy=%s new=%s (floor=%s crouch=%s hit=%s blocking=%s attacking=%s type=%s landing=%s/%d jumping=%s air_atk=%s)" % [
			frame, fighter.name, legacy, unified,
			on_floor, crouch_input, bool(fighter.is_hit), bool(fighter.is_blocking),
			bool(fighter.is_attacking), str(fighter.attack_type),
			bool(fighter.is_landing), int(fighter.landing_lock_frames),
			bool(fighter.is_jumping), bool(fighter.is_air_attacking)])

## 對照組：Player._compute_target_state()（頭段）+ AnimationManager
## .compute_target_state()（尾段）合成後的舊鏈，逐行原樣重寫。
## 尾段中與頭段重複的八段略過（頭段已 return，走不到）；「它們不可達」
## 由 ci/verify_animation_chain.py 連同不可達分支一起窮舉證明。
## 不要改寫成呼叫 FighterState，否則用例會變成自己跟自己比。
func _legacy_chain(f: Node, crouch_input: bool, on_floor: bool, anim_jump_dir: float) -> String:
	var move_set = f.get_node_or_null("MoveSet")

	# ── Player 頭段 ──
	if f.is_layground:
		return "layground"
	if f.is_knockfly:
		return "knockfly"
	if f.is_wakeup_locked:
		return "wakeup"
	if f.is_hit:
		if not on_floor and bool(f.is_air_hit_backjump):
			return "Jump_B"
		if on_floor:
			return "cr_hit" if f.was_hit_while_crouching else "hit"
		return "Jump_B"
	if move_set and move_set.is_spmove:
		var head_move_name: String = str(move_set.get_active_move_name())
		if head_move_name != "":
			return head_move_name
	if f.is_blocking:
		return "cr_block" if f.is_crouch_blocking and crouch_input else "block"
	if f.is_landing and int(f.landing_lock_frames) > 0:
		return "landing"
	if not on_floor and (f.is_jumping or f.is_air_attacking):
		if f.is_air_attacking and str(f.attack_type) in AIR_ATTACK_ANIMS:
			return str(f.attack_type)
		if anim_jump_dir > 0:
			return "Jump_F"
		elif anim_jump_dir < 0:
			return "Jump_B"
		else:
			return "Jump_V"

	# ── AnimationManager 尾段（舊 super；與頭段重複的段落略過，見檔頭）──
	if bool(f.is_air_hit_backjump):
		return "Jump_B"
	if f.is_proximity_blocking:
		return "cr_block" if f.is_crouching else "block"
	if f.is_attacking:
		var atype: String = str(f.attack_type)
		if atype in GROUND_ATTACK_ANIMS:
			return atype
		if atype != "" and atype != "none" and move_set \
				and move_set.has_method("has_move_id") and move_set.has_move_id(atype):
			return atype
		return "Walk"
	if f.is_dashing:
		return "Dash"
	if f.is_backdashing:
		return "Backdash"
	if crouch_input and on_floor and not f.is_blocking:
		return "cr_idle"
	return "Walk"
