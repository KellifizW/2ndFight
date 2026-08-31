class_name FighterState extends RefCounted
## Stage 2 狀態層：顯式狀態機的「單一活動狀態」定義 + 解析器 + 各子系統守衛。
##
## 切片 1 — 唯讀狀態層（已落地）：
##   - State enum（19 態）+ resolve(fighter) 純函數
##   - check_invariants() / known_illegal_overlaps() 結構性不變式
##   - 攻擊 id 唯一清單（GROUND/AIR_ATTACK_IDS）
##   - is_throw_attack_id / is_throw_in_progress
## 切片 2 — 攻擊子系統守衛（已落地）：
##   - can_start_ground_attack / can_start_air_attack
## 切片 3 — 移動子系統守衛（已落地）：
##   - can_walk / can_dash / can_jump
## 切片 4 — 受擊子系統守衛（本檔）：
##   - is_input_locked（Player.get_input 的吞輸入判定）
##   - is_combo_stunned（連段續航判定，HitResponseHandler / fireball 兩份抄本）
##   - can_initiate_throw（摔投發起守衛）/ can_be_thrown（摔投目標守衛）
## 切片 5 — 格擋族守衛：
##   - can_enter_block_stance（BlockingHandler 站姿進入 / 持續擋向重取樣）
##   - can_release_block_stance（BlockingHandler 站姿釋放）
##
## ── 為什麼先做解析器，而不是直接改寫控制流 ─────────────────────────────
## plan_game.md §6 的遷移策略寫得很清楚：「按子系統切段，旗標與狀態並行期間
## 用測試對齊」。本檔就是那個並行期的骨架 —— 它**只讀不寫**：
## 從現有的 ~34 個 bool 旗標推導出「此刻恰好一個」的狀態，
## 不改變任何遊戲行為（一幀都不變），但讓兩件事第一次成為可測的：
##
##   1. 狀態優先序從「散落在 player.gd / AnimationManager.gd 兩條 if 鏈裡的
##      隱性約定」變成一張**寫下來、可被測試釘住**的表（本檔 resolve()）。
##   2. 旗標之間的非法組合（例如同時 is_dashing + is_backdashing）
##      從「靠約定維護、無人檢查」變成 test_25 每幀斷言的不變式。
##
## 之後的切片才會逐一把控制流改成「讀狀態」而不是「讀旗標組合」，
## 每一刀都有 test_25/test_26 當安全網。這一刀本身不動控制流。
##
## ── 優先序從哪裡來（重要：這是描述，不是設計）───────────────────────
## resolve() 的順序**刻意逐條複製**現有動畫層的判定鏈，因為那條鏈就是這個
## 遊戲事實上的狀態優先序：
##   Player._compute_target_state():
##     layground → knockfly → wakeup_locked → hit → spmove → blocking
##     → landing → 空中(air_attack/jump) → super(...)
##   AnimationManager.compute_target_state()（Player 未攔截的尾段）:
##     ... → proximity_block → blocking → attacking → dash → backdash
##     → crouch → 空中 → walk
## 若有人改了其中一條鏈而沒改另一條，test_26 會立刻抓到不一致 ——
## 這正是把隱性約定變成顯式契約的價值。
##
## 兩個刻意的收斂（記錄在案，避免日後誤判為 bug）：
##   - Jump_F / Jump_B / Jump_V 合併為 JUMP：方向是狀態的參數（jump_dir），
##     不是三個狀態。CrouchAttack 同理併入 ATTACK（姿勢由 attack_type 表達）。
##   - WALK / IDLE 在動畫層同為 "Walk"（靠 blend_position 區分），
##     狀態層拆開較有意義，故 test_26 比對時把兩者都映射回 "Walk"。
##
## ── 兩處狀態層與動畫層**確實分岔**的地方（窮舉比對找出，非設計選擇）────
## 把 resolve() 與兩條動畫鏈的所有旗標組合（55k+ 種）拿去對撞後，
## 扣掉下面兩類，其餘**完全一致**。這兩類是動畫層本身的缺口，
## 不是狀態表抄錯 —— 因此狀態層照實模型化，並在 test_26 標記為已知例外：
##
##   1. `is_being_thrown`：動畫層**完全沒有**對應分支。被摔的一方在整個
##      摔投過程中會繼續播放被抓前的任何動畫（走路/攻擊/蹲下…），
##      視覺上由 ThrowHandler 直接接管位置來掩蓋。狀態層給 BEING_THROWN，
##      因為那才是這一幀真正的語意（輸入被吃掉、位置被外部接管）。
##   2. 「在空中但 is_jumping 與 is_air_attacking 皆為 false」：
##      動畫層的空中分支要求 `is_jumping or is_air_attacking`，
##      兩者皆假時會一路掉到最後的 `return "Walk"` —— 也就是人在半空中
##      卻播走路動畫。可達路徑例如空中受擊後跳結束（KnockflyHandler 清掉
##      is_air_hit_backjump 與 is_hit）而尚未落地那幾幀。
##      狀態層回報 JUMP（物理上就是在空中），不跟著動畫層一起錯。
##
## 這兩點都**不在本刀修正範圍**（守則第 2 條：重構期間行為一幀不變），
## 但既然被找出來就記錄下來，Stage 2 後續切片改控制流時一併處理。

