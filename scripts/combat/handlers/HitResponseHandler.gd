class_name HitResponseHandler extends Node

## HitResponseHandler - Phase 4 Refactoring
##
## 職責: 處理攻擊擊中對手時的所有邏輯
## - 碰撞檢測與過濾
## - 攻擊數據查詢（ATTACK_TABLE / MoveSet）
## - 調用目標的 take_hit()
## - VFX/SFX 效果觸發
## - Pushback 處理
## - Hit-confirm cancel 信號
## - 多段招式 hit 追蹤
##
## 基於業界格鬥遊戲模式：
## - Street Fighter V: HitDetector with damage calculator
## - Guilty Gear Strive: DamageHandler with effect spawner
## - Tekken 8: CollisionSystem with hit response

# ── 引用 ──
var parent_player: Node = null
var world: Node = null
var slow_mo_controller: Node = null  # cached in _ready()

# ── 多段招式追蹤 ──
var multi_hit_targets: Dictionary = {}  # {target_id: {hit_index: int, last_hit_frame: int}}

# ── 單段攻擊的命中登記（一次揮拳只能命中同一目標一次）──
# key = target instance_id, value = 攻擊實例 token（attack_type + Player.attack_instance_id）。
# 沒有這層保護時，只要 Hitbox 在同一次出招內離開再重新進入 Hurtbox
#（hitstop 期間攻擊者仍在前衝 / PushManager 仍在推開 pushbox 時很容易發生），
# area_entered 就會再觸發一次完整的命中流程：第二次 take_hit、第二次音效 /
# 特效、第二次 hitstop —— 玩起來就像「一拳打出兩次」。
var single_hit_registry: Dictionary = {}

# 🔍 Debug counter for CI diagnostics（登記過幾次命中，不影響行為）。
var debug_hit_registered_count: int = 0

# ── VFX 系統 ──
const VFXImpact = preload("res://scripts/vfx/vfx_impact.gd")
const VFXSmoke = preload("res://scripts/vfx/vfx_smoke.gd")

func _init(player: Node) -> void:
	parent_player = player

func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	if world and world.has_node("SlowMoController"):
		slow_mo_controller = world.get_node("SlowMoController")

func process_multi_hit_overlaps() -> void:
	"""多段連打專用：每幀輪詢重疊的 Hurtbox，避免只靠 area_entered 漏段"""
	if not parent_player:
		return
	var move_set = parent_player.move_set if "move_set" in parent_player else null
	if not move_set or not move_set.is_spmove or not move_set.current_move_state.active_move:
		return
	var active_move = move_set.current_move_state.active_move
	if not active_move.is_multi_hit:
		return
	
	var hitbox = parent_player.get_node_or_null("Hitbox")
	if not hitbox:
		return
	
	var overlapping = hitbox.get_overlapping_areas()
	for area in overlapping:
		if area is Area2D:
			handle_hitbox_collision(area)

# ═══════════════════════════════════════════════════════════════════════════
# 主要碰撞處理
# ═══════════════════════════════════════════════════════════════════════════

