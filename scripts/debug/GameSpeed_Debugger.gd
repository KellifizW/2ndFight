extends Node

# 遊戲速度診斷工具
# 用於追蹤和分析遊戲運行速度

var start_time: float = 0.0
var frame_count: int = 0
var physics_frame_count: int = 0
var last_report_time: float = 0.0
var last_report_physics: int = 0

var _process_call_count: int = 0
var _physics_process_call_count: int = 0
var last_process_report: float = 0.0

var world: Node = null
var frame_counter: Node = null

func _ready() -> void:
	start_time = Time.get_ticks_msec() / 1000.0
	last_report_time = start_time
	set_process(true)
	set_physics_process(true)
	
	world = get_tree().get_first_node_in_group("world")
	frame_counter = get_tree().get_first_node_in_group("frame_counter")
	
	Debug.log("[GameSpeedDebugger] ✓ 初始化完成")
	Debug.log("[GameSpeedDebugger] 監視項目：")
	Debug.log("  • _process() 調用速率")
	Debug.log("  • _physics_process() 調用速率")
	Debug.log("  • 邏輯幀 vs 物理幀比例")
	Debug.log("  • 動畫速度")

func _process(delta: float) -> void:
	_process_call_count += 1
	frame_count += 1
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed = current_time - last_report_time
	
	# 每 2 秒報告一次
	if elapsed >= 2.0:
		var process_fps = _process_call_count / elapsed
		var expected_process_fps = Engine.get_physics_frames_per_second()  # 應該接近 60
		var delta_avg = elapsed / _process_call_count
		
		Debug.log("\n" + "="*70)
		Debug.log("[GAMESPY DEBUGGER] Process() 速率分析 @ %.2f 秒" % [current_time - start_time])
		Debug.log("="*70)
		Debug.log("  📊 _process() 調用率：%.1f FPS（間隔 %.4f 秒）" % [process_fps, delta_avg])
		Debug.log("  🎯 預期 FPS：60 Hz")
		Debug.log("  ⚖️  異常度：%.1f%%" % [abs(process_fps - 60.0) / 60.0 * 100])
		
		if process_fps > 65:
			Debug.log("  🚨 警告：Process 速率偏高（可能導致動畫加速）")
		elif process_fps < 55:
			Debug.log("  🚨 警告：Process 速率偏低（可能導致動畫減速）")
		
		# 檢查和物理幀的關係
		var physics_physics_ratio = _physics_process_call_count / float(_process_call_count) if _process_call_count > 0 else 0.0
		Debug.log("  🔗 物理幀/邏輯幀比例：%.2f（應為 2.0）" % [physics_physics_ratio])
		
		last_report_time = current_time
		_process_call_count = 0
		_physics_process_call_count = 0

func _physics_process(delta: float) -> void:
	_physics_process_call_count += 1
	physics_frame_count += 1
	
	# 檢查 FrameCounter 的邏輯幀計數
	if frame_counter:
		var current_logic_frame = frame_counter.get("current_logic_frame", 0) if frame_counter and frame_counter.has_method("get_current_logic_frame") else 0
		if current_logic_frame > 0:
			var ratio = physics_frame_count / float(current_logic_frame) if current_logic_frame > 0 else 0.0
			# 每 120 物理幀檢查一次（即 1 秒）
			if physics_frame_count % 120 == 0:
				Debug.log("[GameSpeedDebugger] 物理幀計數：%d，邏輯幀計數：%d，比例：%.2f（應為 2.0）" % [
					physics_frame_count, current_logic_frame, ratio
				])

# 檢查特定动畫的播放速度
func check_animation_speed(anim_player: AnimationPlayer, anim_name: String) -> void:
	if not anim_player:
		return
	
	if anim_player.has_animation(anim_name):
		var anim = anim_player.get_animation(anim_name)
		var speed_scale = anim_player.speed_scale
		var expected_duration = anim.length
		
		Debug.log("\n[AnimationSpeedCheck] '%s'" % [anim_name])
		Debug.log("  動畫時長：%.3f 秒" % [expected_duration])
		Debug.log("  播放速度倍率：%.2f" % [speed_scale])
		Debug.log("  實際播放時長：%.3f 秒" % [expected_duration / speed_scale])
		
		# 計算應該有多少幀
		var expected_logic_frames = int(round(expected_duration * 60))  # 60 FPS 邏輯幀
		var expected_physics_frames = expected_logic_frames * 2  # 120 FPS 物理幀
		Debug.log("  預期：%d 邏輯幀 / %d 物理幀" % [expected_logic_frames, expected_physics_frames])

# 檢查移動速度和距離
func check_move_distance(player: Node, move_name: String, start_pos: Vector2, end_pos: Vector2, duration_frames: int) -> void:
	var distance = start_pos.distance_to(end_pos)
	var expected_distance = 0.0
	var move_set = player.get_node_or_null("MoveSet")
	
	if move_set and move_set.has_method("get_move_data"):
		var move_data = move_set.call("get_move_data", move_name)
		if move_data and "move_distance" in move_data:
			expected_distance = move_data.move_distance
	
	var duration_secs = duration_frames / 60.0
	var speed_fps = distance / duration_secs if duration_secs > 0 else 0.0
	var expected_speed = expected_distance / duration_secs if duration_secs > 0 else 0.0
	
	Debug.log("\n[MoveDistanceCheck] '%s' 移動距離分析" % [move_name])
	Debug.log("  起始位置：(%.1f, %.1f)" % [start_pos.x, start_pos.y])
	Debug.log("  結束位置：(%.1f, %.1f)" % [end_pos.x, end_pos.y])
	Debug.log("  實際移動距離：%.1f 像素" % [distance])
	Debug.log("  預期移動距離：%.1f 像素" % [expected_distance])
	Debug.log("  幀數：%d 邏輯幀（%.3f 秒）" % [duration_frames, duration_secs])
	Debug.log("  實際速度：%.1f px/s（%.1f px/frame）" % [speed_fps, speed_fps / 60.0])
	Debug.log("  預期速度：%.1f px/s（%.1f px/frame）" % [expected_speed, expected_speed / 60.0])
	
	if abs(distance - expected_distance) > 0.5:
		Debug.log("  🚨 偏差：%.1f 像素（%.1f%%）" % [
			distance - expected_distance,
			abs(distance - expected_distance) / expected_distance * 100 if expected_distance > 0 else 0
		])
