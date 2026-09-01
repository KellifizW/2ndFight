class_name Fighter extends Movement

signal block_detected(target: String, block_type: String)

static var PHYSICS_FPS: int = 120
const LOGIC_FPS: int = 60  # 邏輯/顯示幀率（遊戲設計基礎）

func _enter_tree() -> void:
	PHYSICS_FPS = Engine.physics_ticks_per_second   # 這裡才真正賦值

@onready var collision_shape = $Pushbox
@onready var hitbox = $Hitbox/HitShape if has_node("Hitbox/HitShape") else null
@onready var proximitybox = $Proximitybox/ProxShape if has_node("Proximitybox/ProxShape") else null

# 🟢 【新增】Hit Stop 時機調試器（用於診斷連段時機問題）
var hitstop_debugger: HitStopTimingDebugger = null
var push_manager: Node = null       # cached in _ready()
var slow_mo_controller: Node = null  # cached in _ready()

var current_damage: float = 0.0
@export var min_hitstun_duration: float = 8.0 / 60.0

# ── 固定幀數控制（hitstun & blockstun & knockback 都使用）──
var hitstun_frames: int = 0          # hitstun 固定幀數（物理幀）
var blockstun_frames: int = 0        # blockstun 固定幀數（物理幀）
var knockback_frames: int = 0        # knockback 固定幀數（物理幀）
var initial_knockback_frames: int = 0  # ✅ 保存初始 knockback 幀數（物理幀）

# ── Block Knockback 系統（新增）──
var block_knockback_frames: int = 0  # block knockback 固定幀數（物理幀）
var initial_block_knockback_frames: int = 0  # 保存初始 block knockback 幀數（物理幀）

# ── Corner Push 系統（使用與 knockback 相同的機制）──
var corner_push_frames: int = 0  # corner push 固定幀數（物理幀）
var initial_corner_push_frames: int = 0  # 保存初始 corner push 幀數（物理幀）
var corner_push_start_x: float = 0.0  # Corner push 開始時的 X 位置（用於計算移動距離）
var corner_push_velocity: float = 0.0  # Corner push 初始速度

# Stage 2：`knockback_start_x` / `last_hit_attack_name` / `initial_blockstun_frames`
# 已刪除 —— 三者都只被寫入、從未被讀取（純殘骸，非除錯開關）。

# 🟢 待執行的 hit 參數（等待 hit stop 完成後才實際啟動）
var pending_hit_params: Dictionary = {}  # 存儲 take_hit 的所有參數
var waiting_for_hit_stop_end: bool = false  # 標記是否在等待 hit stop 完成

# Stage 1：秒↔幀 / 邏輯↔物理轉換已收攏至 Movement
# （seconds_to_lock_frames / seconds_to_frames_nearest / logic_frames_to_physics_frames）。
# 舊的 logic_seconds_to_physics_frames / sec_to_frames 為無人呼叫的重複實作，已移除。
static func logic_frames_to_physics_frames(logic_frames: float) -> int:
	"""將邏輯幀（60 FPS）轉換為物理幀 — Movement 邊界的委托入口。

	簽名必須與 Movement 完全一致（static + float 參數）：
	GDScript 覆寫不允許任何差異（含 int→float），否則編譯失敗。
	"""
	return Movement.logic_frames_to_physics_frames(logic_frames)

## Stage 2：此刻的單一活動狀態（由現行旗標推導，**唯讀**）。
##
## 這是「旗標與狀態並行期」的觀測窗：控制流仍然讀旗標，但狀態層已經存在
## 且被 test_25/test_26 釘住。等控制流逐段改為讀狀態後，旗標才會真正消失。
## 純推導、無副作用，可以在任何時間點安全呼叫（含測試每幀取樣）。
func get_fighter_state() -> int:
	return FighterState.resolve(self)

## 目前狀態的可讀名稱（除錯/測試輸出用）。
func get_fighter_state_name() -> String:
	return FighterState.state_name(get_fighter_state())

