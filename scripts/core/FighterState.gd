class_name FighterState extends RefCounted
## Stage 2 第 1 刀：顯式狀態機的「單一活動狀態」定義與解析器。
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
		if _string(f, "attack_type") in THROW_ATTACK_TYPES:
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

static func _string(n: Node, prop: String) -> String:
	if n == null or not (prop in n):
		return ""
	return str(n.get(prop))

static func _is_knocked_out(f: Node) -> bool:
	var healthbar = f.get("healthbar") if "healthbar" in f else null
	if healthbar == null or not ("current_health" in healthbar):
		return false
	return float(healthbar.current_health) <= 0.0
