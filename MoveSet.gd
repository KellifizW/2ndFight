class_name MoveSet extends Node

# 招式相關變數
var is_powerkk: bool = false
var is_spnk: bool = false
var is_spmove: bool = false  # 新增 spmove 分類
var powerkk_time: float = 0.933
var spnk_time: float = 0.0  # 改為 0，自動偵測
var powerkk_timer: float = 0.0
var spnk_timer: float = 0.0
var powerkk_damage: float = 20.0
var spnk_damage: float = 20.0
var powerkk_move_distance: float = 150.0
var spnk_move_distance: float = 150.0
var powerkk_initial_facing: float = 0.0
var spnk_initial_facing: float = 0.0
var powerkk_initial_parent_scale_x: float = 0.0
var powerkk_initial_sprite_scale_x: float = 0.0
var spnk_initial_parent_scale_x: float = 0.0
var spnk_initial_sprite_scale_x: float = 0.0
var is_spmove_animation_playing: bool = false  # 新增：追蹤 spnk 動畫是否播放中
@onready var parent = get_parent()
@onready var hitbox = parent.get_node("Hitbox/HitShape") if parent.has_node("Hitbox/HitShape") else null
@onready var animation_player = parent.get_node("AnimationPlayer") if parent.has_node("AnimationPlayer") else null
@onready var sprite = parent.get_node("Sprite2D") if parent.has_node("Sprite2D") else null

func _ready():
	if not parent or not hitbox or not animation_player or not sprite:
		print("Warning: MoveSet initialization failed. Missing parent, Hitbox, AnimationPlayer, or Sprite2D")
	if animation_player:
		for anim_name in ["powerkk", "spnk"]:
			if animation_player.has_animation(anim_name):
				var anim = animation_player.get_animation(anim_name)
				var track_count = anim.get_track_count()
				for track_idx in track_count:
					var track_path = anim.track_get_path(track_idx)
					if track_path.get_subname_count() > 0 and track_path.get_subname(0) == "Sprite2D:transform/scale.x":
						print("Warning: Animation '%s' modifies Sprite2D:transform/scale.x, which may override sprite.scale.x in %s. Consider removing this track." % [anim_name, parent.name])
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

