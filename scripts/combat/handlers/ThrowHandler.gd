# ThrowHandler.gd
class_name ThrowHandler extends Node

## ═══════════════════════════════════════════════════════════════════════════
## 摔投處理器 (Throw Handler)
## 專門處理摔投系統的所有邏輯（參考 Sakuga Engine 架構）
## ═══════════════════════════════════════════════════════════════════════════
##
## 職責：
## - 摔投碰撞檢測（抓取判定）
## - 對手位置鎖定與同步
## - 摔投階段管理（STARTUP → GRAB → HOLD → EXECUTE → RECOVERY）
## - 對手釋放與速度應用
## - 連打逃脫系統
##
## 整合點：
## - Player._physics_process(): 呼叫 handle_throw() 更新邏輯
## - AttackExecutor: 委派 try_initiate_throw() 啟動摔投
## - AnimationPlayer: 時間軸事件觸發 lock/release
##
## 參考：
## - GUIDES/ThrowSystem_GDScript_Tutorial.md
## - Sakuga Engine ThrowPivot + ThrowReleaseEvent 架構
##
## ═══════════════════════════════════════════════════════════════════════════

# ── 摔投階段枚舉 ──
enum ThrowPhase {
	NONE = 0,       # 無摔投狀態
	STARTUP = 1,    # throw_enter 動畫前置階段（碰撞判定期）
	GRAB = 2,       # 成功抓取瞬間
	HOLD = 3,       # throw_seq 期間持續控制對手位置
	EXECUTE = 4,    # 釋放對手並應用速度
	RECOVERY = 5    # 摔投結束後的恢復階段
}

# ── 狀態變量 ──
var current_phase: ThrowPhase = ThrowPhase.NONE
var is_grabbing: bool = false           # throw_enter 檢測階段
var is_executing_throw: bool = false    # throw_seq 執行階段
var grabbed_opponent: Node = null       # 被抓取的對手引用

# ── 位置控制 ──
var throw_pivot_offset: Vector2i = Vector2i.ZERO  # 對手相對於攻擊者的偏移（固定點單位）
var lock_opponent_position: bool = false           # 是否鎖定對手位置

# ── 逃脫系統 ──
var escape_window_active: bool = false             # 逃脫窗口是否開啟
var escape_input_count: int = 0                    # 當前幀內的按鍵計數
var escape_check_frame_start: int = 0              # 逃脫檢測開始的幀數
var escape_mash_threshold: int = 8                 # 逃脫所需按鍵次數（預設）
var hold_start_frame: int = -1                     # 進入 HOLD 的起始物理幀

# ── 引用節點 ──
var player_node: Node = null                       # 主玩家節點（攻擊者）
var world_node: Node = null                        # World 節點（獲取物理常數）

# ── 除錯 ──
var debug_enabled: bool = true


func _ready() -> void:
	name = "ThrowHandler"
	if debug_enabled:
		print("[ThrowHandler] Initialized for player: %s" % player_node.name if player_node else "None")


## ═══════════════════════════════════════════════════════════════════════════
## 初始化與設置
## ═══════════════════════════════════════════════════════════════════════════

func set_player(player: Node) -> void:
	"""設置玩家節點引用"""
	player_node = player
	if player_node and player_node.has_node("/root/World"):
		world_node = player_node.get_node("/root/World")
	if debug_enabled:
		print("[ThrowHandler] Player set to: %s" % player_node.name)


## ═══════════════════════════════════════════════════════════════════════════
## 主要更新函數（每幀呼叫）
## ═══════════════════════════════════════════════════════════════════════════

func handle_throw(delta: float, input_data: Dictionary) -> void:
	"""每幀處理摔投邏輯（在 Player._physics_process 中呼叫）"""
	if not player_node:
		return
	
	match current_phase:
		ThrowPhase.STARTUP:
			_handle_startup_phase()
		ThrowPhase.HOLD:
			_handle_hold_phase(delta)
		ThrowPhase.EXECUTE:
			_handle_execute_phase()
		ThrowPhase.RECOVERY:
			_handle_recovery_phase()


## ═══════════════════════════════════════════════════════════════════════════
## 摔投啟動（從 AttackExecutor 或 Player 呼叫）
## ═══════════════════════════════════════════════════════════════════════════

