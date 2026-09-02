extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 2：顯式狀態層必須與**現行動畫判定鏈**逐狀態對齊。
##
## 為什麼需要這個用例：
## FighterState.resolve() 是照著當年的動畫判定鏈抄出來的優先序
## （切片 6 之前是 Player._compute_target_state() + AnimationManager
##  .compute_target_state() 兩份抄本；切片 6 起合成為唯一的
##  FighterState.animation_for()，逐值等價，由 test_40 釘住）。
## 抄一次容易，保持同步難 —— 只要有人改了動畫鏈而忘了狀態表（或反過來），
## 兩者就會悄悄分岔，而 Stage 2 後續切片正要把控制流改成讀狀態。
## 本用例在幾個**可確定性重現**的關鍵狀態上比對兩層，讓分岔立刻失敗。
##
## 比對規則（刻意的收斂，見 FighterState 檔頭）：
##   - Jump_F / Jump_B / Jump_V   → JUMP（方向是 jump_dir 參數，不是狀態）
##   - IDLE / WALK                → 動畫層同為 "Walk"（靠 blend_position 區分）
##   - cr_idle / cr_down          → CROUCH
##   - hit / cr_hit               → HITSTUN
##   - block / cr_block           → BLOCKSTUN / PROXIMITY_BLOCK
##   - 各招式名（st_mp/dp/...）    → ATTACK / SPECIAL_MOVE
##
## 兩個**已知分岔**（見 FighterState.gd 檔頭的詳細說明）在比對時跳過，
## 因為它們是動畫層的缺口而非狀態表抄錯，且修正它們會改變遊戲行為
## （守則第 2 條：本刀不改行為）：
##   - BEING_THROWN：動畫層沒有對應分支，被摔者續播被抓前的動畫。
##   - 空中且 is_jumping/is_air_attacking 皆假：動畫層會掉回 "Walk"。
## 跳過的次數會被計數並印出來，避免「靜默跳過」把真正的分岔一起吃掉。

## 動畫節點名 → 期望狀態集合（一個動畫可能對應多個合法狀態）
const ANIM_TO_STATES: Dictionary = {
	"Walk": ["IDLE", "WALK"],
	"cr_idle": ["CROUCH"],
	"cr_down": ["CROUCH"],
	"Dash": ["DASH"],
	"Backdash": ["BACKDASH"],
	"Jump_F": ["JUMP", "AIR_ATTACK"],
	"Jump_B": ["JUMP", "AIR_ATTACK", "HITSTUN"],
	"Jump_V": ["JUMP", "AIR_ATTACK"],
	"hit": ["HITSTUN"],
	"cr_hit": ["HITSTUN"],
	"block": ["BLOCKSTUN", "PROXIMITY_BLOCK"],
	"cr_block": ["BLOCKSTUN", "PROXIMITY_BLOCK"],
	"knockfly": ["KNOCKFLY"],
	"layground": ["KNOCKDOWN", "KO"],
	"wakeup": ["WAKEUP"],
	"landing": ["LANDING"],
}