func handle_hitbox_collision(area: Area2D) -> void:
	"""處理 Hitbox 碰撞到 Hurtbox 的邏輯"""
	# ── 碰撞過濾 ──
	if not _is_valid_hit(area):
		return
	
	var target = area.get_parent()
	# Capture combo state before applying the new hit.  Using is_hit alone is
	# unsafe because legacy timers can leave that boolean set after hitstun has
	# reached 0; combo continuation must be based on active stun/knockfly frames.
	var was_in_stun = _target_is_combo_stunned(target)
	var move_set = parent_player.move_set if "move_set" in parent_player else null
	var active_move = move_set.current_move_state.active_move if move_set and move_set.is_spmove else null
	
	if not world:
		return
	
	# 🔴 調試：顯示active_move的狀態
	if active_move:
		Debug.log("[HitResponseHandler] 碰撞檢測：move=%s, is_spmove=%s, is_multi_hit=%s, hit_phases.size()=%d" % [
			active_move.name, move_set.is_spmove, active_move.is_multi_hit, active_move.hit_phases.size()
		])
	
	# ── 多段招式：取得當前段數與參數 ──
	var phase_data = null
	if active_move and active_move.is_multi_hit:
		# 如果hit_phases為空，説明多段配置不完整，降級為非多段模式
		if active_move.hit_phases.size() == 0:
			Debug.log("[HitResponseHandler] ⚠️  %s is_multi_hit=true 但 hit_phases 為空，降級為非多段模式" % active_move.name)
			active_move.is_multi_hit = false
			# ✅ 繼續執行碰撞，使用基礎參數
		else:
			# ✅ hit_phases不為空，使用多段邏輯
			var elapsed_frames = move_set.get_active_move_elapsed_frames() if move_set and move_set.has_method("get_active_move_elapsed_frames") else 0
			phase_data = _get_multi_hit_phase(active_move, target, elapsed_frames)
			if phase_data == null:
				# 未達到hit_phase時間點，不碰撞
				Debug.log("[HitResponseHandler] ⚠️  phase_data=null for multi-hit move '%s', elapsed_frames=%d, target=%s" % [active_move.name, elapsed_frames, target.name])
				return
	
	# ── 單段攻擊：同一次出招不得重複命中同一目標 ──
	# 多段招式（is_multi_hit）走 hit_phases 的段數判定，不套用這條。
	var is_multi_hit_move: bool = active_move != null and active_move.is_multi_hit
	if not is_multi_hit_move:
		if not _register_single_hit(target):
			Debug.log("[HitResponseHandler] ⚠️ 同一次出招已命中過 %s，忽略重複命中" % target.name)
			return

	# ── 獲取攻擊參數 ──
	var hit_params = _get_hit_parameters(phase_data)
	
	Debug.log("═══════════════════════════════════════════════════════════")
	Debug.log("[HitResponseHandler] %s 擊中 %s" % [parent_player.name, target.name])
	Debug.log("  - hitstun: %d frames (%.3fs)" % [hit_params.hitstun, hit_params.hitstun / 60.0])
	Debug.log("  - blockstun: %d frames (%.3fs)" % [hit_params.blockstun, hit_params.blockstun / 60.0])
	Debug.log("  - damage: %.1f" % hit_params.damage)
	
	# 🟢 【重要】先呼叫 take_hit() 讓受擊動畫立即播放
	# 這確保在 hitstop 凍結之前，角色已經開始播放受擊動畫
	target.take_hit(
		hit_params.hitstun,
		hit_params.blockstun,
		hit_params.damage,
		hit_params.skip_push,
		hit_params.force_knockfly,
		hit_params.knockfly_params,
		hit_params.knockback
	)
	
	# 🟢 【重要】在 take_hit() 之後才請求擊中定格（Hitstop）
	# 這樣受擊動畫已經開始播放，hitstop 凍結會發生在動畫進行中，而不是在啟動時
	# 新架構只凍結這兩個角色的動畫 + 視覺微震動，不改 Engine.time_scale。
	if slow_mo_controller:
		slow_mo_controller.request_hit_freeze(parent_player, target)
	
	# ── 播放音效 ──
	var is_blocked: bool = target.is_blocking
	_play_hit_sound(is_blocked, hit_params.damage)
	
	# ── 生成 VFX ──
	var contact = _calculate_contact_point(area)
	_spawn_hit_vfx(is_blocked, contact, target.is_on_floor())
	
	# ── 發射擊中信號（用於 Hit-confirm cancel）──
	var stun_duration = hit_params.blockstun if is_blocked else hit_params.hitstun
	if parent_player.has_signal("hit_detected"):
		parent_player.hit_detected.emit(target.name, stun_duration, is_blocked, was_in_stun)
	
	# ── Pushback 處理 ──
	if not hit_params.penetrable:
		_handle_corner_pushback(target, stun_duration, hit_params.knockback)