## 單一活動狀態。任何時刻 resolve() 只會回傳其中一個。
enum State {
	IDLE,
	WALK,
	CROUCH,
	DASH,
	BACKDASH,
	JUMP,
	AIR_ATTACK,
	ATTACK,
	THROWING,
	BEING_THROWN,
	SPECIAL_MOVE,
	PROXIMITY_BLOCK,
	BLOCKSTUN,
	HITSTUN,
	LANDING,
	KNOCKFLY,
	KNOCKDOWN,
	WAKEUP,
	KO,
}

## 摔投相關的 attack_type（攻擊方）。ThrowHandler 用這兩個字串驅動整段摔投。
const THROW_ATTACK_TYPES: Array = ["throw_enter", "throw_seq"]

# ── 攻擊 id 的唯一定義（Stage 2 切片 2）─────────────────────────────────
##
## 為什麼搬到狀態層：攻擊 id 同時是三種東西 —— 動畫名、`ATTACK_TABLE` 的鍵、
## `attack_type` 的合法值。切片 2 之前它有四份抄本：
##   1. `Player._ATTACK_NAMES`（建 ATTACK_TABLE 用）
##   2. `Player.GROUND_ATTACK_ANIMS`（動畫結束時判斷要不要 reset）
##   3. `Player.AIR_ATTACK_ANIMS`（空中攻擊動畫名 + 空中受擊分支）
##   4. `AnimationManager.compute_target_state` 內嵌的字面值清單
## 四份清單兩兩重疊，任何一份漏改都會讓某個招式在「某一層」失效
## （例：動畫播得出來但 reset 不觸發 → is_attacking 卡住）。
## 現在 1/2/3 全部指向這裡，AnimationManager 的清單留待 Stage 3
## 與 frame data 一起收攏（它是動畫層的表，不是狀態層的）。
const GROUND_ATTACK_IDS: Array = [
	"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
	"cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
]

const AIR_ATTACK_IDS: Array = [
	"jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk",
]

## attack_type 是不是普通攻擊（地面或空中）。
static func is_normal_attack_id(id: String) -> bool:
	return id in GROUND_ATTACK_IDS or id in AIR_ATTACK_IDS

## attack_type 是不是摔投階段（攻擊方）。
## 收攏前這個字面值對在四個檔案裡各寫了一遍
## （Player ×3、AttackExecutor、PushManager ×2）。
static func is_throw_attack_id(id: String) -> bool:
	return id in THROW_ATTACK_TYPES

## attack_type 是不是「真的在出招」的合法值。
static func is_attack_id(id: String) -> bool:
	return is_normal_attack_id(id) or is_throw_attack_id(id)

## 攻擊方是否正在執行摔投。
##
## 語意 = 舊的 `is_attacking and attack_type in ["throw_enter", "throw_seq"]`。
## 這個組合代表「輸入被吃掉、位置由 ThrowHandler 接管」，
## 與 resolve() 的 THROWING 是同一件事的兩種寫法。
static func is_throw_in_progress(f: Node) -> bool:
	return _flag(f, "is_attacking") and is_throw_attack_id(_string(f, "attack_type"))