func process_move(delta: float, input_data: Dictionary, is_valid_state: bool) -> bool:
	if parent.is_hit or parent.is_knockfly:
		if is_spmove:
			stop_special_move()
		return false
	
	if not is_valid_state:
		return false
	
	var player_id = parent.player_id if "player_id" in parent else "p1"
	
	if input_data.spm1_pressed:
		if player_id == "p1" and not is_powerkk:
			is_powerkk = true
			is_spmove = true
			powerkk_timer = powerkk_time
			parent.current_damage = powerkk_damage
			parent.velocity.x = 0
			powerkk_initial_facing = parent.facing_direction
			powerkk_initial_parent_scale_x = parent.scale.x
			powerkk_initial_sprite_scale_x = sprite.scale.x
			animation_player.play("powerkk")
			hitbox.disabled = false
			parent.scale.x = powerkk_initial_parent_scale_x
			sprite.scale.x = powerkk_initial_sprite_scale_x
			print("Debug: Powerkk triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, powerkk_damage, powerkk_initial_facing, parent.scale.x, sprite.scale.x])
			return true
		elif player_id == "p2" and not is_spnk:
			is_spnk = true
			is_spmove = true
			# 自動偵測 spnk 動畫長度
			if animation_player and animation_player.has_animation("spnk"):
				spnk_time = animation_player.get_animation("spnk").length
				spnk_timer = spnk_time
				print("Debug: Spnk length detected: %.2fs" % spnk_time)
			else:
				spnk_timer = 1.2  # 後備值，如果動畫不存在
			parent.current_damage = spnk_damage
			parent.velocity.x = 0
			spnk_initial_facing = parent.facing_direction
			spnk_initial_parent_scale_x = parent.scale.x
			spnk_initial_sprite_scale_x = sprite.scale.x
			animation_player.play("spnk")
			hitbox.disabled = false  # 初始啟用，但讓軌道控制
			parent.scale.x = spnk_initial_parent_scale_x
			sprite.scale.x = spnk_initial_sprite_scale_x
			# 連接動畫結束信號（如果還沒）
			if not animation_player.animation_finished.is_connected(_on_spmove_animation_finished):
				animation_player.animation_finished.connect(_on_spmove_animation_finished)
			is_spmove_animation_playing = true  # 標記開始監聽
			print("Debug: Spnk triggered for %s, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, spnk_damage, spnk_initial_facing, parent.scale.x, sprite.scale.x])
			return true
	
	if is_powerkk:
		parent.velocity.x = 0
		var move_speed = (powerkk_move_distance / powerkk_time) * powerkk_initial_facing
		parent.global_position.x += move_speed * delta
		parent.call_deferred("set", "scale/x", powerkk_initial_parent_scale_x)
		sprite.call_deferred("set", "scale/x", powerkk_initial_sprite_scale_x)
		powerkk_timer -= delta
		if powerkk_timer <= 0:
			is_powerkk = false
			is_spmove = false
			# 移除 hitbox.disabled = true，讓動畫軌道控制
			print("Debug: Powerkk ended for %s, hitbox state after end: %s" % [parent.name, hitbox.disabled])
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
			sprite.scale.x = abs(sprite.scale.x) * sign(powerkk_initial_facing)
			parent.update_facing_direction()
			print("Debug: Powerkk ended for %s, final position: %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, parent.global_position, powerkk_initial_facing, parent.scale.x, sprite.scale.x])
		return true

	if is_spnk:
		parent.velocity.x = 0
		var move_speed = (spnk_move_distance / spnk_time) * spnk_initial_facing
		parent.global_position.x += move_speed * delta
		parent.call_deferred("set", "scale/x", spnk_initial_parent_scale_x)
		sprite.call_deferred("set", "scale/x", spnk_initial_sprite_scale_x)
		spnk_timer -= delta
		print("Debug: Spnk active for %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, spnk_initial_facing, parent.scale.x, sprite.scale.x])
		if spnk_timer <= 0:
			is_spnk = false
			is_spmove = false
			is_spmove_animation_playing = false  # 停止監聽
			var final_position = sprite.position
			animation_player.stop()
			sprite.position = Vector2.ZERO
			parent.global_position.x += final_position.x
			sprite.scale.x = abs(sprite.scale.x) * sign(spnk_initial_facing)
			parent.update_facing_direction()
			print("Debug: Spnk ended for %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [parent.name, spnk_initial_facing, parent.scale.x, sprite.scale.x])
		return true
	
	return false

# 新增：動畫結束時的清理函數
func _on_spmove_animation_finished(anim_name: String):
	if anim_name == "spnk" and is_spmove_animation_playing:
		is_spmove_animation_playing = false
		hitbox.disabled = true  # 最終禁用，確保安全
		print("Debug: Spnk animation finished, Hitbox disabled")

# 新增：在 _process 中實時偵測軌道（加在 process_move 後）
func _process(delta: float):
	if not is_spmove_animation_playing or not animation_player or not animation_player.is_playing():
		return
	
	var current_time = animation_player.get_current_animation_position()  # 取得當前時間
	var anim = animation_player.get_current_animation()  # 確認是 spnk
	if anim != "spnk":
		return
	
	# 自動偵測 Hitbox 軌道（假設軌道索引為 9，從你的 tscn 看是 tracks/9 控制 disabled）
	var hitbox_track_index = 9  # 從 tscn 確認：tracks/9 是 "Hitbox/HitShape:disabled"
	if animation_player.has_animation(anim) and hitbox_track_index < animation_player.get_animation(anim).get_track_count():
		var track = animation_player.get_animation(anim).track_get_path(hitbox_track_index)
		if str(track) == "NodePath(Hitbox/HitShape:disabled)":  # 確認軌道路徑
			# 讀取軌道的鍵值時間和值，檢查當前時間是否在 disabled=false 的窗口
			var keys_times = animation_player.get_animation(anim).track_get_key_times(hitbox_track_index)
			var keys_values = []  # 收集值
			for i in range(animation_player.get_animation(anim).track_get_key_count(hitbox_track_index)):
				keys_values.append(animation_player.get_animation(anim).track_get_key_value(hitbox_track_index, i))
			
			# 簡單邏輯：檢查最近的鍵值，如果最近的是 false，就啟用
			var should_enable = false
			for i in range(keys_times.size()):
				if abs(current_time - keys_times[i]) < 0.01:  # 接近鍵值時間
					should_enable = not keys_values[i]  # 如果值是 false (disabled=false)，啟用
					break
			
			hitbox.disabled = not should_enable  # 同步 Hitbox 狀態
			print("Debug: Spnk time %.2f, Hitbox enabled: %s" % [current_time, should_enable])

func get_special_damage() -> float:
	var player_id = parent.player_id if "player_id" in parent else "p1"
	if player_id == "p1" and is_powerkk:
		return powerkk_damage
	elif player_id == "p2" and is_spnk:
		return spnk_damage
	return 0.0
