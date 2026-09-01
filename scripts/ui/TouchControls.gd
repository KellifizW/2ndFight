## TouchControls.gd
## 觸控 UI 控制面板（操控 Player A）。
##
## 佈局：
##   - 左下：虛擬十字鍵（上 = 跳躍、下 = 蹲下、左/右 = 移動），
##           以 Input.action_press / action_release 模擬 Player A 的鍵盤輸入。
##   - 右下：4 個圓形快速招式按鈕 SPM1～SPM4，
##           直接呼叫 Player A 的 MoveSet 出招（與鍵盤 spmove1/2/3 + super 對應）。
##
## 快速招式對應（與 PlayerController.resolve_attack_type / MoveSet._handle_input 一致）：
##   SPM1：DAV=powerkk、DEN=spnk、WOO=214K
##   SPM2：fireball（DAV / DEN）
##   SPM3：DAV=dp、DEN=hdk、WOO=623K
##   SPM4：super（DAV）
extends Control

# ── 外觀配色 ──────────────────────────────────────────────────
const CIRCLE_COLOR := Color(0.12, 0.5, 0.86, 0.5)
const CIRCLE_COLOR_HOVER := Color(0.2, 0.62, 0.98, 0.7)
const CIRCLE_COLOR_PRESSED := Color(0.32, 0.8, 1.0, 0.85)
const DPAD_COLOR := Color(0.2, 0.2, 0.24, 0.45)
const DPAD_COLOR_HOVER := Color(0.3, 0.3, 0.36, 0.65)
const DPAD_COLOR_PRESSED := Color(0.55, 0.55, 0.6, 0.85)

# ── 尺寸（設計解析度 1280×720）──────────────────────────────
const SKILL_DIAMETER: int = 92
const SKILL_GAP: int = 16
const SKILL_MARGIN_RIGHT: int = 24
const SKILL_MARGIN_BOTTOM: int = 24

const DPAD_DIAMETER: int = 64
const DPAD_GAP: int = 12
const DPAD_CENTER := Vector2(120.0, 620.0)

var player_a: Player = null

func _ready() -> void:
	# 面板本身不攔截滑鼠，讓按鈕自行接收輸入。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_quick_skill_buttons()
	_build_dpad()

# ── 取得 Player A（動態生成，可能晚於本 UI 就緒）──────────────
func _get_player_a() -> Player:
	if player_a != null and is_instance_valid(player_a):
		return player_a
	player_a = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and p.seat == "player_a":
			player_a = p
			break
	return player_a

# ── 圓形按鈕建立（共用樣式）──────────────────────────────────
func _make_circle_button(btn_text: String, diameter: int, font_size: int, palette: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(diameter, diameter)
	btn.size = Vector2(diameter, diameter)
	btn.text = btn_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))

	var radius: int = int(diameter / 2)
	btn.add_theme_stylebox_override("normal", _circle_stylebox(palette["normal"], radius))
	btn.add_theme_stylebox_override("hover", _circle_stylebox(palette["hover"], radius))
	btn.add_theme_stylebox_override("pressed", _circle_stylebox(palette["pressed"], radius))
	btn.add_theme_stylebox_override("focus", _circle_stylebox(palette["normal"], radius))
	return btn

func _circle_stylebox(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb

# ── 右下：4 個圓形快速招式按鈕 ────────────────────────────────
func _build_quick_skill_buttons() -> void:
	var labels: Array[String] = ["SPM1", "SPM2", "SPM3", "SPM4"]
	var palette: Dictionary = {
		"normal": CIRCLE_COLOR,
		"hover": CIRCLE_COLOR_HOVER,
		"pressed": CIRCLE_COLOR_PRESSED,
	}
	# 2×2 網格，貼齊右下角。
	for i in labels.size():
		var col: int = i % 2
		var row: int = int(i / 2)
		var pos := Vector2(
			1280.0 - SKILL_MARGIN_RIGHT - (2 - col) * SKILL_DIAMETER - (1 - col) * SKILL_GAP,
			720.0 - SKILL_MARGIN_BOTTOM - (2 - row) * SKILL_DIAMETER - (1 - row) * SKILL_GAP
		)
		var btn := _make_circle_button(labels[i], SKILL_DIAMETER, 16, palette)
		btn.position = pos
		# 用 button_down 讓出招在「按下」當下就觸發（格鬥遊戲需要即時反應）。
		btn.button_down.connect(_on_skill_pressed.bind(i + 1))
		add_child(btn)

func _on_skill_pressed(slot: int) -> void:
	var pa: Player = _get_player_a()
	if pa == null:
		return
	# AI 操控時無視觸控按鈕（與鍵盤路徑在 is_ai_controlled 時不錄輸入一致）。
	if pa.is_ai_controlled:
		return
	var ms = pa.move_set
	if ms == null:
		return

	match slot:
		1:
			match pa.character_id:
				"DAV":
					ms.start_powerkk()
				"DEN":
					ms.start_spnk()
				"WOO":
					ms.start_214K()
		2:
			# WOO 沒有火球場景（ResourcePreloader 只提供 DAV/DEN），僅 DAV/DEN 可用。
			if pa.character_id in ["DAV", "DEN"]:
				ms.start_fireball()
		3:
			match pa.character_id:
				"DAV":
					ms.start_dp()
				"DEN":
					ms.start_hdk()
				"WOO":
					ms.start_623K()
		4:
			# super 目前只有 DAV 註冊在 move_library。
			if ms.has_move_id("super"):
				ms.start_super()

# ── 左下：虛擬十字鍵（上/下/左/右）────────────────────────────
func _build_dpad() -> void:
	var palette: Dictionary = {
		"normal": DPAD_COLOR,
		"hover": DPAD_COLOR_HOVER,
		"pressed": DPAD_COLOR_PRESSED,
	}
	# [文字, 動作名稱, 位置]
	var pad_buttons: Array = [
		["▲", "jump", Vector2(DPAD_CENTER.x - DPAD_DIAMETER / 2.0, DPAD_CENTER.y - DPAD_DIAMETER - DPAD_GAP)],
		["▼", "crouch", Vector2(DPAD_CENTER.x - DPAD_DIAMETER / 2.0, DPAD_CENTER.y + DPAD_GAP)],
		["◀", "move_left", Vector2(DPAD_CENTER.x - DPAD_DIAMETER - DPAD_GAP, DPAD_CENTER.y - DPAD_DIAMETER / 2.0)],
		["▶", "move_right", Vector2(DPAD_CENTER.x + DPAD_GAP, DPAD_CENTER.y - DPAD_DIAMETER / 2.0)],
	]
	for entry in pad_buttons:
		var btn := _make_circle_button(entry[0], DPAD_DIAMETER, 24, palette)
		btn.position = entry[2]
		var action: String = entry[1]
		btn.button_down.connect(_on_dpad_down.bind(action))
		btn.button_up.connect(_on_dpad_up.bind(action))
		add_child(btn)

func _on_dpad_down(action: String) -> void:
	var pa: Player = _get_player_a()
	if pa == null or pa.is_ai_controlled:
		return
	Input.action_press(action)

func _on_dpad_up(action: String) -> void:
	Input.action_release(action)
