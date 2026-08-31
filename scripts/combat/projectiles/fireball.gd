extends Area2D

var speed: float = 800.0          # 預設速度（DAV）
# Combat values — set by MoveSet.execute_fireball_spawn() from .tres data
# Using stored values avoids fragile runtime lookups at hit time
var hit_damage: float = 10.0
var hit_hitstun: int = 18
var hit_blockstun: int = 10
var hit_knockback: float = 80.0
var direction: int = 1
var is_active: bool = true
var is_penetrating: bool = false  # 擊中後的穿透狀態
var penetration_distance: float = 100.0  # 穿透距離（進入對手body內部）
var penetration_traveled: float = 0.0  # 已穿透的距離
var hit_target: Node = null  # 記錄擊中的目標
var owner_character_id: String = "DAV"  # 現在使用 character_id 而不是舊的 p1/p2
var fireball_owner: Node = null           # 發射者的 Player 實例（避免打到自己）
var special_move_id: String = "fireball"

@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var prox_shape = $Proximitybox/ProxShape
@onready var spawn_sound_player = $SpawnSoundPlayer
@onready var hit_sound_player = $HitSoundPlayer

# 粒子節點引用
@onready var run_particles: GPUParticles2D = $run if has_node("run") else null
@onready var hit_particles: GPUParticles2D = $hit if has_node("hit") else null
@onready var ringexp_particles: GPUParticles2D = $ringexp if has_node("ringexp") else null
@onready var hitexp_particles: GPUParticles2D = $hitexp if has_node("hitexp") else null

func _ready() -> void:
	add_to_group("fireball")
	
	_apply_data_from_moveset()
	
	if sprite == null:
		push_error("Error: Sprite2D node not found in Fireball!")
	else:
		# 場景反轉邏輯（與 Movement.gd 一致）
		scale.x = direction
		scale.y = 1
		sprite.scale.x = 1.0
		# DEN 的 offset 調整（假設你原本有針對 P2 調整）
		if owner_character_id == "DEN":
			sprite.offset.x = abs(sprite.offset.x)
	
	if animation_player == null:
		push_error("Error: AnimationPlayer node not found in Fireball!")
	else:
		animation_player.play("fireball/ball_idle")
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)
	
	if hitbox:
		hitbox.monitoring = true  # 明確確保 monitoring 已啟用（防禦性設置）
		hitbox.area_entered.connect(_on_hitbox_area_entered)
	else:
		push_error("[Fireball] CRITICAL: Hitbox node not found for %s!" % owner_character_id)
	if hurtbox:
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	if prox_shape:
		prox_shape.get_parent().area_entered.connect(_on_proximitybox_area_entered)
	
	monitoring = true
	monitorable = true
	
	# 只關閉爆破粒子，不呼叫 restart() 以避免意外觸發
	if hit_particles:
		hit_particles.emitting = false
	if ringexp_particles:
		ringexp_particles.emitting = false
	if hitexp_particles:
		hitexp_particles.emitting = false
	
	# 飛行軌跡保持開啟
	if run_particles:
		run_particles.emitting = true
	
	# 生成音效
	if spawn_sound_player:
		spawn_sound_player.play()
	else:
		push_warning("Warning: SpawnSoundPlayer not found in Fireball!")

func _physics_process(delta: float) -> void:
	if is_active:
		position.x += speed * direction * delta
	elif is_penetrating:
		# 擊中後繼續移動進入對手body內部
		var move_distance = speed * direction * delta
		position.x += move_distance
		penetration_traveled += abs(move_distance)
		
		if penetration_traveled >= penetration_distance:
			# 完成穿透，停止移動並播放衝擊動畫
			# 🟢 粒子特效已在 _on_hitbox_area_entered() 立即播放，此處不再重複
			is_penetrating = false
			animation_player.play("fireball/ball_impact")
	
	# 超出鏡頭可見範圍自動銷毀（基於實際鏡頭位置動態檢測）
	var camera = get_viewport().get_camera_2d()
	if camera:
		var viewport_size = get_viewport_rect().size
		var camera_zoom = camera.zoom.x
		var visible_half_width = (viewport_size.x / camera_zoom) / 2.0
		var camera_x = camera.global_position.x
		var left_bound = camera_x - visible_half_width - 100  # 額外100像素緩衝
		var right_bound = camera_x + visible_half_width + 100
		
		if global_position.x < left_bound or global_position.x > right_bound:
			_clear_owner_reference()
			queue_free()

func _load_knockback_from_moveset() -> void:
	"""從 MoveSet 讀取 fireball 的 knockback 值（統一實現）"""
	if not fireball_owner:
		return
	
	var move_set = fireball_owner.move_set if "move_set" in fireball_owner else null
	if not move_set:
		return
	
	var fireball_move = move_set.get_move_data_for_character(special_move_id, owner_character_id) if move_set.has_method("get_move_data_for_character") else null