func try_initiate_throw(input_data: Dictionary) -> bool:
	"""嘗試啟動摔投（檢查條件）"""
	if not player_node or not _can_initiate_throw():
		return false
	
	# 進入 STARTUP 階段（throw_enter 動畫開始）
	current_phase = ThrowPhase.STARTUP
	is_grabbing = true
	
	if debug_enabled:
		print("[ThrowHandler] Throw initiated - entering STARTUP phase")
	
	return true


func _can_initiate_throw() -> bool:
	"""檢查是否可以啟動摔投"""
	if not player_node:
		return false
	
	# 檢查基本狀態條件
	if player_node.is_attacking and player_node.attack_type != "throw_enter":
		return false
	if player_node.is_knockfly or player_node.is_hit or player_node.is_blocking:
		return false
	if not player_node.is_on_floor():
		return false
	
	return true


## ═══════════════════════════════════════════════════════════════════════════
## 碰撞檢測與抓取（從動畫事件或 STARTUP 階段呼叫）
## ═══════════════════════════════════════════════════════════════════════════

func check_grab_collision() -> Node:
	"""檢查摔投碰撞，返回被抓取的對手（如果有）"""
	if not player_node or not player_node.has_node("ThrowBox"):
		if debug_enabled:
			print("[ThrowHandler] No ThrowBox found on player")
		return null
	
	# 只有在 ThrowHit 判定框為 active 時才進行檢測
	var throw_box = player_node.get_node("ThrowBox")
	if throw_box.has_node("ThrowHit"):
		var throw_hit = throw_box.get_node("ThrowHit")
		if throw_hit.disabled:
			if debug_enabled:
				print("[ThrowHandler] ThrowHit is disabled - skipping grab detection")
			return null
	
	var overlapping_areas = throw_box.get_overlapping_areas()
	
	if debug_enabled and overlapping_areas.size() > 0:
		print("[ThrowHandler] Found %d overlapping areas" % overlapping_areas.size())
	
	for area in overlapping_areas:
		# 尋找對手的 ThrowBox
		if area.name != "ThrowBox":
			continue
		
		var potential_target = area.get_parent()
		if not potential_target or not potential_target.is_in_group("players"):
			continue
		
		if potential_target == player_node:
			continue  # 自己
		
		# 驗證 ThrowHurt 存在
		if not area.has_node("ThrowHurt"):
			continue
		
		# 檢查對手狀態（是否可被摔投）
		if potential_target.is_knockfly or potential_target.is_being_thrown:
			if debug_enabled:
				print("[ThrowHandler] Target %s in invalid state (knockfly or already thrown)" % potential_target.name)
			continue
		
		# 找到有效目標
		if debug_enabled:
			print("[ThrowHandler] Valid throw target found: %s" % potential_target.name)
		
		# 【雙向摔投衝突檢測】—— Throw Escape
		# 情況 A: 對手的 ThrowHandler 也在 STARTUP 階段（同幀处理）
		# 情況 B: 對手的 InputBuffer 內有近期 throw 輸入（捣處理順序差異）
		var target_throw_handler = _get_throw_handler(potential_target)
		var target_also_threw: bool = false
		
		if target_throw_handler and target_throw_handler.current_phase == ThrowPhase.STARTUP:
			target_also_threw = true
		else:
			# 檢查對手的 input buffer 是否在最近 8 物理幀內按了 throw
			var throw_clash_window: int = 8  # ~67ms @120FPS —— 標準碰擋判定窗口
			if potential_target.has_node("PlayerController"):
				var opp_controller = potential_target.get_node("PlayerController")
				var opp_buffer = opp_controller.input_buffer if "input_buffer" in opp_controller else null
				if opp_buffer and opp_buffer.has_method("is_input_buffered_within"):
					target_also_threw = opp_buffer.is_input_buffered_within("throw", throw_clash_window)
		
		if target_also_threw:
			if debug_enabled:
				print("[ThrowHandler] MUTUAL THROW detected! Triggering Throw Escape")
			handle_mutual_throw_collision(potential_target)
			return null  # 不抓取任何人，雙方觸發 throw escape
		
		return potential_target
	
	return null


