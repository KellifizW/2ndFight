class_name AttackExecutor extends Node

## AttackExecutor Handler - Phase 3 Refactoring
## 
## 職責: 統一處理所有普通攻擊的執行邏輯
## - 地面攻擊檢測（站立/蹲下）
## - 空中攻擊檢測
## - Buffer 消耗管理
## - 表驅動設計，消除 18 個 if-elif 重複代碼
##
## 基於業界格鬥遊戲模式：
## - Street Fighter V: AttackController with table-driven move execution
## - Guilty Gear Strive: MoveDatabase with priority system
## - Tekken 8: CommandList with input mapping

# ── 攻擊優先級定義（按強度排序：重 > 中 > 輕）──
const BUTTON_PRIORITY = ["st_hp", "st_hk", "st_mp", "st_mk", "st_lp", "st_lk"]

# ── 按鈕到攻擊名稱的映射 ──
const BUTTON_TO_ATTACK_PREFIX = {
	"st_hp": "hp",
	"st_hk": "hk",
	"st_mp": "mp",
	"st_mk": "mk",
	"st_lp": "lp",
	"st_lk": "lk"
}

# ── 引用 ──
var parent_player: Node = null
var player_controller: Node = null

func _init(player: Node) -> void:
	parent_player = player

func _ready() -> void:
	if parent_player and parent_player.has_node("PlayerController"):
		player_controller = parent_player.get_node("PlayerController")

# ═══════════════════════════════════════════════════════════════════════════
# 地面攻擊執行（站立/蹲下）
# ═══════════════════════════════════════════════════════════════════════════

func try_execute_ground_attack(input_data: Dictionary, is_crouching: bool) -> bool:
	"""
	嘗試執行地面攻擊（站立或蹲下）
	
	Args:
		input_data: 輸入數據字典（包含 st_lp_pressed, st_mp_pressed 等）
		is_crouching: 是否處於蹲下狀態
	
	Returns:
		bool: 如果執行了攻擊返回 true，否則返回 false
	"""
	var throw_pressed = input_data.get("throw_pressed", false)
	# 【DEBUG】詳細追蹤摔投執行條件 - 所有 AI 相關信息
	if throw_pressed or (input_data.get("st_lp_pressed", false) and input_data.get("st_lk_pressed", false)):
		var parent_seat = parent_player.seat if parent_player and "seat" in parent_player else "?"
		var parent_is_ai = parent_player.is_ai_controlled if parent_player else false
		Debug.log("[ATTACK_EXECUTOR] Frame=%d Seat=%s is_ai=%s | throw_pressed=%s, is_crouching=%s, is_attacking=%s | attack_type=%s" % [
			Engine.get_physics_frames(),
			parent_seat,
			parent_is_ai,
			throw_pressed,
			is_crouching,
			parent_player.is_attacking if parent_player else "?",
			parent_player.attack_type if parent_player else "?"
		])
	
	if throw_pressed and not is_crouching:
		# 【FIXED】Throw CAN interrupt normal attacks (cancel capability)
		# Only reject throw if throw_enter/throw_seq is already executing
		if parent_player and FighterState.is_throw_in_progress(parent_player):
			Debug.log("[THROW BLOCKED] Frame=%d Seat=%s | Already executing throw (attack_type=%s), cannot throw again" % [
				Engine.get_physics_frames(),
				parent_player.seat if parent_player and "seat" in parent_player else "?",
				parent_player.attack_type if parent_player else "?"
			])
			return false
		# Consume and execute throw (interrupts normal attacks)
		_consume_throw_inputs()
		Debug.log("[EXECUTE THROW] Frame=%d Seat=%s | ✅ Executing 'throw_enter' (was attacking: %s)" % [
			Engine.get_physics_frames(),
			parent_player.seat if parent_player and "seat" in parent_player else "?",
			parent_player.attack_type if parent_player else "none"
		])
		_execute_attack("throw_enter")
		return true

	# 遍歷優先級列表，檢查哪個按鈕被按下
	for button in BUTTON_PRIORITY:
		var input_key = button + "_pressed"
		if input_data.get(input_key, false):
			# 構建攻擊名稱：cr_lp 或 st_lp
			var stance_prefix = "cr_" if is_crouching else "st_"
			var attack_suffix = BUTTON_TO_ATTACK_PREFIX[button]
			var attack_name = stance_prefix + attack_suffix
			
			# 消耗 buffer 輸入
			_consume_button_input(button)
			
			# 執行攻擊
			_execute_attack(attack_name)
			
			return true
	
	return false

