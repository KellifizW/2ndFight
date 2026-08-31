extends "res://tests/frame_tests/frame_test_case.gd"
## 地面煙霧 / 火花特效（VFXSmoke，AnimationPlayer + AnimatedSprite2D 呈現）的契約：
##   1. **前衝**生成 dashsmoke、**後衝**生成 bdashsmoke（仿照前衝煙）。
##   2. 特效生成在「事件那一刻的世界座標」，之後**不跟著身體移動**。
##   3. 特效是一次性的：播完自己 queue_free()；沒觸發時 world 的直接子節點裡
##      不該有任何「非模板」特效節點。
##   4. **著地煙 / 跳起煙是遊戲全局特效**：任何角色（frame runner 用 DAV/DEN，
##      不是 WOO）著地生成 land_smoke、離地生成 vjumpsmoke。
##   5. 編輯器直覺化契約：`world.tscn` 的 `VFXLayer/SmokeVFX` 是掛在場景上的
##      特效模板（`is_template = true`，執行期不可見、不播放、不自毀）；
##      生成出來的特效從這份模板 `duplicate()`，所以在編輯器對模板做的調整
##      （節點大小 / 位置 / AnimationPlayer 動畫）會直接反映到遊戲中的特效。
##
## 為什麼需要這個用例：
## 舊版把 VFX 節點常駐在角色底下，煙會跟著身體跑、每個行動共用同一節點、
## sprite 停在某一幀導致「煙永遠存在」；另一版則把特效完全藏在程式裡
## （world.tscn 看不到任何節點），美術無從下手。本用例同時釘死
## 「一次性的世界座標特效」與「world.tscn 可見可調的模板」兩端。
##
## 注意：runner 生成的對戰角色是 DAV vs DEN（兩者場景都已內建 DashSmokePoint
## 作為生成點微調），所以著地煙的全局性直接 observable。

## 煙霧動畫總長約 0.3～0.6 秒。給寬鬆上限，動畫節奏被調整時用例不會跟著紅。
const SMOKE_MAX_LIFETIME_FRAMES: int = 600

