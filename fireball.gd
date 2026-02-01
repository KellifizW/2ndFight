extends Area2D

var speed: float = 800.0          # 預設速度（DAV）
var direction: int = 1
var damage: float = 8.0          # 預設傷害（DAV）
var blockstun_duration: float = 0.3
var is_active: bool = true
var is_penetrating: bool = false  # 擊中後的穿透狀態
var penetration_distance: float = 100.0  # 穿透距離（進入對手body內部）
var penetration_traveled: float = 0.0  # 已穿透的距離
var hit_target: Node = null  # 記錄擊中的目標
var owner_character_id: String = "DAV"  # 現在使用 character_id 而不是舊的 p1/p2
var fireball_owner: Node = null           # 發射者的 Player 實例（避免打到自己）

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
	
	# 根據角色設定參數（DAV 與 DEN 不同）
	if owner_character_id == "DAV":
		speed = 800.0
		damage = 8.0
	elif owner_character_id == "DEN":
		speed = 600.0
		damage = 7.0
	else:
		push_warning("未知的 fireball owner_character_id: %s，使用預設值" % owner_character_id)
	
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
		hitbox.area_entered.connect(_on_hitbox_area_entered)
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
	
	print("Debug: Fireball initialized, owner_character_id: %s, speed: %s, damage: %s, direction: %s" %
		[owner_character_id, speed, damage, direction])

func _physics_process(delta: float) -> void:
	if is_active:
		position.x += speed * direction * delta
	elif is_penetrating:
		# 擊中後繼續移動進入對手body內部
		var move_distance = speed * direction * delta
		position.x += move_distance
		penetration_traveled += abs(move_distance)
		
		if penetration_traveled >= penetration_distance:
			# 完成穿透，停止移動並播放爆炸效果
			is_penetrating = false
			_stop_trail_immediately()
			_play_explosion_particles()
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
			print("Fireball out of camera bounds, destroying at position: %s (camera: %s, bounds: %s to %s)" % 
				[global_position.x, camera_x, left_bound, right_bound])
			_clear_owner_reference()
			queue_free()

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
		
		# 不在這裡播放爆炸效果，等穿透完成後再播放
		
		# 立即造成傷害（不等穿透完成）
		var world = get_tree().get_first_node_in_group("world")
		if world:
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze()
		
		target.take_hit(blockstun_duration, blockstun_duration, damage, false)
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		if target.has_signal("hit_detected"):
			target.hit_detected.emit(name, blockstun_duration, is_blocked)
		
		# 擊中音效
		if hit_sound_player:
			var sound = hit_sound_player.duplicate()
			get_tree().current_scene.add_child(sound)
			sound.play()
			sound.finished.connect(func(): sound.queue_free())
		else:
			push_warning("Warning: HitSoundPlayer not found in Fireball!")
		
		print("Fireball hit %s, is_blocked: %s, damage: %s, owner: %s" %
			[target.name, is_blocked, damage, owner_character_id])
		
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
		
		animation_player.play("fireball/ball_impact")
		
		if area.get_parent().is_in_group("fireball"):
			print("Fireball collided with another fireball, owner: %s" % owner_character_id)
		else:
			print("Fireball hit by %s's Hitbox, owner: %s" % [area.get_parent().name, owner_character_id])

func _on_proximitybox_area_entered(area: Area2D) -> void:
	if not is_active: return
	
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
			
			# 不在這裡播放爆炸效果，等穿透完成後再播放
			
			target.take_hit(blockstun_duration, 0.0, false)  # 格擋無傷害
			if target.has_signal("block_detected"):
				target.block_detected.emit(name, "proximity")
			
			# 近距離格擋音效
			if hit_sound_player:
				var sound = hit_sound_player.duplicate()
				get_tree().current_scene.add_child(sound)
				sound.play()
				sound.finished.connect(func(): sound.queue_free())
			
			print("Fireball proximity blocked by %s, owner: %s" % [target.name, owner_character_id])
			
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
		print("Fireball impact animation finished, destroying, owner: %s" % owner_character_id)
		queue_free()

# 清除發射者的 active_fireball 引用
func _clear_owner_reference() -> void:
	if fireball_owner and is_instance_valid(fireball_owner) and "active_fireball" in fireball_owner:
		if fireball_owner.active_fireball == self:
			fireball_owner.active_fireball = null
			print("[Fireball] Cleared active_fireball reference for %s" % fireball_owner.name)
