extends Node2D
class_name VFXSmoke

## 一次性地面煙霧 / 命中火花特效（AnimationPlayer 驅動 AnimatedSprite2D 版）。
##
## 【設計】特效屬於「那一瞬間、那個位置」，不屬於角色：
##   1. 掛在角色底下 → 煙會跟著身體移動（前衝時煙追著人跑）。
##   2. 常駐節點 → 沒觸發時也在畫面上。
## 所以這裡是「觸發時生成、播完自己消失」：
##
##     VFXSmoke.spawn(world, 世界座標, 面向)              # 前衝煙（smoke）
##     VFXSmoke.spawn_animation(world, 座標, 動畫名, 面向)  # land_smoke / hit_spark_m
##
## 節點掛在 world 底下（跟 VFXImpact 的 hit/block 特效同一套做法），
## 播完 `queue_free()`，畫面上不留任何東西。
##
## 【編輯器直覺化：模板複製機制】
## `world.tscn` 裡的 `VFXLayer/SmokeVFX` 是本場景的一份實例，其
## `is_template = true`。執行期觸發特效時**不再從 PackedScene 重新
## instantiate**，而是把節點樹上那份模板 `duplicate()` 出來：
##   - 在 world.tscn 裡對 SmokeVFX 做的任何調整（子節點位置 / 大小、
##     AnimationPlayer 動畫 keyframe、AnimatedSprite2D 的 SpriteFrames……）
##     都會原樣帶進每一團生成出來的特效 —— 改什麼、遊戲裡就長什麼樣。
##   - 模板節點本身在執行期永遠不可見、不播放、不自毀，只當複製來源。
##   - 找不到模板時（例如 headless 精簡場景、F6 預覽 vfx.tscn）退回
##     ResourcePreloadManager 預載的 PackedScene（或 load()）直接實例化，
##     行為與舊版一致。
##
## 【呈現方式】`AnimationPlayer` 子節點驅動一個 `AnimatedSprite2D`：
##   `SpriteFrames` 定義三組動畫的圖（smoke.png 3×3 / landsmoke.png 3×3 /
##   spark1.png 3×3），AnimationPlayer 的每個動畫用 frame / animation /
##   offset / scale / modulate 等 track 決定播放節奏與逐格位移、透明度。
##   要改「快慢、每格偏移、淡出」全部在 world.tscn 的 AnimationPlayer
##   動畫軌道上調，不用碰程式。
##
## 【目前動畫清單】（vfx.tscn 的 AnimationPlayer，程式以名字播放）
##   - `smoke`        前衝地面煙（dash smoke）
##   - `land_smoke`   著地煙 —— 遊戲全局：所有角色著地都會噴
##   - `hit_spark_m`  中攻擊命中火花 —— 遊戲全局：所有角色的 *_mp / *_mk 命中都播
##
## 【要調每個角色特效的出現點】角色場景裡 `DashSmokePoint`（Marker2D）
##   的位置就是生成點；沒有 Marker 的角色，著地煙退回角色自身座標。

## AnimationPlayer 裡的動畫名稱（在編輯器改名時要同步改這裡，
## 因為程式用它播放；test_33 也會釘住這個契約）。
const ANIMATION: StringName = &"smoke"

## Alternate one-shot animations stored in the same VFX scene.  Keeping the
## scene shared means newly added sprite-sheet effects are preloaded together
## with dash smoke and do not introduce a first-use hitch.
## Landing smoke and medium-hit spark are GAME-GLOBAL: every fighter uses
## them, they are not gated to a specific character any more.
const LANDING_ANIMATION: StringName = &"land_smoke"
const MEDIUM_HIT_ANIMATION: StringName = &"hit_spark_m"
var animation_name: StringName = ANIMATION

## 標記「世界場景裡的模板」。放在 world.tscn（VFXLayer/SmokeVFX）時勾選；
## 模板只作為執行期 duplicate() 的來源，本身永不顯示、永不自我銷毀。
## 生成出來的特效副本一定被程式重設回 false。
@export var is_template: bool = false

## 模板註冊用的群組名（spawn_animation 靠它找到世界場景上的模板）。
const TEMPLATE_GROUP: StringName = &"vfx_smoke_template"

## 在 ResourcePreloadManager 登記的型別名（預載 + 預熱，見 get_vfx_scene）。
## 只有在世界場景裡找不到模板時才會用到這條備援路徑。
const VFX_TYPE: String = "dash_smoke"
## 預載器不在時（例如單獨執行本場景做預覽）的備援路徑。
const SCENE_PATH: String = "res://assets/vfx/vfx.tscn"

@onready var _player: AnimationPlayer = $AnimationPlayer


## 在世界座標 `pos` 生成一團前衝煙霧並立刻開始播放。
##
## `parent` 請給 world（或任何「不會移動」的特效層）—— 不要給角色，
## 否則煙霧又會跟著身體跑。`facing` 只決定要不要水平鏡像。
static func spawn(parent: Node, pos: Vector2, facing: float = 1.0) -> VFXSmoke:
	return spawn_animation(parent, pos, ANIMATION, facing)

