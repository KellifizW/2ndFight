extends "res://tests/frame_tests/frame_test_case.gd"
## 前衝煙霧（AnimationPlayer 呈現版）的三個不變式：
##   1. **只有前衝**會生成煙霧 —— landing / backdash 都不生成。
##   2. 煙霧生成在「發動那一刻的世界座標」，之後**不跟著身體移動**。
##   3. 煙霧是一次性的：播完自己 queue_free()；沒觸發時畫面上（以及場景樹裡）
##      不該有任何煙霧節點。
##
## 呈現結構契約（本用例同時釘死 AnimationPlayer 這個呈現方式）：
##   - 煙霧場景由 `AnimationPlayer` 子節點呈現：`smoke` 動畫裡有一條
##     value track 驅動 `Sprite2D:texture`（一個 keyframe = smoke.png 一格），
##     如此每格的時序 / 透明度 / 大小 / 偏移才能進編輯器逐格微調。
##   - 場景裡不得再有 `AnimatedSprite2D`（舊 SpriteFrames 呈現法已退役 ——
##     SpriteFrames 只能調「整體 speed + 每幀 duration」，無法加逐格軌道）。
##
## 為什麼需要這個用例：
## 舊版把 VFX 節點常駐在角色底下（`groundsmoke` 子節點），三個症狀全部來自
## 「節點歸屬錯」：(a) 煙跟著身體跑、(b) landing / backdash 也共用同一個節點
## 所以都會噴、(c) sprite 的 frame 停著不動 → 煙永遠存在。這類問題在實戰裡
## 肉眼很難抓（尤其 hitstop 期間），所以用 frame 測試釘死。
##
## 注意：runner 生成的對戰角色是 DAV vs DEN，兩者都刻意**沒有** DashSmokePoint，
## 所以這裡先給 p1 裝一個同名 Marker2D（等價於 WOO 的場景結構），再跑真實的
## double-tap 前衝 / 後衝 / 跳躍著地流程。

## 煙霧動畫總長 0.6 秒（texture track：9 格 keyframe）≈ 72 個物理幀。
## 這裡給寬鬆上限，動畫節奏被調整時用例不會跟著紅。
const SMOKE_MAX_LIFETIME_FRAMES: int = 600

func run() -> bool:
	await await_frames(5)

	# ── 契約：只有放了 DashSmokePoint 的角色才有煙霧 ──
	check(_scene_has_marker("res://characters/WOO.tscn"), "WOO 場景應該有 DashSmokePoint")
	check(not _scene_has_marker("res://characters/DAV.tscn"), "DAV 場景不應該有 DashSmokePoint")
	check(not _scene_has_marker("res://characters/DEN.tscn"), "DEN 場景不應該有 DashSmokePoint")

	# ── 呈現結構契約：AnimationPlayer 驅動 texture track，SpriteFrames 版退役 ──
	_check_animation_player_presentation()

	# ── 沒被觸發的煙霧節點必須不可見（舊版「煙永遠存在」的根因）──
	var idle: Node = load("res://assets/vfx/vfx.tscn").instantiate()
	world.add_child(idle)
	await await_frames(2)
	check(not idle.visible, "沒有被觸發的煙霧節點不應該是可見的")
	idle.queue_free()
	await await_frames(2)

	check(_count_smokes() == 0, "未觸發任何行動時，world 底下不該有煙霧節點")

	# ── 前衝：應該生成恰好一團煙，而且煙不跟著身體跑 ──
	_install_marker(p1)
	var me = p1

	var fwd_action: String = "move_right" if p1.facing_direction > 0 else "move_left"
	var x_before_dash: float = px(p1)
	await tap(fwd_action)
	await await_frames(1)
	Input.action_press(fwd_action)
	var dash_started: bool = await wait_until(func(): return me.is_dashing, 10)
	Input.action_release(fwd_action)
	check(dash_started, "前衝應該被觸發")
	if not dash_started:
		return not has_failures()

	await await_frames(2)
	var smokes: Array = _find_smokes()
	check(smokes.size() == 1, "前衝應該生成恰好 1 團煙霧，實為 %d 團" % smokes.size())
	if smokes.is_empty():
		return not has_failures()

	var smoke: Node = smokes[0]
	check(smoke.get_parent() == world, "煙霧應該掛在 world 底下（而不是角色底下）")
	check(not p1.is_ancestor_of(smoke), "煙霧不應該是角色的子節點")
	check(abs(smoke.global_position.x - x_before_dash) < 60.0,
		"煙霧應該生成在發動前衝的位置附近（發動時 x=%.1f，煙霧 x=%.1f）" % [x_before_dash, smoke.global_position.x])

	var smoke_x: float = smoke.global_position.x
	var smoke_y: float = smoke.global_position.y
	# 再推進 10 個物理幀：角色應該已經衝出去 ~175px，煙必須原地不動。
	await await_frames(10)
	check(is_instance_valid(smoke), "煙霧動畫（0.6s）應該比前衝的前 10 幀還長")
	if is_instance_valid(smoke):
		check(is_equal_approx(smoke.global_position.x, smoke_x) \
				and is_equal_approx(smoke.global_position.y, smoke_y),
			"煙霧不應該跟著身體移動（原 (%.1f, %.1f)，現 (%.1f, %.1f)）" % [
				smoke_x, smoke_y, smoke.global_position.x, smoke.global_position.y])
	check(abs(px(p1) - smoke_x) > 100.0,
		"角色應該已經離開煙霧位置（現在 x=%.1f，煙霧 x=%.1f）" % [px(p1), smoke_x])

	# ── 播放期間 texture 真的有切換 + 播完自行 queue_free ──
	# 逐幀採樣 Sprite2D 的 texture：AnimationPlayer 的 texture track 必須
	# 真的在驅動 sprite（防「動畫播完了、特效卻停在一格」的斷線），
	# 而且播完後節點要離開場景樹。
	var sprite: Node = smoke.get_node_or_null("Sprite2D") if is_instance_valid(smoke) else null
	var first_texture: Resource = null
	if sprite != null and is_instance_valid(sprite) and sprite.texture != null:
		first_texture = sprite.texture
	var texture_changed: bool = false
	var freed: bool = false
	for i in SMOKE_MAX_LIFETIME_FRAMES:
		if not texture_changed and sprite != null and is_instance_valid(sprite) \
				and sprite.texture != null and sprite.texture != first_texture:
			texture_changed = true
		if _count_smokes() == 0:
			freed = true
			break
		await await_frames(1)
	check(freed, "煙霧播完後應該自行 queue_free()，不該常駐在場景樹裡")
	check(texture_changed,
		"煙霧 sprite 的 texture 應該在播放期間真的切換（AnimationPlayer 的 texture track 未驅動 Sprite2D？）")

	# ── 後衝：不該有煙霧 ──
	var back_action: String = "move_left" if p1.facing_direction > 0 else "move_right"
	await tap(back_action)
	await await_frames(1)
	Input.action_press(back_action)
	var backdash_started: bool = await wait_until(func(): return me.is_backdashing, 10)
	Input.action_release(back_action)
	check(backdash_started, "後衝應該被觸發")
	await await_frames(10)
	check(_count_smokes() == 0, "後衝不應該生成煙霧，實為 %d 團" % _count_smokes())
	var backdash_ended: bool = await wait_until(func(): return not me.is_backdashing, 90)
	check(backdash_ended, "後衝應該在 90 物理幀內結束")

	# ── 跳躍著地：不該有煙霧 ──
	await tap("jump")
	var landed: bool = await wait_until(func(): return me.is_on_floor() and me.is_landing, 360)
	check(landed, "跳躍後應該著地並進入 landing 狀態")
	await await_frames(5)
	check(_count_smokes() == 0, "著地不應該生成煙霧，實為 %d 團" % _count_smokes())

	return not has_failures()


