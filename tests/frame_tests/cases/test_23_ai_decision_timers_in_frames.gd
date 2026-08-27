extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1 收尾：AI 決策計時器（decision_cooldown / commitment / opponent-search）
## 必須是 int 物理幀，與渲染幀率、Engine.time_scale 脫鉤。
##
## 舊版：`decision_cooldown`、`commitment_timer` 以 _process 的真實 delta 在
## 每個 physics tick 扣一次 —— 同一個 0.033s 冷卻在 60fps 渲染約 2-3 tick、
## 在 headless 高速 _process 下完全另一回事。幀制後：種子只經
## Movement.seconds_to_frames_nearest 換算一次，之後每 tick 恰 -1。
##
## 本用例用同步直呼 _compute_ai_input()（繞過 per-frame 快取）把 LAYER 3 冷卻
## 路徑的「每幀 -1、歸零後下一幀重新決策並重種」釘死，不受玩家狀態機排程干擾。

func run() -> bool:
	await await_frames(10)
	teleport_x(p1, 550.0)
	teleport_x(p2, 1050.0)
	await await_frames(2)

	var cpu = world.get_node_or_null("CPUController")
	check(cpu != null, "world 應有 CPUController")
	if cpu == null:
		return not has_failures()
	cpu.toggle_ai_a()
	await await_frames(2)

	var ai = p1.get_node_or_null("AIBehavior")
	check(ai != null and ai.ai_enabled, "P1 AIBehavior 應已啟用")
	if ai == null:
		return not has_failures()

	# 型別不變量：三個計時器都要是 int 物理幀
	check(typeof(ai.decision_cooldown_frames) == TYPE_INT,
		"decision_cooldown_frames 必須是 int，實為 %s" % type_string(typeof(ai.decision_cooldown_frames)))
	check(typeof(ai.commitment_frames) == TYPE_INT,
		"commitment_frames 必須是 int，實為 %s" % type_string(typeof(ai.commitment_frames)))
	check(typeof(ai.opponent_search_frames) == TYPE_INT,
		"opponent_search_frames 必須是 int，實為 %s" % type_string(typeof(ai.opponent_search_frames)))

	# 固定決策間隔 0.05s → 6 物理幀（0.05×120）
	ai.decision_interval_override = 0.05

	# 進入「只有冷卻、無承諾」的狀態，直呼 4 次 _compute：3→2→1→0→重新決策重種 6
	ai.commitment_frames = 0
	ai.current_committed_action = ""
	ai.committed_input = {}
	ai.decision_cooldown_frames = 3

	ai._compute_ai_input()
	check(ai.decision_cooldown_frames == 2, "冷卻每呼一次應恰 -1（3→2），實為 %d" % ai.decision_cooldown_frames)
	ai._compute_ai_input()
	check(ai.decision_cooldown_frames == 1, "冷卻應繼續 -1（2→1），實為 %d" % ai.decision_cooldown_frames)
	ai._compute_ai_input()
	check(ai.decision_cooldown_frames == 0, "冷卻歸零時不得變負數，實為 %d" % ai.decision_cooldown_frames)

	# 冷卻結束那一幀落入 LAYER 4 新決策：重新承諾 + 依 override 重種 6 幀
	ai._compute_ai_input()
	check(ai.commitment_frames >= 1, "新決策應建立 >=1 幀的承諾，實為 %d" % ai.commitment_frames)
	check(ai.decision_cooldown_frames == 6,
		"override 0.05s 應種子 6 物理幀（round(0.05×120)），實為 %d" % ai.decision_cooldown_frames)
	ai.decision_interval_override = 0.0
	return not has_failures()