## Spawn one of the one-shot sprite-sheet animations stored in vfx.tscn
## (smoke / land_smoke / hit_spark_m).  The instance is placed under the
## world rather than the fighter so the effect stays at the point where the
## event occurred — every character shares the same effect set (global VFX).
##
## 優先複製 world.tscn 上的模板（編輯器所見即所得），沒有模板才退回
## 預載場景實例化。
static func spawn_animation(parent: Node, pos: Vector2, animation: StringName, facing: float = 1.0) -> VFXSmoke:
	if parent == null:
		return null
	var smoke: VFXSmoke = _duplicate_template(parent)
	if smoke == null:
		var scene: PackedScene = _resolve_scene(parent)
		if scene == null:
			return null
		smoke = scene.instantiate() as VFXSmoke
		if smoke == null:
			push_error("[VFXSmoke] %s 的根節點掛的不是 VFXSmoke 腳本" % SCENE_PATH)
			return null
	# 副本不是模板：要能被播放、播完要能自己消失。
	# （duplicate() 會把模板的群組成員身分一起複製到副本上，副本進入場景
	# 樹時會照舊註冊 —— 由 _ready() 在非模板分支裡退出群組。）
	smoke.is_template = false
	smoke.animation_name = animation
	parent.add_child(smoke)
	smoke.global_position = pos
	# 根節點只負責翻面；大小交給模板（或動畫）裡 AnimatedSprite2D 的 scale。
	# 用「保留絕對值、只翻轉 X 符號」的寫法，編輯器在模板上調好的
	# 根縮放才會原樣帶進副本。
	var flip: float = sign(facing) if facing != 0.0 else 1.0
	var root_scale: Vector2 = smoke.scale
	root_scale.x = flip * absf(root_scale.x)
	smoke.scale = root_scale
	smoke.play_smoke()
	return smoke


## 世界場景（world.tscn → VFXLayer/SmokeVFX）上的模板副本。
## 複製的是「節點樹上的即時狀態」，所以在編輯器存進 world.tscn 的
## 屬性覆蓋（override）也會一起被複製 —— 這正是「看得見、改得動」的重點。
static func _duplicate_template(from_node: Node) -> VFXSmoke:
	var tree: SceneTree = from_node.get_tree()
	if tree == null:
		return null
	# 取「第一個仍是模板」的節點：萬一有尚未退出群組的副本混進來，
	# is_template 篩選保證我們永遠複製的是 world.tscn 上那份原始模板。
	for candidate: Node in tree.get_nodes_in_group(TEMPLATE_GROUP):
		var tmpl := candidate as VFXSmoke
		if tmpl != null and tmpl.is_template and is_instance_valid(tmpl):
			return tmpl.duplicate() as VFXSmoke
	return null


## 沒有模板時退回 ResourcePreloadManager 預載好的場景（零卡頓）；
## 預載器也不在時退回 load()（例如編輯器裡單獨執行本場景預覽）。
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
	if is_template:
		_prepare_template()
		return
	# duplicate() 會把模板所屬的群組一起複製到副本上；副本不是模板，
	# 必須退出群組，否則群組裡會混進「播完就消失」的一次性特效，
	# 後續 spawn 找模板就會不穩。
	if is_in_group(TEMPLATE_GROUP):
		remove_from_group(TEMPLATE_GROUP)
	# 「沒在播 = 畫面上不能有任何東西」。這是舊版「煙永遠存在」的根因：
	# sprite 停在某一幀，節點又一直掛在角色身上，所以隨時都看得到。
	visible = false
	if _player != null and _player.has_animation(animation_name):
		if not _player.animation_finished.is_connected(_on_animation_finished):
			_player.animation_finished.connect(_on_animation_finished)
	# 編輯器裡直接執行本場景（F6 預覽）時自動播一次，方便調特效。
	# 程式 spawn 出來的實例不會走這條（spawn() 自己會呼叫 play_smoke()）。
	if get_parent() is Window:
		play_smoke()


## 模板模式（world.tscn 裡那份 SmokeVFX）：執行期註冊給 spawn_animation，
## 並保證自己「不會」被播到畫面上或被 queue_free。編輯器裡則照常可見
## （visible 屬性在場景檔維持 true，只有執行期 _ready 才隱藏）。
func _prepare_template() -> void:
	visible = false
	if _player != null:
		_player.stop()
	if not is_in_group(TEMPLATE_GROUP):
		add_to_group(TEMPLATE_GROUP)


## 從第 0 幀重新播放目前選定的動畫。
func play_smoke() -> void:
	# 保險：在編輯器裡把動畫改名/刪掉時，寧可報錯也不要
	# 留一個看不見又不會自己消失的節點在場景樹裡。
	if _player == null or not _player.has_animation(animation_name):
		push_error("[VFXSmoke] AnimationPlayer 裡找不到動畫 \"%s\"，特效無法播放" % String(animation_name))
		queue_free()
		return
	visible = true
	_player.play(animation_name)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != animation_name:
		return
	# 播完就消失：特效只在「那個行動發生的時候」存在。
	# （AnimationPlayer 播完非循環動畫會自己停下，不需要再 stop()。）
	visible = false
	queue_free()
