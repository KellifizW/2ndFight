extends Area2D

var speed: float = 600.0  # 預設速度（Player1）
var direction: int = 1
var damage: float = 15.0  # 預設傷害（Player1）
var blockstun_duration: float = 0.3  # 格擋硬直時間，稍短於 powerkk 的 0.4
var is_active: bool = true  # 控制火球是否仍可造成傷害
var owner_id: String = "p1"  # 識別火球的發射者（p1 或 p2）

@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var prox_shape = $Proximitybox/ProxShape
@onready var spawn_sound_player = $SpawnSoundPlayer  # 生成音效播放器（AudioStreamPlayer）
@onready var hit_sound_player = $HitSoundPlayer  # 新增：擊中音效播放器（AudioStreamPlayer）

func _ready():
	# 為火球添加組以便識別
	add_to_group("fireball")
	
	# 根據 owner_id 設置火球參數
	if owner_id == "p1":
		speed = 700.0
		damage = 15.0
	elif owner_id == "p2":
		speed = 500.0
		damage = 11.0
	
	if sprite == null:
		print("Error: Sprite2D node not found in Fireball!")
	else:
		# 使用場景反轉，與 Movement.gd 一致
		scale.x = direction
		scale.y = 1
		sprite.scale.x = 1.0  # 保持 sprite 不被場景反轉影響
		# 為 P2 調整 offset 以適應場景反轉
		if owner_id == "p2":
			sprite.offset.x = abs(sprite.offset.x)  # 確保 offset.x 為正，與 P1 對齊
	if animation_player == null:
		print("Error: AnimationPlayer node not found in Fireball!")
	else:
		animation_player.play("fireball/ball_idle")  # 使用動畫庫路徑
		animation_player.animation_finished.connect(_on_animation_finished)
	if hitbox:
		hitbox.area_entered.connect(_on_hitbox_area_entered)
	if hurtbox:
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	if prox_shape:
		prox_shape.get_parent().area_entered.connect(_on_proximitybox_area_entered)  # 添加 Proximitybox 信號
	monitoring = true
	monitorable = true
	
	# 播放生成音效
	if spawn_sound_player:
		spawn_sound_player.play()
		print("Debug: Fireball spawn sound played for owner_id: %s" % owner_id)
	else:
		print("Warning: SpawnSoundPlayer not found in Fireball!")
	
	print("Fireball initialized, owner_id: %s, speed: %s, damage: %s, collision_layer: %s, collision_mask: %s, direction: %s, sprite.offset: %s, scale.x: %s" % [owner_id, speed, damage, collision_layer, collision_mask, direction, sprite.offset, scale.x])

func _physics_process(delta):
	if is_active:
		position.x += speed * direction * delta
	if position.x > 2000 or position.x < -2000:
		print("Fireball out of bounds, destroying at position: %s" % position.x)
		queue_free()

func _on_hitbox_area_entered(area: Area2D):
	if not is_active:
		return
	if area.name == "Hurtbox" and area.get_parent().is_in_group("players"):
		var target = area.get_parent()
		is_active = false
		if hitbox:
			hitbox.monitoring = false
		if prox_shape:
			prox_shape.disabled = true
		animation_player.play("fireball/ball_impact")
		var world = get_tree().get_first_node_in_group("world")
		if world:
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze()
		# 修正參數順序：hitstun_duration, blockstun_duration, damage, skip_push
		target.take_hit(blockstun_duration, blockstun_duration, damage, false)
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		if target.has_signal("hit_detected"):
			target.hit_detected.emit(name, blockstun_duration, is_blocked)
		# 新增：播放擊中音效（無論是否格擋）
		if hit_sound_player:
			var sound = hit_sound_player.duplicate()
			get_tree().current_scene.add_child(sound)
			sound.play()
			sound.finished.connect(func(): sound.queue_free())
			print("Debug: Fireball hit sound played for owner_id: %s, target: %s, is_blocked: %s" % [owner_id, target.name, is_blocked])
		else:
			print("Warning: HitSoundPlayer not found in Fireball!")
		print("Fireball hit %s, is_blocked: %s, damage: %s, owner_id: %s" % [target.name, is_blocked, damage, owner_id])
		# 根據是否格擋選擇 VFX 場景
		var vfx_position = (global_position + area.global_position) / 2.0
		var vfx_scene_path = "res://vfx_blk.tscn" if is_blocked else "res://vfx_hit.tscn"
		var vfx_scene = load(vfx_scene_path).instantiate()
		vfx_scene.global_position = vfx_position
		get_tree().current_scene.add_child(vfx_scene)
		print("Debug: VFX instantiated at %s for %s on %s" % [vfx_position, "block" if is_blocked else "hit", target.name])

func _on_hurtbox_area_entered(area: Area2D):
	if not is_active:
		return
	# 檢查是否與玩家的 Hitbox 或另一顆火球的 Hitbox 碰撞
	if area.name == "Hitbox" and (area.get_parent().is_in_group("players") or area.get_parent().is_in_group("fireball")):
		is_active = false
		if hitbox:
			hitbox.monitoring = false
		if prox_shape:
			prox_shape.disabled = true
		animation_player.play("fireball/ball_impact")  # 使用動畫庫路徑
		if area.get_parent().is_in_group("fireball"):
			# 確保對方火球也銷毀（由對方火球的 Hurtbox 處理）
			print("Fireball collided with another fireball, playing impact and destroying, owner_id: %s" % owner_id)
		else:
			print("Fireball hit by %s's Hitbox, playing impact and destroying, owner_id: %s" % [area.get_parent().name, owner_id])

func _on_proximitybox_area_entered(area: Area2D):
	if not is_active:
		return
	if area.name == "Hurtbox" and area.get_parent().is_in_group("players"):
		var target = area.get_parent()
		if target.is_holding_back or target.is_crouch_blocking:
			is_active = false
			if hitbox:
				hitbox.monitoring = false
			if prox_shape:
				prox_shape.disabled = true
			animation_player.play("fireball/ball_impact")  # 使用動畫庫路徑
			target.take_hit(blockstun_duration, 0.0, false)  # 格擋時無傷害
			if target.has_signal("block_detected"):
				target.block_detected.emit(name, "proximity")
			# 新增：播放擊中音效（近距離格擋）
			if hit_sound_player:
				var sound = hit_sound_player.duplicate()
				get_tree().current_scene.add_child(sound)
				sound.play()
				sound.finished.connect(func(): sound.queue_free())
				print("Debug: Fireball hit sound played for owner_id: %s, target: %s (proximity block)" % [owner_id, target.name])
			else:
				print("Warning: HitSoundPlayer not found in Fireball!")
			print("Fireball blocked by %s, playing impact and destroying, owner_id: %s" % [target.name, owner_id])
			# 實例化格擋 VFX
			var vfx_position = (global_position + area.global_position) / 2.0
			var vfx_blk = load("res://vfx_blk.tscn").instantiate()
			vfx_blk.global_position = vfx_position
			get_tree().current_scene.add_child(vfx_blk)
			print("Debug: VFX_blk instantiated at %s for proximity block on %s" % [vfx_position, target.name])

func _on_animation_finished(anim_name: String):
	if anim_name == "fireball/ball_impact":  # 使用動畫庫路徑
		print("Fireball impact animation finished, destroying, owner_id: %s" % owner_id)
		queue_free()
