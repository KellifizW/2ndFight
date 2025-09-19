class_name DebugNode extends Node

func _ready():
	add_to_group("debug_node")
	var players = get_tree().get_nodes_in_group("players")
	if players.size() < 2:
		print("Warning: DebugNode found fewer than 2 players in group 'players'")

func log_initialization(player: Node, hitbox: Node, proxbox: Node, move_set: Node):
	if hitbox and hitbox is CollisionShape2D:
		var layer = hitbox.get_parent().collision_layer
		var mask = hitbox.get_parent().collision_mask
		var layer_indices = _get_collision_layer_indices(layer)
		var mask_indices = _get_collision_layer_indices(mask)
		var shape_status = "null" if not hitbox.shape else hitbox.shape.get_class()
		var anim_state = "pending"
		var animation_state = player.animation_state if "animation_state" in player else null
		if animation_state:
			anim_state = animation_state.get_current_node() if animation_state.get_current_node() else "pending"
		else:
			anim_state = "uninitialized"
		print("Debug [%s]: Hitbox found, Collision Layer: %s, Collision Mask: %s, Shape: %s, Current Animation: %s" % [player.name, layer_indices, mask_indices, shape_status, anim_state])
	else:
		print("Warning [%s]: HitShape (CollisionShape2D) not found under Hitbox" % player.name)
	if proxbox and proxbox is CollisionShape2D:
		var layer = proxbox.get_parent().collision_layer
		var mask = proxbox.get_parent().collision_mask
		var layer_indices = _get_collision_layer_indices(layer)
		var mask_indices = _get_collision_layer_indices(mask)
		var shape_status = "null" if not proxbox.shape else proxbox.shape.get_class()
		var anim_state = "pending"
		var animation_state = player.animation_state if "animation_state" in player else null
		if animation_state:
			anim_state = animation_state.get_current_node() if animation_state.get_current_node() else "pending"
		else:
			anim_state = "uninitialized"
		print("Debug [%s]: Proximitybox found, Collision Layer: %s, Collision Mask: %s, Shape: %s, Current Animation: %s" % [player.name, layer_indices, mask_indices, shape_status, anim_state])
	else:
		print("Warning [%s]: ProxShape (CollisionShape2D) not found under Proximitybox" % player.name)
	if move_set and player.player_id != "p1" and player.player_id != "p2":
		print("Warning [%s]: MoveSet node found, but only P1 or P2 should have MoveSet" % player.name)
	if not player.get_node_or_null("Pushbox") or not player.get_node("Pushbox").shape is RectangleShape2D:
		print("Warning [%s]: Pushbox not found or invalid" % player.name)
	if not player.get_tree().get_first_node_in_group("ui") or not player.get_tree().get_first_node_in_group("ui").get_node("%sHealthbar" % player.name):
		print("Warning [%s]: Healthbar not found" % player.name)

func log_hitbox_state(player: Node, hit_shape: Node, is_enabled: bool, anim_state: String):
	if hit_shape and hit_shape is CollisionShape2D:
		var hitbox_pos = hit_shape.get_parent().global_position
		var shape_status = "null" if not hit_shape.shape else hit_shape.shape.get_class()
		if is_enabled:
			print("Debug [%s]: Hitbox enabled during attack at global_position: (%s, %s), shape: %s, animation: %s" % [player.name, hitbox_pos.x, hitbox_pos.y, shape_status, anim_state])
		else:
			print("Debug [%s]: Hitbox state after attack ended at global_position: (%s, %s), shape: %s, animation: %s" % [player.name, hitbox_pos.x, hitbox_pos.y, shape_status, anim_state])
	else:
		print("Warning [%s]: Failed to check Hitbox state, HitShape not found or invalid" % player.name)

func log_proximitybox_state(player: Node, prox_shape: Node, is_enabled: bool, anim_state: String):
	if prox_shape and prox_shape is CollisionShape2D:
		var proxbox_pos = prox_shape.get_parent().global_position
		var shape_status = "null" if not prox_shape.shape else prox_shape.shape.get_class()
		var disabled_status = prox_shape.disabled
		if is_enabled:
			print("Debug [%s]: ProximityBox enabled during attack at global_position: (%s, %s), disabled: %s, shape: %s, animation: %s" % [player.name, proxbox_pos.x, proxbox_pos.y, disabled_status, shape_status, anim_state])
		else:
			print("Debug [%s]: ProximityBox disabled after attack ended at global_position: (%s, %s), disabled: %s, shape: %s, animation: %s" % [player.name, proxbox_pos.x, proxbox_pos.y, disabled_status, shape_status, anim_state])
	else:
		print("Warning [%s]: Failed to check Proximitybox state, ProxShape not found or invalid" % player.name)