func lock_opponent(opponent: Node) -> void:
	"""鎖定對手（進入 GRAB 階段）"""
	if not opponent:
		return
	
	grabbed_opponent = opponent
	current_phase = ThrowPhase.GRAB
	is_grabbing = false
	lock_opponent_position = true
	
	# 設置對手狀態
	if "is_being_thrown" in opponent:
		opponent.is_being_thrown = true
	opponent.is_attacking = false
	opponent.is_blocking = false
	if "is_crouch_blocking" in opponent:
		opponent.is_crouch_blocking = false
	if "is_proximity_blocking" in opponent:
		opponent.is_proximity_blocking = false
	if "block_type" in opponent:
		opponent.block_type = "none"
	if "blockstun_frames" in opponent:
		opponent.blockstun_frames = 0
	if "block_knockback_frames" in opponent:
		opponent.block_knockback_frames = 0
	
	# 清空對手輸入緩衝
	if opponent.has_node("PlayerController") and opponent.get_node("PlayerController").has_method("clear_input_buffer"):
		print("[🔴 ThrowHandler] Clearing opponent's input_buffer at frame %d | opponent: %s" % [
			Engine.get_physics_frames(), opponent.name
		])
		opponent.get_node("PlayerController").input_buffer.clear()
		print("[ThrowHandler] Input buffer cleared. Calling input display clear() if it exists...")
		# 檢查是否有輸入歷史顯示並嘗試調用clear
		var input_display = get_tree().root.find_child("InputHistoryDisplayIcon", true, false)
		if input_display:
			print("[⚠️ ThrowHandler] Found InputHistoryDisplayIcon - NOT calling clear() to preserve history")
			# 【改動】不調用clear() 以保留歷史
			# input_display.call("clear")
		
	
	# 計算位置偏移（從 ThrowData 獲取）
	var throw_data = _get_throw_data()
	var pivot_x = throw_data.get("pivot_offset_x", 50.0)  # 預設 50 像素
	var pivot_y = throw_data.get("pivot_offset_y", -30.0)  # 預設 -30 像素（向上）
	if world_node:
		throw_pivot_offset = Vector2i(
			int(pivot_x * world_node.SIMULATION_SCALE),
			int(pivot_y * world_node.SIMULATION_SCALE)
		)
	else:
		# 無 world 引用時使用預設 SIMULATION_SCALE = 1000
		throw_pivot_offset = Vector2i(int(pivot_x * 1000), int(pivot_y * 1000))
	
	if debug_enabled:
		print("[ThrowHandler] Opponent locked: %s | pivot_offset: %s" % [opponent.name, throw_pivot_offset])
	
	# 【新增】清空攻擊者的速度（防止在 throw_seq 期間移動）
	if player_node and "fixed_velocity" in player_node:
		player_node.fixed_velocity.x = 0
		player_node.fixed_velocity.y = 0
		if debug_enabled:
			print("[ThrowHandler] Attacker velocity cleared to prevent movement during throw")
	
	# 【新增】停止攻擊者的衝刺狀態（如果有）
	if player_node:
		if "is_dashing" in player_node:
			player_node.is_dashing = false
		if "is_backdashing" in player_node:
			player_node.is_backdashing = false
		if "dash_timer" in player_node:
			player_node.dash_timer = 0
	
	# 立即進入 HOLD 階段
	current_phase = ThrowPhase.HOLD
	hold_start_frame = Engine.get_physics_frames()

	# 進入 throw_seq 動畫（抓到後正式執行摔投）
	if player_node:
		player_node.is_attacking = true
		player_node.attack_type = "throw_seq"
		if "attack_duration_timer" in player_node:
			if player_node.animation_player and player_node.animation_player.has_animation("throw_seq"):
				var anim_length = player_node.animation_player.get_animation("throw_seq").length
				player_node.attack_duration_timer = int(round(anim_length * 60 * 2))
				if debug_enabled:
					print("[ThrowHandler] Switched to throw_seq | timer=%d frames" % player_node.attack_duration_timer)
				else:
					player_node.attack_duration_timer = 60
			else:
				player_node.attack_duration_timer = 60
		if player_node.animation_state:
			player_node.animation_state.travel("throw_seq")
	
	# 啟動逃脫窗口
	_start_escape_window()


