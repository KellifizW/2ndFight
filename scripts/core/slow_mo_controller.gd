extends Node

class_name SlowMoController

signal time_scale_changed(new_time_scale: float)
signal hit_slowmo_finished  # 🟢 Hit stop 完成信號，讓 hitstun/knockback 在 hit stop 後開始

# ═══════════════════════════════════════════════════════════════════════════
# ⚙️ Hit Stop（擊中凍結）設定 —— 可在編輯器 Inspector 直接調整
# （world.tscn → SlowMoController 節點）
# ═══════════════════════════════════════════════════════════════════════════
@export_group("Hit Stop（擊中凍結）")
## 是否開啟 hitstop 功能
@export var enable_hitstop: bool = true
## hitstop 時長，以 60fps 邏輯幀計（8 幀 ≈ 0.133 秒真實時間）。
## 想要更重的打擊感就調大（重攻擊常用 10~14 幀），輕快手感則調小。
@export_range(0, 30, 1, "suffix:frames@60fps") var hitstop_frames: int = 8
## hitstop 期間的 Engine.time_scale。
## 越小越接近完全凍結；不要設為 0，0 會破壞物理引擎的內部運算。
@export_range(0.001, 0.5, 0.001) var hit_slowmo_time_scale: float = 0.02
## 是否同步動畫速度（解決連段時機問題）
@export var sync_animation_speed: bool = true

@export_group("Slow Motion（KO 慢動作）")
## KO 慢動作的時間縮放
@export_range(0.05, 1.0, 0.01) var slowmo_time_scale: float = 0.2
## 進入慢動作的過渡時間（秒）
@export_range(0.0, 2.0, 0.05, "suffix:s") var slowmo_enter_time: float = 0.4
## 退出慢動作的過渡時間（秒）
@export_range(0.0, 2.0, 0.05, "suffix:s") var slowmo_exit_time: float = 0.4

# 正常時間縮放（恢復目標值）
var normal_time_scale: float = 1.0

## hitstop 持續時間（秒，真實時間）—— 由 hitstop_frames 推導，供除錯/相容使用
var hit_slowmo_time: float:
	get:
		return float(hitstop_frames) / 60.0

# 追蹤受影響的玩家（用於同步動畫速度）
var affected_players: Array[Node] = []
var slowmo_active: bool = false
var is_hit_slowmo: bool = false     # 標記是否處於擊中凍結（hitstop）狀態
var pending_slowmo_request: bool = false  # 延遲在 hit stop 結束後啟動 slowmo

# Tween 只用於 KO 慢動作的平滑過渡；hitstop 不再依賴 Tween（見 _process）
var tween: Tween

# 除錯：記錄擊中凍結開始的真實時間（毫秒）
var hit_start_time: int = 0
# hitstop 結束的真實時間（毫秒）——用 wall clock 計時，與 Engine.time_scale 完全脫鉤
var _hit_freeze_end_ms: int = 0

func _ready():
	# 設置 process_mode 為始終運行
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 確保初始時間縮放為正常
	Engine.time_scale = normal_time_scale
	emit_signal("time_scale_changed", normal_time_scale)
	Debug.log("Debug: SlowMoController initialized, time_scale set to %s, process_mode set to ALWAYS" % normal_time_scale)

func _process(_delta):
	# 🟢 【修復】hitstop 改用真實時間（wall clock）計時：
	# _process 每個渲染幀都會被呼叫，且不受 Engine.time_scale 影響，
	# 因此凍結「一定」會在 hitstop_frames 對應的真實時間後結束。
	# 舊實現用 Tween + set_ignore_time_scale 計時，Tween 被殺掉或
	# 引擎版本行為差異都會讓 is_hit_slowmo 卡死、時間縮放沒有生效，
	# 造成「完全沒有 hitstop」的症狀。
	if is_hit_slowmo and Time.get_ticks_msec() >= _hit_freeze_end_ms:
		_on_hit_slowmo_finished()

# 請求切換慢動作狀態（手動切換）
func request_slowmo_change():
	if is_hit_slowmo:
		pending_slowmo_request = true
		Debug.log("Debug: Slowmo request deferred until hit stop ends")
		return
	if slowmo_active:
		exit_slowmo_animation()
	else:
		enter_slowmo_animation()

# 請求擊中凍結（hitstop）效果
# custom_frames：可選的單次覆蓋時長（60fps 邏輯幀）；<= 0 時使用 hitstop_frames
func request_hit_freeze(custom_frames: int = -1):
	var frames: int = custom_frames if custom_frames > 0 else hitstop_frames
	if not enable_hitstop or frames <= 0:
		Debug.log("Debug: Hit slowmo request ignored (enable_hitstop=%s, frames=%d)" % [enable_hitstop, frames])
		# 🟢 即使跳過凍結，仍發送信號讓 hitstun/knockback 正常進行
		emit_signal("hit_slowmo_finished")
		return
	if slowmo_active or is_hit_slowmo:
		Debug.log("Debug: Hit slowmo request ignored (slowmo_active=%s, is_hit_slowmo=%s)" % [slowmo_active, is_hit_slowmo])
		return  # 避免重複觸發
	is_hit_slowmo = true

	# 🟢 暫停幀計數器（用群組尋找，不再依賴 "World/FrameCounter" 絕對路徑）
	var frame_counter = _get_frame_counter()
	if frame_counter:
		frame_counter.pause()

	# KO 慢動作過渡中的 Tween 讓位給 hitstop（hitstop 優先，結束後恢復正常）
	if tween and tween.is_running():
		tween.kill()

	# 🟢 【修正】同步所有玩家的動畫速度，確保動畫與物理同步暫停
	if sync_animation_speed:
		_sync_player_animations(hit_slowmo_time_scale)

	# 立即進入擊中凍結
	Engine.time_scale = hit_slowmo_time_scale
	emit_signal("time_scale_changed", hit_slowmo_time_scale)
	# 記錄開始/結束的真實時間（毫秒）——由 _process 負責在到期時恢復
	hit_start_time = Time.get_ticks_msec()
	_hit_freeze_end_ms = hit_start_time + int(round(float(frames) / 60.0 * 1000.0))