## 驗證煙霧場景由 AnimationPlayer 呈現（「逐格可調」的結構契約）：
##   - 有 AnimationPlayer 子節點，且存在 `smoke` 動畫
##   - 該動畫有一條 value track 驅動 `Sprite2D:texture`（一個 keyframe = 一格），
##     keyframe >= 2 且時間非遞減
##   - 場景裡沒有殘留 AnimatedSprite2D（舊 SpriteFrames 呈現法）
func _check_animation_player_presentation() -> void:
	var instance: Node = load("res://assets/vfx/vfx.tscn").instantiate()
	if instance == null:
		check(false, "載入 res://assets/vfx/vfx.tscn 失敗")
		return
	var player: Node = instance.get_node_or_null("AnimationPlayer")
	check(player != null and player is AnimationPlayer,
		"煙霧場景應該由 AnimationPlayer 子節點呈現（逐格特效可調的前提）")
	if player != null and player is AnimationPlayer:
		var animation_player: AnimationPlayer = player
		check(animation_player.has_animation(VFXSmoke.ANIMATION),
			"AnimationPlayer 應該有 \"%s\" 動畫" % String(VFXSmoke.ANIMATION))
		if animation_player.has_animation(VFXSmoke.ANIMATION):
			var anim: Animation = animation_player.get_animation(VFXSmoke.ANIMATION)
			var texture_track: int = -1
			if anim != null:
				for i in anim.get_track_count():
					if anim.get_track_type(i) == Animation.TRACK_VALUE \
							and String(anim.track_get_path(i)) == "Sprite2D:texture":
						texture_track = i
						break
			check(texture_track != -1,
				"\"%s\" 動畫應該有一條驅動 Sprite2D:texture 的 texture track（一個 keyframe = 一格）" % String(VFXSmoke.ANIMATION))
			if texture_track != -1:
				var key_count: int = anim.track_get_key_count(texture_track)
				check(key_count >= 2, "texture track 應該有 >= 2 個 keyframe，實為 %d" % key_count)
				var times_ok: bool = true
				for k in range(1, key_count):
					if anim.track_get_key_time(texture_track, k) < anim.track_get_key_time(texture_track, k - 1):
						times_ok = false
				check(times_ok, "texture track 的 keyframe 時間應該非遞減")
	var old_sprite: bool = false
	for child in instance.get_children():
		if child is AnimatedSprite2D:
			old_sprite = true
	check(not old_sprite, "煙霧場景不應該再有 AnimatedSprite2D（SpriteFrames 呈現法已退役）")
	instance.free()

## 給 player 裝上 WOO 場景裡那個同名 Marker2D（runner 的 DAV/DEN 刻意沒有）。
func _install_marker(player: Node) -> void:
	var marker: Marker2D = Marker2D.new()
	marker.name = "DashSmokePoint"
	player.add_child(marker)
	marker.position = Vector2(0, 100)
	player.dash_smoke_point = marker

## world 底下「目前活著」的煙霧節點。
## 刻意只看 world 的直接子節點：ResourcePreloader 的預熱實例掛在它自己底下，
## 不該被算進來。
func _find_smokes() -> Array:
	var found: Array = []
	for child in world.get_children():
		if child is VFXSmoke:
			found.append(child)
	return found

func _count_smokes() -> int:
	return _find_smokes().size()

## 場景裡有沒有 DashSmokePoint（只 instantiate 不加進樹，_ready 不會跑）。
func _scene_has_marker(scene_path: String) -> bool:
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return false
	var instance: Node = scene.instantiate()
	if instance == null:
		return false
	var found: bool = instance.get_node_or_null("DashSmokePoint") != null
	instance.free()
	return found
