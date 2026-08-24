extends "res://tests/frame_tests/frame_test_case.gd"
## 世界生成基本狀態：雙玩家、血量、面向、初始動畫

func run() -> bool:
	check(p1 != null, "player_a 不存在")
	check(p2 != null, "player_b 不存在")
	if p1 == null or p2 == null:
		return false

	check(p1.is_on_floor(), "P1 生成時應在地面")
	check(p2.is_on_floor(), "P2 生成時應在地面")

	check(p1.healthbar != null, "P1 healthbar 未設定")
	check(p2.healthbar != null, "P2 healthbar 未設定")
	if p1.healthbar and p2.healthbar:
		check(abs(p1.healthbar.current_health - 100.0) < 0.001, "P1 初始血量應為 100，實為 %s" % p1.healthbar.current_health)
		check(abs(p2.healthbar.current_health - 100.0) < 0.001, "P2 初始血量應為 100，實為 %s" % p2.healthbar.current_health)

	check(abs(p1.facing_direction - 1.0) < 0.001, "P1 應面向右（+1），實為 %s" % p1.facing_direction)
	check(abs(p2.facing_direction - (-1.0)) < 0.001, "P2 應面向左（-1），實為 %s" % p2.facing_direction)

	check(p1.is_attacking == false, "P1 生成時不應該在攻擊")
	check(p2.is_attacking == false, "P2 生成時不應該在攻擊")

	await await_frames(10)
	var a_state = p1.animation_state.get_current_node() if p1.animation_state else "?"
	var b_state = p2.animation_state.get_current_node() if p2.animation_state else "?"
	check(a_state in ["Walk", "idle"], "P1 初始動畫應為 Walk/idle，實為 %s" % a_state)
	check(b_state in ["Walk", "idle"], "P2 初始動畫應為 Walk/idle，實為 %s" % b_state)

	return not has_failures()