func _apply_data_from_moveset() -> void:
	if not fireball_owner:
		return
	var move_set = fireball_owner.move_set if "move_set" in fireball_owner else null
	if not move_set:
		return
	# 優先從 SpecialMoveData .tres 讀取（用戶在 Inspector 編輯的戰鬥值）
	if move_set.has_method("get_special_move_resource"):
		var smd: Resource = move_set.get_special_move_resource(special_move_id)
		if smd != null:
			var ps: float = smd.get("projectile_speed")
			if ps > 0.0:
				speed = ps
			return
	# Fallback: 使用 MoveData wrapper
	if move_set.has_method("get_move_data_for_character"):
		var fireball_move = move_set.get_move_data_for_character(special_move_id, owner_character_id)
		if fireball_move and fireball_move.projectile_speed > 0.0:
			speed = fireball_move.projectile_speed
		else:
			push_warning("Fireball speed missing for %s/%s, using default %.1f" % [owner_character_id, special_move_id, speed])

func _get_fireball_params_from_moveset() -> Dictionary:
	"""
	從 MoveSet 讀取 fireball 的所有參數（單一來源）
	返回: {\"damage\": float, \"hitstun\": int, \"blockstun\": int, \"knockback\": float}
	"""
	var params = {
		"damage": 10.0,        # 預設值
		"hitstun": 18,         # 預設值（邏輯幀）
		"blockstun": 10,       # 預設值（邏輯幀）
		"knockback": 80.0      # 預設 knockback
	}
	
	if not fireball_owner:
		return params
	
	var move_set = fireball_owner.move_set if "move_set" in fireball_owner else null
	if not move_set:
		return params
	
	if not move_set.has_method("get_move_data_for_character"):
		return params
	
	# 優先從 SpecialMoveData .tres 讀取（用戶在 Inspector 編輯的寫真數據）
	if move_set.has_method("get_special_move_resource"):
		var smd: Resource = move_set.get_special_move_resource(special_move_id)
		if smd != null:
			params["damage"] = smd.get("damage")
			params["knockback"] = smd.get("knockback")
			params["hitstun"] = smd.get("hitstun_frames")
			params["blockstun"] = smd.get("blockstun_frames")
			return params
	# Fallback: 使用 MoveData wrapper
	var fireball_move = move_set.get_move_data_for_character(special_move_id, owner_character_id)
	if fireball_move:
		params["damage"] = fireball_move.damage
		params["knockback"] = fireball_move.knockback
		params["hitstun"] = fireball_move.hitstun
		params["blockstun"] = fireball_move.blockstun
	
	return params

func _stop_trail_immediately() -> void:
	if run_particles:
		run_particles.emitting = false
		run_particles.queue_free()

func _play_explosion_particles() -> void:
	if hit_particles:
		hit_particles.restart()
		hit_particles.emitting = true
	if ringexp_particles:
		ringexp_particles.restart()
		ringexp_particles.emitting = true
	if hitexp_particles:
		hitexp_particles.restart()
		hitexp_particles.emitting = true