## State → 可讀名稱（測試輸出與除錯用；不參與遊戲邏輯）。
static func state_name(state: int) -> String:
	match state:
		State.IDLE: return "IDLE"
		State.WALK: return "WALK"
		State.CROUCH: return "CROUCH"
		State.DASH: return "DASH"
		State.BACKDASH: return "BACKDASH"
		State.JUMP: return "JUMP"
		State.AIR_ATTACK: return "AIR_ATTACK"
		State.ATTACK: return "ATTACK"
		State.THROWING: return "THROWING"
		State.BEING_THROWN: return "BEING_THROWN"
		State.SPECIAL_MOVE: return "SPECIAL_MOVE"
		State.PROXIMITY_BLOCK: return "PROXIMITY_BLOCK"
		State.BLOCKSTUN: return "BLOCKSTUN"
		State.HITSTUN: return "HITSTUN"
		State.LANDING: return "LANDING"
		State.KNOCKFLY: return "KNOCKFLY"
		State.KNOCKDOWN: return "KNOCKDOWN"
		State.WAKEUP: return "WAKEUP"
		State.KO: return "KO"
	return "?(%d)" % state

## 由現行旗標推導單一活動狀態。**純函數：不寫入 fighter 的任何欄位。**
##
## 順序即優先序，逐條對應上面記錄的兩條動畫判定鏈。
static func resolve(f: Node) -> int:
	if f == null:
		return State.IDLE

	# ── 倒地/擊飛族（最高優先：這些狀態會吞掉所有輸入）──
	# KO 是 KNOCKDOWN 的細化：AnimationManager 在血量歸零且 is_layground 時
	# 強制停在 layground（不進 wakeup），狀態層據此分出 KO。
	if _flag(f, "is_layground"):
		if _is_knocked_out(f):
			return State.KO
		return State.KNOCKDOWN
	if _flag(f, "is_knockfly"):
		return State.KNOCKFLY
	# 被摔投：輸入被 Player.get_input() 全部吃掉、位置由 ThrowHandler 接管。
	# 排在 knockfly 之後，與 PushManager 的 `is_being_thrown and not is_knockfly`
	# 判定一致（摔投最後的拋飛階段屬於 KNOCKFLY）。
	if _flag(f, "is_being_thrown"):
		return State.BEING_THROWN
	if _flag(f, "is_wakeup_locked"):
		return State.WAKEUP

	# ── 受擊/防禦族 ──
	if _flag(f, "is_hit"):
		return State.HITSTUN

	# ── 特殊招式（Player 鏈中排在 blocking 之前）──
	var move_set: Node = f.get_node_or_null("MoveSet")
	if move_set != null and _flag(move_set, "is_spmove"):
		return State.SPECIAL_MOVE

	if _flag(f, "is_blocking"):
		return State.BLOCKSTUN

	# ── 著地鎖（Stage 1 不變式：狀態的權威是幀計數，不是動畫長度）──
	if _flag(f, "is_landing") and _int(f, "landing_lock_frames") > 0:
		return State.LANDING

	# ── 空中族 ──
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		if _flag(f, "is_air_attacking"):
			return State.AIR_ATTACK
		if _flag(f, "is_jumping"):
			return State.JUMP

	# ── 地面動作族（對應 AnimationManager 尾段順序）──
	if _flag(f, "is_proximity_blocking"):
		return State.PROXIMITY_BLOCK
	if _flag(f, "is_attacking"):
		if is_throw_attack_id(_string(f, "attack_type")):
			return State.THROWING
		return State.ATTACK
	if _flag(f, "is_dashing"):
		return State.DASH
	if _flag(f, "is_backdashing"):
		return State.BACKDASH
	if on_floor and _flag(f, "is_crouching"):
		return State.CROUCH

	# 空中但既非 jump 也非 air attack（例：空中受擊後跳結束仍未落地）
	# 動畫層在這裡會落到 Jump_*，狀態層同樣視為 JUMP。
	if not on_floor:
		return State.JUMP

	# WALK/IDLE 以實際水平速度區分（動畫層同為 "Walk"，靠 blend_position 表現）。
	if "fixed_velocity" in f and f.fixed_velocity.x != 0:
		return State.WALK
	return State.IDLE