# ═══════════════════════════════════════════════════════════════════════════
# 內部輔助函數
# ═══════════════════════════════════════════════════════════════════════════

func _is_valid_hit(area: Area2D) -> bool:
	"""檢查碰撞是否有效"""
	if area.name != "Hurtbox":
		return false
	if parent_player and parent_player.attack_type in ["throw_enter", "throw_seq"]:
		return false
	if not area.get_parent().is_in_group("players"):
		return false
	if area.get_parent() == parent_player:
		return false
	return true

func _target_is_combo_stunned(target: Node) -> bool:
	"""Return true only when the target was still comboable before this hit.

	Stage 2 切片 4：5 條 or 鏈（hitstun 幀計數 / hitstop 等待 / 空中受擊後跳 /
	knockfly juggle / 無 hitstun_frames 欄位時的 is_hit 後備）收攏到
	FighterState.is_combo_stunned() —— 近身攻擊與火球（fireball.gd）原本各抄
	一份，現在共用同一個定義，連段計數與 hit-confirm 在兩條攻擊路徑上不再有
	分歧風險。
	"""
	return FighterState.is_combo_stunned(target)

func _get_hit_parameters(phase_data = null) -> Dictionary:
	"""從 ATTACK_TABLE 或 MoveSet 獲取攻擊參數"""
	var params = {
		"hitstun": 18,      # 18 幀 = 0.30 秒
		"blockstun": 10,    # 10 幀 = 0.167 秒
		"damage": parent_player.current_damage if "current_damage" in parent_player else 10.0,
		"skip_push": false,
		"force_knockfly": false,
		"knockfly_params": {},
		"knockback": -1.0,
		"penetrable": false
	}
	
	var attack_type = parent_player.attack_type if "attack_type" in parent_player else "none"
	var attack_table = parent_player.ATTACK_TABLE if "ATTACK_TABLE" in parent_player else {}
	var move_set = parent_player.move_set if "move_set" in parent_player else null
	
	# ── 優先從 ATTACK_TABLE 查詢 ──
	if attack_table.has(attack_type):
		var a = attack_table[attack_type]
		params.hitstun = a.get("hitstun", params.hitstun)      # 現在是幀數
		params.blockstun = a.get("blockstun", params.blockstun) # 現在是幀數
		params.damage = a.get("damage", params.damage)
		params.knockback = a.get("knockback", -1.0)
	
	# ── 如果是特殊招式，從 MoveSet 查詢 ──
	elif move_set and move_set.is_spmove and move_set.current_move_state.active_move:
		var active_move = move_set.current_move_state.active_move
		params.damage = active_move.damage
		params.knockback = active_move.knockback
		params.penetrable = active_move.penetrable
		params.hitstun = active_move.hitstun
		params.blockstun = active_move.blockstun
		if phase_data != null:
			# 🔴 改進：phase中的參數優先，但如果為0則使用base參數
			params.damage = phase_data.damage if phase_data.damage != 0.0 else active_move.damage
			params.hitstun = phase_data.hitstun if phase_data.hitstun != 0 else active_move.hitstun  # 如果使用0則降級
			params.blockstun = phase_data.blockstun if phase_data.blockstun != 0 else active_move.blockstun
			params.knockback = phase_data.knockback if phase_data.knockback != 0.0 else active_move.knockback
		
		# ──  特殊招式的特殊參數 ──
		var move_name = active_move.name
		if move_name == "spnk":
			# spnk 的傷害會根據動畫時間調整
			var animation_player = parent_player.animation_player if "animation_player" in parent_player else null
			if animation_player:
				var pos = animation_player.current_animation_position
				if pos < 0.2667:
					params.damage = 6.0
		
		# ✅ 【新增】檢查強制 Knockfly 選項
		var phase_force_knockfly = phase_data.force_knockfly if phase_data != null else false
		if phase_force_knockfly:
			params.force_knockfly = true
			params.knockfly_params = _make_knockfly_params(phase_data if phase_data != null else active_move, params.hitstun)
		elif active_move.knockfly_force_enable:
			params.force_knockfly = true
			params.knockfly_params = _make_knockfly_params(active_move, params.hitstun)
		# 向後兢容：如果沒有設置 knockfly_force_enable，但有設置 knockfly 參數，則也啟用 knfly
		elif active_move.knockfly_gravity != 0.0 or active_move.knockfly_vertical_speed != 0.0 or active_move.knockfly_horizontal_speed != 0.0:
			params.force_knockfly = true
			params.knockfly_params = _make_knockfly_params(active_move, params.hitstun)
	
	return params

