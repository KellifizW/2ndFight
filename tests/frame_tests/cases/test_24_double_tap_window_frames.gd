extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1 收尾：PlayerController 的雙擊窗口從「_process 真實秒」改為
## 「_physics_process 物理幀」後，窗口必須恰好涵蓋 36 個物理 tick，
## 且每 tick 遞減 1、歸零那一幀清除 last_input_dir。
##
## 舊版行為随渲染幀率浮動（60fps/144fps/headless 各自不同）、hitstop 時
## 再被 time_scale 縮放，是「同一隻手按兩下，dash 觸發與否看環境」的根源。
##
## 計時點：tap 那一 tick，Parent（Player）先讀輸入種子 36，Child（PlayerController）
## 同 tick 尾遞減 → 測試在 tick 边界觀察到的首值為 35，之後每 tick -1。

func run() -> bool:
	await await_frames(5)
	var controller = p1.get_node_or_null("PlayerController")
	check(controller != null, "P1 應有 PlayerController")
	if controller == null:
		return not has_failures()

	check(typeof(controller.double_tap_frames) == TYPE_INT,
		"double_tap_frames 必須是 int，實為 %s" % type_string(typeof(controller.double_tap_frames)))
	check(controller.double_tap_frames == 0, "初始不應有窗口")

	Input.action_press("move_right")
	await await_frames(1)
	Input.action_release("move_right")
	# tick A：種子 36（get_input_data）→ 同 tick 遞減 → 35
	check(controller.double_tap_frames == 35,
		"首次點按 tick 後應剩 35（36-1），實為 %d" % controller.double_tap_frames)

	await await_frames(33)
	check(controller.double_tap_frames == 2, "34 個 tick 後應剩 2，實為 %d" % controller.double_tap_frames)

	await await_frames(1)
	check(controller.double_tap_frames == 1, "35 個 tick 後窗口仍開（最後 1 幀），實為 %d" % controller.double_tap_frames)

	await await_frames(1)
	check(controller.double_tap_frames == 0, "第 36 個 tick 窗口應恰好歸零，實為 %d" % controller.double_tap_frames)
	check(controller.last_input_dir == 0, "窗口歸零同幀應清除 last_input_dir，實為 %d" % controller.last_input_dir)
	return not has_failures()