## 這一幀能不能開始一個**地面**普通攻擊或摔投。
##
## 切片 2 之前這個判斷有三份互不相同的抄本：
##   - `Player._physics_process` 的 `is_valid_ground_state`
##   - 同函式裡「著地攻擊取消」之後的**重算版**（少掉 landing 那一項）
##   - `Fighter._physics_process` 舊攻擊入口的 `is_valid_state`
##     （多一項 `not is_crouching`、少 landing / wakeup / layground 三項）
## 前兩份已收攏到這裡；第三份連同它所在的舊入口一起移除
## （見 fighter.gd 的 Stage 2 註解）。
##
## 注意 landing 那一項刻意放行最後 `LANDING_INTERRUPT_FRAMES` 幀：
## 著地鎖的尾巴本來就要能被攻擊取消，這是既有行為，不是新規則。
static func can_start_ground_attack(f: Node) -> bool:
	if f == null:
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		return false
	if _flag(f, "is_dashing") or _flag(f, "is_backdashing") or _flag(f, "is_jumping"):
		return false
	if _flag(f, "is_blocking") or _flag(f, "is_knockfly") \
			or _flag(f, "is_wakeup") or _flag(f, "is_layground"):
		return false
	if _flag(f, "is_landing") and _int(f, "landing_lock_frames") > Movement.LANDING_INTERRUPT_FRAMES:
		return false
	return true

## 這一幀能不能開始一個**空中**普通攻擊。
##
## 語意 = 舊的 `Player.is_valid_air_state`（一字不差搬過來）。
## 這裡刻意保留 `is_hit` 一項 —— 地面版沒有它，因為地面受擊時
## `get_input()` 已經回傳空輸入；空中受擊（air_hit_backjump）則不然，
## 這一項是空中版唯一的輸入防線，不能跟著地面版一起拿掉。
static func can_start_air_attack(f: Node) -> bool:
	if f == null:
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if on_floor:
		return false
	if not _flag(f, "is_jumping") or _flag(f, "is_air_attacking") or _flag(f, "has_air_attacked"):
		return false
	if _flag(f, "is_blocking") or _flag(f, "is_knockfly") or _flag(f, "is_hit") \
			or _flag(f, "is_wakeup") or _flag(f, "is_layground"):
		return false
	return true

## 這一刻能不能開始**走路**（WalkHandler 的 can_walk 等價收攏）。
##
## 切片 3 之前這條表達式在 WalkHandler 內聯展開（player.gd 還有一份稍異的舊版），
## 且同時被 Movement._physics_process 結尾的「能不能清零水平速度」邏輯參考。
## 收攏後**所有「能不能走」判定都讀這個函式**，讓「走路被某個旗標擋下」
## 這類型 bug 變成結構上集中在一處。
##
## 注意 is_special_moving 是 Player / MoveSet 持有的非狀態機旗標（特殊招式期間
## 走任何地面動作都該被擋下），它不屬於 resolve() 的 State 列舉，所以保留成參數。
## 若 is_special_moving 為 true，整個表達式恆為 false（與舊版一致）。
##
## 對應舊版（WalkHandler.handle_walk）：
##   can_walk = is_on_floor() and not is_attacking and not is_dashing
##     and not is_backdashing and not is_special_moving
##     and not (is_hit or is_knockfly or is_blocking or is_layground
##              or is_in_knockback or is_in_corner_push or is_in_block_knockback)
##     and not is_crouching
static func can_walk(f: Node, is_special_moving: bool = false) -> bool:
	if f == null:
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		return false
	if is_special_moving:
		return false
	if _flag(f, "is_attacking") or _flag(f, "is_dashing") or _flag(f, "is_backdashing"):
		return false
	if _flag(f, "is_hit") or _flag(f, "is_knockfly") or _flag(f, "is_blocking") \
			or _flag(f, "is_layground") or _flag(f, "is_crouching"):
		return false
	# knockback / corner push / block knockback 是幀計數器（hitstun / blockstun
	# 期間的附加水平位移），期間不該允許玩家主動走路 —— 與舊版一致。
	if _int(f, "knockback_frames") > 0 or _int(f, "corner_push_frames") > 0 \
			or _int(f, "block_knockback_frames") > 0:
		return false
	return true

