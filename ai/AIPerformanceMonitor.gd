class_name AIPerformanceMonitor extends Node

# ============================================================
# AI PERFORMANCE MONITOR (Phase 2 Debugging Tool)
# ============================================================
# 實時監測 AI 系統的性能指標
# - 決策計算時間
# - 威脅評估時間
# - FPS 和幀時間
# - 決策開銷百分比
#
# 使用方法：
# 1. 在 world.gd 或遊戲場景中附加此腳本
# 2. 在 Inspector 中啟用 "Enabled"
# 3. 檢查控制台輸出性能報告

@export var enabled: bool = false
@export var log_interval: float = 5.0  # 每 5 秒輸出一次報告
@export var show_realtime: bool = false  # 每幀顯示性能數據（較少用）

# 性能計時數據
var frame_times: Array[float] = []
var decision_times: Array[int] = []  # 微秒
var threat_eval_times: Array[int] = []  # 微秒

var log_timer: float = 0.0
var frame_counter: int = 0

# AI 行為引用（用於插件式監測）
var ai_behaviors: Array = []

func _ready() -> void:
	if not enabled:
		set_process(false)
		return
	
	add_to_group("ai_profiler")
	print("[AI PROFILER] ✓ 性能監視器已啟用，間隔: %.1f秒" % log_interval)
	
	# 自動搜索 AI 行為實例
	call_deferred("_find_ai_behaviors")

func _find_ai_behaviors() -> void:
	"""搜索場景中的所有 AIBehavior 實例"""
	ai_behaviors.clear()
	var all_ai = get_tree().get_nodes_in_group("ai_systems")  # 需要 AI 添加到該組
	
	for ai in all_ai:
		if ai is Node and ai.name.contains("AIBehavior"):
			ai_behaviors.append(ai)
	
	if ai_behaviors.is_empty():
		push_warning("[AI PROFILER] ⚠️ 未找到 AI 行為實例。請確保 AIBehavior 已添加到 'ai_systems' 組")

func record_decision_time(time_usec: int) -> void:
	"""記錄決策計算時間（微秒）"""
	decision_times.append(time_usec)

func record_threat_eval_time(time_usec: int) -> void:
	"""記錄威脅評估計算時間（微秒）"""
	threat_eval_times.append(time_usec)

func _process(delta: float) -> void:
	frame_times.append(delta * 1000.0)  # 轉換為毫秒
	frame_counter += 1
	
	log_timer += delta
	if log_timer >= log_interval:
		_print_stats()
		_reset_stats()
		log_timer = 0.0
	
	if show_realtime and frame_counter % 60 == 0:  # 每秒顯示一次
		_print_realtime_stats()

func _print_stats() -> void:
	"""列印性能統計報告"""
	if frame_times.is_empty():
		return
	
	var avg_frame_time = _calculate_average(frame_times)
	var max_frame_time = _calculate_max(frame_times)
	var min_frame_time = _calculate_min(frame_times)
	var fps = 1000.0 / avg_frame_time if avg_frame_time > 0 else 0.0
	
	# 決策和威脅評估時間（轉換為毫秒）
	var avg_decision_time = _calculate_average_int(decision_times) / 1000.0
	var avg_threat_time = _calculate_average_int(threat_eval_times) / 1000.0
	
	var decision_overhead = (avg_decision_time / avg_frame_time * 100.0) if avg_frame_time > 0 else 0.0
	var threat_overhead = (avg_threat_time / avg_frame_time * 100.0) if avg_frame_time > 0 else 0.0
	
	print("\n" + "=".repeat(60))
	print("█ AI PERFORMANCE REPORT - %.1f秒" % log_interval)
	print("=".repeat(60))
	
	# FPS 和幀時間
	print("\n📊 幀速率:")
	print("  平均 FPS: %.1f" % fps)
	print("  平均幀時間: %.2f ms" % avg_frame_time)
	print("  最小幀時間: %.2f ms" % min_frame_time)
	print("  最大幀時間: %.2f ms" % max_frame_time)
	print("  樣本數: %d" % frame_times.size())
	
	# 決策計算開銷
	if not decision_times.is_empty():
		print("\n⚙️ 決策系統:")
		print("  平均決策時間: %.2f ms" % avg_decision_time)
		print("  決策開銷: %.1f%%" % decision_overhead)
		print("  決策調用數: %d" % decision_times.size())
	
	# 威脅評估開銷
	if not threat_eval_times.is_empty():
		print("\n⚔️ 威脅評估:")
		print("  平均評估時間: %.2f ms" % avg_threat_time)
		print("  威脅評估開銷: %.1f%%" % threat_overhead)
		print("  評估調用數: %d" % threat_eval_times.size())
	
	# 性能等級
	print("\n⭐ 性能等級:")
	if fps >= 58:
		print("  A+ (卓越 - 60 FPS穩定)")
	elif fps >= 55:
		print("  A (優秀 - 55+ FPS)")
	elif fps >= 50:
		print("  B (良好 - 50+ FPS)")
	elif fps >= 45:
		print("  C (尚可 - 45+ FPS)")
	else:
		print("  D (需改進 - FPS < 45)")
		if decision_overhead > 20:
			print("  💡 建議: 考慮增加決策間隔或啟用自適應間隔")
		if threat_overhead > 15:
			print("  💡 建議: 考慮優化威脅評估邏輯")
	
	print("=".repeat(60) + "\n")

func _print_realtime_stats() -> void:
	"""實時性能統計（每秒）"""
	if frame_times.size() < 60:
		return
	
	var recent_frames = frame_times.slice(-60)
	var avg_frame = _calculate_average(recent_frames)
	var fps = 1000.0 / avg_frame if avg_frame > 0 else 0.0
	
	print("🔴 [FPS] %.1f (幀時: %.2f ms)" % [fps, avg_frame])

func _calculate_average(arr: Array[float]) -> float:
	"""計算浮點數組平均值"""
	if arr.is_empty():
		return 0.0
	var sum: float = 0.0
	for val in arr:
		sum += val
	return sum / arr.size()

func _calculate_average_int(arr: Array[int]) -> int:
	"""計算整數數組平均值"""
	if arr.is_empty():
		return 0
	var sum: int = 0
	for val in arr:
		sum += val
	return sum / arr.size()

func _calculate_max(arr: Array[float]) -> float:
	"""計算最大值"""
	if arr.is_empty():
		return 0.0
	var max_val: float = arr[0]
	for val in arr:
		if val > max_val:
			max_val = val
	return max_val

func _calculate_min(arr: Array[float]) -> float:
	"""計算最小值"""
	if arr.is_empty():
		return 0.0
	var min_val: float = arr[0]
	for val in arr:
		if val < min_val:
			min_val = val
	return min_val

func _reset_stats() -> void:
	"""重置統計數據"""
	frame_times.clear()
	decision_times.clear()
	threat_eval_times.clear()

# ============================================================
# 集成點：從其他系統調用這些方法來記錄性能數據
# ============================================================

func start_decision_timer() -> int:
	"""開始測量決策時間"""
	return Time.get_ticks_usec()

func end_decision_timer(start_usec: int) -> void:
	"""結束決策計時"""
	var elapsed = Time.get_ticks_usec() - start_usec
	record_decision_time(elapsed)

func start_threat_timer() -> int:
	"""開始測量威脅評估時間"""
	return Time.get_ticks_usec()

func end_threat_timer(start_usec: int) -> void:
	"""結束威脅評估計時"""
	var elapsed = Time.get_ticks_usec() - start_usec
	record_threat_eval_time(elapsed)