## ═══════════════════════════════════════════════════════════════════════════
## 位置同步（HOLD 階段每幀更新）
## ═══════════════════════════════════════════════════════════════════════════

func update_opponent_position(delta: float) -> void:
	"""更新對手位置（鎖定在攻擊者旁邊）"""
	if not lock_opponent_position or not grabbed_opponent or not player_node:
		return
	
	# 計算目標位置（攻擊者位置 + 偏移 * 朝向）
	var facing = player_node.facing_direction if "facing_direction" in player_node else 1.0
	var target_position = player_node.fixed_position + Vector2i(
		int(throw_pivot_offset.x * facing),
		throw_pivot_offset.y
	)
	
	# 強制設置對手位置和速度
	grabbed_opponent.fixed_position = target_position
	grabbed_opponent.fixed_velocity = Vector2i.ZERO
	
	# 每 30 幀輸出一次除錯（0.25 秒）
	if debug_enabled and Engine.get_physics_frames() % 30 == 0:
		print("[ThrowHandler] Position locked | attacker: %s | opponent: %s | offset: %s" % [
			player_node.fixed_position, target_position, throw_pivot_offset
		])


## ═══════════════════════════════════════════════════════════════════════════
## 對手釋放（從動畫事件呼叫）
## ═══════════════════════════════════════════════════════════════════════════

func release_opponent() -> void:
	"""釋放對手並應用發射速度（從 AnimationPlayer 事件呼叫）"""
	if not grabbed_opponent or not player_node:
		if debug_enabled:
			print("[ThrowHandler] Release called but no grabbed opponent")
		return
	
	current_phase = ThrowPhase.EXECUTE
	lock_opponent_position = false
	
	var throw_data = _get_throw_data()
	if not throw_data:
		push_error("[ThrowHandler] No throw data available for release")
		reset_throw_state()
		return
	
	# 應用傷害
	var damage = throw_data.get("damage", 8.0)
	_apply_throw_damage(grabbed_opponent, damage)
	
	# 應用速度和 knockfly 狀態
	_apply_launch_velocity(grabbed_opponent, throw_data)
	
	# 設置 hitstun
	var hitstun_frames = throw_data.get("hitstun", 36)
	var hitstun_physics = _logic_frames_to_physics_frames(hitstun_frames)
	grabbed_opponent.hitstun_frames = hitstun_physics
	grabbed_opponent.is_knockfly = true
	
	# 初始化 knockfly 計時與水平速度，避免下一幀被清零
	var physics_fps = Engine.physics_ticks_per_second
	var knockfly_seconds = float(hitstun_physics) / float(physics_fps)
	if "default_knockfly_duration" in grabbed_opponent:
		knockfly_seconds = max(knockfly_seconds, float(grabbed_opponent.default_knockfly_duration))
	if "knockfly_timer" in grabbed_opponent:
		grabbed_opponent.knockfly_timer = knockfly_seconds
	if "knockfly_duration" in grabbed_opponent:
		grabbed_opponent.knockfly_duration = knockfly_seconds
	if "knockfly_velocity_x" in grabbed_opponent:
		grabbed_opponent.knockfly_velocity_x = grabbed_opponent.fixed_velocity.x
	if "knockfly_accumulated_distance" in grabbed_opponent:
		grabbed_opponent.knockfly_accumulated_distance = 0.0
	grabbed_opponent.just_thrown = true
	
	# 播放 knockfly 動畫
	if grabbed_opponent.animation_state:
		grabbed_opponent.animation_state.travel("knockfly")
	
	if debug_enabled:
		print("[ThrowHandler] Opponent released | damage: %.1f | hitstun: %d physics frames | velocity: %s" % [
			damage, hitstun_physics, grabbed_opponent.fixed_velocity
		])
	
	# 清理狀態
	_cleanup_opponent_state()
	
	# 進入恢復階段
	current_phase = ThrowPhase.RECOVERY


## ═══════════════════════════════════════════════════════════════════════════
## 連打逃脫系統
## ═══════════════════════════════════════════════════════════════════════════