func _ready() -> void:
	super._ready()
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var collision_scale = collision_shape.scale
		colbox_half_width = collision_shape.shape.size.x * collision_scale.x / 2.0
		colbox_half_height = collision_shape.shape.size.y * collision_scale.y / 2.0
	else:
		Debug.log("Warning: CollisionShape2D not found or invalid for %s" % name)
	
	add_to_group("players")
	
	# 🟢 緩存常用節點
	push_manager = get_tree().get_first_node_in_group("push_manager") if get_tree() else null
	# 🟢 連接 SlowMoController 信號，在 hit stop 完成後啟動 hitstun/knockback/blockstun
	if world and world.has_node("SlowMoController"):
		slow_mo_controller = world.get_node("SlowMoController")
		slow_mo_controller.hit_slowmo_finished.connect(_on_hit_slowmo_finished)
	
	# 🟢 【新增】獲取場景中的 HitStopTimingDebugger（如果存在）
	if world and world.has_node("HitStopTimingDebugger"):
		hitstop_debugger = world.get_node("HitStopTimingDebugger")

func _physics_process(delta: float) -> void:
	if not world:
		Debug.log("Warning: World node not found in group 'world' for %s" % name)
		return

	# 🟢 【調試】監控 DP 期間的垂直速度變化
	# （已移除 DP debug 列印）
	# 🟢 【修正】檢查是否在 hit stop 期間，如果是則暫停所有幀數遞減
	var is_in_hitstop = slow_mo_controller and slow_mo_controller.is_hit_slowmo
	
	# 🟢 Hit stop 期間，完全跳過幀數遞減邏輯
	if is_in_hitstop:
		# 在 hit stop 期間不執行任何幀數遞減，保持狀態凍結
		return

	# ── 【固定幀數 hitstun 和 knockback 同時遞減】──
	if hitstun_frames > 0:
		hitstun_frames -= 1
		# 🔴 同時遞減 knockback_frames，確保完全同步
		if knockback_frames > 0:
			knockback_frames -= 1
		
		is_hit = true
		if hitstun_frames <= 0:
			# 如果不是在空中受擊狀態，才清除 is_hit
			if not is_air_hit_backjump:
				is_hit = false
				was_hit_while_crouching = false  # 重置蹲姿受擊標記
		# 確保 knockback 也在 hitstun 結束時停止
		if knockback_frames <= 0:
			knockback_frames = 0
	else:
		# 如果不是在空中受擊狀態，才清除 is_hit
		if not is_air_hit_backjump:
			is_hit = false
			was_hit_while_crouching = false  # 重置蹲姿受擊標記
		knockback_frames = 0  # 確保 knockback 也被清除

	# ── 【固定幀數 blockstun 及 block knockback】與 hitstun 完全一致──
	if blockstun_frames > 0:
		blockstun_frames -= 1
		# 同時遞減 block_knockback_frames，確保完全同步
		if block_knockback_frames > 0:
			block_knockback_frames -= 1
		
		is_blocking = true
		if blockstun_frames <= 0:
			is_blocking = false
			block_type = "none"
			Debug.log("[FIXED-FRAME BLOCKSTUN END] %s 格擋結束！" % name)
			block_knockback_frames = 0  # 確保 block knockback 也被清除
	else:
		if blockstun_frames <= 0:
			is_blocking = false
		block_knockback_frames = 0  # 確保 block knockback 也被清除

	# ── 【Corner Push 幀數遞減】獨立系統，不與 hitstun 同步──
	if corner_push_frames > 0:
		corner_push_frames -= 1
		if corner_push_frames <= 0:
			corner_push_frames = 0
			corner_push_velocity = 0.0
			fixed_velocity.x = 0

	# ── super 先執行（block_lock_frames 仍由 PushManager 遞減，狀態以 blockstun_frames 為準）──
	super._physics_process(delta)

	# ── Stage 2 切片 2：舊的第二攻擊入口已移除 ──────────────────────
	#
	# 這裡原本有一段「保持舊版」的攻擊輸入檢查：
	#   is_valid_state = on_floor and not (dashing/backdashing/crouching/jumping)
	#   if (st_mp_pressed or st_mk_pressed) and is_valid_state
	#      and not (is_hit or is_knockfly or is_blocking):
	#       current_damage = input_data.damage if input_data.has("damage") else 10.0
	#       is_attacking = true
	#
	# 它是 AttackExecutor 出現之前的攻擊入口，重構後沒有被刪掉，於是攻擊子系統
	# 長期存在**兩個**入口，而且這一個的守衛跟另一個不一樣（多一項 not is_crouching、
	# 少 landing / wakeup / layground 三項），也不走按鈕優先序、不消耗輸入 buffer。
	# 它每一幀都比 Player 的攻擊邏輯早跑（Player._physics_process 先呼叫
	# super._physics_process），因此有三種可觀測效果，逐一確認後移除：
	#
	#   1. `current_damage = 10.0`：不可觀測。current_damage 唯一的讀取點是
	#      HitResponseHandler._get_hit_parameters() 的預設值，而該函式接著
	#      一律用 ATTACK_TABLE[attack_type].damage（普通攻擊）或
	#      active_move.damage（特殊招）覆寫它；`input_data.has("damage")`
	#      那一支更是全倉庫沒有任何輸入來源會放 "damage" 鍵。
	#   2. `is_attacking = true`：在 AttackExecutor 同一幀也會出招的情況下
	#      完全重複（值相同）。
	#   3. `is_attacking = true` 而 AttackExecutor **沒有**出招：這是唯一的
	#      行為差異，而且它是 bug —— attack_type 停在 "none"，產生
	#      「在出招但不知道出哪一招」的孤兒狀態（動畫層當 Walk 播、
	#      MoveSet 拒開新招、跳躍/衝刺守衛全擋、attack_duration_timer=0
	#      所以沒有計時器會收回來）。可達窗口只有兩個，都很窄：
	#        a. 無輸入著地後的第 1 個物理幀（landing_lock_frames=5→4，
	#           _landing_forced_frames=1 < 2，著地攻擊取消還不能觸發）；
	#        b. 攻擊動畫結束當幀（reset_attack_state 剛把 attack_type 清成
	#           "none"，同幀的攻擊去重鎖又擋掉重新出招）。
	#      兩者都要「按鍵恰好在下一幀消失」才會留下殘留狀態（InputBuffer 保留
	#      30 物理幀，所以實務上通常下一幀就自愈）；但窗口窄不代表它合法。
	#
	# 移除後 `is_attacking = true` 只剩兩個寫入點（Player._execute_attack、
	# ThrowHandler 進入 throw_seq），兩者都在同一個區塊裡寫入合法 attack_type，
	# 於是 FighterState.check_invariants() 的「攻擊必須成對」不變式
	# 從「靠約定」變成「結構上成立」。test_25/test_29 每幀釘住它。
	var input_data = get_input()

	# ── 【動畫更新】保持舊版邏輯──
	# Stage 2 切片 2：原本這裡是 `if is_hit or is_knockfly or is_blocking: … else: …`，
	# 兩個分支一字不差（都是同一個 _update_animation_state 呼叫）。
	# 分支本身在暗示「受擊時動畫更新不一樣」，但實際上差別全在
	# Player._compute_target_state / AnimationManager.compute_target_state 裡面，
	# 這個 if 只是噪音（與 Movement._physics_process 裡切片 1 收掉的
	# is_crouch_transition_played if/else 同一類殘骸）。
	_update_animation_state(input_data.input_dir, input_data.crouch_pressed)