# ═══════════════════════════════════════════════════════════════════════════
# 空中攻擊執行
# ═══════════════════════════════════════════════════════════════════════════

func try_execute_air_attack(input_data: Dictionary) -> bool:
	"""
	嘗試執行空中攻擊
	
	Args:
		input_data: 輸入數據字典
	
	Returns:
		bool: 如果執行了攻擊返回 true，否則返回 false
	"""
	# 遍歷優先級列表（空中攻擊同樣遵循優先級）
	for button in BUTTON_PRIORITY:
		var input_key = button + "_pressed"
		if input_data.get(input_key, false):
			# 構建空中攻擊名稱：jump_lp, jump_mp, 等
			var attack_suffix = BUTTON_TO_ATTACK_PREFIX[button]
			var attack_name = "jump_" + attack_suffix
			
			# 消耗 buffer 輸入
			_consume_button_input(button)
			
			# 設置空中攻擊狀態
			parent_player.is_air_attacking = true
			parent_player.has_air_attacked = true
			
			# 執行攻擊
			_execute_attack(attack_name)
			
			return true
	
	return false

# ═══════════════════════════════════════════════════════════════════════════
# 內部輔助函數
# ═══════════════════════════════════════════════════════════════════════════

func _consume_button_input(button: String) -> void:
	"""消耗 buffer 中的按鈕輸入"""
	if player_controller and player_controller.has_method("consume_button_input"):
		player_controller.consume_button_input(button)

func _consume_throw_inputs() -> void:
	"""消耗 throw 相關的按鈕輸入"""
	# 【關鍵】消費 "throw" 輸入本身，而不是 st_lp / st_lk
	# 因為 PlayerController 當同時按下 st_lp + st_lk 時，只記錄 "throw"
	_consume_button_input("throw")

func _execute_attack(attack_name: String) -> void:
	"""執行攻擊（委託給 Player）"""
	if parent_player and parent_player.has_method("_execute_attack"):
		parent_player._execute_attack(attack_name)

# ═══════════════════════════════════════════════════════════════════════════
# 調試輔助
# ═══════════════════════════════════════════════════════════════════════════

func debug_air_attack_blocked(input_data: Dictionary, parent: Node) -> void:
	"""調試：顯示空中攻擊被阻擋的原因"""
	var has_button_input = (
		input_data.get("st_lp_pressed", false) or
		input_data.get("st_mp_pressed", false) or
		input_data.get("st_hp_pressed", false) or
		input_data.get("st_lk_pressed", false) or
		input_data.get("st_mk_pressed", false) or
		input_data.get("st_hk_pressed", false)
	)
	
	if not has_button_input:
		return
	
	var blocked_reasons = []
	if parent.is_on_floor(): blocked_reasons.append("on_floor")
	if not parent.is_jumping: blocked_reasons.append("not_jumping")
	if parent.is_air_attacking: blocked_reasons.append("is_air_attacking")
	if parent.is_blocking: blocked_reasons.append("is_blocking")
	if parent.is_knockfly: blocked_reasons.append("is_knockfly")
	if parent.is_hit: blocked_reasons.append("is_hit")
	if FighterState.is_wakeup_active(parent): blocked_reasons.append("wakeup_timer>0")
	if parent.has_air_attacked: blocked_reasons.append("has_air_attacked=TRUE")
	if parent.is_layground: blocked_reasons.append("is_layground")
	
	if blocked_reasons.size() > 0:
		Debug.log("[AIR ATTACK BLOCKED] Seat: ", parent.seat, " | Reasons: ", blocked_reasons)