func _start_escape_window() -> void:
	"""啟動逃脫窗口"""
	escape_window_active = true
	escape_input_count = 0
	escape_check_frame_start = Engine.get_physics_frames()
	
	# 從 ThrowData 獲取逃脫閾值
	var throw_data = _get_throw_data()
	if throw_data:
		escape_mash_threshold = throw_data.get("escape_mash_threshold", 8)
	
	if debug_enabled:
		print("[ThrowHandler] Escape window started | threshold: %d inputs" % escape_mash_threshold)


func check_throw_escape() -> bool:
	"""檢查對手是否成功逃脫（連打檢測）"""
	if not escape_window_active or not grabbed_opponent:
		return false
	
	var throw_data = _get_throw_data()
	if not throw_data:
		return false
	
	var escape_window_end_frame = throw_data.get("escape_window_end_frame", 15)
	var current_frame = Engine.get_physics_frames()
	var elapsed_frames = current_frame - escape_check_frame_start
	
	# 窗口已關閉
	if elapsed_frames > _logic_frames_to_physics_frames(escape_window_end_frame):
		escape_window_active = false
		if debug_enabled:
			print("[ThrowHandler] Escape window closed | inputs: %d/%d" % [escape_input_count, escape_mash_threshold])
		return false
	
	# 檢測對手輸入（任意按鍵）
	if grabbed_opponent.has_node("PlayerController"):
		var opponent_controller = grabbed_opponent.get_node("PlayerController")
		var input_buffer = opponent_controller.input_buffer if "input_buffer" in opponent_controller else null
		
		if input_buffer:
			# 計算最近 15 幀內的按鍵數量
			var recent_inputs = _count_recent_inputs(input_buffer, 15)
			escape_input_count = recent_inputs
			
			# 達到逃脫閾值
			if escape_input_count >= escape_mash_threshold:
				_execute_escape()
				return true
	
	return false


func _count_recent_inputs(input_buffer: Node, frame_window: int) -> int:
	"""計算最近幀數內的按鍵次數"""
	if not input_buffer or not input_buffer.has_method("get_buffer"):
		return 0
	
	var buffer = input_buffer.get_buffer()
	var count = 0
	var physics_window = _logic_frames_to_physics_frames(frame_window)
	
	for i in range(min(physics_window, buffer.size())):
		var input_entry = buffer[i]
		if input_entry and typeof(input_entry) == TYPE_DICTIONARY:
			# 檢查是否有任意按鍵按下（st_lp, st_mp, st_hp, st_lk, st_mk, st_hk）
			for key in ["st_lp_pressed", "st_mp_pressed", "st_hp_pressed", "st_lk_pressed", "st_mk_pressed", "st_hk_pressed"]:
				if input_entry.get(key, false):
					count += 1
					break  # 每幀只計算一次
	
	return count


func _execute_escape() -> void:
	"""執行逃脫（雙方進入硬直）"""
	if not grabbed_opponent or not player_node:
		return
	
	if debug_enabled:
		print("[ThrowHandler] THROW ESCAPED! | inputs: %d/%d" % [escape_input_count, escape_mash_threshold])
	
	# 對手逃脫成功
	grabbed_opponent.is_being_thrown = false
	grabbed_opponent.is_knockfly = false
	grabbed_opponent.hitstun_frames = _logic_frames_to_physics_frames(10)  # 10 幀硬直
	
	# 攻擊者也進入硬直
	player_node.attack_duration_timer = _logic_frames_to_physics_frames(15)  # 15 幀硬直（較長）
	
	# 輕微推開雙方
	var push_distance = 30000  # 30 像素 * SIMULATION_SCALE
	if "facing_direction" in player_node:
		var facing = player_node.facing_direction
		grabbed_opponent.fixed_velocity.x = int(push_distance * facing)  # 對手被推向前方
		player_node.fixed_velocity.x = int(-push_distance * facing * 0.5)  # 攻擊者微小後退
	
	# 播放逃脫動畫（回到 idle 或自訂逃脫動畫）
	if grabbed_opponent.animation_state:
		grabbed_opponent.animation_state.travel("idle")
	if player_node.animation_state:
		player_node.animation_state.travel("idle")
	
	# 清理狀態
	_cleanup_opponent_state()
	reset_throw_state()
	
	# TODO: 播放逃脫特效和音效
	escape_window_active = false


