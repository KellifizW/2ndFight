extends Area2D

var speed: float = 800.0
var direction: int = 1
var damage: float = 15.0
var blockstun_duration: float = 0.3
var is_active: bool = true
var owner_character_id: String = "DAV"
var fireball_owner: Node = null

@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var prox_shape = $Proximitybox/ProxShape
@onready var spawn_sound_player = $SpawnSoundPlayer
@onready var hit_sound_player = $HitSoundPlayer

# 粒子節點引用
@onready var hit_particles: GPUParticles2D = $hit
@onready var ringexp_particles: GPUParticles2D = $ringexp
@onready var run_particles: GPUParticles2D = $run     # ← 新增這一行

func _ready() -> void:
	add_to_group("fireball")
	
	if owner_character_id == "DAV":
		speed = 800.0
		damage = 15.0
	elif owner_character_id == "DEN":
		speed = 600.0
		damage = 11.0
	else:
		push_warning("未知的 fireball owner_character_id: %s，使用預設值" % owner_character_id)
	
	if sprite == null:
		push_error("Error: Sprite2D node not found in Fireball!")
	else:
		scale.x = direction
		scale.y = 1
		sprite.scale.x = 1.0
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
	
	if spawn_sound_player:
		spawn_sound_player.play()
	else:
		push_warning("Warning: SpawnSoundPlayer not found in Fireball!")
	
	print("Debug: Fireball initialized, owner_character_id: %s, speed: %s, damage: %s, direction: %s" %
		[owner_character_id, speed, damage, direction])

func _physics_process(delta: float) -> void:
	if is_active:
		position.x += speed * direction * delta
	
	if position.x > 2000 or position.x < -2000:
		print("Fireball out of bounds, destroying at position: %s" % position.x)
		queue_free()

func _stop_trail_immediately() -> void:
	if run_particles:
		run_particles.emitting = false
		run_particles.queue_free()          # 立即移除節點，最快消失
		# 或是你也可以選擇： run_particles.visible = false  (但節點還在，比較浪費)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if not is_active: return
	
	if fireball_owner and area.get_parent() == fireball_owner:
		return
	if area.get_parent() == self:
		return
	
	if area.name == "Hurtbox" and area.get_parent().is_in_group("players"):
		var target = area.get_parent()
		is_active = false
		if hitbox: hitbox.monitoring = false
		if prox_shape: prox_shape.disabled = true
		
		# 立即停止並移除飛行軌跡粒子
		_stop_trail_immediately()
		
		# 爆破粒子
		if hit_particles:
			hit_particles.restart()
			hit_particles.emitting = true
		if ringexp_particles:
			ringexp_particles.restart()
			ringexp_particles.emitting = true
		
		animation_player.play("fireball/ball_impact")
		
		var world = get_tree().get_first_node_in_group("world")
		if world:
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze()
		
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		var actual_damage = damage if not is_blocked else 0.0
		target.take_hit(blockstun_duration, blockstun_duration, actual_damage, false)
		
		if target.has_signal("hit_detected"):
			target.hit_detected.emit(name, blockstun_duration, is_blocked)
		
		if hit_sound_player:
			var sound = hit_sound_player.duplicate()
			get_tree().current_scene.add_child(sound)
			sound.play()
			sound.finished.connect(func(): sound.queue_free())
		else:
			push_warning("Warning: HitSoundPlayer not found in Fireball!")
		
		print("Fireball hit %s, is_blocked: %s, damage: %s, owner: %s" %
			[target.name, is_blocked, actual_damage, owner_character_id])
		
		var vfx_position = (global_position + area.global_position) / 2.0
		var vfx_type = "block" if is_blocked else "hit"
		var preloader = get_tree().get_first_node_in_group("resource_preloader")
		if preloader:
			var vfx_scene = preloader.get_vfx_scene(vfx_type)
			if vfx_scene:
				var vfx = vfx_scene.instantiate()
				vfx.global_position = vfx_position
				get_tree().current_scene.add_child(vfx)

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if not is_active: return
	
	if fireball_owner and area.get_parent() == fireball_owner:
		return
	if area.get_parent() == self:
		return
	
	if area.name == "Hitbox" and (area.get_parent().is_in_group("players") or area.get_parent().is_in_group("fireball")):
		is_active = false
		if hitbox: hitbox.monitoring = false
		if prox_shape: prox_shape.disabled = true
		
		# 被其他火球或攻擊打到，也停止軌跡
		_stop_trail_immediately()
		
		animation_player.play("fireball/ball_impact")
		
		if area.get_parent().is_in_group("fireball"):
			print("Fireball collided with another fireball, owner: %s" % owner_character_id)
		else:
			print("Fireball hit by %s's Hitbox, owner: %s" % [area.get_parent().name, owner_character_id])

func _on_proximitybox_area_entered(area: Area2D) -> void:
	if not is_active: return
	
	if fireball_owner and area.get_parent() == fireball_owner:
		return
	
	if area.name == "Hurtbox" and area.get_parent().is_in_group("players"):
		var target = area.get_parent()
		if target.is_holding_back or target.is_crouch_blocking:
			is_active = false
			if hitbox: hitbox.monitoring = false
			if prox_shape: prox_shape.disabled = true
			
			# 近距離格擋也停止軌跡 + 播放爆破
			_stop_trail_immediately()
			
			if hit_particles:
				hit_particles.restart()
				hit_particles.emitting = true
			if ringexp_particles:
				ringexp_particles.restart()
				ringexp_particles.emitting = true
			
			animation_player.play("fireball/ball_impact")
			
			target.take_hit(blockstun_duration, 0.0, false)
			if target.has_signal("block_detected"):
				target.block_detected.emit(name, "proximity")
			
			if hit_sound_player:
				var sound = hit_sound_player.duplicate()
				get_tree().current_scene.add_child(sound)
				sound.play()
				sound.finished.connect(func(): sound.queue_free())
			
			print("Fireball proximity blocked by %s, owner: %s" % [target.name, owner_character_id])
			
			var vfx_position = (global_position + area.global_position) / 2.0
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
