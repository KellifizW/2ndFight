extends Node

## Hit Stop 時機測試腳本
## 用於自動測試連段時機是否正確

@export var test_interval: float = 2.0  # 測試間隔（秒）
@export var auto_test: bool = false  # 是否自動測試
@export var test_count: int = 5  # 測試次數

var world: Node
var player_a: Node
var player_b: Node
var slowmo_controller: Node
var debugger: Node
var test_timer: float = 0.0
var current_test: int = 0
var test_results: Array = []

func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	if not world:
		Debug.log("[HITSTOP TEST] 錯誤：找不到 world 節點")
		return
	
	# 等待一幀讓 world 完成初始化
	await get_tree().process_frame
	
	player_a = world.get("player_a")
	player_b = world.get("player_b")
	slowmo_controller = world.get_node_or_null("SlowMoController")
	debugger = world.get_node_or_null("HitStopTimingDebugger")
	
	if not player_a or not player_b:
		Debug.log("[HITSTOP TEST] 錯誤：找不到玩家節點")
		return
	
	Debug.log("[HITSTOP TEST] 初始化完成")
	Debug.log("  - 自動測試：%s" % auto_test)
	Debug.log("  - 測試次數：%d" % test_count)
	Debug.log("  - 測試間隔：%.1fs" % test_interval)
	Debug.log("\n按鍵說明：")
	Debug.log("  - T: 手動觸發單次測試")
	Debug.log("  - Y: 開始/停止自動測試")
	Debug.log("  - U: 打印測試摘要")
	Debug.log("  - I: 切換 hit stop 開關")
	Debug.log("  - O: 切換動畫同步開關")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):  # T 鍵
		_run_single_test()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Y:  # 切換自動測試
				auto_test = !auto_test
				current_test = 0
				Debug.log("[HITSTOP TEST] 自動測試：%s" % ("開啟" if auto_test else "關閉"))
			KEY_U:  # 打印摘要
				_print_test_summary()
			KEY_I:  # 切換 hit stop
				if slowmo_controller:
					slowmo_controller.enable_hitstop = !slowmo_controller.enable_hitstop
					Debug.log("[HITSTOP TEST] Hit Stop：%s" % ("開啟" if slowmo_controller.enable_hitstop else "關閉"))
			KEY_O:  # 切換動畫同步
				if slowmo_controller:
					slowmo_controller.sync_animation_speed = !slowmo_controller.sync_animation_speed
					Debug.log("[HITSTOP TEST] 動畫同步：%s" % ("開啟" if slowmo_controller.sync_animation_speed else "關閉"))

func _process(delta: float) -> void:
	if not auto_test:
		return
	
	test_timer += delta
	if test_timer >= test_interval and current_test < test_count:
		test_timer = 0.0
		_run_single_test()
		current_test += 1
		
		if current_test >= test_count:
			auto_test = false
			Debug.log("\n[HITSTOP TEST] 自動測試完成！")
			_print_test_summary()

func _run_single_test() -> void:
	"""執行單次測試：Player A 使用 st_lp 擊中 Player B"""
	if not player_a or not player_b:
		return
	
	Debug.log("\n" + "═" * 60)
	Debug.log("[HITSTOP TEST #%d] 開始測試" % (test_results.size() + 1))
	Debug.log("  - Hit Stop：%s" % ("開啟" if slowmo_controller and slowmo_controller.enable_hitstop else "關閉"))
	Debug.log("  - 動畫同步：%s" % ("開啟" if slowmo_controller and slowmo_controller.sync_animation_speed else "關閉"))
	Debug.log("═" * 60)
	
	# 重置兩個玩家的狀態
	_reset_player_state(player_a)
	_reset_player_state(player_b)
	
	# 等待一幀
	await get_tree().process_frame
	
	# Player A 站在 Player B 旁邊
	player_a.global_position = player_b.global_position + Vector2(-100, 0)
	player_a.facing_direction = 1.0
	player_b.facing_direction = -1.0
	
	# 等待一幀
	await get_tree().process_frame
	
	# Player A 使用 st_lp
	_simulate_attack(player_a, "st_lp")
	
	# 等待攻擊動畫完成（st_lp 約 12 幀 = 0.2 秒）
	await get_tree().create_timer(0.25).timeout
	
	# 記錄測試結果
	var result = _capture_test_result()
	test_results.append(result)
	
	Debug.log("\n[HITSTOP TEST #%d] 測試完成" % test_results.size())
	_print_test_result(result)

