extends Node2D
class_name VFXSmoke

## 一次性地面煙霧（AnimationPlayer 呈現版）
##
## 【設計】特效屬於「那一瞬間、那個位置」，不屬於角色：
##   1. 掛在角色底下 → 煙會跟著身體移動（前衝時煙追著人跑）。
##   2. 常駐節點 → 沒觸發時也在畫面上（舊版 sprite 的 frame 停著不動，
##      所以煙永遠存在）。
## 所以這裡改成「觸發時生成、播完自己消失」：
##
##     VFXSmoke.spawn(world, 世界座標, 面向)
##
## 節點掛在 world 底下（跟 VFXImpact 的 hit/block 特效同一套做法），
## 播完 `queue_free()`，畫面上不留任何東西。
##
## 【呈現方式】`AnimationPlayer` 子節點驅動一個 `Sprite2D`：
##   `smoke` 動畫的 texture track 一個 keyframe = smoke.png 一格。
##   不用 `AnimatedSprite2D` + SpriteFrames 的原因：SpriteFrames 只能調
##   「整體 speed + 每幀 duration」，無法針對任何一格加軌道；
##   AnimationPlayer 則每一格都是可拖的 keyframe，還可以任意疊加
##   其他 track —— 特效由「動畫」呈現，時序與設定只有一個真相來源。
##
##   動畫時序（與舊 SpriteFrames 版完全一致，9 格總長 0.6 秒）：
##   每格 duration 0.5/1/0.5/1/1.5/1.5/1.5/1/0.5（單位）@ speed 15
##   → keyframe 時間 0, 0.0333, 0.1, 0.1333, 0.2, 0.3, 0.4, 0.5, 0.5667 秒。
##
## 【要改外觀】全部在編輯器裡調，不用碰程式：
##   - 大小：本場景 Sprite2D 的 `scale`
##   - 出現位置：角色場景裡 `DashSmokePoint`（Marker2D）的位置
##   - 快慢/節奏：`AnimationPlayer` 的 `smoke` 動畫 length 與 texture track
##     的 keyframe 時間（keyframe 時間 = 該格開始顯示的時刻）
##   - 逐格微調：在 `smoke` 動畫上加 track（例如 `Sprite2D:modulate`
##     調每格透明度、`Sprite2D:scale` / `Sprite2D:offset` 調每格大小/偏移）
##   - 換圖：重新切割 smoke.png（目前是 3×3 = 9 格）後，把 texture
##     track 的 keyframe 換成新的 AtlasTexture（keyframe 數量跟著格數走）
##
## 【要給新角色加煙霧】在該角色場景裡拖一個名為 `DashSmokePoint` 的
## Marker2D 到腳下想要的位置即可 —— 沒有這個節點的角色不會噴煙。

## AnimationPlayer 裡的動畫名稱（在編輯器改名時要同步改這裡，
## 因為程式用它播放；test_33 也會釘住這個契約）。
const ANIMATION: StringName = &"smoke"
## 在 ResourcePreloadManager 登記的型別名（預載 + 預熱，見 get_vfx_scene）。
const VFX_TYPE: String = "dash_smoke"
## 預載器不在時（例如單獨執行本場景做預覽）的備援路徑。
const SCENE_PATH: String = "res://assets/vfx/vfx.tscn"

@onready var _player: AnimationPlayer = $AnimationPlayer


## 在世界座標 `pos` 生成一團煙霧並立刻開始播放。
##
## `parent` 請給 world（或任何「不會移動」的特效層）—— 不要給角色，
## 否則煙霧又會跟著身體跑。`facing` 只決定要不要水平鏡像。
static func spawn(parent: Node, pos: Vector2, facing: float = 1.0) -> VFXSmoke:
	if parent == null:
		return null
	var scene: PackedScene = _resolve_scene(parent)
	if scene == null:
		return null
	var smoke: VFXSmoke = scene.instantiate() as VFXSmoke
	if smoke == null:
		push_error("[VFXSmoke] %s 的根節點掛的不是 VFXSmoke 腳本" % SCENE_PATH)
		return null
	parent.add_child(smoke)
	smoke.global_position = pos
	# 根節點只負責翻面；大小交給場景裡 Sprite2D 自己的 scale。
	smoke.scale = Vector2(sign(facing) if facing != 0.0 else 1.0, 1.0)
	smoke.play_smoke()
	return smoke


## 優先用 ResourcePreloadManager 預載好的場景（零卡頓）；
## 預載器不在時退回 load()（例如編輯器裡單獨執行本場景預覽）。
static func _resolve_scene(from_node: Node) -> PackedScene:
	var tree: SceneTree = from_node.get_tree()
	if tree != null:
		var preloader: Node = tree.get_first_node_in_group("resource_preloader")
		if preloader != null and preloader.has_method("get_vfx_scene"):
			var preloaded: PackedScene = preloader.get_vfx_scene(VFX_TYPE)
			if preloaded != null:
				return preloaded
	return load(SCENE_PATH)


func _ready() -> void:
	# 「沒在播 = 畫面上不能有任何東西」。這是舊版「煙永遠存在」的根因：
	# sprite 停在某一幀，節點又一直掛在角色身上，所以隨時都看得到。
	visible = false
	if _player != null and _player.has_animation(ANIMATION):
		if not _player.animation_finished.is_connected(_on_animation_finished):
			_player.animation_finished.connect(_on_animation_finished)
	# 編輯器裡直接執行本場景（F6 預覽）時自動播一次，方便調特效。
	# 程式 spawn 出來的實例不會走這條（spawn() 自己會呼叫 play_smoke()）。
	if get_parent() is Window:
		play_smoke()


## 從第 0 幀重新播放。
func play_smoke() -> void:
	# 保險：在編輯器裡把動畫改名/刪掉時，寧可報錯也不要
	# 留一個看不見又不會自己消失的節點在場景樹裡。
	if _player == null or not _player.has_animation(ANIMATION):
		push_error("[VFXSmoke] AnimationPlayer 裡找不到動畫 \"%s\"，煙霧無法播放" % String(ANIMATION))
		queue_free()
		return
	visible = true
	# play() 從時間 0 開始；texture track 的第 0 個 keyframe 在播放開始後
	# 第一幀套用（Sprite2D 的預設 texture 就是第 1 格，不會有空白幀）。
	_player.play(ANIMATION)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != ANIMATION:
		return
	# 播完就消失：特效只在「那個行動發生的時候」存在。
	# （AnimationPlayer 播完非循環動畫會自己停下，不需要再 stop()。）
	visible = false
	queue_free()
