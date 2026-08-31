extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 4 收攏：人類與 AI 兩條輸入路徑在「check_cancel 看了什麼」這件事上對齊。
##
## 為什麼需要這個用例：
## Stage 2 切片 2 披露的 finding #3 —— `check_cancel(input_data.attack_type, ...)`
## 對 AI 角色永遠是 "none"，所以命中確認取消（hit-confirm cancel）對 CPU 失效。
## 根本原因：AI 的 `_neutral_input()` / `_compute_ai_input()` 完全沒帶
## `attack_type` 鍵，而 Player.get_input() 把它原封不動地 merge 進 ai_input。
##
## 修法：把 PlayerController 內聯展開的 17 行攻擊優先級鏈抽成 static helper
## `PlayerController.resolve_attack_type(d)`，AI merge 之後由 Player.get_input()
## 補上正確的 attack_type —— 與人類路徑完全共用同一份邏輯。
##
## 本用例驗證兩件事：
##   1. **形狀**：人類與 AI 兩條路徑的 input 字典**都**帶 `attack_type` 鍵
##      （型別為 String），任何缺失都會被斷言。
##   2. **值**：當輸入按鍵一致時，人類與 AI 給出的 attack_type 必須相同。
##      用 `resolve_attack_type()` 直接重算作對照組 —— 它就是 PlayerController
##      內聯的同一條鏈。
##
## 斷言覆蓋：跑固定種子 600 幀隨機按鍵（混 spm1/2/3 + 普通拳腳 + 摔投 + DP），
## 兩個角色都同時觸發人類路徑與 AI 路徑（p1=AI, p2=人類），逐幀比對：
##   - p1.get_input()["attack_type"] == resolve_attack_type(ai_inputs)
##   - p2.get_input()["attack_type"] == resolve_attack_type(play_inputs)
## 同時記錄出現過的 attack_type 分布，要求 ≥ 3 種（否則測試在沒人按鍵時會假綠）。

const FRAMES: int = 600
const SEED: int = 20260832