## 這一刻能不能開始一個**衝刺/後衝**（DashHandler / Movement._physics_process
## 的 AI 直接 dash 守衛）。不含中性 timer / 雙擊方向匹配等「觸發條件」——
## 那些是 DashHandler 內部的細節，與「能不能衝」是兩件事。
##
## 對應舊版（DashHandler.handle_dash 與 Movement._physics_process 的 AI 分支）：
##   is_on_floor() and not is_landing_locked and not is_attacking
##     and not is_dashing and not is_backdashing and not is_special_moving
##     and not (is_hit or is_knockfly or is_blocking or is_layground)
##     and not is_crouching
## is_landing_locked = is_landing and landing_lock_frames > 0
static func can_dash(f: Node, is_special_moving: bool = false) -> bool:
	if f == null:
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		return false
	if is_special_moving:
		return false
	if _flag(f, "is_attacking") or _flag(f, "is_dashing") or _flag(f, "is_backdashing"):
		return false
	if _flag(f, "is_hit") or _flag(f, "is_knockfly") or _flag(f, "is_blocking") \
			or _flag(f, "is_layground") or _flag(f, "is_crouching"):
		return false
	# 著地鎖的尾巴本來就可以被 dash 觸發（與攻擊守衛一致，見 can_start_ground_attack），
	# 因此這裡**只**擋「正在鎖住」的幀：is_landing 為真且 lock 幀數 > 0。
	if _flag(f, "is_landing") and _int(f, "landing_lock_frames") > 0:
		return false
	return true

## 這一刻能不能開始**跳躍**。含三個舊版的隱性條件：
##   1. 不在著地鎖內（JumpHandler 的第一個 if）
##   2. 不在被摔投狀態（ThrowHandler 期間位置外部接管）
##   3. jump_delay_timer <= 0（重複觸發保護）
## 加上 is_on_floor() + 跳躍輸入 + 「不在戰鬥狀態」標準清單。
##
## 對應舊版（JumpHandler.handle_jump）：
##   not is_landing and not is_being_thrown
##   and jump_pressed and is_on_floor() and not is_crouching
##   and not is_dashing and not is_backdashing and not is_attacking
##   and not is_special_moving
##   and not (is_hit or is_knockfly or is_blocking or is_layground)
##   and jump_delay_timer <= 0
##
## jump_pressed / is_special_moving 同 can_walk 的設計理由 —— 不在狀態機列舉內，
## 保留為參數。
static func can_jump(f: Node, jump_pressed: bool, is_special_moving: bool = false) -> bool:
	if f == null or not jump_pressed:
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		return false
	if is_special_moving:
		return false
	# 著地中：JumpHandler 第一個 if 直接 return，沒有任何分支允許在著地期間起跳。
	if _flag(f, "is_landing"):
		return false
	# 被摔投期間位置由 ThrowHandler 接管，禁止起跳。
	if _flag(f, "is_being_thrown"):
		return false
	if _flag(f, "is_crouching") or _flag(f, "is_dashing") or _flag(f, "is_backdashing") \
			or _flag(f, "is_attacking"):
		return false
	if _flag(f, "is_hit") or _flag(f, "is_knockfly") or _flag(f, "is_blocking") \
			or _flag(f, "is_layground"):
		return false
	# 重複觸發保護：跳躍延遲計時器尚未歸零時不允許再跳。
	if _int(f, "jump_delay_timer") > 0:
		return false
	return true

# ── 受擊族守衛（Stage 2 切片 4）─────────────────────────────────────────
##
## 受擊族 = Hitstun / Blockstun / Knockfly / Knockdown(layground) / Wakeup，
## 加上摔投的兩個專屬階段（THROWING / BEING_THROWN）。切片 4 之前，「這個
## 狀態會不會吞輸入 / 算不算連段續航 / 能不能發起摔投 / 能不能被摔」這些
## 判定各自散落在 player.gd、HitResponseHandler.gd、fireball.gd、
## ThrowHandler.gd，且彼此抄得不完全一樣（例：輸入吞沒收 blockstun，
## 連段續航有收）。收攏後**所有受擊相關的「能不能」判定都讀這裡**。