func post_physics_process(_delta: float) -> void:
	pass

func _calc_knockback_velocity(push_distance: float, frames: int) -> float:
	if push_manager:
		return push_manager.calculate_required_knockback_velocity(
			int(push_distance * world.SIMULATION_SCALE), frames, name)
	return push_distance * world.SIMULATION_SCALE * 4.0

# ── 【關鍵修復】take_hit：hitstun & blockstun 都使用固定幀數，並改用新版掉血方式──
func take_hit(
	hitstun_duration: int = 18,
	blockstun_duration: int = 10,
	damage: float = 10.0,
	skip_push: bool = false,
	force_knockfly: bool = false,
	knockfly_params: Dictionary = {},
	knockback_distance: float = -1.0
) -> void:
	if not world:
		Debug.log("Warning: World node not found in group 'world' for %s" % name)
		return
	
	# 🟢 輸入是邏輯幀（60 FPS 基準），需轉換為物理幀
	var physics_hitstun = logic_frames_to_physics_frames(hitstun_duration)
	var physics_blockstun = logic_frames_to_physics_frames(blockstun_duration)
	
	# 記錄被擊中時是否處於蹲姿（用於選擇正確的受擊動畫）
	was_hit_while_crouching = is_crouching
	
	# Clear input buffer when getting hit
	if has_node("PlayerController"):
		var controller = get_node("PlayerController")
		if controller.has_method("clear_buffer"):
			controller.clear_buffer()
	
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove
	
	var input_data = get_input()
	
	if is_attacking:
		is_attacking = false
		if is_spmove:
			move_set.stop_special_move()
	
	# ── 格擋判斷（不變）──
	if (is_holding_back or is_crouch_blocking) and is_on_floor() and not is_spmove:
		# ...（格擋部分保持原樣，不改動）
		is_blocking = true
		is_crouch_blocking = input_data.crouch_pressed and input_data.input_dir * get_facing_multiplier() < 0
		blockstun_frames = physics_blockstun  # ✅ 使用轉換後的物理幀
		block_lock_frames = physics_blockstun
		
		# 🟢 【修正】強制重置垂直速度和位置，確保完全在地面上（避免 DP 跳躍條件失敗）
		# ⚠️  注意：這只清零防禦方的速度，不應影響攻擊方
		fixed_velocity.x = 0
		fixed_velocity.y = 0
		if fixed_position.y != world.FLOOR_Y:
			fixed_position.y = world.FLOOR_Y
		
		if not skip_push:
			# ── 【新增】Block Knockback 使用幀計數系統，與 Hit Knockback 對齐 ──
			# ✅ 關鍵：使用相同的 knockback_distance 參數，確保 block knockback 距離 = hit knockback 距離
			var push_distance = knockback_distance if knockback_distance > 0 else block_push_distance
			
			# 🟢 使用反推函數計算所需的初始速度，確保實際距離 = push_distance
			block_push_initial_velocity = _calc_knockback_velocity(push_distance, physics_blockstun)
			
			block_knockback_frames = physics_blockstun  # Block knockback 持續時間 = blockstun 時間
			initial_block_knockback_frames = physics_blockstun  # 保存初始幀數用於衰減計算
			
			# @deprecated 保留舊計時器以維持向後兼容（test_18 釘住其型別）
			block_push_frames = physics_blockstun
		
		block_detected.emit(name, block_type)
		_update_animation_state(0, input_data.crouch_pressed)
		return
	
	# ── 離開格擋狀態 ──
	if is_blocking:
		is_blocking = false
		block_type = "none"
	
	# 真正被打中：中斷自己正在播的普通攻擊喊聲與衝刺聲效（前衝 / 後撤步）
	AttackSoundResolver.stop_attack_grunts(self)
	AttackSoundResolver.stop_dash_sounds(self)
	
	# ── 播放受擊痛苦叫聲 - 根據傷害值選擇普通或強力叫聲 ──
	var is_heavy_hit = damage >= 8.0
	var hurt_player_name = "HeavyHurtGruntPlayer" if is_heavy_hit else "HurtGruntPlayer"
	var hurt_grunt_player = null
	if has_node(hurt_player_name):
		hurt_grunt_player = get_node(hurt_player_name)
	elif has_node("HurtGruntPlayer"):
		# 回退到 HurtGruntPlayer
		hurt_grunt_player = get_node("HurtGruntPlayer")
	if hurt_grunt_player:
		hurt_grunt_player.play()
	
	if not is_on_floor():
		update_facing_direction()
	
	# ── 扣血（不變）──
	if healthbar != null:
		healthbar.current_health -= damage
		Debug.log("Debug: %s 受到 %.1f 傷害，剩餘血量 %.1f" % [name, damage, healthbar.current_health])
	else:
		Debug.log("Warning: healthbar 未設定，無法扣血（%s）" % name)
	
	var facing_mult = get_facing_multiplier()
	var should_knockfly: bool = force_knockfly or damage > 10.0 or (healthbar != null and healthbar.current_health <= 0)
	
	# ── 清除跳躍延遲（避免與受擊狀態衝突）──
	if not is_on_floor():
		jump_delay_timer = 0
	
	if should_knockfly:
		# ── Knockfly 專用處理 ──
		var params = {
			"gravity": default_knockfly_gravity,
			"vertical_speed": default_knockfly_vertical_speed,
			"horizontal_speed": default_knockfly_horizontal_speed,
			"duration": default_knockfly_duration
		}
		params.merge(knockfly_params, true)
		
		is_knockfly = true
		# Stage 1：秒 → 物理幀，由 PushManager 每幀 -1（hitstop 期間凍結）
		start_knockfly_timer(float(params.duration))
		Debug.log("[KNOCKFLY DEBUG] Started | params.duration: %.3fs -> knockfly_frames: %d" % [params.duration, knockfly_frames])
		is_immune_to_floor_snap = true
		floor_snap_immunity_timer = Movement.seconds_to_frames_nearest(floor_snap_immunity_duration)  # 幀數（唯一秒→幀邊界）
		
		knockfly_gravity = params.gravity
		knockfly_vertical_speed = params.vertical_speed
		knockfly_horizontal_speed = params.horizontal_speed
		
		# 強制設定垂直速度（避免任何殘留跳躍速度）
		fixed_velocity.y = int(params.vertical_speed * world.SIMULATION_SCALE)
		fixed_position.y -= 1
		
		# 記錄並打印垂直速度來源
		var final_vertical = params.vertical_speed * world.SIMULATION_SCALE
		Debug.log("[KNOCKFLY VERTICAL SPEED] %s 被擊飛 → 垂直速度 = %d (原始: %.1f * SIMULATION_SCALE %.1f)" % [
			name, final_vertical, params.vertical_speed, world.SIMULATION_SCALE
		])
		
		is_jumping = true
		
		if not skip_push:
			# 設置 knockfly_horizontal_speed 屬性
			if "horizontal_speed" in params:
				knockfly_horizontal_speed = params["horizontal_speed"]
			
			var calculated_velocity = -knockfly_horizontal_speed * world.SIMULATION_SCALE * facing_mult
			knockfly_velocity_x = calculated_velocity
			fixed_velocity.x = int(knockfly_velocity_x)
		
		_update_animation_state(0, input_data.crouch_pressed)
		
	else:
		# ── 普通受擊 → 空中/地面分別處理 ──
		is_hit = true
		var hit_frames = physics_hitstun  # ✅ 使用轉換後的物理幀
		
		# 🟢 檢查是否有 hit stop 正在進行
		if slow_mo_controller and slow_mo_controller.is_hit_slowmo:
			# Hit stop 正在進行 → 延遲設置 hitstun/knockback/blockstun，等待 hit stop 完成
			Debug.log("[HITSTUN DELAYED] %s - Hit stop 進行中，延遲設置 hitstun/knockback/blockstun" % name)
			waiting_for_hit_stop_end = true
			pending_hit_params = {
				"hit_frames": hit_frames,
				"blockstun": 0,  # 普通受擊不設置 blockstun
				"skip_push": skip_push,
				"hit_push_initial_velocity": 0.0  # 將在下面計算
			}
			
			# 🟢 【新增】記錄 Hit Stop 開始事件（用於調試）
			if hitstop_debugger:
				var attacker = _find_attacker()
				if attacker:
					var attack_name = attacker.get("attack_type") if "attack_type" in attacker else "unknown"
					hitstop_debugger.start_hitstop_event(attacker, self, attack_name)
			
			# 計算 knockback 速度（必須在設置 pending_hit_params 之前）
			if not skip_push:
				var push_distance = knockback_distance if knockback_distance > 0 else hit_push_distance
				# 🟢 使用反推函數計算所需的初始速度，確保實際距離 = push_distance
				pending_hit_params["hit_push_initial_velocity"] = _calc_knockback_velocity(push_distance, hit_frames)
		else:
			# Hit stop 未進行或已完成 → 立即設置 hitstun/knockback/blockstun
			hitstun_frames = hit_frames
		
		# 舊 hit_timer 的幀制版：與 hitstun_frames 同長度，由 PushManager 遞減
		hit_lock_frames = hit_frames
		
		if not is_on_floor():
			# 空中普通攻擊：強制使用後跳邏輯，垂直速度為正常跳躍的 0.7 倍
			is_air_hit_backjump = true
			# Stage 1：秒數種子統一經 Movement.seconds_to_frames_nearest 轉物理幀
			# （0.2s×120=24，數值與舊式 round(dur*LOGIC_FPS*2) 完全相同，僅收攏轉換點）
			air_hit_backjump_timer = Movement.seconds_to_frames_nearest(air_hit_backjump_duration)
			is_jumping = true  # 確保 GravityHandler 正常懂用重力
			just_jumped = true  # 防止 GravityHandler 重置速度為 0
			fixed_velocity.x = int(-air_hit_backjump_speed * world.SIMULATION_SCALE * facing_mult)
			# 使用正常跳躍速度的 0.7 倍作為垂直速度(jump_vertical_speed 約為 -2300)
			var normal_jump_speed = jump_vertical_speed if "jump_vertical_speed" in self else -2300.0
			fixed_velocity.y = int(normal_jump_speed * 0.7 * world.SIMULATION_SCALE)
			is_immune_to_floor_snap = true
			floor_snap_immunity_timer = Movement.seconds_to_frames_nearest(floor_snap_immunity_duration)
			Debug.log("[AIR HIT DEBUG] air_hit_backjump_timer: %.3fs -> %d frames, floor_snap_immunity_timer: %.3fs -> %d frames @120 FPS physics" % [air_hit_backjump_duration, air_hit_backjump_timer, floor_snap_immunity_duration, floor_snap_immunity_timer])
			fixed_position.y -= 2
			Debug.log("[AIR HIT] %s 空中受擊 → 後跳速度 x=%d, y=%d (0.7x 正常跳躍)" % [name, fixed_velocity.x, fixed_velocity.y])
		else:
			# 地面普通受擊 → 只有 hitstun，無垂直速度（讓 PushManager 處理水平推擊）
			fixed_velocity.y = 0
		
		if not skip_push:
			var push_distance = knockback_distance if knockback_distance > 0 else hit_push_distance
			# knockback 使用固定幀數系統，持續時間 = hitstun 時間（物理幀）
			
			knockback_start_time = 0.0  # 重置時間戳，讓 PushManager 重新記錄
			
			# 🟢 使用反推函數計算所需的初始速度，確保實際距離 = push_distance
			hit_push_initial_velocity = _calc_knockback_velocity(push_distance, hit_frames)
			# 🟢 如果不在等待 hit stop 結束，才立即啟動 knockback
			if not waiting_for_hit_stop_end:
				# 立即啟動 knockback（無延遲）
				knockback_frames = hit_frames  # 立即設置為 hitstun 幀數
				initial_knockback_frames = hit_frames  # ✅ 保存初始幀數
				hit_push_velocity = hit_push_initial_velocity
				# 不在這裡設置 knockback_start_time，讓 PushManager 首次執行時記錄

		# 🟢 【關鍵】普通受擊也要立刻把狀態機推向受擊動畫：
		# 格擋 / knockfly 分支本來就會呼叫 _update_animation_state，唯獨普通受擊
		# 漏掉了 —— 結果 sprite 在 hitstop 期間一直停在被打前的舊姿勢，要等
		# hitstop 結束、_physics_process 恢復後才切進 hit / cr_hit，完全沒有
		# 「定格在受擊幀」的感覺。這裡把 travel 排進佇列（is_hit 已為 true，
		# compute_target_state 會選對受擊動畫）；真正套用由 HitStopController
		# 凍結時的 advance(0)（delta=0 沖洗）完成，sprite 會停在受擊動畫第 0 格、
		# 直到 hitstop 結束才開始播放。
		_update_animation_state(0, input_data.crouch_pressed)