func run() -> bool:
	await await_frames(5)

	# ── 契約 1：角色場景的生成點 Marker2D（所有角色統一內建）──
	check(_scene_has_marker("res://characters/WOO.tscn"), "WOO 場景應該有 DashSmokePoint")
	check(_scene_has_marker("res://characters/DAV.tscn"), "DAV 場景應該有 DashSmokePoint")
	check(_scene_has_marker("res://characters/DEN.tscn"), "DEN 場景應該有 DashSmokePoint")

	# ── 契約 2：world.tscn 掛了可編輯的特效模板（所見即所得的來源）──
	_check_world_template()

	# ── 契約 3：呈現結構 —— AnimationPlayer 具備三支全局動畫 ──
	_check_animation_player_presentation()

	# ── 沒被觸發的特效節點必須不可見（「煙永遠存在」的根因）──
	var idle: Node = load("res://assets/vfx/vfx.tscn").instantiate()
	world.add_child(idle)
	await await_frames(2)
	check(not idle.visible, "沒有被觸發的煙霧節點不應該是可見的")
	idle.queue_free()
	await await_frames(2)

	check(_count_smokes() == 0, "未觸發任何行動時，world 底下不該有（非模板）特效節點")

	# ── 前衝：應該生成恰好一團煙，而且煙不跟著身體跑 ──
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
	check(not smoke.is_template, "生成出來的特效副本不應該是模板")
	check(smoke.get_parent() == world, "煙霧應該掛在 world 底下（而不是角色底下）")
	check(not p1.is_ancestor_of(smoke), "煙霧不應該是角色的子節點")
	check(abs(smoke.global_position.x - x_before_dash) < 60.0,
		"煙霧應該生成在發動前衝的位置附近（發動時 x=%.1f，煙霧 x=%.1f）" % [x_before_dash, smoke.global_position.x])

	var smoke_x: float = smoke.global_position.x
	var smoke_y: float = smoke.global_position.y
	# 再推進 10 個物理幀：角色應該已經衝出去 ~175px，煙必須原地不動。
	await await_frames(10)
	check(is_instance_valid(smoke), "煙霧動畫應該比前衝的前 10 幀還長")
	if is_instance_valid(smoke):
		check(is_equal_approx(smoke.global_position.x, smoke_x) \
				and is_equal_approx(smoke.global_position.y, smoke_y),
			"煙霧不應該跟著身體移動（原 (%.1f, %.1f)，現 (%.1f, %.1f)）" % [
				smoke_x, smoke_y, smoke.global_position.x, smoke.global_position.y])
	check(abs(px(p1) - smoke_x) > 100.0,
		"角色應該已經離開煙霧位置（現在 x=%.1f，煙霧 x=%.1f）" % [px(p1), smoke_x])

	# ── 播放期間 sprite 真的有逐幀推進 + 播完自行 queue_free ──
	var sprite: Node = smoke.get_node_or_null("AnimatedSprite2D") if is_instance_valid(smoke) else null
	var first_frame: int = -1
	if sprite != null and is_instance_valid(sprite):
		first_frame = sprite.frame
	var frame_changed: bool = false
	var freed: bool = false
	for i in SMOKE_MAX_LIFETIME_FRAMES:
		if not frame_changed and sprite != null and is_instance_valid(sprite) \
				and sprite.frame != first_frame:
			frame_changed = true
		if _count_smokes() == 0:
			freed = true
			break
		await await_frames(1)
	check(freed, "煙霧播完後應該自行 queue_free()，不該常駐在場景樹裡")
	check(frame_changed,
		"煙霧 AnimatedSprite2D 的 frame 應該在播放期間真的推進（AnimationPlayer 沒有驅動動畫？）")

	# ── 後衝：應該生成恰好一團 bdashsmoke（仿照前衝煙）──
	var back_action: String = "move_left" if p1.facing_direction > 0 else "move_right"
	await tap(back_action)
	await await_frames(1)
	Input.action_press(back_action)
	# [TEMP DIAG] 捕捉雙擊檢測狀態（綠了就刪）—— 在既有等待迴圈內逐幀取 meta，
	# 不額外 await，避免改變時序。
	var _dash_diag: Array = []
	var backdash_started: bool = false
	for _df in 8:
		await await_frames(1)
		if _df < 5 and p1.has_meta("diag_dash_f"):
			_dash_diag.append("f%s{dir=%s can=%s neutral=%s pending=%s last=%s floor=%s dsh=%s bds=%s blk=%s prox=%s btype=%s}" % [
				p1.get_meta("diag_dash_f"), p1.get_meta("diag_dash_input_dir"),
				p1.get_meta("diag_dash_can"), p1.get_meta("diag_dash_neutral"),
				p1.get_meta("diag_dash_pending"), p1.get_meta("diag_dash_last"),
				p1.get_meta("diag_dash_on_floor"), p1.get_meta("diag_dash_dashing"),
				p1.get_meta("diag_dash_bdashing"), p1.get_meta("diag_dash_blocking"),
				p1.get_meta("diag_dash_prox"), p1.get_meta("diag_dash_block_type")])
		if me.is_backdashing:
			backdash_started = true
			break
	Input.action_release(back_action)
	check(backdash_started, "後衝應該被觸發 DIAG=" + " ".join(_dash_diag))
	await await_frames(10)
	var back_smokes: Array = _find_smokes()
	check(back_smokes.size() == 1, "後衝應該生成恰好 1 團 bdashsmoke，實為 %d 團" % back_smokes.size())
	if not back_smokes.is_empty():
		check((back_smokes[0] as VFXSmoke).animation_name == VFXSmoke.BDASH_ANIMATION,
			"後衝特效應該播放 \"%s\" 動畫" % String(VFXSmoke.BDASH_ANIMATION))
		check(back_smokes[0].get_parent() == world, "後衝煙霧也該掛在 world 底下、不跟著角色")
	var backdash_ended: bool = await wait_until(func(): return not me.is_backdashing, 90)
	check(backdash_ended, "後衝應該在 90 物理幀內結束")
	# 等後衝煙播完消失，別把殘留煙算進下一段的著地煙數量。
	var back_smoke_gone: bool = await wait_until(func(): return _count_smokes() == 0, SMOKE_MAX_LIFETIME_FRAMES)
	check(back_smoke_gone, "後衝煙霧播完後應該自行消失")

	# ── 跳起煙：離地那一瞬間應該生成 vjumpsmoke（全局特效）──
	await tap("jump")
	var vjump_started: bool = await wait_until(func(): return _count_smokes() > 0, 30)
	check(vjump_started, "跳起時應該生成一團 vjumpsmoke")
	if vjump_started:
		var jump_smokes: Array = _find_smokes()
		if not jump_smokes.is_empty():
			check((jump_smokes[0] as VFXSmoke).animation_name == VFXSmoke.VJUMP_ANIMATION,
				"跳起特效應該播放 \"%s\" 動畫" % String(VFXSmoke.VJUMP_ANIMATION))
			check(jump_smokes[0].get_parent() == world, "跳起煙霧也該掛在 world 底下、不跟著角色")
		# 等跳起煙播完消失，別把殘留煙算進下一段的著地煙數量。
		var jump_smoke_gone: bool = await wait_until(func(): return _count_smokes() == 0, SMOKE_MAX_LIFETIME_FRAMES)
		check(jump_smoke_gone, "跳起煙霧播完後應該自行消失")

	# ── 跳躍著地：全局特效 —— 任何角色（這裡是 DAV）都該生成一團著地煙 ──
	var landed: bool = await wait_until(func(): return me.is_on_floor() and me.is_landing, 360)
	check(landed, "跳躍後應該著地並進入 landing 狀態")
	await await_frames(2)
	var landing_smokes: Array = _find_smokes()
	check(landing_smokes.size() == 1, "任何角色著地都應該生成 1 團著地煙（全局特效），實為 %d 團" % landing_smokes.size())
	if not landing_smokes.is_empty():
		var land_smoke: Node = landing_smokes[0]
		check(land_smoke.animation_name == VFXSmoke.LANDING_ANIMATION,
			"著地特效應該播放 \"%s\" 動畫" % String(VFXSmoke.LANDING_ANIMATION))
		check(land_smoke.get_parent() == world, "著地煙霧也該掛在 world 底下、不跟著角色")
		var smoke_gone: bool = await wait_until(func(): return _count_smokes() == 0, SMOKE_MAX_LIFETIME_FRAMES)
		check(smoke_gone, "著地煙霧播完後應該自行消失")

	return not has_failures()