## 這一幀玩家輸入是否應被**完全吞沒**（回傳中性輸入）。
##
## 對應舊版（Player.get_input() 開頭的五個提前返回）：
##   is_knockfly or is_wakeup or is_hit or is_layground
##     or is_throw_in_progress(self)
##     or is_being_thrown
##
## 注意三件刻意保留的語意：
##   1. **不含 blockstun**（`is_blocking`）。格擋硬直中 `get_input()` 仍回傳
##      真實輸入 —— 這是防禦中能緩衝反擊招的既有行為，不能跟著受擊一起吞。
##      （blockstun 期間能不能「出招」仍由 can_start_ground_attack 等守衛擋，
##      那是另一道閘門。）
##   2. **不含 layground 之外的 KO**。KO 是 layground 的細化（resolve() 內
##      `is_layground + 血量歸零`），is_layground 已涵蓋。
##   3. `is_wakeup`（起身后搖，等價於 is_wakeup_locked）有收 —— 醒來那幾幀
##      輸入是被吃掉的，與動畫鏈的 wakeup 優先序一致。
static func is_input_locked(f: Node) -> bool:
	if f == null:
		return false
	if _flag(f, "is_knockfly") or _flag(f, "is_wakeup") \
			or _flag(f, "is_hit") or _flag(f, "is_layground"):
		return true
	if is_throw_in_progress(f):
		return true
	if _flag(f, "is_being_thrown"):
		return true
	return false

## 這一幀目標是否仍處於「可被接段」的硬直中（連段續航判定）。
##
## 收攏前這份 5 條 or 鏈在 HitResponseHandler._target_is_combo_stunned 與
## fireball._target_is_combo_stunned 各抄了一份（逐字相同）。連段計數靠它
## 判斷「這一擊算不算接在同一套連段後面」；任何一份漏判都會讓連段數或
## hit-confirm 在某條攻擊路徑（近身 vs 火球）上默默不同。
##
## 五條語意（照舊，不增刪）：
##   1. hitstun_frames > 0 —— 權威的幀制硬直（is_hit 旗標可能因舊計時器
##      殘留而在 hitstun 歸零後仍為 true，故連段以幀計數器為準）。
##   2. waiting_for_hit_stop_end —— hitstop 期間 hitstun 還沒正式寫入，
##      這幾幀仍算接段窗口。
##   3. is_air_hit_backjump —— 空中受擊後跳是 juggle 狀態。
##   4. is_knockfly —— 擊飛 / 彈牆 juggle。
##   5. 沒有 hitstun_frames 欄位時退回 is_hit（非 Fighter 目標的後備，
##      實際遊戲中所有玩家都有 hitstun_frames，此分支為防禦性保留）。
static func is_combo_stunned(target: Node) -> bool:
	if target == null:
		return false
	if _has_int(target, "hitstun_frames"):
		if _int(target, "hitstun_frames") > 0:
			return true
	elif _flag(target, "is_hit"):
		# 後備：目標連 hitstun_frames 欄位都沒有時才退回旗標。
		return true
	if _flag(target, "waiting_for_hit_stop_end"):
		return true
	if _flag(target, "is_air_hit_backjump"):
		return true
	if _flag(target, "is_knockfly"):
		return true
	return false

## 這一刻能不能**發起**摔投（攻擊方守衛）。
##
## 對應舊版（ThrowHandler._can_initiate_throw）：
##   is_attacking 且 attack_type != "throw_enter" → false
##   is_knockfly or is_hit or is_blocking          → false
##   not is_on_floor()                             → false
##
## 第一條刻意只擋 `throw_enter`：throw_seq 階段（已抓到人）呼叫進來時
## is_attacking 為 true、attack_type 為 "throw_seq"，不能被自己擋掉。
## 注意此守衛**未**列 is_layground / is_wakeup —— 那些狀態下 get_input()
## 早已被 is_input_locked 吞成中性輸入，throw_pressed 根本到不了這裡；
## 守衛維持與舊式逐值等價（不無故加嚴）。
static func can_initiate_throw(f: Node) -> bool:
	if f == null:
		return false
	if _flag(f, "is_attacking") and _string(f, "attack_type") != "throw_enter":
		return false
	if _flag(f, "is_knockfly") or _flag(f, "is_hit") or _flag(f, "is_blocking"):
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		return false
	return true

## 這個目標此刻能不能**被**摔投（受害者守衛）。
##
## 對應舊版（ThrowHandler.check_grab_collision 的目標過濾）：
##   potential_target.is_knockfly or potential_target.is_being_thrown → 略過
## 擊飛中不能抓、已經被抓的不能重複抓。其餘狀態（blockstun / hitstun /
## layground）舊版都允許抓取，這裡照舊，不無故加嚴。
static func can_be_thrown(target: Node) -> bool:
	if target == null:
		return false
	if _flag(target, "is_knockfly") or _flag(target, "is_being_thrown"):
		return false
	return true

