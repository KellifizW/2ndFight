extends Node

# 選角結果。這裡「沒有選擇」保持 null：
# - 直接執行 world.tscn 時，用 world.tscn Inspector 上設定的 Character A / Character B；
# - 進入選角畫面後，CharacterSelect.gd 會把選擇寫進 p1/p2_character。
var p1_character: CharacterData = null
var p2_character: CharacterData = null

func _ready() -> void:
	# 不要在 Autoload _ready() 用 DAV/DEN 預設覆蓋 world.tscn 的編輯器設定。
	# 選角畫面（CharacterSelect.gd._ready()）會自行初始化 p1/p2_character。
	pass
