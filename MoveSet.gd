class_name MoveSet extends Node

# 招式相關變數
var is_powerkk: bool = false
var is_spnk: bool = false
var powerkk_time: float = 0.933
var spnk_time: float = 1.2
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var powerkk_damage: float = 20.0
var spnk_damage: float = 20.0
<<<<<<< HEAD
<<<<<<< HEAD
var powerkk_move_distance: float = 150.0
var spnk_move_distance: float = 150.0
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var powerkk_initial_parent_scale_x: float = 0.0
var powerkk_initial_sprite_scale_x: float = 0.0
var spnk_initial_parent_scale_x: float = 0.0
var spnk_initial_sprite_scale_x: float = 0.0
var is_spmove_animation_playing: bool = false  # 新增：追蹤 spnk 動畫是否播放中
=======
var powerkk_move_distance: float = 150.0  # powerkk 總移動距離
var spnk_move_distance: float = 150.0     # spnk 總移動距離
>>>>>>> parent of 2da39c1 (91733)
=======
var powerkk_move_distance: float = 150.0  # powerkk 總移動距離
var spnk_move_distance: float = 150.0     # spnk 總移動距離
var powerkk_initial_facing: float = 0.0   # 鎖定初始面向方向
var spnk_initial_facing: float = 0.0      # 鎖定初始面向方向
var powerkk_initial_parent_scale_x: float = 0.0  # 鎖定初始 parent.scale.x
var powerkk_initial_sprite_scale_x: float = 0.0  # 鎖定初始 sprite.scale.x
var spnk_initial_parent_scale_x: float = 0.0     # 鎖定初始 parent.scale.x
var spnk_initial_sprite_scale_x: float = 0.0     # 鎖定初始 sprite.scale.x
>>>>>>> parent of 034eb24 (9191)
@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")
<<<<<<< HEAD
<<<<<<< HEAD
=======
	# 檢查 AnimationPlayer 的 powerkk/spnk 動畫是否影響 scale.x
>>>>>>> parent of 034eb24 (9191)
	if animation_player:
		for anim_name in ["powerkk", "spnk"]:
			if animation_player.has_animation(anim_name):
				var anim = animation_player.get_animation(anim_name)
				var track_count = anim.get_track_count()
				for track_idx in track_count:
					var track_path = anim.track_get_path(track_idx)
					if track_path.get_subname_count() > 0 and track_path.get_subname(0) == "Sprite2D:transform/scale.x":
						print("Warning: Animation '%s' modifies Sprite2D:transform/scale.x, which may override sprite.scale.x in %s. Consider removing this track." % [anim_name, parent.name])
<<<<<<< HEAD
		# 連接動畫結束信號
		animation_player.animation_finished.connect(_on_spmove_animation_finished)

func stop_special_move():
	if is_powerkk or is_spnk:
		is_powerkk = false
		is_spnk = false
		is_spmove = false
		is_spmove_animation_playing = false
		# 移除 hitbox.disabled = true，讓動畫軌道控制
		var final_position = sprite.position
		animation_player.stop()
		sprite.position = Vector2.ZERO
		parent.global_position.x += final_position.x
		sprite.scale.x = abs(sprite.scale.x) * sign(parent.facing_direction)
		parent.update_facing_direction()
		print("Debug: Special move stopped for %s due to hit, position: %s, sprite.scale.x=%s" % [parent.name, parent.global_position, sprite.scale.x])
=======
>>>>>>> parent of 2da39c1 (91733)
=======
>>>>>>> parent of 034eb24 (9191)

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if not is_valid_state:
		return false
	
	var player_id = parent.player_id if "player_id" in parent else "p1"
	
	if input_data.spm1_pressed:
		if player_id == "p1" and not is_powerkk:
			is_powerkk = true
			powerkk_timer = powerkk_time
			parent.current_damage = powerkk_damage
			parent.velocity.x = 0
			parent.update_facing_direction()
			animation_player.play("powerkk")
			hitbox.disabled = false
<<<<<<< HEAD
<<<<<<< HEAD
=======
			# 立即設置，防止初始幀被覆蓋