func log_hit_detected(player: Node, target: Node, blockstun_duration: float, damage: float, is_blocked: bool, hit_shape: Node, anim_state: String):
	if hit_shape and hit_shape is CollisionShape2D:
		var hitbox_pos = hit_shape.get_parent().global_position
		var shape_status = "null" if not hit_shape.shape else hit_shape.shape.get_class()
		print("Debug [%s]: Hitbox hit detected on %s at global_position: (%s, %s), shape: %s, animation: %s" % [player.name, target.name, hitbox_pos.x, hitbox_pos.y, shape_status, anim_state])
		print("Debug [%s]: Hit detected on %s with blockstun duration %s, damage %s, is_blocked: %s, animation: %s" % [player.name, target.name, blockstun_duration, damage, is_blocked, anim_state])
	else:
		print("Warning [%s]: Failed to log hit, HitShape not found or invalid" % player.name)

func log_special_move_trigger(player: Node, move_name: String, damage: float, initial_facing: float, parent_scale_x: float, sprite_scale_x: float, hitbox_pos: Vector2, shape_status: String):
	print("Debug [%s]: %s triggered, current_damage=%s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s, Hitbox global_position: (%s, %s), shape: %s" % [player.name, move_name, damage, initial_facing, parent_scale_x, sprite_scale_x, hitbox_pos.x, hitbox_pos.y, shape_status])

func log_special_move_active(player: Node, move_name: String, hitbox_pos: Vector2, shape_status: String, proxbox_pos: Vector2 = Vector2.ZERO):
	print("Debug [%s]: %s active, Hitbox global_position: (%s, %s), shape: %s" % [player.name, move_name, hitbox_pos.x, hitbox_pos.y, shape_status])
	if proxbox_pos != Vector2.ZERO:
		print("Debug [%s]: %s active, Proximitybox global_position: (%s, %s)" % [player.name, move_name, proxbox_pos.x, proxbox_pos.y])

func log_special_move_end(player: Node, move_name: String, hitbox_pos: Vector2, shape_status: String, final_position: Vector2, initial_facing: float, parent_scale_x: float, sprite_scale_x: float, proxbox_pos: Vector2 = Vector2.ZERO):
	print("Debug [%s]: %s ended, Hitbox final global_position: (%s, %s), shape: %s" % [player.name, move_name, hitbox_pos.x, hitbox_pos.y, shape_status])
	if proxbox_pos != Vector2.ZERO:
		print("Debug [%s]: %s ended, Proximitybox final global_position: (%s, %s)" % [player.name, move_name, proxbox_pos.x, proxbox_pos.y])
	print("Debug [%s]: %s ended, final position: %s, initial_facing=%s, parent.scale.x=%s, sprite.scale.x=%s" % [player.name, move_name, final_position, initial_facing, parent_scale_x, sprite_scale_x])

func log_special_move_stop(player: Node, final_position: Vector2, sprite_scale_x: float, hitbox_pos: Vector2, shape_status: String, proxbox_pos: Vector2 = Vector2.ZERO):
	print("Debug [%s]: Special move stopped due to hit, Hitbox global_position: (%s, %s), shape: %s" % [player.name, hitbox_pos.x, hitbox_pos.y, shape_status])
	if proxbox_pos != Vector2.ZERO:
		print("Debug [%s]: Special move stopped, Proximitybox global_position: (%s, %s)" % [player.name, proxbox_pos.x, proxbox_pos.y])
	print("Debug [%s]: Special move stopped, final position: %s, sprite.scale.x=%s" % [player.name, final_position, sprite_scale_x])

