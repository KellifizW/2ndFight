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

# ── 多段招式追蹤 ──
var multi_hit_targets: Dictionary = {}  # {target_id: {hit_index: int, last_hit_frame: int}}

# ── VFX 系統 ──
const VFXImpact = preload("res://vfx_impact.gd")

func _init(player: Node) -> void:
	parent_player = player

func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")

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
	var was_in_stun = target.is_hit or target.is_knockfly
	var move_set = parent_player.move_set if "move_set" in parent_player else null
	var active_move = move_set.current_move_state.active_move if move_set and move_set.is_spmove else null
	
	if not world:
		return
	
	# ── 多段招式：取得當前段數與參數 ──
	var phase_data = null
	if active_move and active_move.is_multi_hit and active_move.hit_phases.size() > 0:
		var elapsed_frames = move_set.get_active_move_elapsed_frames() if move_set and move_set.has_method("get_active_move_elapsed_frames") else 0
		phase_data = _get_multi_hit_phase(active_move, target, elapsed_frames)
		if phase_data == null:
			return
	
	# ── 獲取攻擊參數 ──
	var hit_params = _get_hit_parameters(phase_data)
	
	print("═══════════════════════════════════════════════════════════")
	print("[HitResponseHandler] %s 擊中 %s" % [parent_player.name, target.name])
	print("  - hitstun: %d frames (%.3fs)" % [hit_params.hitstun, hit_params.hitstun / 60.0])
	print("  - blockstun: %d frames (%.3fs)" % [hit_params.blockstun, hit_params.blockstun / 60.0])
	print("  - damage: %.1f" % hit_params.damage)
	
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
	
	# 🟢 【重要】在 take_hit() 之後才請求擊中凍結（Slow-mo）
	# 這樣受擊動畫已經開始播放，hitstop 凍結會發生在動畫進行中，而不是在啟動時
	var slowmo = world.get_node_or_null("SlowMoController")
	if slowmo:
		slowmo.request_hit_freeze()
	
	# ── 播放音效 ──
	var is_blocked: bool = target.is_blocking
	_play_hit_sound(is_blocked)
	
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
			params.damage = phase_data.damage if phase_data.damage != 0.0 else params.damage
			params.hitstun = phase_data.hitstun if phase_data.hitstun != 0 else params.hitstun
			params.blockstun = phase_data.blockstun if phase_data.blockstun != 0 else params.blockstun
			params.knockback = phase_data.knockback if phase_data.knockback != 0.0 else params.knockback
		
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
			params.knockfly_params = {
				"gravity": phase_data.knockfly_gravity if phase_data != null else active_move.knockfly_gravity,
				"vertical_speed": phase_data.knockfly_vertical_speed if phase_data != null else active_move.knockfly_vertical_speed,
				"horizontal_speed": phase_data.knockfly_horizontal_speed if phase_data != null else active_move.knockfly_horizontal_speed,
				"duration": params.hitstun / 60.0
			}
		elif active_move.knockfly_force_enable:
			params.force_knockfly = true
			params.knockfly_params = {
				"gravity": active_move.knockfly_gravity,
				"vertical_speed": active_move.knockfly_vertical_speed,
				"horizontal_speed": active_move.knockfly_horizontal_speed,
				"duration": params.hitstun / 60.0
			}
		# 向後兼容：如果沒有設置 knockfly_force_enable，但有設置 knockfly 參數，則也啟用 knfly
		elif active_move.knockfly_gravity != 0.0 or active_move.knockfly_vertical_speed != 0.0 or active_move.knockfly_horizontal_speed != 0.0:
			params.force_knockfly = true
			params.knockfly_params = {
				"gravity": active_move.knockfly_gravity,
				"vertical_speed": active_move.knockfly_vertical_speed,
				"horizontal_speed": active_move.knockfly_horizontal_speed,
				"duration": params.hitstun / 60.0
			}
	
	return params

func reset_multi_hit_state() -> void:
	multi_hit_targets.clear()

