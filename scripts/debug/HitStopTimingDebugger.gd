class_name HitStopTimingDebugger extends Node

# ═══════════════════════════════════════════════════════════════════════════
# Hit Stop 時機調試器
# 用於追蹤 hit stop 前後的幀數據，診斷連段時機問題
# ═══════════════════════════════════════════════════════════════════════════

@export var enabled: bool = true  # 是否開啟調試輸出
@export var detailed_logging: bool = false  # 是否輸出詳細日誌

# 調試數據結構
class HitStopEvent:
	var attacker_name: String
	var defender_name: String
	var attack_name: String
	
	# Hit stop 開始時的狀態
	var start_time: float
	var start_frame: int
	var attacker_anim_time: float
	var attacker_anim_length: float
	var defender_hitstun_frames: int
	
	# Hit stop 結束時的狀態
	var end_time: float
	var end_frame: int
	var duration_real: float  # 真實時間持續
	var duration_game: float  # 遊戲時間持續
	var attacker_anim_time_end: float
	var defender_hitstun_frames_end: int
	
	# 時機偏移計算
	var anim_progress_real_frames: float  # 動畫推進的真實幀數
	var physics_progress_game_frames: float  # 物理推進的遊戲幀數
	var timing_mismatch: float  # 時機錯位（正值 = 攻擊者提前恢復）

var current_event: HitStopEvent = null
var event_history: Array[HitStopEvent] = []
const MAX_HISTORY: int = 10

func _ready() -> void:
	if not enabled:
		return
	print("[HITSTOP DEBUGGER] 初始化完成，詳細日誌：%s" % detailed_logging)

# ═══════════════════════════════════════════════════════════════════════════
# 公開方法：記錄 Hit Stop 事件
# ═══════════════════════════════════════════════════════════════════════════

func start_hitstop_event(attacker: Node, defender: Node, attack_name: String) -> void:
	if not enabled:
		return
	
	current_event = HitStopEvent.new()
	current_event.attacker_name = attacker.name
	current_event.defender_name = defender.name
	current_event.attack_name = attack_name
	
	# 記錄開始狀態
	current_event.start_time = Time.get_ticks_msec() / 1000.0
	current_event.start_frame = Engine.get_physics_frames()
	
	# 攻擊者動畫狀態
	if attacker.has_node("AnimationPlayer"):
		var anim_player = attacker.get_node("AnimationPlayer")
		current_event.attacker_anim_time = anim_player.current_animation_position
		if anim_player.current_animation != "" and anim_player.has_animation(anim_player.current_animation):
			var anim = anim_player.get_animation(anim_player.current_animation)
			if anim:
				current_event.attacker_anim_length = anim.length
			else:
				current_event.attacker_anim_length = 0.0
		else:
			current_event.attacker_anim_length = 0.0
	
	# 防守者 hitstun 狀態
	if "hitstun_frames" in defender:
		current_event.defender_hitstun_frames = defender.hitstun_frames
	
	if detailed_logging:
		print("[HITSTOP START] %s 使用 %s 擊中 %s" % [
			current_event.attacker_name,
			current_event.attack_name,
			current_event.defender_name
		])
		print("  - 物理幀：%d，真實時間：%.3fs" % [
			current_event.start_frame,
			current_event.start_time
		])
		print("  - 攻擊者動畫：%.3fs / %.3fs (%.1f%%)" % [
			current_event.attacker_anim_time,
			current_event.attacker_anim_length,
			(current_event.attacker_anim_time / current_event.attacker_anim_length * 100.0) if current_event.attacker_anim_length > 0 else 0.0
		])
		print("  - 防守者 hitstun：%d 幀（等待啟動）" % current_event.defender_hitstun_frames)

func end_hitstop_event(attacker: Node, defender: Node) -> void:
	if not enabled or not current_event:
		return
	
	# 記錄結束狀態
	current_event.end_time = Time.get_ticks_msec() / 1000.0
	current_event.end_frame = Engine.get_physics_frames()
	current_event.duration_real = current_event.end_time - current_event.start_time
	
	# 攻擊者動畫狀態
	if attacker.has_node("AnimationPlayer"):
		var anim_player = attacker.get_node("AnimationPlayer")
		current_event.attacker_anim_time_end = anim_player.current_animation_position
	
	# 防守者 hitstun 狀態
	if "hitstun_frames" in defender:
		current_event.defender_hitstun_frames_end = defender.hitstun_frames
	
	# 計算時機偏移
	_calculate_timing_mismatch()
	
	# 輸出報告
	_print_event_report()
	
	# 保存到歷史
	event_history.append(current_event)
	if event_history.size() > MAX_HISTORY:
		event_history.pop_front()
	
	current_event = null

# ═══════════════════════════════════════════════════════════════════════════
# 內部方法：計算時機偏移
# ═══════════════════════════════════════════════════════════════════════════