## ═══════════════════════════════════════════════════════════════════════════
## 階段處理函數
## ═══════════════════════════════════════════════════════════════════════════

func _handle_startup_phase() -> void:
	"""處理 STARTUP 階段（throw_enter 期間）"""
	# 若玩家已不在 throw_enter 攻擊狀態，說明動畫結束但未抓到人，立即終止
	if not player_node:
		reset_throw_state()
		return
	
	var still_in_throw_enter = player_node.is_attacking and player_node.attack_type == "throw_enter"
	if not still_in_throw_enter:
		if debug_enabled:
			print("[ThrowHandler] throw_enter ended without grab - resetting throw state")
		reset_throw_state()
		return
	
	# 持續檢查碰撞直到抓取成功或階段結束
	if is_grabbing:
		var opponent = check_grab_collision()
		if opponent:
			lock_opponent(opponent)


func _handle_hold_phase(delta: float) -> void:
	"""處理 HOLD 階段（throw_seq 期間）"""
	# 按 ThrowData 設定的持有幀數釋放（避免長時間綁定）
	if hold_start_frame >= 0:
		var throw_data = _get_throw_data()
		var hold_frames = throw_data.get("hold_duration_frames", 30)
		var hold_physics = _logic_frames_to_physics_frames(hold_frames)
		if Engine.get_physics_frames() - hold_start_frame >= hold_physics:
			release_opponent()
			return

	# 【新增】自動釋放機制：如果 throw_seq 動畫結束但沒有觸發事件，自動釋放
	if player_node and "attack_duration_timer" in player_node:
		# 當攻擊計時器歸零且還在 HOLD 階段，說明動畫已結束但沒有釋放
		if player_node.attack_duration_timer <= 0 and player_node.attack_type == "throw_seq":
			if debug_enabled:
				print("[ThrowHandler] HOLD phase auto-release: throw_seq animation completed but no release event triggered")
			release_opponent()
			return
	
	# 【新增】清空攻擊者速度（防止在摔投期間移動）
	if player_node and "fixed_velocity" in player_node:
		player_node.fixed_velocity.x = 0
	
	# 更新對手位置
	update_opponent_position(delta)
	
	# 檢查逃脫
	if check_throw_escape():
		return  # 逃脫成功，狀態已重置


func _handle_execute_phase() -> void:
	"""處理 EXECUTE 階段（釋放後單幀）"""
	# 釋放已完成，立即進入恢復
	current_phase = ThrowPhase.RECOVERY


func _handle_recovery_phase() -> void:
	"""處理 RECOVERY 階段（摔投結束）"""
	# 【修正】確保在 RECOVERY 階段也會重置狀態
	if player_node:
		# 檢查動畫是否已結束或狀態已改變
		if player_node.attack_type != "throw_seq" or not player_node.is_attacking:
			if debug_enabled:
				print("[ThrowHandler] RECOVERY phase complete, resetting state")
			reset_throw_state()
		# 【新增】額外保護：如果攻擊計時器歸零，也重置
		elif "attack_duration_timer" in player_node and player_node.attack_duration_timer <= 0:
			if debug_enabled:
				print("[ThrowHandler] RECOVERY phase: attack timer expired, resetting state")
			reset_throw_state()


## ═══════════════════════════════════════════════════════════════════════════
## 輔助函數
## ═══════════════════════════════════════════════════════════════════════════

func _get_throw_handler(target: Node) -> ThrowHandler:
	"""取得目標角色的 ThrowHandler"""
	for child in target.get_children():
		if child is ThrowHandler:
			return child
	return null


func _get_throw_data() -> Dictionary:
	"""獲取 ThrowData 資源數據"""
	if player_node and player_node.has_method("get_throw_data"):
		return player_node.get_throw_data()
	return {}


