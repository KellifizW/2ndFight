extends Area2D

var speed: float = 800.0          # 預設速度（DAV）
var direction: int = 1
var damage: float = 15.0          # 預設傷害（DAV）
var blockstun_duration: float = 0.3
var is_active: bool = true
var owner_character_id: String = "DAV"  # 現在使用 character_id 而不是舊的 p1/p2
var fireball_owner: Node = null           # 發射者的 Player 實例（避免打到自己）

@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var prox_shape = $Proximitybox/ProxShape
@onready var spawn_sound_player = $SpawnSoundPlayer
@onready var hit_sound_player = $HitSoundPlayer

func _ready() -> void:
	add_to_group("fireball")
	
	# 根據角色設定參數（DAV 與 DEN 不同）
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
	# 超出畫面自動銷毀
	if position.x > 2000 or position.x < -2000:
		print("Fireball out of bounds, destroying at position: %s" % position.x)
		queue_free()

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
		is_active = false
		if hitbox: hitbox.monitoring = false
		if prox_shape: prox_shape.disabled = true
		animation_player.play("fireball/ball_impact")
		
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
		var vfx_scene_path = "res://vfx_blk.tscn" if is_blocked else "res://vfx_hit.tscn"
		var vfx_scene = load(vfx_scene_path)
		if vfx_scene:
			var vfx = vfx_scene.instantiate()
			vfx.global_position = vfx_position
			get_tree().current_scene.add_child(vfx)
		else:
			push_error("無法載入 VFX 場景：%s" % vfx_scene_path)

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
			is_active = false
			if hitbox: hitbox.monitoring = false
			if prox_shape: prox_shape.disabled = true
			animation_player.play("fireball/ball_impact")
			
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
			var vfx_blk = load("res://vfx_blk.tscn")
			if vfx_blk:
				var vfx = vfx_blk.instantiate()
				vfx.global_position = vfx_position
				get_tree().current_scene.add_child(vfx)

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "fireball/ball_impact":
		print("Fireball impact animation finished, destroying, owner: %s" % owner_character_id)
		queue_free()