# ── 格擋族守衛（Stage 2 切片 5）──────────────────────────────────────────
##
## 格擋站姿（is_holding_back / is_crouch_blocking / is_proximity_blocking）
## 的進入與釋放各有一份守衛，切片 5 之前兩份都內聯在
## BlockingHandler.handle_blocking 裡。它們**不是同一個條件**：
##   - 進入（含「持續重取樣 held 方向」）：**不含 is_blocking**。這是既有
##     的預期行為 —— blockstun 期間進入分支每幀照跑，重取樣「此刻按住
##     哪個方向」（格擋中持續按住後退方向就一直是 held back；切片 4
##     finding #1 披露過這裡）。若誤把 is_blocking 加進進入守衛，
##     is_holding_back 會停在格擋前最後一幀的值。
##   - 釋放：**含 is_blocking** —— 硬直（受擊 / 擊飛 / blockstun / 倒地）
##     期間不釋放站姿旗標，保留給進入分支在硬直結束後重取樣。
## 兩份守衛刻意**不能**合併成一份（合併會改變行為），這裡收攏的是
## 「各自只有一份定義」：Python 暴力窮舉（256 / 16 組合，含 is_blocking
## 靈敏度掃描 512 組合）0 分岔，test_36 引擎內逐幀釘住。

## 這一刻能不能**進入 / 維持**格擋站姿（重取樣 held-back 方向）。
##
## 語意 = 舊的 BlockingHandler.handle_blocking 進入守衛（逐字搬運）：
##   is_on_floor() and not is_attacking and not is_dashing
##     and not is_backdashing and not is_special_moving
##     and not (is_hit or is_knockfly or is_layground)
## 注意三件刻意保留的事：
##   1. **不含 is_blocking**（見段頭）—— blockstun 重取樣路徑依賴它。
##   2. 不含 is_crouching —— 蹲防走同一條進入路徑（is_crouch_blocking =
##      is_crouching and is_holding_back，由進入分支內部寫入）。
##   3. is_special_moving 是 MoveSet 持有的非狀態機旗標（同 can_walk /
##      can_dash 的設計），保留為參數。
static func can_enter_block_stance(f: Node, is_special_moving: bool = false) -> bool:
	if f == null:
		return false
	var on_floor: bool = f.is_on_floor() if f.has_method("is_on_floor") else true
	if not on_floor:
		return false
	if is_special_moving:
		return false
	if _flag(f, "is_attacking") or _flag(f, "is_dashing") or _flag(f, "is_backdashing"):
		return false
	if _flag(f, "is_hit") or _flag(f, "is_knockfly") or _flag(f, "is_layground"):
		return false
	return true

## 這一刻能不能**釋放**格擋站姿旗標（is_holding_back / is_crouch_blocking /
## is_proximity_blocking 歸零）。
##
## 語意 = 舊的 BlockingHandler.handle_blocking else 分支守衛（逐字搬運）：
##   not (is_hit or is_knockfly or is_blocking or is_layground)
## 受擊 / 擊飛 / blockstun / 倒地期間回 false —— 站姿旗標在硬直期間
## 保留不釋放（進入分支同時也在跑，負責重取樣方向），硬直結束後
## 由這裡統一清空。
static func can_release_block_stance(f: Node) -> bool:
	if f == null:
		return false
	if _flag(f, "is_hit") or _flag(f, "is_knockfly") or _flag(f, "is_blocking"):
		return false
	if _flag(f, "is_layground"):
		return false
	return true