func _target_is_combo_stunned(target: Node) -> bool:
	# Stage 2 切片 4：連段續航判定與近身攻擊（HitResponseHandler）共用同一個
	# 定義 FighterState.is_combo_stunned()，不再各抄一份 5 條 or 鏈。
	return FighterState.is_combo_stunned(target)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if not is_active: return
	
	# 過濾 1: 不要打發射者角色
	if fireball_owner and area.get_parent() == fireball_owner:
		return
	
	# 過濾 2: 不要打自己的 Hurtbox（內部碰撞）
	if area.get_parent() == self:
		return
	
	if area.name == "Hurtbox" and area.get_parent().is_in_group("players"):
		var target = area.get_parent()
		
		# 進入穿透模式，繼續移動進入對手body內部
		is_active = false
		is_penetrating = true
		hit_target = target
		penetration_traveled = 0.0
		
		# 立即禁用碰撞檢測，避免重複觸發
		if hitbox: hitbox.monitoring = false
		if prox_shape: prox_shape.disabled = true
		
		_clear_owner_reference()
		
		# 🟢 【重要】立即播放粒子特效和音效（在穿透時持續顯示）
		_stop_trail_immediately()
		_play_explosion_particles()
		
		# 擊中音效
		if hit_sound_player:
			var sound = hit_sound_player.duplicate()
			get_tree().current_scene.add_child(sound)
			sound.play()
			sound.finished.connect(func(): sound.queue_free())
		else:
			push_warning("Warning: HitSoundPlayer not found in Fireball!")
		
		# 🟢 【重要】先呼叫 take_hit() 讓受擊動畫立即播放
		# 戰鬥屬性已在 spawn 時直接寫入，不需運行時查找
		var final_hitstun = hit_hitstun
		var final_blockstun = hit_blockstun
		var final_damage = hit_damage
		var final_knockback = hit_knockback
		var world = get_tree().get_first_node_in_group("world")
		# Must be captured before take_hit(); after take_hit() the new hitstun
		# would make every projectile hit look like a combo continuation.
		var was_in_stun = _target_is_combo_stunned(target)
		
		# 🟢 【關鍵】禁用 target 的 hitbox 碰撞，避免 HitResponseHandler 重複調用 take_hit()
		if target.has_node("Hitbox/HitShape"):
			var target_hitbox = target.get_node("Hitbox/HitShape")
			target_hitbox.disabled = true
		
		# 與普通攻擊統一：傳遞所有參數
		target.take_hit(final_hitstun, final_blockstun, final_damage, false, false, {}, final_knockback)
		
		# 🟢 【重要】在 take_hit() 之後才請求擊中定格（Hitstop）
		# 這樣受擊動畫已經開始播放，hitstop 凍結會發生在動畫進行中
		# 火球不凍結攻擊者（距離遠），只定格受擊者並施予視覺微震動。
		if world:
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze(null, target)
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		# Fireball is owned by the attacker, so emit hit_detected from the owner.
		# This keeps hit-confirm/cancel and combo ownership identical to melee hits.
		var signal_owner = fireball_owner if fireball_owner and fireball_owner.has_signal("hit_detected") else target
		if signal_owner and signal_owner.has_signal("hit_detected"):
			# 傳遞 4 個參數：target名稱、hitstun幀數、是否格擋、是否已在硬直中
			signal_owner.hit_detected.emit(target.name, final_hitstun, is_blocked, was_in_stun)
		
		# VFX
		var vfx_position = (global_position + area.global_position) / 2.0
		var vfx_type = "block" if is_blocked else "hit"
		
		# 使用預載和預熱的資源（零卡頓）
		var preloader = get_tree().get_first_node_in_group("resource_preloader")
		if preloader:
			var vfx_scene = preloader.get_vfx_scene(vfx_type)
			if vfx_scene:
				var vfx = vfx_scene.instantiate()
				vfx.global_position = vfx_position
				get_tree().current_scene.add_child(vfx)

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not is_active: return
	
	# 過濾 1: 不要被發射者角色打到
	if fireball_owner and area.get_parent() == fireball_owner:
		return
	
	# 過濾 2: 不要被自己的 Hitbox 打到（內部碰撞）
	if area.get_parent() == self:
		return
	
	if area.name == "Hitbox" and (area.get_parent().is_in_group("players") or area.get_parent().is_in_group("fireball")):
		is_active = false
		if hitbox: hitbox.monitoring = false
		if prox_shape: prox_shape.disabled = true
		
		_stop_trail_immediately()
		_clear_owner_reference()
		
		# 🟢 播放擊中特效（與打中角色時相同）
		_play_explosion_particles()
		
		# 擊中音效
		if hit_sound_player:
			var sound = hit_sound_player.duplicate()
			get_tree().current_scene.add_child(sound)
			sound.play()
			sound.finished.connect(func(): sound.queue_free())
		
		# 擊中 VFX（在碰撞點顯示）
		var vfx_position = (global_position + area.global_position) / 2.0
		var preloader = get_tree().get_first_node_in_group("resource_preloader")
		if preloader:
			var vfx_scene = preloader.get_vfx_scene("hit")
			if vfx_scene:
				var vfx = vfx_scene.instantiate()
				vfx.global_position = vfx_position
				get_tree().current_scene.add_child(vfx)
		
		animation_player.play("fireball/ball_impact")

func _on_proximitybox_area_entered(area: Area2D) -> void:
	if not is_active:
		return
	
	# 過濾自己，避免近距離格擋自己
	if fireball_owner and area.get_parent() == fireball_owner:
		return
	
	if area.name == "Hurtbox" and area.get_parent().is_in_group("players"):
		var target = area.get_parent()
		
		if target.is_holding_back or target.is_crouch_blocking:
			# 進入穿透模式
			is_active = false
			is_penetrating = true
			hit_target = target
			penetration_traveled = 0.0
			
			if hitbox: hitbox.monitoring = false
			if prox_shape: prox_shape.disabled = true
			
			_clear_owner_reference()
			
			# 🟢 近距離格擋：只播放音效和信號，不額外調用 take_hit()
			# Hitbox 已經在之前調用過 take_hit() 了
			if target.has_signal("block_detected"):
				target.block_detected.emit(name, "proximity")
			
			# 近距離格擋音效
			if hit_sound_player:
				var sound = hit_sound_player.duplicate()
				get_tree().current_scene.add_child(sound)
				sound.play()
				sound.finished.connect(func(): sound.queue_free())
			
			# 格擋 VFX
			var vfx_position = (global_position + area.global_position) / 2.0
			
			# 使用預載和預熱的資源（零卡頓）
			var preloader = get_tree().get_first_node_in_group("resource_preloader")
			if preloader:
				var vfx_scene = preloader.get_vfx_scene("block")
				if vfx_scene:
					var vfx = vfx_scene.instantiate()
					vfx.global_position = vfx_position
					get_tree().current_scene.add_child(vfx)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "fireball/ball_impact":
		queue_free()

# 清除發射者的 active_fireball 引用
func _clear_owner_reference() -> void:
	if fireball_owner and is_instance_valid(fireball_owner) and "active_fireball" in fireball_owner:
		if fireball_owner.active_fireball == self:
			fireball_owner.active_fireball = null
		else:
			pass