func take_knockfly() -> void:
	var move_set = $MoveSet if has_node("MoveSet") else null
	var is_spmove = move_set and move_set.is_spmove

	if not is_hit and not is_knockfly and is_on_floor():
		if is_spmove:
			move_set.stop_special_move()
		is_knockfly = true
		# Stage 1：秒 → 物理幀
		start_knockfly_timer(max(default_knockfly_duration, min_hitstun_duration))
		Debug.log("[KNOCKFLY TAKE DEBUG] default_knockfly_duration: %.3fs -> knockfly_frames: %d" % [default_knockfly_duration, knockfly_frames])
		_update_animation_state(0, is_crouching)

func get_contact_point(hit_area: Area2D, hurt_area: Area2D) -> Vector2:
	var hit_shape_node = hit_area.get_node_or_null("HitShape") as CollisionShape2D
	var hurt_shape_node = hurt_area.get_node_or_null("HurtShape") as CollisionShape2D

	if not hit_shape_node or not hurt_shape_node or not (hit_shape_node.shape is RectangleShape2D) or not (hurt_shape_node.shape is RectangleShape2D):
		return (hit_area.global_position + hurt_area.global_position) / 2.0

	var SIMULATION_SCALE = world.SIMULATION_SCALE if world else 1000.0
	var TOLERANCE = 2.0 * SIMULATION_SCALE

	var hit_shape_pos = hit_shape_node.global_position
	var hit_half_size = hit_shape_node.shape.extents * abs(hit_shape_node.global_scale)
	var hit_left = (hit_shape_pos.x - hit_half_size.x) * SIMULATION_SCALE
	var hit_right = (hit_shape_pos.x + hit_half_size.x) * SIMULATION_SCALE
	var hit_bottom = (hit_shape_pos.y - hit_half_size.y) * SIMULATION_SCALE
	var hit_top = (hit_shape_pos.y + hit_half_size.y) * SIMULATION_SCALE

	var hurt_shape_pos = hurt_shape_node.global_position
	var hurt_half_size = hurt_shape_node.shape.extents * abs(hurt_shape_node.global_scale)
	var hurt_left = (hurt_shape_pos.x - hurt_half_size.x) * SIMULATION_SCALE
	var hurt_right = (hurt_shape_pos.x + hurt_half_size.x) * SIMULATION_SCALE
	var hurt_bottom = (hurt_shape_pos.y - hurt_half_size.y) * SIMULATION_SCALE
	var hurt_top = (hurt_shape_pos.y + hurt_half_size.y) * SIMULATION_SCALE

	var overlap_left = max(int(hit_left), int(hurt_left))
	var overlap_right = min(int(hit_right), int(hurt_right))
	var overlap_bottom = max(int(hit_bottom), int(hurt_bottom))
	var overlap_top = min(int(hit_top), int(hurt_top))

	if overlap_left <= overlap_right + TOLERANCE and overlap_bottom <= overlap_top + TOLERANCE:
		var median_x = (overlap_left + overlap_right) / 2.0 / SIMULATION_SCALE
		var median_y = (overlap_bottom + overlap_top) / 2.0 / SIMULATION_SCALE
		return Vector2(median_x, median_y)

	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	query.set_shape(hit_shape_node.shape)
	query.transform = hit_shape_node.global_transform
	query.collision_mask = hurt_area.collision_layer
	var result = space_state.intersect_shape(query, 1)
	if result and result.size() > 0 and result[0].has("point"):
		return result[0].point

	return (hit_area.global_position + hurt_area.global_position) / 2.0