## 驗證 world.tscn 的特效層與模板：
##   - World 底下有 VFXLayer（Node2D）與 VFXLayer/SmokeVFX（vfx.tscn 實例）
##   - 模板 is_template = true、執行期不可見、註冊在 vfx_smoke_template 群組
##   - 生成副本走模板 duplicate()：模板上的調整（這裡用根節點 scale 驗證）
##     會原樣帶進執行期特效
func _check_world_template() -> void:
	var layer: Node = world.get_node_or_null("VFXLayer")
	check(layer != null and layer is Node2D, "world.tscn 應該掛一個 VFXLayer（Node2D）特效層")
	var template: Node = world.get_node_or_null("VFXLayer/SmokeVFX")
	if check(template is VFXSmoke, "VFXLayer 底下應該實例化 vfx.tscn 作為可編輯的特效模板（SmokeVFX）"):
		var tmpl := template as VFXSmoke
		check(tmpl.is_template, "world.tscn 裡那份 SmokeVFX 模板必須勾選 is_template = true")
		check(not tmpl.visible, "模板在執行期不應該顯示在畫面上")
		check(world.get_tree().get_first_node_in_group(&"vfx_smoke_template") == tmpl,
			"模板應該註冊在 vfx_smoke_template 群組（spawn_animation 靠它複製）")
		# 所見即所得：模板 scale → 副本 scale（僅 X 依面向翻號）
		var saved_scale: Vector2 = tmpl.scale
		tmpl.scale = Vector2(1.5, 1.5)
		var probe: VFXSmoke = VFXSmoke.spawn(world, Vector2(500, 500), 1.0)
		check(probe != null, "VFXSmoke.spawn 應該成功生成副本")
		if probe != null:
			check(probe != tmpl and probe.is_inside_tree(), "副本應該進入場景樹")
			check(is_equal_approx(probe.scale.x, 1.5) and is_equal_approx(probe.scale.y, 1.5),
				"模板上調整的根縮放應該帶進生成的特效（所見即所得）")
			probe.queue_free()
		tmpl.scale = saved_scale


## 驗證特效場景的呈現結構（vfx.tscn）：
##   - 有 AnimationPlayer 子節點，且存在 smoke / bdashsmoke / vjumpsmoke /
##     land_smoke / hit_spark_m 動畫
##   - 有 AnimatedSprite2D（frame / offset / scale 等 track 都挂在它上面調）
func _check_animation_player_presentation() -> void:
	var instance: Node = load("res://assets/vfx/vfx.tscn").instantiate()
	if instance == null:
		check(false, "載入 res://assets/vfx/vfx.tscn 失敗")
		return
	var player: Node = instance.get_node_or_null("AnimationPlayer")
	check(player != null and player is AnimationPlayer,
		"特效場景應該由 AnimationPlayer 子節點驅動（逐格特效可調的前提）")
	if player != null and player is AnimationPlayer:
		var animation_player: AnimationPlayer = player
		for anim in [VFXSmoke.ANIMATION, VFXSmoke.BDASH_ANIMATION,
				VFXSmoke.VJUMP_ANIMATION, VFXSmoke.LANDING_ANIMATION, VFXSmoke.MEDIUM_HIT_ANIMATION]:
			check(animation_player.has_animation(anim),
				"AnimationPlayer 應該有 \"%s\" 動畫（所有角色共用的全局特效）" % String(anim))
	check(instance.get_node_or_null("AnimatedSprite2D") != null,
		"特效場景應該有 AnimatedSprite2D 作為顯示載體")
	instance.free()

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

## world 底下「目前活著」的特效節點。
## 只看 world 的直接子節點、且排除 is_template 的模板：
##   - VFXLayer/SmokeVFX（編輯器模板）不該被算進「觸發生成」的數量；
##   - ResourcePreloader 的預熱實例掛在它自己底下，也不算。
func _find_smokes() -> Array:
	var found: Array = []
	for child in world.get_children():
		if child is VFXSmoke and not (child as VFXSmoke).is_template:
			found.append(child)
	return found

func _count_smokes() -> int:
	return _find_smokes().size()
