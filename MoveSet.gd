class_name MoveSet extends Node

# 招式相關變數
var is_powerkk: bool = false
var powerkk_time: float = 0.6
var powerkk_timer: float = 0.0
var powerkk_damage: float = 20.0  # powerkk 傷害值
@onready var parent = get_parent()  # 獲取父節點（Davis）
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if not is_valid_state:
		return false
	
	# 處理 powerkk 輸入
	if input_data.spm1_pressed and not is_powerkk:
		is_powerkk = true
		powerkk_timer = powerkk_time
		parent.current_damage = powerkk_damage  # 設置 powerkk 的傷害
		parent.velocity.x = 0  # 鎖定移動
		sprite.scale.x = parent.facing_direction  # 設置動畫方向
		animation_player.play("powerkk")
		hitbox.disabled = false
		print("Debug: Powerkk triggered for %s, current_damage set to %s" % [parent.name, powerkk_damage])
		return true
	
	# powerkk 持續處理
	if is_powerkk:
		parent.velocity.x = 0  # 持續鎖定移動
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			is_powerkk = false
			hitbox.disabled = true
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO  # 重置 Sprite2D 位置
			parent.global_position.x += final_position.x  # 更新 CharacterBody2D 位置
			sprite.scale.x = 1.0  # 恢復縮放
			print("Debug: Powerkk ended for %s, final position: %s" % [parent.name, parent.global_position])
		return true
	
	return false

func get_powerkk_damage() -> float:
	return powerkk_damage if is_powerkk else 0.0