func _make_knockfly_params(source: Object, hitstun: int) -> Dictionary:
	return {
		"gravity": source.knockfly_gravity,
		"vertical_speed": source.knockfly_vertical_speed,
		"horizontal_speed": source.knockfly_horizontal_speed,
		"duration": hitstun / 60.0
	}

func reset_multi_hit_state() -> void:
	multi_hit_targets.clear()
	single_hit_registry.clear()


## 登記「這一次出招」對 target 的命中。已登記過就回傳 false（拒絕重複命中）。
func _register_single_hit(target: Node) -> bool:
	var token: String = _attack_instance_token()
	var target_id: int = target.get_instance_id()
	if single_hit_registry.get(target_id, "") == token:
		return false
	single_hit_registry[target_id] = token
	debug_hit_registered_count += 1
	return true


## 「同一次揮拳」的識別碼：招式名 + 出招流水號。
## 流水號由 Player._execute_attack() 每次成功出招 +1，因此連續兩次同名攻擊
## （例如快速連按兩下 st_lp）會拿到不同 token，第二拳照樣能打中。
func _attack_instance_token() -> String:
	if parent_player == null:
		return "none#0"
	var move_set = parent_player.move_set if "move_set" in parent_player else null
	if move_set and move_set.is_spmove and move_set.current_move_state.active_move:
		# 特殊招式：用招式名 + 目前這一招的起始幀當識別碼。
		return "sp:%s#%d" % [
			move_set.current_move_state.active_move.name,
			int(parent_player.attack_instance_id) if "attack_instance_id" in parent_player else 0,
		]
	var atype: String = str(parent_player.attack_type) if "attack_type" in parent_player else "none"
	var instance_id: int = int(parent_player.attack_instance_id) if "attack_instance_id" in parent_player else 0
	return "%s#%d" % [atype, instance_id]

func _get_multi_hit_phase(active_move, target: Node, elapsed_frames: int):
	if elapsed_frames < 0:
		return null
	var hit_index = -1
	var phase_data = null
	
	# 🔴 詳細診斷
	Debug.log("[_get_multi_hit_phase] Checking move=%s, elapsed_frames=%d (physics), target=%s" % [active_move.name, elapsed_frames, target.name])
	
	for i in active_move.hit_phases.size():
		var phase = active_move.hit_phases[i]
		if phase == null:
			continue
		var phase_frame = int(phase.frame)
		if phase_frame < 0:
			continue
		var phase_physics = Movement.logic_frames_to_physics_frames(phase_frame)
		Debug.log("    [Phase%d] frame(logic)=%d → phase_physics=%d (elapsed=%d, match=%s)" % [
			i, phase_frame, phase_physics, elapsed_frames, elapsed_frames >= phase_physics
		])
		if elapsed_frames >= phase_physics:
			hit_index = i
			phase_data = phase
	
	if hit_index < 0:
		Debug.log("[_get_multi_hit_phase] ❌ No matching phase found (elapsed_frames=%d too early)" % elapsed_frames)
		return null
	
	# 🔴 【新增】檢查phase是否有有效數據（不能所有値都為0）
	if phase_data != null and phase_data.damage == 0.0 and phase_data.hitstun == 0 and phase_data.knockback == 0.0:
		Debug.log("[_get_multi_hit_phase] ⚠️  Phase%d 無效（所有値為0） frame=%d" % [hit_index, phase_data.frame])
		return null
	
	var target_id = target.get_instance_id()
	var record = multi_hit_targets.get(target_id, {"hit_index": -1, "last_hit_frame": -1})
	Debug.log("[_get_multi_hit_phase] Target=%s (id=%d), current_hit_index=%d, previous_hit_index=%d" % [
		target.name, target_id, hit_index, record["hit_index"]
	])
	if record["hit_index"] == hit_index:
		Debug.log("[_get_multi_hit_phase] ⚠️  Already hit this target with phase%d, skipping" % hit_index)
		return null
	record["hit_index"] = hit_index
	record["last_hit_frame"] = elapsed_frames
	multi_hit_targets[target_id] = record
	Debug.log("[_get_multi_hit_phase] ✅ Returning phase%d for target %s" % [hit_index, target.name])
	return phase_data

