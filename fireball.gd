extends Area2D

var speed: float = 300.0  # 預設速度（Player1）
var direction: int = 1
var damage: float = 15.0  # 預設傷害（Player1）
var blockstun_duration: float = 0.3  # 格擋硬直時間，稍短於 powerkk 的 0.4
var is_active: bool = true  # 控制火球是否仍可造成傷害
var owner_id: String = "p1"  # 新增：識別火球的發射者（p1 或 p2）

@onready var sprite = $Sprite2D
@onready var animation_player = $AnimationPlayer
@onready var hitbox = $Hitbox
@onready var hurtbox = $Hurtbox
@onready var prox_shape = $Proximitybox/ProxShape

func _ready():
	# 根據 owner_id 設置火球參數
	if owner_id == "p1":
		speed = 300.0
		damage = 15.0
	elif owner_id == "p2":
		speed = 250.0
		damage = 11.0
	
	if sprite == null:
		print("Error: Sprite2D node not found in Fireball!")
	else:
		sprite.flip_h = direction < 0
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
	print("Fireball initialized, owner_id: %s, speed: %s, damage: %s, collision_layer: %s, collision_mask: %s, direction: %s" % [owner_id, speed, damage, collision_layer, collision_mask, direction])

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
		animation_player.play("fireball/ball_impact")  # 使用動畫庫路徑
		var world = get_tree().get_first_node_in_group("world")
		if world:
			var slowmo_controller = world.get_node_or_null("SlowMoController")
			if slowmo_controller:
				slowmo_controller.request_hit_freeze()
		target.take_hit(blockstun_duration, damage, false)
		var is_blocked = target.is_blocking and target.block_type == "ordinary"
		if target.has_signal("hit_detected"):
			target.hit_detected.emit(name, blockstun_duration, is_blocked)
		print("Fireball hit %s, is_blocked: %s, damage: %s, owner_id: %s" % [target.name, is_blocked, damage, owner_id])

func _on_hurtbox_area_entered(area: Area2D):
	if not is_active:
		return
	if area.name == "Hitbox" and area.get_parent().is_in_group("players"):
		is_active = false
		if hitbox:
			hitbox.monitoring = false
		if prox_shape:
			prox_shape.disabled = true
		animation_player.play("fireball/ball_impact")  # 使用動畫庫路徑
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
			print("Fireball blocked by %s, playing impact and destroying, owner_id: %s" % [target.name, owner_id])

func _on_animation_finished(anim_name: String):
	if anim_name == "fireball/ball_impact":  # 使用動畫庫路徑
		print("Fireball impact animation finished, destroying, owner_id: %s" % owner_id)
		queue_free()