func run() -> bool:
	await await_frames(10)
	# 距離刻意拉近到 ~180px：第 7 段互毆時 st_hp/st_mk 才打得到，
	# 讓 hit / block / knockfly 這些狀態真的出現在比對樣本裡。
	teleport_x(p1, 520.0)
	teleport_x(p2, 700.0)
	await await_frames(5)

	# ── 1. 靜止：IDLE ──────────────────────────────────────────────
	check(FighterState.state_name(p1.get_fighter_state()) == "IDLE",
		"靜止站立應為 IDLE，實為 %s" % p1.get_fighter_state_name())

	# ── 2. 走路：WALK（且 fixed_velocity.x != 0）────────────────────
	# 注意：第 2 幀才取樣。第 1 幀輸入剛送進去，速度要等 WalkHandler 跑過
	# 才非零 —— 這不是行為問題，是取樣時機問題。
	Input.action_press("move_right")
	await await_frames(6)
	var walk_state: String = p1.get_fighter_state_name()
	var walk_vel: int = p1.fixed_velocity.x
	Input.action_release("move_right")
	check(walk_state == "WALK",
		"按住方向鍵應為 WALK（vel_x=%d），實為 %s" % [walk_vel, walk_state])
	await await_frames(10)
	# 放開後應回到 IDLE（速度歸零）
	check(p1.get_fighter_state_name() == "IDLE",
		"放開方向鍵後應回到 IDLE，實為 %s" % p1.get_fighter_state_name())

	# ── 3. 蹲下：CROUCH ────────────────────────────────────────────
	Input.action_press("crouch")
	await await_frames(6)
	var crouch_state: String = p1.get_fighter_state_name()
	Input.action_release("crouch")
	check(crouch_state == "CROUCH", "按住下蹲應為 CROUCH，實為 %s" % crouch_state)
	await await_frames(10)

	# ── 4. 地面攻擊：ATTACK ────────────────────────────────────────
	# 【必要】先清空輸入歷史再按攻擊鍵。
	# 上面第 2/3 段剛按過「右」與「下」，若立刻補一個拳，
	# InputManager 會把 右→下→拳 當成方向指令宏（DP/fireball 之類）而發特殊招 ——
	# CI 第一次跑就是這樣掛的：is_attacking 沒設起來、狀態變成 SPECIAL_MOVE，
	# 連帶後面的 JUMP/LANDING 斷言一起崩（DP 自帶著地，不會進 landing 狀態）。
	var me = p1
	await _flush_motion_history()
	Input.action_press("st_mp")
	var attacking: bool = await wait_until(func(): return me.is_attacking, 20)
	Input.action_release("st_mp")
	check(attacking, "st_mp 應進入攻擊狀態（狀態=%s）" % p1.get_fighter_state_name())
	if attacking:
		check(p1.get_fighter_state_name() == "ATTACK",
			"地面攻擊應為 ATTACK，實為 %s" % p1.get_fighter_state_name())
	await wait_until(func(): return not me.is_attacking, 120)
	await await_frames(10)

	# ── 5. 跳躍：JUMP（三個方向動畫都收斂到同一狀態）──────────────
	# 同樣先清歷史：避免上一段的攻擊輸入與跳躍組成宏。
	await _flush_motion_history()
	await tap("jump")
	var airborne: bool = await wait_until(func(): return not me.is_on_floor(), 120)
	check(airborne, "跳躍應離地")
	if airborne:
		check(p1.get_fighter_state_name() == "JUMP",
			"空中應為 JUMP，實為 %s" % p1.get_fighter_state_name())

	# ── 6. 著地：LANDING，且與 Stage 1 的幀鎖不變式一致 ────────────
	var landing: bool = await wait_until(
		func(): return me.is_on_floor() and me.is_landing, 360)
	check(landing, "應進入著地狀態")
	if landing:
		check(p1.get_fighter_state_name() == "LANDING",
			"著地期間應為 LANDING，實為 %s" % p1.get_fighter_state_name())
		check(p1.landing_lock_frames > 0,
			"LANDING 狀態必須伴隨 landing_lock_frames > 0（Stage 1 不變式）")
	await wait_until(func(): return not me.is_landing, 240)
	await await_frames(5)

	# ── 7. 全程比對：狀態層 vs 動畫層不得分岔 ──────────────────────
	# 讓兩個角色互毆 240 幀，每幀比對「動畫節點名」與「解析狀態」。
	# 只在 ANIM_TO_STATES 有登記的節點上比對（招式動畫名太多且會隨角色變）。
	var mismatches: Array = []
	var compared: int = 0
	var skipped_known: int = 0
	# 【1 幀容差】AnimationTree.travel() 是延遲生效的：狀態旗標在第 N 幀改變，
	# animation_state.get_current_node() 要到第 N+1 幀才反映。因此比對時
	# 只要「當前狀態」或「上一幀狀態」其一符合該動畫即算通過。
	# 這不會放過真正的分岔 —— 持續超過 1 幀的不一致仍然會失敗。
	var prev_state: Dictionary = {}
	Input.action_press("move_right")
	for frame in 240:
		if frame == 40:
			Input.action_release("move_right")
		if frame % 30 == 10:
			Input.action_press("st_mk_p2")
		if frame % 30 == 12:
			Input.action_release("st_mk_p2")
		if frame % 40 == 20:
			Input.action_press("st_hp")
		if frame % 40 == 22:
			Input.action_release("st_hp")
		await await_frames(1)

		for fighter in [p1, p2]:
			var actual: String = fighter.get_fighter_state_name()
			var previous: String = str(prev_state.get(fighter.name, actual))
			prev_state[fighter.name] = actual

			var anim: String = _current_anim(fighter)
			if not ANIM_TO_STATES.has(anim):
				continue
			if _is_known_divergence(fighter):
				skipped_known += 1
				continue
			compared += 1
			var expected: Array = ANIM_TO_STATES[anim]
			# 容許動畫落後狀態 1 幀（travel 延遲），見上方說明。
			if (actual in expected) or (previous in expected):
				continue
			if mismatches.size() < 6:
				mismatches.append("frame %d %s: 動畫 '%s' 期望 %s，狀態層給 %s（前一幀 %s）" % [
					frame, fighter.name, anim, str(expected), actual, previous])
	Input.action_release("move_right")
	Input.action_release("st_hp")
	Input.action_release("st_mk_p2")

	print("      比對樣本數: %d（跳過已知分岔 %d）" % [compared, skipped_known])
	check(compared >= 100,
		"比對樣本過少（%d），本用例失去意義" % compared)
	check(mismatches.is_empty(),
		"狀態層與動畫層分岔：%s" % " | ".join(mismatches))
	return not has_failures()

