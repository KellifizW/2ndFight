# 初始化工具：自動將特殊招式資源轉換為 MoveSet.special_moves_data export 數組
# 使用方式：
# 1. 在 Editor 控制台或其他地方調用此函數
# 2. 或在某個 _ready() 中調用（邊界情況）

extends Node

const LEGACY_PATHS: Array[String] = [
	"res://data/specials/dav_powerkk.tres",
	"res://data/specials/dav_super.tres",
	"res://data/specials/dav_dp.tres",
	"res://data/specials/den_spnk.tres",
	"res://data/specials/den_hdk.tres",
	"res://data/specials/dav_fireball.tres",
	"res://data/specials/den_fireball.tres"
]

# 調用此函數自動初始化 MoveSet 的 special_moves_data
static func migrate_special_moves_to_export() -> void:
	Debug.log("[InitializeSpecialMovesResources] ========================================")
	Debug.log("[InitializeSpecialMovesResources] 開始遷移特殊招式資源...")
	
	# 需要場景樹中存在 Player 節點
	var tree = Engine.get_main_window().get_tree()
	if tree == null:
		push_error("InitializeSpecialMovesResources: 無法取得場景樹")
		return
	
	var players = []
	if tree.root.get_child(0) is Node:
		var world = tree.root.get_child(0)
		if world.has_node("p1") and world.has_node("p2"):
			players.append(world.get_node("p1"))
			players.append(world.get_node("p2"))
	
	if players.is_empty():
		Debug.log("[InitializeSpecialMovesResources] ⚠️  未找到 Player 節點，請確保遊戲場景已加載")
		return
	
	# 加載所有資源
	var loaded_resources: Array[SpecialMoveData] = []
	for path in LEGACY_PATHS:
		var resource = load(path)
		if resource is SpecialMoveData:
			loaded_resources.append(resource)
			Debug.log("[InitializeSpecialMovesResources] ✅ 已加載: %s (%s)" % [resource.move_id, path])
		else:
			Debug.log("[InitializeSpecialMovesResources] ❌ 找不到或無效: %s" % path)
	
	# 設定每個玩家的 MoveSet
	for player in players:
		if player.has_node("MoveSet"):
			var move_set = player.get_node("MoveSet")
			move_set.special_moves_data = loaded_resources.duplicate()
			move_set._initialize_move_library()
			Debug.log("[InitializeSpecialMovesResources] ✅ %s 的 special_moves_data 已更新 (%d 招)" % [player.name, loaded_resources.size()])
	
	Debug.log("[InitializeSpecialMovesResources] ========================================")
	Debug.log("[InitializeSpecialMovesResources] ✨ 遷移完成！")

# 如果此腳本直接在場景樹中運行，自動執行初始化
func _ready() -> void:
	# 只在編輯器中自動運行（避免遊戲中多次初始化）
	if not Engine.is_editor_hint():
		await get_tree().process_frame
		migrate_special_moves_to_export()
