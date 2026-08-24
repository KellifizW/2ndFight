extends "res://tests/frame_tests/frame_test_case.gd"
## 走路移動：持續按住方向 24 物理幀（0.2 秒）
## 期望位移 = walk_speed(360 px/s) × 0.2s = 72 px（允許 60~84 容差）
## 同時確認：單一持續按住不會觸發 dash（dash 需要 double-tap）

func run() -> bool:
	await await_frames(10)  # 穩定
	var x0: float = px(p1)

	await hold("move_right", 24)

	check(p1.is_dashing == false, "持續按住不應該觸發 dash")
	check(p1.is_backdashing == false, "持續按住不應該觸發 backdash")
	var dx: float = px(p1) - x0
	check(dx >= 60.0 and dx <= 84.0, "P1 位移 %.1f px，期望 ~72 px (60..84)" % dx)
	check(abs(p1.facing_direction - 1.0) < 0.001, "面向應保持 +1，實為 %s" % p1.facing_direction)
	check(p1.is_on_floor(), "走路後應仍在地面")

	# 停止輸入後應停止移動
	var x_stop: float = px(p1)
	await await_frames(10)
	check(abs(px(p1) - x_stop) < 0.5, "停止輸入後應停止移動（漂移 %.2f px）" % (px(p1) - x_stop))

	return not has_failures()