func _apply_throw_damage(opponent: Node, damage: float) -> void:
	"""應用摔投傷害"""
	if "healthbar" in opponent and opponent.healthbar != null:
		opponent.healthbar.current_health -= damage
		if debug_enabled:
			print("[ThrowHandler] Applied %.1f damage | remaining health: %.1f" % [damage, opponent.healthbar.current_health])
	else:
		push_warning("[ThrowHandler] Cannot apply damage: healthbar not found on %s" % opponent.name)


func _apply_launch_velocity(opponent: Node, throw_data: Dictionary) -> void:
	"""應用發射速度和重力"""
	if not world_node:
		push_error("[ThrowHandler] World node not found, cannot apply velocity")
		return
	
	var knockback = throw_data.get("knockback", 120.0)
	var horizontal_speed = throw_data.get("launch_horizontal_speed", 0.0)
	var vertical_speed = throw_data.get("launch_vertical_speed", -2200.0)
	var custom_gravity = throw_data.get("gravity", 0.0)
	
	# 計算總水平速度
	var facing = player_node.facing_direction if "facing_direction" in player_node else 1.0
	var total_horizontal = knockback + horizontal_speed
	
	opponent.fixed_velocity.x = int(total_horizontal * world_node.SIMULATION_SCALE * facing)
	opponent.fixed_velocity.y = int(vertical_speed * world_node.SIMULATION_SCALE)
	
	# 應用自訂重力（如果有）
	if custom_gravity > 0 and "knockfly_gravity" in opponent:
		opponent.knockfly_gravity = custom_gravity
	
	# 抬起對手位置（避免地面碰撞）
	opponent.fixed_position.y = world_node.FLOOR_Y - 10000  # 抬起 10 像素
	
	if debug_enabled:
		print("[ThrowHandler] Launch velocity applied | horizontal: %d | vertical: %d | gravity: %.0f" % [
			opponent.fixed_velocity.x, opponent.fixed_velocity.y, custom_gravity
		])


func _cleanup_opponent_state() -> void:
	"""清理對手狀態標記"""
	if grabbed_opponent:
		if "is_being_thrown" in grabbed_opponent:
			grabbed_opponent.is_being_thrown = false
		grabbed_opponent = null


func reset_throw_state() -> void:
	"""重置摔投狀態（摔投結束後呼叫）"""
	current_phase = ThrowPhase.NONE
	is_grabbing = false
	is_executing_throw = false
	lock_opponent_position = false
	escape_window_active = false
	escape_input_count = 0
	hold_start_frame = -1
	
	_cleanup_opponent_state()
	
	# 【關鍵修復】確保清除攻擊者的攻擊狀態
	# 原因： take_hit() 會將 attack_duration_timer 归零，導致計數器無法再自然減到 0 觸發 reset_attack_state()
	# 結果： attack_type 永遠停在 "throw_seq"，PushManager 持續跳過攻擊者 pushbox
	if player_node:
		player_node.is_attacking = false
		player_node.attack_type = "none"
		if "attack_duration_timer" in player_node:
			player_node.attack_duration_timer = 0
		var cwh = player_node.get_node_or_null("CancelWindowHandler")
		if cwh and cwh.has_method("reset"):
			cwh.reset()
	
	if debug_enabled:
		print("[ThrowHandler] State reset")


func _logic_frames_to_physics_frames(logic_frames: int) -> int:
	"""轉換邏輯幀（60 FPS）到物理幀（120 FPS）"""
	return int(round(logic_frames * 2.0))  # 120 / 60 = 2


## ═══════════════════════════════════════════════════════════════════════════
## 動畫事件接口（從 AnimationPlayer Call Method Track 呼叫）
## ═══════════════════════════════════════════════════════════════════════════

func on_animation_grab_check() -> void:
	"""動畫事件：檢查並抓取對手（throw_enter Frame 5）"""
	var opponent = check_grab_collision()
	if opponent:
		lock_opponent(opponent)


func on_animation_release() -> void:
	"""動畫事件：釋放對手（throw_seq Frame 29）"""
	release_opponent()


func on_animation_start_hold() -> void:
	"""動畫事件：開始持有階段（throw_seq Frame 1）"""
	if current_phase == ThrowPhase.GRAB:
		current_phase = ThrowPhase.HOLD
		if debug_enabled:
			print("[ThrowHandler] HOLD phase started via animation event")