func run() -> bool:
	await await_frames(10)
	# 距離拉近以確保攻擊 / 受擊能進入樣本
	teleport_x(p1, 520.0)
	teleport_x(p2, 680.0)
	await await_frames(5)

	# 把 p1 切到 AI 控制、p2 保持人類，這樣 get_input() 在同一幀走兩條路徑。
	# （Player 在測試 world 生成時預設都是人類控制 —— 透過 character_data
	# 與 scene 結構；這裡直接覆寫 is_ai_controlled 即可切換路徑。）
	p1.is_ai_controlled = true
	p2.is_ai_controlled = false

	# AI 路徑不讀 InputMap：PlayerController._physics_process 在
	# is_ai_controlled 時直接 return（不錄 buffer），真實 AI 的按鍵由
	# AIBehavior.get_ai_input() 回傳。因此這裡掛一個測試替身 AIBehavior，
	# 每幀回傳「與人類路徑同一套隨機按鍵」的 dict —— 兩條路徑吃相同輸入，
	# attack_type 才有意義可比。（舊寫法把攻擊鍵按進 InputMap 想餵 AI，
	# 實際上 AI 的 PlayerController 根本不錄，p1 永遠收到中立輸入，
	# 於是「AI attack_type 永遠 none」讓覆蓋度斷言必紅。）
	_install_attack_stub(p1)

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	# 攻擊鍵清單（不含方向/跳躍：AI 的移動輸入不進攻擊優先級鏈，
	# 人類路徑的隨機方向還會額外觸發 move-special 偵測，污染對照）。
	var actions: Array = [
		"st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
		"spm1", "spm2", "spm3",
		"throw",
	]
	var p2_actions: Array = [
		"st_lp_p2", "st_mp_p2", "st_hp_p2",
		"st_lk_p2", "st_mk_p2", "st_hk_p2",
		"spmove1_p2", "spmove2_p2", "spmove3_p2",
	]
	var held: Dictionary = {}

	var shape_mismatches: Array = []
	var value_mismatches: Array = []
	var seen_attack_types: Dictionary = {}
	var human_attack_type_count: int = 0
	var ai_attack_type_count: int = 0
	var both_have_key_count: int = 0

	for frame in FRAMES:
		if frame % 4 == 0:
			for action in held.keys():
				Input.action_release(action)
			held.clear()
			_stub_ai.reset_to_neutral()

			# p1（AI 路徑）：隨機選一個攻擊鍵，直接餵進替身 AIBehavior 的
			# input dict（Player.get_input() merge 後會 resolve_attack_type）。
			var a: String = actions[rng.randi_range(0, actions.size() - 1)]
			if a == "spm1":
				_stub_ai.next_input["spm1_pressed"] = true
			elif a == "spm2":
				_stub_ai.next_input["spm2_pressed"] = true
			elif a == "spm3":
				_stub_ai.next_input["spm3_pressed"] = true
			elif a == "throw":
				_stub_ai.next_input["throw_pressed"] = true
			else:
				_stub_ai.next_input[a + "_pressed"] = true

			# p2（人類路徑）：隨機 0～2 個攻擊鍵按進 InputMap
			var n: int = rng.randi_range(0, 2)
			for i in n:
				var b: String = p2_actions[rng.randi_range(0, p2_actions.size() - 1)]
				if not held.has(b):
					Input.action_press(b)
					held[b] = true

		await await_frames(1)

		# ── 1. 形狀：兩條路徑的 input 字典都必須帶 attack_type 鍵 ─────────────
		var ai_input: Dictionary = p1.get_input()
		var human_input: Dictionary = p2.get_input()

		var ai_has_key: bool = ai_input.has("attack_type")
		var human_has_key: bool = human_input.has("attack_type")
		if not ai_has_key and shape_mismatches.size() < 8:
			shape_mismatches.append("frame %d AI: input dict 缺 attack_type 鍵（keys=%s）"
				% [frame, str(ai_input.keys())])
		if not human_has_key and shape_mismatches.size() < 8:
			shape_mismatches.append("frame %d human: input dict 缺 attack_type 鍵（keys=%s）"
				% [frame, str(human_input.keys())])
		if ai_has_key and human_has_key:
			both_have_key_count += 1

		# ── 2. 值：與對照組 resolve_attack_type() 比對 ─────────────────────
		if ai_has_key:
			var ai_actual: String = str(ai_input["attack_type"])
			var ai_expected: String = PlayerController.resolve_attack_type(ai_input)
			if ai_actual != ai_expected and value_mismatches.size() < 8:
				value_mismatches.append("frame %d AI: attack_type='%s' expected='%s' (spm1=%s spm2=%s spm3=%s st_mp=%s st_lp=%s throw=%s)"
					% [frame, ai_actual, ai_expected,
						ai_input.get("spm1_pressed", false), ai_input.get("spm2_pressed", false),
						ai_input.get("spm3_pressed", false), ai_input.get("st_mp_pressed", false),
						ai_input.get("st_lp_pressed", false), ai_input.get("throw_pressed", false)])
			seen_attack_types[ai_actual] = int(seen_attack_types.get(ai_actual, 0)) + 1
			if ai_actual != "none":
				ai_attack_type_count += 1

		if human_has_key:
			var h_actual: String = str(human_input["attack_type"])
			var h_expected: String = PlayerController.resolve_attack_type(human_input)
			if h_actual != h_expected and value_mismatches.size() < 8:
				value_mismatches.append("frame %d human: attack_type='%s' expected='%s' (spm1=%s spm2=%s st_mp=%s st_lp=%s)"
					% [frame, h_actual, h_expected,
						human_input.get("spm1_pressed", false), human_input.get("spm2_pressed", false),
						human_input.get("st_mp_pressed", false), human_input.get("st_lp_pressed", false)])
			seen_attack_types[h_actual] = int(seen_attack_types.get(h_actual, 0)) + 1
			if h_actual != "none":
				human_attack_type_count += 1

	for action in held.keys():
		Input.action_release(action)

	check(shape_mismatches.is_empty(),
		"input 字典形狀不一致（attack_type 鍵缺失）：%s" % " | ".join(shape_mismatches))
	check(value_mismatches.is_empty(),
		"attack_type 值與 resolve_attack_type() 對照組分岔：%s" % " | ".join(value_mismatches))

	# 覆蓋度：600 幀內兩條路徑的 attack_type 至少應該出現 3 種不同值，
	# 否則「全部相等」可能是因為根本沒按鍵。
	var names: Array = []
	for atype in seen_attack_types.keys():
		names.append("%s×%d" % [atype, seen_attack_types[atype]])
	names.sort()
	print("      attack_type 分佈: %s（human 非 none=%d 幀, AI 非 none=%d 幀, 共 %d 幀 兩路徑都帶鍵）"
		% [", ".join(names), human_attack_type_count, ai_attack_type_count, both_have_key_count])
	check(seen_attack_types.size() >= 3,
		"600 幀應至少出現 3 種 attack_type，實際 %d 種（%s）"
		% [seen_attack_types.size(), ", ".join(names)])
	# 至少 AI 路徑要觸發過一次非 none 的 attack_type —— 修法的價值就在這裡。
	check(ai_attack_type_count > 0,
		"AI 路徑的 attack_type 600 幀內應至少一次非 'none'（否則測試的 AI merge 修法無意義）；實際 %d 次"
		% ai_attack_type_count)

	# 收尾：還原人類控制並移除替身（world 會整個釋放，保險起見）。
	p1.is_ai_controlled = false
	if _stub_ai != null and is_instance_valid(_stub_ai):
		_stub_ai.queue_free()

	return not has_failures()

# ── 測試替身 AIBehavior ──────────────────────────────────────────────────
# Player.get_input() 在 is_ai_controlled 時找名為 "AIBehavior" 的子節點
# 呼叫 get_ai_input()，把回傳 dict merge 進默認輸入。替身只回傳測試
# 每 4 幀設定的攻擊按鍵，繞過真實決策層。
class _StubAIBehavior extends Node:
	var next_input: Dictionary = {}
	func get_ai_input() -> Dictionary:
		return next_input.duplicate(true)
	## 測試每 4 幀換新決策時呼叫：重設為中立再逐鍵打開。
	func reset_to_neutral() -> void:
		for k in next_input.keys():
			next_input[k] = false
		next_input["input_dir"] = 0

var _stub_ai: Node = null

func _install_attack_stub(fighter: Node) -> void:
	var real_ai: Node = fighter.get_node_or_null("AIBehavior")
	if real_ai != null:
		real_ai.set_process(false)
		real_ai.set_physics_process(false)
		real_ai.name = "AIBehavior_real"
	_stub_ai = _StubAIBehavior.new()
	_stub_ai.name = "AIBehavior"
	fighter.add_child(_stub_ai)
	_stub_ai.next_input = _neutral_stub_input()

func _neutral_stub_input() -> Dictionary:
	return {
		"input_dir": 0,
		"crouch_pressed": false,
		"jump_pressed": false,
		"st_lp_pressed": false, "st_mp_pressed": false, "st_hp_pressed": false,
		"st_lk_pressed": false, "st_mk_pressed": false, "st_hk_pressed": false,
		"spm1_pressed": false, "spm2_pressed": false, "spm3_pressed": false,
		"dp_pressed": false, "super_pressed": false,
		"block_pressed": false,
		"dash_pressed": false, "backdash_pressed": false,
		"throw_pressed": false,
	}