## 這一幀是否落在兩個「已知動畫層缺口」之一（見檔頭）。
## 刻意寫成**狀態條件**而非「比對失敗就原諒」，否則真正的新分岔會被吃掉。
func _is_known_divergence(fighter: Node) -> bool:
	# 1) 被摔投：動畫層無對應分支
	if "is_being_thrown" in fighter and fighter.is_being_thrown:
		return true
	# 2) 在空中，但動畫層的空中分支條件（is_jumping / is_air_attacking）皆不成立
	var on_floor: bool = fighter.is_on_floor()
	var jumping: bool = "is_jumping" in fighter and fighter.is_jumping
	var air_attacking: bool = "is_air_attacking" in fighter and fighter.is_air_attacking
	if not on_floor and not jumping and not air_attacking:
		return true
	return false

## 等待足夠久，讓 InputManager 的方向指令宏視窗過期。
##
## `InputManager.MAX_TOTAL_FRAMES = 120`（1 秒 @120Hz）是整段宏的匹配上限，
## 因此只要中間隔了 >120 幀的中立輸入，先前按過的方向就不可能再與後續按鍵
## 組成宏。這裡取 130 幀留一點餘裕。
##
## 為什麼不能只 await 幾幀：本用例按順序測 走路(右) → 蹲下(下) → 攻擊(拳)，
## 這個序列本身就長得像 DP（右→下→右下+拳）。不隔開的話會發特殊招而非普通攻擊。
func _flush_motion_history() -> void:
	await await_frames(130)

## 目前的動畫節點名（AnimationTree 播放中的狀態；landing 走 AnimationPlayer）
func _current_anim(fighter: Node) -> String:
	if fighter.animation_tree and not fighter.animation_tree.active:
		# landing 期間 AnimationManager 會關掉 AnimationTree 改用 AnimationPlayer
		if fighter.animation_player:
			return str(fighter.animation_player.current_animation)
	if fighter.animation_state:
		return str(fighter.animation_state.get_current_node())
	return ""