>>>>>>> parent of 034eb24 (9191)
			parent.scale.x = powerkk_initial_parent_scale_x
			sprite.scale.x = powerkk_initial_sprite_scale_x
			print("Debug: Powerkk triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, powerkk_damage, powerkk_initial_facing, parent.scale.x, sprite.scale.x])
=======
			print("Debug: Powerkk triggered for %s, current_damage set to %s" % [parent.name, powerkk_damage])
>>>>>>> parent of 2da39c1 (91733)
			return true
		elif player_id == "p2" and not is_spnk:
			is_spnk = true
			spnk_timer = spnk_time
			parent.current_damage = spnk_damage
			parent.velocity.x = 0
			parent.update_facing_direction()
			animation_player.play("spnk")
<<<<<<< HEAD
<<<<<<< HEAD
			hitbox.disabled = false  # 初始啟用，但讓軌道控制
=======
			hitbox.disabled = false
			# 立即設置，防止初始幀被覆蓋
>>>>>>> parent of 034eb24 (9191)
			parent.scale.x = spnk_initial_parent_scale_x
			sprite.scale.x = spnk_initial_sprite_scale_x
			print("Debug: Spnk triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, spnk_damage, spnk_initial_facing, parent.scale.x, sprite.scale.x])
=======
			hitbox.disabled = false
			print("Debug: Spnk triggered for %s, current_damage set to %s" % [parent.name, spnk_damage])
>>>>>>> parent of 2da39c1 (91733)
			return true
	
	if is_powerkk:
		parent.velocity.x = 0
		var move_speed = (powerkk_move_distance / powerkk_time) * parent.facing_direction
		parent.global_position.x += move_speed * delta
<<<<<<< HEAD
<<<<<<< HEAD
=======
		# 使用 call_deferred 確保在動畫和其他邏輯後設置 scale.x
>>>>>>> parent of 034eb24 (9191)
		parent.call_deferred("set", "scale/x", powerkk_initial_parent_scale_x)
		sprite.call_deferred("set", "scale/x", powerkk_initial_sprite_scale_x)
=======
>>>>>>> parent of 2da39c1 (91733)
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			is_powerkk = false
			hitbox.disabled = true
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
<<<<<<< HEAD
<<<<<<< HEAD
			sprite.scale.x = abs(sprite.scale.x) * sign(powerkk_initial_facing)
			parent.update_facing_direction()
=======
			sprite.scale.x = abs(sprite.scale.x) * sign(powerkk_initial_facing)  # 與 initial_facing 同步
			parent.update_facing_direction()  # 恢復正常更新
>>>>>>> parent of 034eb24 (9191)
			print("Debug: Powerkk ended for %s, final position: %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, parent.global_position, powerkk_initial_facing, parent.scale.x, sprite.scale.x])
=======
			parent.update_facing_direction()
			print("Debug: Powerkk ended for %s, final position: %s, facing_direction=%s" % [parent.name, parent.global_position, parent.facing_direction])
>>>>>>> parent of 2da39c1 (91733)
		return true

	if is_spnk:
		parent.velocity.x = 0
		var move_speed = (spnk_move_distance / spnk_time) * parent.facing_direction
		parent.global_position.x += move_speed * delta
<<<<<<< HEAD
<<<<<<< HEAD
=======
		# 使用 call_deferred 確保在動畫和其他邏輯後設置 scale.x
>>>>>>> parent of 034eb24 (9191)
		parent.call_deferred("set", "scale/x", spnk_initial_parent_scale_x)
		sprite.call_deferred("set", "scale/x", spnk_initial_sprite_scale_x)
=======
>>>>>>> parent of 2da39c1 (91733)
		spnk_timer -= delta
		print("Debug: Spnk active, facing_direction=%s, sprite.scale.x=%s, parent.scale.x=%s" % [parent.facing_direction, sprite.scale.x, parent.scale.x])
		if spnk_timer <= 0:
			is_spnk = false
			hitbox.disabled = true
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
<<<<<<< HEAD
<<<<<<< HEAD
			sprite.scale.x = abs(sprite.scale.x) * sign(spnk_initial_facing)
			parent.update_facing_direction()
=======
			sprite.scale.x = abs(sprite.scale.x) * sign(spnk_initial_facing)  # 與 initial_facing 同步
			parent.update_facing_direction()  # 恢復正常更新
>>>>>>> parent of 034eb24 (9191)
			print("Debug: Spnk ended for %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, spnk_initial_facing, parent.scale.x, sprite.scale.x])
=======
			parent.update_facing_direction()
			print("Debug: Spnk ended, sprite.scale.x=%s, facing_direction=%s, parent.scale.x=%s" % [sprite.scale.x, parent.facing_direction, parent.scale.x])
>>>>>>> parent of 2da39c1 (91733)
		return true
	
	return false

func get_special_damage() -> float:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p1" and is_powerkk:
		return powerkk_damage
	elif player_id == "p2" and is_spnk:
		return spnk_damage
	return 0.0
