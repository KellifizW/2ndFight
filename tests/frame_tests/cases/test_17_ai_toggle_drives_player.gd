extends "res://tests/frame_tests/frame_test_case.gd"
## AI toggle should connect the CPUController state to actual player input.
## Regression target: Web builds showed the AI button/key changing UI state while
## the controlled player kept receiving neutral input and never moved.

func run() -> bool:
	await await_frames(10)
	teleport_x(p1, 550.0)
	teleport_x(p2, 1050.0)
	await await_frames(2)

	var cpu_controller = world.get_node_or_null("CPUController")
	check(cpu_controller != null, "CPUController should exist in world")
	if cpu_controller == null:
		return false

	cpu_controller.toggle_ai_a()
	await await_frames(2)

	var ai_behavior = p1.get_node_or_null("AIBehavior")
	check(p1.is_ai_controlled, "P1 should be marked AI-controlled after toggle")
	check(ai_behavior != null, "P1 should have AIBehavior")
	if ai_behavior == null:
		return false
	check(ai_behavior.ai_enabled, "AIBehavior should be enabled after CPUController toggle")

	var sample_input: Dictionary = ai_behavior.get_ai_input()
	check(ai_behavior.opponent == p2, "AIBehavior should resolve P2 as opponent")
	check(_has_active_ai_input(sample_input), "AI should produce non-neutral input at round-start distance")

	var x0: float = px(p1)
	await await_frames(48)
	var dx: float = abs(px(p1) - x0)
	var started_action: bool = p1.is_dashing or p1.is_jumping or p1.is_attacking or (p1.move_set and p1.move_set.is_spmove)
	check(dx > 1.0 or started_action, "AI should move or start an action after toggle (dx=%.2f)" % dx)

	return not has_failures()

func _has_active_ai_input(input_data: Dictionary) -> bool:
	return input_data.get("input_dir", 0) != 0 \
		or input_data.get("jump_pressed", false) \
		or input_data.get("dash_pressed", false) \
		or input_data.get("backdash_pressed", false) \
		or input_data.get("st_lp_pressed", false) \
		or input_data.get("st_mp_pressed", false) \
		or input_data.get("st_hp_pressed", false) \
		or input_data.get("st_lk_pressed", false) \
		or input_data.get("st_mk_pressed", false) \
		or input_data.get("st_hk_pressed", false) \
		or input_data.get("throw_pressed", false) \
		or input_data.get("spm1_pressed", false) \
		or input_data.get("spm2_pressed", false) \
		or input_data.get("spm3_pressed", false) \
		or input_data.get("dp_pressed", false) \
		or input_data.get("super_pressed", false)