func _get_multi_hit_phase(active_move, target: Node, elapsed_frames: int):
	if elapsed_frames < 0:
		return null
	var physics_fps = parent_player.PHYSICS_FPS if "PHYSICS_FPS" in parent_player else 120
	var hit_index = -1
	var phase_data = null
	for i in active_move.hit_phases.size():
		var phase = active_move.hit_phases[i]
		if phase == null:
			continue
		var phase_frame = int(phase.frame)
		if phase_frame < 0:
			continue
		var phase_physics = int(round(phase_frame * float(physics_fps) / 60.0))
		if elapsed_frames >= phase_physics:
			hit_index = i
			phase_data = phase
	
	if hit_index < 0:
		return null
	
	var target_id = target.get_instance_id()
	var record = multi_hit_targets.get(target_id, {"hit_index": -1, "last_hit_frame": -1})
	if record["hit_index"] == hit_index:
		return null
	record["hit_index"] = hit_index
	record["last_hit_frame"] = elapsed_frames
	multi_hit_targets[target_id] = record
	return phase_data

func _play_hit_sound(is_blocked: bool) -> void:
	"""播放擊中/格擋音效"""
	if is_blocked:
		var block_sound = parent_player.get_node_or_null("BlockSoundPlayer")
		if block_sound and block_sound.has_method("play"):
			block_sound.play()
	else:
		var hit_sound = parent_player.get_node_or_null("HitSoundPlayer")
		if hit_sound and hit_sound.has_method("play"):
			hit_sound.play()

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
	"""生成擊中特效"""
	var vfx_type = "block" if is_blocked else "hit"
	var adjusted_contact = contact
	
	# 空中擊中時調整 Y 座標
	if not target_on_floor:
		adjusted_contact.y += 10
	
	var facing = parent_player.facing_direction if "facing_direction" in parent_player else 1.0
	VFXImpact.spawn_vfx(world, vfx_type, adjusted_contact, facing)

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
	
	# 🟢 轉換 stun_duration（邏輯幀）為物理幀
	var physics_push_frames = int(round(stun_duration * (parent_player.PHYSICS_FPS / 60.0)))
	
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
		print("[CORNER PUSH WARNING] PushManager 未找到或無反推函數，使用後備係數")
	
	# 🟢 初始化 corner push 狀態（攻擊者被推回）
	parent_player.corner_push_frames = physics_push_frames
	parent_player.initial_corner_push_frames = physics_push_frames
	parent_player.corner_push_start_x = parent_player.position.x
	
	print("\n╔════════════════════════════════════════════════════════════════╗")
	print("║ CORNER PUSH INITIALIZATION (攻擊者被推回)                   ║")
	print("╚════════════════════════════════════════════════════════════════╝")
	print("  🎮 Player: %s" % parent_player.name)
	print("  📍 Position: (%.2f, %.2f)" % [parent_player.position.x, parent_player.position.y])
	print("  📏 Corner push distance: %.1f pixels (與攻擊 knockback 相同)" % corner_push_distance)
	print("  ⏱️  Push frames: %d (%.3fs @ 60 FPS)" % [physics_push_frames, physics_push_frames / 60.0])
	print("  ⚡ Corner push velocity: %.2f units (%.2f px/frame)" % [parent_player.corner_push_velocity, parent_player.corner_push_velocity / world.SIMULATION_SCALE])
	print()

# ═══════════════════════════════════════════════════════════════════════════
# 【新增】Fireball 專用：供 fireball.gd 動態讀取 hitstun 參數
# ═══════════════════════════════════════════════════════════════════════════

func get_fireball_hitstun_frames() -> int:
	"""
	供 fireball.gd 調用，動態讀取火球的 hitstun 幀數
	這樣修改此值時無需同時修改 fireball.gd
	"""
	return 60  # 🟢 60 邏輯幀 = 1.0 秒（修改此值即可控制 fireball hitstun)