## ═══════════════════════════════════════════════════════════════════════════
## 互相摔投衝突處理（雙方同時執行摔投時）—— Throw Escape
## ═══════════════════════════════════════════════════════════════════════════

func handle_mutual_throw_collision(opponent: Node) -> void:
	"""
	處理雙方同時執行摔投的衝突（Throw Escape）
	
	觸發條件: 雙方的 ThrowHandler 都在 STARTUP 階段時
	
	效果:
		- 播放 vfx_blk 特效於兩人中間
		- 雙方出現 block knockback 後退移動
		- 重置雙方摔投狀態，不造成傷害
	"""
	if not player_node or not world_node:
		return
	
	var throw_data = _get_throw_data()
	var escape_frames = throw_data.get("throw_escape_knockback_frames", 20)
	var escape_distance = throw_data.get("throw_escape_knockback_distance", 50.0)
	var sim_scale = float(world_node.SIMULATION_SCALE)
	
	# 計算 block knockback 初始速度
	var push_manager = player_node.get_tree().get_first_node_in_group("push_manager") if player_node else null
	var initial_velocity: float
	if push_manager:
		initial_velocity = push_manager.calculate_required_knockback_velocity(
			int(escape_distance * sim_scale), escape_frames
		)
	else:
		initial_velocity = escape_distance * sim_scale * 4.0  # 後備方案
	
	if debug_enabled:
		print("[THROW ESCAPE] Mutual throw! escape_frames=%d distance=%.1fpx initial_vel=%.0f" % [escape_frames, escape_distance, initial_velocity])
	
	# ── 重置雙方 ThrowHandler 狀態 ──
	reset_throw_state()
	var opponent_throw_handler = _get_throw_handler(opponent)
	if opponent_throw_handler:
		opponent_throw_handler.reset_throw_state()
	
	# ── 重置雙方攻擊狀態 ──
	player_node.is_attacking = false
	player_node.attack_type = "none"
	if "attack_duration_timer" in player_node:
		player_node.attack_duration_timer = 0
	var player_cwh = player_node.get_node_or_null("CancelWindowHandler")
	if player_cwh and player_cwh.has_method("reset"):
		player_cwh.reset()
	
	if "is_attacking" in opponent:
		opponent.is_attacking = false
		opponent.attack_type = "none"
	if "attack_duration_timer" in opponent:
		opponent.attack_duration_timer = 0
	var opp_cwh = opponent.get_node_or_null("CancelWindowHandler")
	if opp_cwh and opp_cwh.has_method("reset"):
		opp_cwh.reset()
	
	# ── 清除 is_being_thrown 標記（防止邊界狀態） ──
	if "is_being_thrown" in player_node:
		player_node.is_being_thrown = false
	if "is_being_thrown" in opponent:
		opponent.is_being_thrown = false
	
	# ── 應用後退移動（使用 corner_push 系統，獨立於 blockstun）──
	# 注意：不使用 block_knockback，因為 fighter.gd 在 blockstun_frames=0 時會立即清零
	# corner_push 是獨立系統，不依賴 blockstun 即可持續生效
	if "corner_push_frames" in player_node:
		player_node.corner_push_frames = escape_frames
		player_node.initial_corner_push_frames = escape_frames
		player_node.corner_push_velocity = initial_velocity
	
	if "corner_push_frames" in opponent:
		opponent.corner_push_frames = escape_frames
		opponent.initial_corner_push_frames = escape_frames
		opponent.corner_push_velocity = initial_velocity
	
	# ── 播放 vfx_blk 特效（在兩人中間） ──
	# 注意：get_vfx_scene() 接受 "block" 非 "vfx_block"
	var midpoint = (player_node.position + opponent.position) / 2.0
	VFXImpact.spawn_vfx(world_node, "block", midpoint, player_node.facing_direction)
	
	# ── 重置雙方動畫到 idle ──
	if player_node.animation_state:
		player_node.animation_state.travel("idle")
	if "animation_state" in opponent and opponent.animation_state:
		opponent.animation_state.travel("idle")
	
	if debug_enabled:
		print("[THROW ESCAPE] Done | %s → idle | %s → idle" % [player_node.name, opponent.name])
