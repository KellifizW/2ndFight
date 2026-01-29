# ShadowSyncHandler.gd
# 職責: 同步角色陰影的動畫和位置
# 遷移自 Player.gd 的 _sync_shadow_animation() 和 _process()

class_name ShadowSyncHandler extends Node

var parent_player: Player = null
var body_sprite: AnimatedSprite2D = null
var shadow_sprite: AnimatedSprite2D = null

func _ready() -> void:
	parent_player = get_parent() as Player
	if not parent_player:
		push_error("[ShadowSyncHandler] Must be child of Player node!")
		return
	
	# 等待父節點完全初始化
	await get_tree().process_frame
	_initialize_sprites()

func _initialize_sprites() -> void:
	if not parent_player:
		return
	
	body_sprite = parent_player.get_node_or_null("AnimatedSprite2D")
	if not body_sprite:
		push_warning("[ShadowSyncHandler] AnimatedSprite2D not found on Player")
		return
	
	# 陰影節點現在固定用席位名稱
	var shadow_node_name = "PlayerAShadowSprite" if parent_player.seat == "player_a" else "PlayerBShadowSprite"
	var world_node = parent_player.get_parent()
	if world_node:
		shadow_sprite = world_node.get_node_or_null(shadow_node_name)
	
	if not shadow_sprite:
		push_warning("[ShadowSyncHandler] Shadow sprite '%s' not found" % shadow_node_name)

func _process(_delta: float) -> void:
	sync_shadow()

func sync_shadow() -> void:
	"""同步陰影動畫、位置和模糊效果"""
	if not body_sprite or not shadow_sprite or not parent_player:
		return
	
	# 確保陰影有 ShaderMaterial
	if not (shadow_sprite.material is ShaderMaterial):
		return
	
	var mat: ShaderMaterial = shadow_sprite.material
	
	# 同步動畫
	shadow_sprite.animation = body_sprite.animation
	shadow_sprite.frame = body_sprite.frame
	shadow_sprite.offset = body_sprite.offset
	shadow_sprite.flip_h = parent_player.facing_direction < 0
	
	# 同步位置
	shadow_sprite.global_position.x = parent_player.global_position.x
	shadow_sprite.global_position.y = 555 + 120  # 固定在地面下方
	
	# 更新模糊效果（基於高度）
	update_blur(mat)

func update_blur(material: ShaderMaterial) -> void:
	"""根據角色高度更新陰影模糊度"""
	if not parent_player:
		return
	
	if parent_player.is_on_floor():
		material.set_shader_parameter("blur_factor", 0.0)
	else:
		var height = 570.0 - parent_player.global_position.y
		var blur = clamp(height / 200.0, 0.0, 1.0)
		material.set_shader_parameter("blur_factor", blur)
