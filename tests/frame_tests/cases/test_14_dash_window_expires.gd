extends "res://tests/frame_tests/frame_test_case.gd"
## The double-tap dash window is 36 physics frames (0.3s at 120 Hz).
## Pressing the second direction after that window must walk, not dash.

func run() -> bool:
	await await_frames(5)
	await tap("move_right")

	# Wait longer than DOUBLE_TAP_TIME (0.3s = 36 physics frames).
	await await_frames(45)

	Input.action_press("move_right")
	await await_frames(6)
	Input.action_release("move_right")

	check(not p1.is_dashing, "逾時後第二次方向輸入不應觸發前衝")
	check(not p1.is_backdashing, "逾時後第二次方向輸入不應觸發後衝")
	check(p1.pending_dash_dir == 0, "dash window 過期後 pending_dash_dir 應清除，實為 %d" % p1.pending_dash_dir)
	check(p1.neutral_timer == 0, "dash window 過期後 neutral_timer 應為 0，實為 %s" % p1.neutral_timer)
	return not has_failures()
