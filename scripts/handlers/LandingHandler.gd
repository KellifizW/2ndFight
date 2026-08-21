class_name LandingHandler extends Node

# Handles landing mechanics for both normal jumps and knockfly states
# 【改進】支援正常著地和被擊飛著地（→layground）
var movement_node: Node

func _init(movement: Node) -> void:
	movement_node = movement

func handle_landing(input_data: Dictionary, floor_y: int, delta: float) -> void:
	# ========== 檢查著地條件 ==========
	# 【改進】條件簡化：使用統一的空中狀態檢查
	var is_airborne = movement_node.is_jumping or movement_node.is_knockfly or movement_node.is_air_hit_backjump
	var is_falling = movement_node.fixed_velocity.y >= 0
	var reached_floor = movement_node.fixed_position.y >= floor_y
	var jump_delay_passed = movement_node.jump_delay_timer <= 0
	var not_just_jumped = not movement_node.just_jumped
	
	var seat = movement_node.seat if "seat" in movement_node else "?"
	
	if not (is_airborne and is_falling and reached_floor and jump_delay_passed and not_just_jumped):
		return
	
	var move_set = movement_node.get_node_or_null("MoveSet")
	var is_spmove_active = move_set and move_set.is_spmove
	var active_move = move_set.get_active_move_name() if move_set and move_set.has_method("get_active_move_name") else "none"
	
	# 【業界標準】檢查是否在特殊招式期間
	if is_spmove_active:
		# 【除錯】詳細記錄觸發條件，幫助診斷誤觸發
		Debug.log("[LANDING_DETECTED_DURING_SPMOVE] %s | move=%s | pos_y=%d floor_y=%d | vel_y=%d | is_jumping=%s | conditions: airborne=%s falling=%s reached_floor=%s delay_passed=%s not_just_jumped=%s" % [
			seat, active_move, movement_node.fixed_position.y, floor_y, movement_node.fixed_velocity.y, movement_node.is_jumping,
			is_airborne, is_falling, reached_floor, jump_delay_passed, not_just_jumped
		])
		
		# 【防護】如果速度向上（vel_y < 0），是因為PushManager推擠導致vel_y=0的誤觸發，不應重置
		# 注意：此時vel_y=0是因為PushManager在hitstop期間持續把位置snap回地面，
		# 導致重力累積使速度趨近0——實際上角色應該要上升，不應被當作著地處理
		if movement_node.fixed_velocity.y < 0:
			Debug.log("[LANDING_SPMOVE_GUARD] %s | vel_y=%d < 0，角色正在上升，跳過著地重置（防止DP跳躍被中斷）" % [
				seat, movement_node.fixed_velocity.y
			])
			return  # ← 不重置，讓角色繼續上升
		
		# 【重要】在特殊招式期間真正著地時：
		# ✅ 重置位置和速度（防止穿過地面）
		# ❌ 但NOT觸發landing動畫（animation由extended move animation包含）
		movement_node.fixed_position.y = floor_y
		movement_node.fixed_velocity.y = 0
		movement_node.is_jumping = false
		movement_node.just_jumped = false
		return  # ← 提早退出，不設置 is_landing = true
	
	# ========== 處理正常著地（從普通跳躍或特殊招式結束後著地） ==========
	if not movement_node.is_knockfly:
		Debug.log("[LANDING_DETECT_NORMAL] %s | move=%s | is_jumping=%s" % [seat, active_move, movement_node.is_jumping])
		_handle_normal_landing(input_data, floor_y, delta)
		return
	
	# ========== 處理被擊飛後著地（knockfly → layground） ==========
	# 【注意】實際轉換由 KnockflyHandler 負責，此處只確保不觸發landing動畫
	if movement_node.is_knockfly:
		# knockfly狀態由KnockflyHandler管理，此處不做任何操作
		return

func _handle_normal_landing(input_data: Dictionary, floor_y: int, delta: float) -> void:
	"""Handle landing from regular jump or completed DP/special move
	
	著地處理流程（新規則）：
	1. 重置位置和速度
	2. 清除jump狀態
	3. 【新增】總是播放至少2幀的landing動畫（強制landing lock）
	4. 2幀後，檢查輸入：
	   - 無輸入 → 繼續完整landing動畫（landing_duration）
	   - 有輸入 → 中斷landing，進入輸入狀態
	5. 播放著地效果音和粒子
	6. 更新動畫狀態
	"""
	
	var seat = movement_node.seat if "seat" in movement_node else "?"
	var move_set = movement_node.get_node_or_null("MoveSet")
	var active_move = move_set.get_active_move_name() if move_set and move_set.has_method("get_active_move_name") else "none"
	
	# 【重要】重置位置到正確的floor_y
	movement_node.fixed_position.y = floor_y
	movement_node.fixed_velocity.y = 0
	movement_node.is_jumping = false
	movement_node.just_jumped = false  # 【關鍵】立即清除 just_jumped，防止新跳躍在著地期間覆蓋狀態
	
	# 【著地時停止水平移動】確保著地後不會繼續滑動
	var pre_clear_vel_x = movement_node.fixed_velocity.x
	if pre_clear_vel_x != 0:
		Debug.log("[LANDING HANDLER] %s: About to clear vel_x=%d, is_knockfly=%s" % [seat, pre_clear_vel_x, movement_node.is_knockfly])
	movement_node.fixed_velocity.x = 0
	
	# 重置相關狀態
	movement_node.neutral_timer = 0.0
	movement_node.pending_dash_dir = 0
	movement_node.last_input_dir = 0
	movement_node.landing_facing_lock = false
	movement_node.jump_delay_timer = 0  # 【關鍵】清除跳躍延遲，準備下一次跳躍
	
	# 【新規則】總是播放至少2幀的landing動畫（無論輸入狀態）
	movement_node.is_landing = true
	movement_node.landing_lock_timer = 2.0 / 60.0  # 2 frames at 60 FPS = 0.0333秒
	movement_node._landing_timer_initialized = false  # 【新增】標記此timer剛設置，下一frame才能檢查
	movement_node._landing_checkpoint_executed = false  # 【新增】重置checkpoint執行標記
	movement_node._landing_forced_frames = 0  # 【新增】重置強制幀數計數器
	if movement_node.has_method("force_update_facing_direction"):
		movement_node.force_update_facing_direction()
	
	Debug.log("[LANDING_START] %s: is_landing=true, timer=2f, checkpoint_reset" % [seat])
	
	# 【視覺效果】著地時播放粒子和sound
	if movement_node.groundsmoke:
		movement_node.groundsmoke.scale.x = movement_node.facing_direction
		movement_node.groundsmoke.restart()
	
	# 【重點】保存landing timer，然後更新動畫狀態，再恢復timer
	var saved_landing_timer = movement_node.landing_lock_timer
	var saved_is_landing = movement_node.is_landing
	
	# 更新動畫狀態以觸發landing動畫
	movement_node._update_animation_state(input_data.input_dir, input_data.crouch_pressed)
	
	# 恢復landing狀態（防止被其他狀態覆蓋）
	movement_node.landing_lock_timer = saved_landing_timer
	movement_node.is_landing = saved_is_landing
	
	# 【推擠系統】處理著地時的pushbox碰撞
	var push_manager = movement_node.get_tree().get_first_node_in_group("push_manager")
	if push_manager:
		push_manager._physics_process(delta)
