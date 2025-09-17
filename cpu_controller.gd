extends Node

@onready var player1: Node = get_parent().get_node("Player1")  # 抓Player1
@onready var player2: Node = get_parent().get_node("Player2")  # 抓Player2

var ai_enabled_p1: bool = false  # Player1的AI開關
var ai_enabled_p2: bool = false  # Player2的AI開關

func _ready():
	# 確認玩家節點存在
	if not player1:
		print("Warning: Player1 not found for CPUController")
	if not player2:
		print("Warning: Player2 not found for CPUController")
	# 設定輸入地圖（如果你還沒加，按下面步驟3加）
	print("Debug: CPUController ready! Press 'C' for P1 AI, 'V' for P2 AI")

func _input(event):
	# 監聽按鍵事件
	if event.is_action_pressed("cpu_p1"):  # 'C' 鍵切換P1 AI
		ai_enabled_p1 = !ai_enabled_p1  # 切換開關
		if player1:
			player1.is_ai_controlled = ai_enabled_p1  # 傳給Player1
			var ai_behavior = player1.get_node("AIBehavior") if player1.has_node("AIBehavior") else null
			if ai_behavior:
				ai_behavior.set_ai_enabled(ai_enabled_p1)  # 傳給AI腳本
			print("Debug: P1 AI %s!" % ("enabled" if ai_enabled_p1 else "disabled"))
	if event.is_action_pressed("cpu_p2"):  # 'V' 鍵切換P2 AI
		ai_enabled_p2 = !ai_enabled_p2
		if player2:
			player2.is_ai_controlled = ai_enabled_p2
			var ai_behavior = player2.get_node("AIBehavior") if player2.has_node("AIBehavior") else null
			if ai_behavior:
				ai_behavior.set_ai_enabled(ai_enabled_p2)
			print("Debug: P2 AI %s!" % ("enabled" if ai_enabled_p2 else "disabled"))
