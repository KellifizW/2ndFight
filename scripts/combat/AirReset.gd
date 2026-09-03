class_name AirReset extends RefCounted

## ══════════════════════════════════════════════════════════════════════════
## AirReset —— 全局「空中重置 / Air Reset（Flip-out）」機制
## ══════════════════════════════════════════════════════════════════════════
##
## 這是一條**全局規則**（所有角色、所有攻擊來源共用）：
## 當「非擊倒性攻擊」（輕/中普通攻擊、輕特殊招等，不帶 Launch / Hard Knockdown
## 屬性）擊中一個處於 `Airborne`（跳躍、空中攻擊、浮空殘留幀）的目標時，
## 目標**不會**進入 knockfly（擊飛倒地），而是進入「空中重置」狀態：
##
##   1. 狀態檢測 (State Detection)
##      受擊方 not is_on_floor()，且本次命中沒有 force_knockfly / 傷害門檻
##      觸發的 knockfly（見 `should_air_reset`）。
##   2. 打擊停頓 (Hitstop)
##      沿用全局 HitStopController（本檔不重複實作）；空中重置的速度向量在
##      hitstop **之前**寫入，因此定格結束的第一幀就已經是重置後的軌跡。
##   3. 強制狀態轉換 (State Transition)
##      受擊方從「跳躍 / 空中攻擊 / 特殊招」被**強制**切成空中受擊重置狀態：
##      清掉攻擊狀態、關掉自己的 Hitbox、禁止在這次滯空中再出招
##      （has_air_attacked = true），動畫鎖到 Jump_B。
##   4. 賦予物理向量 (Velocity Application)
##      清除原有跳躍動量（x、y 一律歸零後重寫），再賦予一組**固定**的
##      X 軸（向後推力）+ Y 軸（向上微浮空）速度向量，並在滯空期間套用
##      空氣阻力與（可調降的）重力，形成「向後滯空」的弧線。
##
## 為什麼要獨立成一個檔：
## 之前這段邏輯散在 fighter.gd 的 take_hit 裡（只寫速度、沒清狀態），
## 而滯空期間的重力/摩擦在 KnockflyHandler、水平推擠又被 PushManager 的
## knockback 分支蓋掉 —— 三處互相打架，所以「看起來會後跳，但不是真正的
## 空中重置」。現在**參數與判定只有這一份**，任何角色、任何攻擊來源
## （近身攻擊 HitResponseHandler / 火球 fireball.gd）都走同一條路。
##
## 狀態旗標沿用既有的 `is_air_hit_backjump`（動畫鏈、FighterState、
## LandingHandler、KnockflyHandler 都已認得它），避免再多一個平行旗標。

# ── 全局可調參數（所有角色共用；角色場景不覆寫）─────────────────────────
## X 軸向後推力（px/s，正值代表「往受擊者背後」）。
const BACK_SPEED: float = 400.0
## Y 軸向上微浮空（px/s，負值向上）。刻意比正常跳躍(-2500)小很多：
## 這是「被打得輕輕飄起來」，不是再跳一次。
const UP_SPEED: float = -1100.0
## 最短滯空幀數（物理幀 @120Hz）。實際時長 = max(本值, 該招 hitstun)。
const MIN_FRAMES: int = 24
## 滯空幀數上限，避免長 hitstun 招把人吊在空中太久。
const MAX_FRAMES: int = 72
## 空中重置期間的重力倍率（<1 = 更長的滯空感 / hang time）。
const GRAVITY_SCALE: float = 0.80
## 空中重置期間每物理幀的水平衰減量（fixed units），讓後退是「滑出去再停」。
const AIR_FRICTION: float = 90.0


## 這一次命中該不該走空中重置？
##
## 三個條件（對應「一、系統底層的觸發原理」的第 1 點）：
##   - 受擊方在空中（Airborne）
##   - 這一招沒有 Launch / Hard Knockdown 屬性（force_knockfly）
##   - 沒有因傷害門檻或 KO 而升級成 knockfly
## 任何一項不成立就回到原本的 knockfly / 地面 hitstun 流程。
static func should_air_reset(target: Node, should_knockfly: bool) -> bool:
	if target == null:
		return false
	if should_knockfly:
		return false
	if target.has_method("is_on_floor") and target.is_on_floor():
		return false
	return true


## 空中重置的實際時長（物理幀）：以該招 hitstun 為底，夾在 [MIN, MAX]。
static func resolve_frames(hitstun_physics_frames: int) -> int:
	return clampi(hitstun_physics_frames, MIN_FRAMES, MAX_FRAMES)