func is_in_hitstun() -> bool:
	return hitstun_frames > 0

func is_in_blockstun() -> bool:
	return blockstun_frames > 0

# 🟢 Hit stop 完成後的回調 - 啟動被延遲的 hitstun/knockback/blockstun
func _on_hit_slowmo_finished() -> void:
	if waiting_for_hit_stop_end and pending_hit_params.size() > 0:
		Debug.log("[HIT STOP END] %s - 啟動被延遲的 hitstun/knockback/blockstun" % name)
		_apply_pending_hit_effect()
		waiting_for_hit_stop_end = false
		pending_hit_params.clear()
		
		# 🟢 【新增】記錄 Hit Stop 結束事件（用於調試）
		if hitstop_debugger:
			var attacker = _find_attacker()
			if attacker:
				hitstop_debugger.end_hitstop_event(attacker, self)

# 🟢 實際應用被延遲的 hit 效果（在 hit stop 完成後執行）
func _apply_pending_hit_effect() -> void:
	var hit_frames = pending_hit_params.get("hit_frames", 0)
	var blockstun = pending_hit_params.get("blockstun", 0)
	var skip_push = pending_hit_params.get("skip_push", false)
	
	# 啟動 hitstun（blockstun 只在格擋時設置）
	Debug.log("[DEBUG _apply_pending_hit_effect] 執行前: hitstun_frames=%d, 即將設置為 %d" % [hitstun_frames, hit_frames])
	hitstun_frames = hit_frames
	hit_lock_frames = hit_frames
	Debug.log("[DEBUG _apply_pending_hit_effect] 執行後: hitstun_frames=%d" % hitstun_frames)
	if blockstun > 0:
		blockstun_frames = blockstun
		block_lock_frames = blockstun
	
	# 啟動 knockback（如果不跳過 push）
	if not skip_push:
		var hit_frames_val = pending_hit_params.get("hit_frames", 0)
		var hit_push_initial_velocity_val = pending_hit_params.get("hit_push_initial_velocity", 0)
		
		# 立即啟動 knockback（無延遲）
		knockback_frames = hit_frames_val
		initial_knockback_frames = hit_frames_val
		hit_push_velocity = hit_push_initial_velocity_val
	
	Debug.log("[HIT EFFECT APPLIED] %s - hitstun: %d frames, blockstun: %d frames, knockback: %d frames" % [
		name, hitstun_frames, blockstun_frames, knockback_frames
	])

# 🟢 【新增】查找攻擊者（用於調試）
func _find_attacker() -> Node:
	"""嘗試找到攻擊這個角色的玩家"""
	var all_players = get_tree().get_nodes_in_group("players")
	for p in all_players:
		if p == self:
			continue
		# 簡單判斷：如果另一個玩家正在攻擊，假設是他
		if "is_attacking" in p and p.is_attacking:
			return p
	# 如果找不到，返回第一個不是自己的玩家
	for p in all_players:
		if p != self:
			return p
	return null