func _play_hit_sound(is_blocked: bool, damage: float = 10.0) -> void:
	"""
	播放擊中/格擋音效

	- 擊中：按「攻擊類型」播放專屬音效（st_lp/cr_lp/jump_lp → LPSoundPlayer，
	  hk 系列 → HKSoundPlayer，如此類推）。
	  特殊招式或角色場景未加設專屬節點時，回退到舊有的
	  HitSoundPlayer / HeavyHitSoundPlayer（按傷害判定）。
	- 格擋：維持原本的 BlockSoundPlayer / HeavyBlockSoundPlayer（按傷害判定）。
	"""
	if parent_player == null:
		return
	
	if is_blocked:
		AttackSoundResolver.play_block_sound(parent_player, damage)
		return
	
	var attack_type: String = str(parent_player.attack_type) if "attack_type" in parent_player else ""
	AttackSoundResolver.play_hit_sound(parent_player, attack_type, damage)

func _calculate_contact_point(area: Area2D) -> Vector2:
	"""計算碰撞接觸點"""
	var contact = _get_contact_point_internal(area)
	if contact == Vector2.ZERO:
		var hitbox = parent_player.get_node_or_null("Hitbox")
		if hitbox:
			contact = (area.global_position + hitbox.global_position) / 2.0
		else:
			contact = area.global_position
	return contact

func _get_contact_point_internal(area: Area2D) -> Vector2:
	"""獲取實際的接觸點（從 Player 複製）"""
	var hitbox = parent_player.get_node_or_null("Hitbox")
	if not hitbox or not parent_player.has_method("get_contact_point"):
		return Vector2.ZERO
	return parent_player.get_contact_point(hitbox, area)

func _spawn_hit_vfx(is_blocked: bool, contact: Vector2, target_on_floor: bool) -> void:
	"""生成擊中特效；所有角色的中攻擊命中另加 hit_spark_m（遊戲全局特效）。"""
	var vfx_type = "block" if is_blocked else "hit"
	var adjusted_contact = contact
	
	# 空中擊中時調整 Y 座標
	if not target_on_floor:
		adjusted_contact.y += 10
	
	var facing = parent_player.facing_direction if "facing_direction" in parent_player else 1.0
	VFXImpact.spawn_vfx(world, vfx_type, adjusted_contact, facing)

	# 只在真正命中（不是格擋）且攻擊是中攻擊時播放。hit_spark_m 是遊戲全局
	# 特效：不再綁定 WOO，任何角色都適用 —— suffix 判斷涵蓋 st_mp / cr_mp /
	# jump_mp 以及對應的 mk，同時自然排除輕攻擊與重攻擊。
	if not is_blocked and _is_medium_attack():
		VFXSmoke.spawn_animation(world, adjusted_contact, VFXSmoke.MEDIUM_HIT_ANIMATION, facing)