## 套用空中重置。呼叫時機：Fighter.take_hit() 內、hitstop 請求**之前**。
##
## `facing_mult` = 受擊者的面向乘數（get_facing_multiplier）；X 推力方向為
## 「受擊者的背後」= -facing。
static func apply(f: Node, hitstun_physics_frames: int, facing_mult: float) -> void:
	if f == null:
		return
	var scale: float = f.world.SIMULATION_SCALE if f.world else 1000.0

	# ── 3. 強制狀態轉換：先把受擊方身上「進攻中」的一切關掉 ──────────────
	_cancel_offense(f)

	# ── 4. 賦予物理向量：先清除原有動量，再寫入固定向量 ──────────────────
	f.fixed_velocity.x = 0
	f.fixed_velocity.y = 0
	f.fixed_velocity.x = int(-BACK_SPEED * scale * facing_mult)
	f.fixed_velocity.y = int(UP_SPEED * scale)
	# 抬離地面 2 unit，確保 is_on_floor() 當幀就是 false（否則 GravityHandler
	# 會把剛寫進去的向上速度清成 0，人就「被打在原地」）。
	f.fixed_position.y -= 2

	# ── 狀態旗標 ────────────────────────────────────────────────────────
	f.is_air_hit_backjump = true
	f.air_hit_backjump_timer = resolve_frames(hitstun_physics_frames)
	f.is_jumping = true          # 讓空中族的動畫/落地判定成立
	f.just_jumped = true         # 擋掉 GravityHandler 的「地面清速度」
	f.jump_dir = -f.facing_direction   # Jump_B（向後翻）當幀就對
	f.jump_delay_timer = 0
	f.is_immune_to_floor_snap = true
	f.floor_snap_immunity_timer = Movement.seconds_to_frames_nearest(
		f.floor_snap_immunity_duration)

	Debug.log("[AIR RESET] %s 空中重置 → vel=(%d, %d), frames=%d (hitstun=%d)" % [
		f.name, f.fixed_velocity.x, f.fixed_velocity.y,
		f.air_hit_backjump_timer, hitstun_physics_frames])


## 空中重置期間的每幀物理（由 KnockflyHandler 呼叫）：重力 + 空氣阻力。
## 回傳 true 表示這一幀「空中重置狀態已結束」（呼叫端負責收尾）。
static func step(f: Node) -> bool:
	f.air_hit_backjump_timer = max(0, f.air_hit_backjump_timer - 1)

	# 重力：以真實物理步長（1/120）套用，並乘上 GRAVITY_SCALE。
	# （舊版寫死 1/60 —— 在 120Hz 物理下等於**兩倍重力**，所以根本沒有滯空感。）
	var gravity: float = float(f.world.GRAVITY) if f.world else 6000000.0
	var timestep: float = 1.0 / float(max(1, Engine.physics_ticks_per_second))
	f.fixed_velocity.y += int(gravity * GRAVITY_SCALE * timestep)

	# 空氣阻力：水平速度朝 0 收斂，形成「滑出去、慢慢停」的後退弧線。
	var friction: int = int(AIR_FRICTION)
	if f.fixed_velocity.x > 0:
		f.fixed_velocity.x = max(0, f.fixed_velocity.x - friction)
	elif f.fixed_velocity.x < 0:
		f.fixed_velocity.x = min(0, f.fixed_velocity.x + friction)

	return f.air_hit_backjump_timer <= 0 or f.is_on_floor()


## 關掉受擊方身上所有「進攻中」的狀態。
##
## 這是舊實作最大的缺口：舊版只寫速度，於是被打的人**還在出招**——
## is_air_attacking 沒清、Hitbox 還開著（空中對拳時會互相貫穿命中）、
## has_air_attacked 沒鎖（重置後還能在同一次滯空再出一招），
## 特殊招也還在跑。真正的空中重置必須把這些一次歸零。
static func _cancel_offense(f: Node) -> void:
	var move_set: Node = f.get_node_or_null("MoveSet")
	if move_set != null and "is_spmove" in move_set and move_set.is_spmove \
			and move_set.has_method("stop_special_move"):
		move_set.stop_special_move()

	if "is_attacking" in f:
		f.is_attacking = false
	if "is_air_attacking" in f:
		f.is_air_attacking = false
	# 這次滯空不得再出招（空中重置 = 失去空中行動權，直到落地）。
	if "has_air_attacked" in f:
		f.has_air_attacked = true
	if "attack_type" in f:
		f.attack_type = "none"
	if "attack_duration_timer" in f:
		f.attack_duration_timer = 0
	if "is_special_moving" in f:
		f.is_special_moving = false

	# 關掉自己還開著的 Hitbox：被重置的一方不該還能打到人。
	var hit_shape: Node = f.get_node_or_null("Hitbox/HitShape")
	if hit_shape != null and "disabled" in hit_shape:
		hit_shape.set_deferred("disabled", true)
