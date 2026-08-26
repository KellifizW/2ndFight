extends Control

# 對戰畫面下方的兩個觸碰式 AI 開關按鈕。
# 按鈕的 pressed 信號直接連到 CPUController.toggle_ai_a() / toggle_ai_b()，
# 畫面狀態由 CPUController 的 ai_state_changed 信號同步，C / V 鍵切換時也會更新。

@onready var p1_button: Button = $P1AIButton
@onready var p2_button: Button = $P2AIButton

const ON_COLOR := Color(0.22, 0.85, 0.32, 1.0)
const OFF_COLOR := Color(0.85, 0.25, 0.25, 1.0)

func _ready() -> void:
	# 初始為關閉狀態
	_apply_state("player_a", false)
	_apply_state("player_b", false)

func _on_ai_state_changed(seat: String, enabled: bool) -> void:
	_apply_state(seat, enabled)

func _apply_state(seat: String, enabled: bool) -> void:
	if seat == "player_a":
		p1_button.text = "P1 AI: " + ("ON" if enabled else "OFF")
		p1_button.modulate = ON_COLOR if enabled else OFF_COLOR
	elif seat == "player_b":
		p2_button.text = "P2 AI: " + ("ON" if enabled else "OFF")
		p2_button.modulate = ON_COLOR if enabled else OFF_COLOR