func _is_medium_attack() -> bool:
	"""是否為「中攻擊」（*_mp / *_mk）——對所有角色一致的全局判定。"""
	if parent_player == null:
		return false
	var attack_type: String = str(parent_player.get("attack_type"))
	return attack_type.ends_with("_mp") or attack_type.ends_with("_mk")

func _handle_corner_pushback(target: Node, stun_duration: float, knockback_distance: float = -1.0) -> void:
	"""
	處理角落推回
	使用與 knockback 相同的機制，但作用於攻擊者而非被擊者
	
	參數：
	- target: 被擊中的角色
	- stun_duration: 受擊時間（邏輯幀）
	- knockback_distance: 原始攻擊的 knockback 距離。如果 -1.0 則使用預設 corner_push_distance
	"""
	var push_manager = get_tree().get_first_node_in_group("push_manager")
	if not push_manager or not push_manager.is_at_corner(target):
		return
	
	if not parent_player.has_method("get_facing_multiplier"):
		return
	
	# 🟢 【修復】使用原始攻擊的 knockback 距離，如果沒有則使用預設值
	var corner_push_distance = knockback_distance
	if corner_push_distance <= 0:
		corner_push_distance = parent_player.corner_push_distance if "corner_push_distance" in parent_player else 250.0
	
	# 🟢 轉換 stun_duration（邏輯幀）為物理幀 — Stage 1 唯一邏輯↔物理邊界
	var physics_push_frames = Movement.logic_frames_to_physics_frames(stun_duration)
	
	# 🟢 使用 PushManager 計算所需的初始速度
	if push_manager and push_manager.has_method("calculate_required_knockback_velocity"):
		var target_distance_units = int(corner_push_distance * world.SIMULATION_SCALE)
		parent_player.corner_push_velocity = push_manager.calculate_required_knockback_velocity(
			target_distance_units,
			physics_push_frames,
			"[CORNER PUSH] " + parent_player.name
		)
	else:
		# 後備方案：使用舊的係數
		parent_player.corner_push_velocity = corner_push_distance * world.SIMULATION_SCALE * 4.0
		Debug.log("[CORNER PUSH WARNING] PushManager 未找到或無反推函數，使用後備係數")
	
	# 🟢 初始化 corner push 狀態（攻擊者被推回）
	parent_player.corner_push_frames = physics_push_frames
	parent_player.initial_corner_push_frames = physics_push_frames
	parent_player.corner_push_start_x = parent_player.position.x
	
	Debug.log("\n╔════════════════════════════════════════════════════════════════╗")
	Debug.log("║ CORNER PUSH INITIALIZATION (攻擊者被推回)                   ║")
	Debug.log("╚════════════════════════════════════════════════════════════════╝")
	Debug.log("  🎮 Player: %s" % parent_player.name)
	Debug.log("  📍 Position: (%.2f, %.2f)" % [parent_player.position.x, parent_player.position.y])
	Debug.log("  📏 Corner push distance: %.1f pixels (與攻擊 knockback 相同)" % corner_push_distance)
	Debug.log("  ⏱️  Push frames: %d (%.3fs @ 60 FPS)" % [physics_push_frames, physics_push_frames / 60.0])
	Debug.log("  ⚡ Corner push velocity: %.2f units (%.2f px/frame)" % [parent_player.corner_push_velocity, parent_player.corner_push_velocity / world.SIMULATION_SCALE])
	Debug.log()

# ═══════════════════════════════════════════════════════════════════════════
# 【新增】Fireball 專用：供 fireball.gd 動態讀取 hitstun 參數
# ═══════════════════════════════════════════════════════════════════════════

func get_fireball_hitstun_frames() -> int:
	"""
	供 fireball.gd 調用，動態讀取火球的 hitstun 幀數
	這樣修改此值時無需同時修改 fireball.gd
	"""
	return 60  # 🟢 60 邏輯幀 = 1.0 秒（修改此值即可控制 fireball hitstun)