func _reset_player_state(player: Node) -> void:
	"""重置玩家狀態"""
	if not player:
		return
	
	player.is_attacking = false
	player.is_hit = false
	player.is_blocking = false
	player.hitstun_frames = 0
	player.blockstun_frames = 0
	player.knockback_frames = 0
	player.fixed_velocity = Vector2i.ZERO
	
	if player.has_method("reset_attack_state"):
		player.reset_attack_state()

func _simulate_attack(player: Node, attack_name: String) -> void:
	"""模擬玩家使用攻擊"""
	if not player:
		return
	
	# 直接設置攻擊狀態
	player.is_attacking = true
	player.attack_type = attack_name
	
	# 播放動畫
	if player.has_node("AnimationState"):
		var anim_state = player.get_node("AnimationState")
		anim_state.travel(attack_name)
	
	Debug.log("[HITSTOP TEST] %s 使用 %s" % [player.name, attack_name])

func _capture_test_result() -> Dictionary:
	"""捕捉測試結果"""
	var result = {
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"hitstop_enabled": slowmo_controller and slowmo_controller.enable_hitstop,
		"animation_sync_enabled": slowmo_controller and slowmo_controller.sync_animation_speed,
		"timing_mismatch": 0.0,
		"success": false
	}
	
	# 從調試器獲取最近的事件
	if debugger:
		var last_event = debugger.get_last_event()
		if last_event:
			result["timing_mismatch"] = last_event.timing_mismatch
			result["success"] = abs(last_event.timing_mismatch) < 1.0  # 偏移小於 1 幀視為成功
	
	return result

func _print_test_result(result: Dictionary) -> void:
	"""打印單次測試結果"""
	Debug.log("  - 時機偏移：%.2f 幀" % result.timing_mismatch)
	Debug.log("  - 結果：%s" % ("✅ 成功" if result.success else "❌ 失敗"))

func _print_test_summary() -> void:
	"""打印測試摘要"""
	if test_results.is_empty():
		Debug.log("\n[HITSTOP TEST] 尚無測試結果")
		return
	
	Debug.log("\n" + "═" * 60)
	Debug.log("[HITSTOP TEST SUMMARY] 測試摘要")
	Debug.log("═" * 60)
	Debug.log("總測試次數：%d" % test_results.size())
	
	var success_count = 0
	var total_mismatch = 0.0
	var max_mismatch = -999.0
	var min_mismatch = 999.0
	
	for i in range(test_results.size()):
		var result = test_results[i]
		if result.success:
			success_count += 1
		total_mismatch += result.timing_mismatch
		max_mismatch = max(max_mismatch, result.timing_mismatch)
		min_mismatch = min(min_mismatch, result.timing_mismatch)
		
		var status = "✅" if result.success else "❌"
		var sync = "✓" if result.animation_sync_enabled else "✗"
		Debug.log("[%d] %s 偏移：%.2f 幀（動畫同步：%s）" % [
			i + 1, status, result.timing_mismatch, sync
		])
	
	Debug.log("─" * 60)
	Debug.log("成功率：%d / %d (%.1f%%)" % [
		success_count, test_results.size(),
		(float(success_count) / test_results.size() * 100.0)
	])
	Debug.log("平均偏移：%.2f 幀" % (total_mismatch / test_results.size()))
	Debug.log("最大偏移：%.2f 幀" % max_mismatch)
	Debug.log("最小偏移：%.2f 幀" % min_mismatch)
	Debug.log("═" * 60)
	
	# 如果有調試器，也打印其摘要
	if debugger:
		debugger.print_summary()