## 這一刻旗標之間是否存在**結構性不可能**的組合。
##
## 回傳違反的不變式描述（空陣列 = 乾淨）。只收「由現行程式碼可證明互斥」
## 的組合，因此任何一條爆掉都代表真的有東西壞了，而不是測試太嚴。
## （刻意**不**收 is_hit + is_blocking：那組合現在確實可達 ——
##   在 blockstun 期間被打會讓 blockstun_frames 與 hitstun_frames 同時 > 0。
##   這是 Stage 2 要消滅的目標之一，記錄在 README/plan，不在此處當作綠燈條件。）
static func check_invariants(f: Node) -> Array:
	var broken: Array = []
	if f == null:
		return broken

	# DashHandler 兩個分支互斥、且進入前都要求兩者皆 false；TimerHandler 一起清零。
	# AI 的直接 dash 路徑（Movement._physics_process）同樣要求兩者皆 false 才進入。
	if _flag(f, "is_dashing") and _flag(f, "is_backdashing"):
		broken.append("is_dashing 與 is_backdashing 同時為真")

	# Stage 1 不變式：著地狀態的唯一權威是幀計數器。
	# is_landing 為真卻沒有剩餘鎖幀 = 殘留鎖（會凍結 _update_animation_state）。
	if _flag(f, "is_landing") and _int(f, "landing_lock_frames") <= 0:
		broken.append("is_landing 為真但 landing_lock_frames=%d（殘留鎖）"
			% _int(f, "landing_lock_frames"))

	# wakeup 鎖定必然伴隨仍在倒數的 wakeup_timer（歸零那幀一起清除）。
	if _flag(f, "is_wakeup_locked") and _int(f, "wakeup_timer") <= 0:
		broken.append("is_wakeup_locked 為真但 wakeup_timer=%d"
			% _int(f, "wakeup_timer"))

	# ── Stage 2 切片 2 新增：攻擊狀態必須「成對」出現 ──
	# is_attacking 與 attack_type 是同一件事的兩半：前者說「在出招」，
	# 後者說「出哪一招」。全倉庫每一個 `is_attacking = true` 的寫入點
	# 都在同一個區塊裡寫入合法 attack_type（Player._execute_attack、
	# ThrowHandler 進入 throw_seq），每一個 `attack_type = "none"` 的
	# 寫入點也都在同一個區塊裡清掉 is_attacking（reset_attack_state /
	# reset_air_state / stop_attack / spmove 分支 / world.reset_players /
	# ThrowHandler 收尾）—— 所以這個組合**結構上不可達**。
	#
	# 唯一曾經能產生它的來源是 fighter.gd 裡的舊第二攻擊入口：
	# 它只寫 is_attacking = true、完全不碰 attack_type，於是留下了
	# 「在出招但不知道出哪一招」的孤兒狀態 —— 動畫層把它當 "Walk" 播、
	# MoveSet 拒絕開新招、跳躍/衝刺守衛全部擋下，而 attack_duration_timer
	# 仍是 0，沒有任何計時器會把它收回來。該入口已於本切片移除。
	if _flag(f, "is_attacking") and not is_attack_id(_string(f, "attack_type")):
		broken.append("is_attacking 為真但 attack_type='%s'（孤兒攻擊狀態）"
			% _string(f, "attack_type"))

	return broken

## 已知**可達但不應存在**的旗標重疊（Stage 2 的待辦清單，非失敗條件）。
## 提供給測試印出來，讓「還沒修完」這件事有數據而不是感覺。
static func known_illegal_overlaps(f: Node) -> Array:
	var found: Array = []
	if f == null:
		return found
	if _int(f, "hitstun_frames") > 0 and _int(f, "blockstun_frames") > 0:
		found.append("hitstun_frames 與 blockstun_frames 同時 > 0")
	if _flag(f, "is_hit") and _flag(f, "is_blocking"):
		found.append("is_hit 與 is_blocking 同時為真")
	if _flag(f, "is_attacking") and _flag(f, "is_hit"):
		found.append("is_attacking 與 is_hit 同時為真")
	# knockfly 與 layground 在正常流程中成對切換（_enter_layground 會先清 knockfly），
	# 但摔投不檢查目標是否倒地（ThrowHandler 只擋 is_knockfly / is_being_thrown），
	# 因此「摔一個剛倒地的對手」可造成短暫重疊。列為待辦而非硬性不變式。
	if _flag(f, "is_knockfly") and _flag(f, "is_layground"):
		found.append("is_knockfly 與 is_layground 同時為真")
	return found

# ── 內部：容錯讀取（fighter 可能是 Movement / Fighter / Player 任一層）──

static func _flag(n: Node, prop: String) -> bool:
	if n == null or not (prop in n):
		return false
	return bool(n.get(prop))

static func _int(n: Node, prop: String) -> int:
	if n == null or not (prop in n):
		return 0
	return int(n.get(prop))

static func _has_int(n: Node, prop: String) -> bool:
	return n != null and prop in n

static func _string(n: Node, prop: String) -> String:
	if n == null or not (prop in n):
		return ""
	return str(n.get(prop))

static func _is_knocked_out(f: Node) -> bool:
	var healthbar = f.get("healthbar") if "healthbar" in f else null
	if healthbar == null or not ("current_health" in healthbar):
		return false
	return float(healthbar.current_health) <= 0.0