## 強制結束 hitstop 並完整還原所有狀態（回合重置等外部流程使用）。
## 不要在外部直接改 is_hit_slowmo，否則動畫速度 / 幀計數器 / 等待中的
## hitstun 會停留在不一致的狀態。
func cancel_hit_freeze() -> void:
	pending_slowmo_request = false
	if is_hit_slowmo:
		_on_hit_slowmo_finished()

# 進入慢動作的動畫（手動切換）
func enter_slowmo_animation():
	if tween and tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(Engine, "time_scale", slowmo_time_scale, slowmo_enter_time)
	tween.tween_callback(_on_enter_slowmo_finished)
	emit_signal("time_scale_changed", slowmo_time_scale)
	Debug.log("Debug: Entering slow motion, transitioning to time_scale=%s over %s seconds" % [slowmo_time_scale, slowmo_enter_time])

# 退出慢動作的動畫（手動切換）
func exit_slowmo_animation():
	if tween and tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(Engine, "time_scale", normal_time_scale, slowmo_exit_time)
	tween.tween_callback(_on_exit_slowmo_finished)
	emit_signal("time_scale_changed", normal_time_scale)
	Debug.log("Debug: Exiting slow motion, transitioning to time_scale=%s over %s seconds" % [normal_time_scale, slowmo_exit_time])

# 進入慢動作完成
func _on_enter_slowmo_finished():
	slowmo_active = true
	Debug.log("Debug: Slow motion activated, slowmo_active=%s" % slowmo_active)

# 退出慢動作完成
func _on_exit_slowmo_finished():
	slowmo_active = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)
	Debug.log("Debug: Slow motion deactivated, slowmo_active=%s, time_scale=%s" % [slowmo_active, Engine.time_scale])

# 擊中凍結完成（由 _process 的真實時間計時觸發，或由 cancel_hit_freeze 強制觸發）
func _on_hit_slowmo_finished():
	if not is_hit_slowmo:
		return
	is_hit_slowmo = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)

	# 🟢 恢復幀計數器
	var frame_counter = _get_frame_counter()
	if frame_counter:
		frame_counter.resume()

	# 🟢 【修正】恢復所有玩家的動畫速度
	if sync_animation_speed:
		_sync_player_animations(1.0)

	# 除錯：計算並打印真實持續時間（秒）
	var duration_sec = (Time.get_ticks_msec() - hit_start_time) / 1000.0
	Debug.log("Debug: Hit stop finished, real duration=%.4fs (target %.4fs / %d frames@60fps)" % [duration_sec, hit_slowmo_time, hitstop_frames])
	# 🟢 發送信號通知所有 Fighter，hit stop 已完成，可以開始 hitstun/knockback/blockstun
	emit_signal("hit_slowmo_finished")
	if pending_slowmo_request:
		pending_slowmo_request = false
		enter_slowmo_animation()

# 手動切換慢動作開關（用於測試或手動控制）
func toggle_slowmo():
	request_slowmo_change()

# ═══════════════════════════════════════════════════════════════════════════
# 🟢 內部：尋找幀計數器（FrameCounter 會把自己加入 "frame_counter" 群組）
# ═══════════════════════════════════════════════════════════════════════════

func _get_frame_counter() -> Node:
	return get_tree().get_first_node_in_group("frame_counter")

# ═══════════════════════════════════════════════════════════════════════════
# 🟢 【修正】同步玩家動畫速度方法
# ═══════════════════════════════════════════════════════════════════════════

func register_player(player: Node) -> void:
	"""註冊玩家，用於同步動畫速度"""
	if player not in affected_players:
		affected_players.append(player)
		if Engine.is_editor_hint():
			return
		Debug.log("[SLOWMO] 註冊玩家：%s" % player.name)

func unregister_player(player: Node) -> void:
	"""取消註冊玩家"""
	if player in affected_players:
		affected_players.erase(player)
		if Engine.is_editor_hint():
			return
		Debug.log("[SLOWMO] 取消註冊玩家：%s" % player.name)

func _sync_player_animations(speed_scale: float) -> void:
	"""同步所有註冊玩家的動畫速度"""
	# 如果沒有註冊的玩家，自動查找場景中的所有玩家
	if affected_players.is_empty():
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			if player.has_node("AnimationPlayer"):
				affected_players.append(player)

	# 設置所有玩家的動畫速度
	for player in affected_players:
		if not is_instance_valid(player):
			continue

		if player.has_node("AnimationPlayer"):
			var anim_player = player.get_node("AnimationPlayer")
			anim_player.speed_scale = speed_scale