func _calculate_timing_mismatch() -> void:
	if not current_event:
		return
	
	# 動畫推進的真實幀數（假設 60 FPS）
	var anim_progress_seconds = current_event.attacker_anim_time_end - current_event.attacker_anim_time
	current_event.anim_progress_real_frames = anim_progress_seconds * 60.0
	
	# 物理推進的遊戲幀數
	var frame_diff = current_event.end_frame - current_event.start_frame
	current_event.physics_progress_game_frames = float(frame_diff)
	
	# 時機錯位 = 動畫推進 - 物理推進
	# 正值表示動畫比物理快（攻擊者提前恢復）
	current_event.timing_mismatch = current_event.anim_progress_real_frames - current_event.physics_progress_game_frames

# ═══════════════════════════════════════════════════════════════════════════
# 內部方法：輸出報告
# ═══════════════════════════════════════════════════════════════════════════

func _print_event_report() -> void:
	if not current_event:
		return
	
	print("\n═══════════════════════════════════════════════════════════")
	print("[HITSTOP TIMING REPORT] %s (%s) → %s" % [
		current_event.attacker_name,
		current_event.attack_name,
		current_event.defender_name
	])
	print("───────────────────────────────────────────────────────────")
	
	# Hit Stop 持續時間
	print("【Hit Stop 持續時間】")
	print("  - 真實時間：%.4fs (%.1f 真實幀 @60fps)" % [
		current_event.duration_real,
		current_event.duration_real * 60.0
	])
	print("  - 物理幀差：%d 幀" % [
		current_event.end_frame - current_event.start_frame
	])
	
	# 攻擊者動畫進度
	print("\n【攻擊者動畫進度】")
	print("  - 開始：%.3fs / %.3fs (%.1f%%)" % [
		current_event.attacker_anim_time,
		current_event.attacker_anim_length,
		(current_event.attacker_anim_time / current_event.attacker_anim_length * 100.0) if current_event.attacker_anim_length > 0 else 0.0
	])
	print("  - 結束：%.3fs / %.3fs (%.1f%%)" % [
		current_event.attacker_anim_time_end,
		current_event.attacker_anim_length,
		(current_event.attacker_anim_time_end / current_event.attacker_anim_length * 100.0) if current_event.attacker_anim_length > 0 else 0.0
	])
	print("  - 推進：%.1f 真實幀 (動畫時間 × 60fps)" % current_event.anim_progress_real_frames)
	
	# 防守者 hitstun 狀態
	print("\n【防守者 Hitstun 狀態】")
	print("  - Hit Stop 前：%d 幀（延遲啟動）" % current_event.defender_hitstun_frames)
	print("  - Hit Stop 後：%d 幀（開始計時）" % current_event.defender_hitstun_frames_end)
	
	# 時機偏移分析
	print("\n【時機偏移分析】")
	print("  - 物理推進：%.2f 遊戲幀" % current_event.physics_progress_game_frames)
	print("  - 動畫推進：%.2f 真實幀" % current_event.anim_progress_real_frames)
	print("  - 偏移量：%.2f 幀 (%s)" % [
		current_event.timing_mismatch,
		"攻擊者提前恢復" if current_event.timing_mismatch > 0 else "同步正確" if current_event.timing_mismatch == 0 else "攻擊者延遲恢復"
	])
	
	if current_event.timing_mismatch > 1.0:
		print("  ⚠️ 警告：時機錯位超過 1 幀，可能影響連段")
	elif current_event.timing_mismatch > 3.0:
		print("  🚨 嚴重：時機錯位超過 3 幀，連段時機錯誤")
	elif abs(current_event.timing_mismatch) < 0.5:
		print("  ✅ 正常：時機同步良好")
	
	print("═══════════════════════════════════════════════════════════\n")

# ═══════════════════════════════════════════════════════════════════════════
# 公開方法：獲取最近的事件
# ═══════════════════════════════════════════════════════════════════════════

func get_last_event() -> HitStopEvent:
	if event_history.is_empty():
		return null
	return event_history[-1]

func get_average_mismatch() -> float:
	if event_history.is_empty():
		return 0.0
	
	var total: float = 0.0
	for event in event_history:
		total += event.timing_mismatch
	
	return total / float(event_history.size())

func print_summary() -> void:
	if not enabled or event_history.is_empty():
		return
	
	print("\n═══════════════════════════════════════════════════════════")
	print("[HITSTOP TIMING SUMMARY] 最近 %d 次事件" % event_history.size())
	print("───────────────────────────────────────────────────────────")
	
	var total_mismatch: float = 0.0
	var max_mismatch: float = 0.0
	var min_mismatch: float = 999.0
	
	for i in range(event_history.size()):
		var event = event_history[i]
		total_mismatch += event.timing_mismatch
		max_mismatch = max(max_mismatch, event.timing_mismatch)
		min_mismatch = min(min_mismatch, event.timing_mismatch)
		
		print("[%d] %s (%s): 偏移 %.2f 幀" % [
			i + 1,
			event.attacker_name,
			event.attack_name,
			event.timing_mismatch
		])
	
	print("───────────────────────────────────────────────────────────")
	print("平均偏移：%.2f 幀" % (total_mismatch / float(event_history.size())))
	print("最大偏移：%.2f 幀" % max_mismatch)
	print("最小偏移：%.2f 幀" % min_mismatch)
	print("═══════════════════════════════════════════════════════════\n")
