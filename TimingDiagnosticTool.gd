# TimingDiagnosticTool.gd
# 診斷遊戲時間流逝和速度問題的工具

extends Node

const REPORT_INTERVAL = 3.0  # 每 3 秒報告一次

var last_report_time: float = 0.0
var physics_frame_count_at_last_report: int = 0
var wall_clock_time_at_last_report: float = 0.0

var _physics_frame_counter: int = 0
var _process_frame_counter: int = 0

var world: Node = null
var frame_counter: Node = null

func _ready() -> void:
	set_physics_process(true)
	set_process(true)
	world = get_tree().get_first_node_in_group("world")
	frame_counter = get_tree().get_first_node_in_group("frame_counter")
	last_report_time = Time.get_ticks_msec() / 1000.0
	wall_clock_time_at_last_report = last_report_time
	print("[TimingDiagnostics] ✓ 初始化完成，將每 %.1f 秒進行一次診斷" % [REPORT_INTERVAL])

func _physics_process(delta: float) -> void:
	_physics_frame_counter += 1
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var wall_elapsed = current_time - wall_clock_time_at_last_report
	
	# 每 REPORT_INTERVAL 秒進行一次診斷報告
	if wall_elapsed >= REPORT_INTERVAL:
		_generate_timing_report(current_time, delta)
		wall_clock_time_at_last_report = current_time

func _process(_delta: float) -> void:
	_process_frame_counter += 1

func _generate_timing_report(current_time: float, physics_delta: float) -> void:
	var elapsed_frames = _physics_frame_counter - physics_frame_count_at_last_report
	var elapsed_wall_time = current_time - wall_clock_time_at_last_report
	
	# 計算實際的物理 FPS
	var actual_physics_fps = elapsed_frames / elapsed_wall_time if elapsed_wall_time > 0 else 0.0
	var physics_fps_error = abs(actual_physics_fps - 120.0) / 120.0 * 100.0
	
	# 從 FrameCounter 獲取邏輯幀信息
	var current_logic_frame = 0
	var logic_fps = 0.0
	if frame_counter and frame_counter.has_method("get_current_logic_frame"):
		current_logic_frame = frame_counter.call("get_current_logic_frame")
	
	print("\n" + "="*80)
	print("[TIMING DIAGNOSTIC] @ 牆上時鐘 %.2f秒" % [current_time])
	print("="*80)
	print("📊 物理幀速統計:")
	print("  實際 Physics FPS: %.1f（預期：120.0）" % [actual_physics_fps])
	print("  誤差：%.1f%%（%s）" % [
		physics_fps_error,
		"✓ 正常" if physics_fps_error < 5.0 else "❌ 偏差過大"
	])
	print("  物理 Delta 值：%.6f（預期：%.6f）" % [physics_delta, 1.0 / 120.0])
	print()
	print("📊 邏輯幀速統計:")
	if frame_counter:
		print("  當前邏輯幀：%d" % [current_logic_frame])
		var expected_logic_frames = int(elapsed_frames / 2.0)  # 120 FPS / 60 FPS = 2:1
		var logic_frames_error = abs(current_logic_frame -expected_logic_frames) if expected_logic_frames > 0 else 0
		print("  預期邏輯幀：%d（基於 %d 物理幀）" % [expected_logic_frames, elapsed_frames])
		if logic_frames_error > 0:
			print("  邏輯幀誤差：%d 幀（%.1f%%）" % [
				logic_frames_error,
				float(logic_frames_error) / float(expected_logic_frames) * 100.0 if expected_logic_frames > 0 else 0.0
			])
	else:
		print("  ⚠️  FrameCounter 未找到")
	print()
	print("🎬 動畫播放診斷:")
	_diagnose_animation_speed()
	print()
	
	# 檢查特殊招式的移動速度
	_diagnose_special_move_speed()
	
	physics_frame_count_at_last_report = _physics_frame_counter

func _diagnose_animation_speed() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player and "animation_player" in player:
			var anim_player = player.animation_player
			if anim_player:
				var anim_speed = anim_player.speed_scale
				var is_playing = anim_player.is_playing()
				var current_anim = anim_player.current_animation if is_playing else "(無)"
				var progress = anim_player.current_animation_position if is_playing else 0.0
				
				var status = "播放中"
				if not is_playing:
					status = "停止"
				elif anim_speed != 1.0:
					status = "減速中 (speed_scale=%.2f)" % [anim_speed]
				
				print("    %s: %s | 動畫: '%s' | 進度: %.2f%%" % [
					player.name,
					status,
					current_anim,
					progress
				])

func _diagnose_special_move_speed() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player and "is_special_moving" in player and player.is_special_moving:
			if "current_move_state" in player:
				var move_state = player.current_move_state
				if move_state:
					var duration = move_state.total_duration if "total_duration" in move_state else 0.0
					var timer = move_state.timer if "timer" in move_state else 0
					var progress = 0.0
					if duration > 0:
						progress = (1.0 - (timer / duration)) * 100.0
					
					print("  特殊招式 (%s):" % [player.name])
					print("    總時長：%.3f 秒" % [duration])
					print("    剩餘幀數：%d" % [timer])
					print("    進度：%.1f%%" % [progress])
					
					if "initial_speed" in move_state:
						var speed_units = move_state.initial_speed
						var speed_px_per_sec = abs(speed_units) / 1000.0 if speed_units > 0 else 0.0
						print("    運動速度：%.0f units/s = %.1f px/s" % [speed_units, speed_px_per_sec])