func log_spnk_animation(player: Node, current_time: float, hitbox_pos: Vector2, shape_status: String, proxbox_pos: Vector2 = Vector2.ZERO):
	print("Debug [%s]: Spnk time %.2f, Hitbox global_position: (%s, %s), shape: %s" % [player.name, current_time, hitbox_pos.x, hitbox_pos.y, shape_status])
	if proxbox_pos != Vector2.ZERO:
		print("Debug [%s]: Spnk time %.2f, Proximitybox global_position: (%s, %s)" % [player.name, current_time, proxbox_pos.x, proxbox_pos.y])

func log_spnk_animation_finished(player: Node, hitbox_pos: Vector2, shape_status: String, proxbox_pos: Vector2 = Vector2.ZERO):
	print("Debug [%s]: Spnk animation finished, Hitbox global_position: (%s, %s), shape: %s" % [player.name, hitbox_pos.x, hitbox_pos.y, shape_status])
	if proxbox_pos != Vector2.ZERO:
		print("Debug [%s]: Spnk animation finished, Proximitybox global_position: (%s, %s)" % [player.name, proxbox_pos.x, proxbox_pos.y])

func log_animation_switch(player: Node, target_state: String, sprite_scale_x: float):
	print("Debug [%s]: Animation switched to %s, sprite.scale.x=%s" % [player.name, target_state, sprite_scale_x])

func log_jump(player: Node, direction: float):
	print("Debug [%s]: Jump triggered, direction: %s" % [player.name, direction])

func log_jump_position(player: Node, position: Vector2):
	print("Debug [%s]: Jump position: x=%s, y=%s" % [player.name, position.x, position.y])

func log_landing(player: Node):
	print("Debug [%s]: Landing, resetting is_jumping" % player.name)

func log_facing_direction(player: Node, direction: String, scale_x: float, sprite_scale_x: float):
	print("Debug [%s]: Facing %s, scale.x=%s, sprite.scale.x=%s" % [player.name, direction, scale_x, sprite_scale_x])

func log_attack_end(player: Node):
	print("Debug [%s]: Attack ended, is_attacking set to false" % player.name)

func log_hitstun_end(player: Node):
	print("Debug [%s]: Hitstun ended" % player.name)

func log_block_end(player: Node):
	print("Debug [%s]: Block ended, is_blocking set to false" % player.name)

func log_knockfly_end(player: Node):
	print("Debug [%s]: Knockfly ended, transitioning to wakeup" % player.name)

func log_knockfly_stay(player: Node):
	print("Debug [%s]: Health is zero, staying in knockfly" % player.name)

func log_push_back_end(player: Node):
	print("Debug [%s]: Attacker push_back ended" % player.name)

func log_block_success(player: Node, blockstun_duration: float):
	print("Debug [%s]: Ordinary block successful, blockstun duration %s" % [player.name, blockstun_duration])

func log_special_hit(player: Node):
	print("Debug [%s]: Special move hit, triggering knockfly" % player.name)

func log_ground_hitstun(player: Node, duration: float, damage: float):
	print("Debug [%s]: Ground hitstun triggered, duration %s, damage %s" % [player.name, duration, damage])

func log_air_hit_knockfly(player: Node):
	print("Debug [%s]: Air hit by normal attack, triggering knockfly with 40px pushback" % player.name)

func log_hitstun_no_healthbar(player: Node):
	print("Warning [%s]: No healthbar, hitstun triggered without damage" % player.name)

func log_knockfly_taken(player: Node):
	print("Debug [%s]: Knockfly taken, knockfly_timer set to 0.75" % player.name)

func log_proximity_detected(player: Node, other_player: Node):
	print("Debug [%s]: Hurtbox detected %s's ProximityBox" % [player.name, other_player.name])

func log_proximity_exited(player: Node, other_player: Node):
	print("Debug [%s]: Hurtbox no longer detects %s's ProximityBox" % [player.name, other_player.name])

func log_proximity_block(player: Node):
	print("Debug [%s]: Proximity block triggered" % player.name)

func log_corner_push(player: Node, duration: float, velocity_x: float):
	print("Debug [%s]: Corner push triggered, duration %s, velocity.x=%s" % [player.name, duration, velocity_x])

func log_spnk_length(player: Node, length: float):
	print("Debug [%s]: Spnk length detected: %.2fs" % [player.name, length])

func _get_collision_layer_indices(value: int) -> Array:
	var indices = []
	for i in range(32):
		if value & (1 << i):
			indices.append(i + 1)
	return indices
