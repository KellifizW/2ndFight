extends Node

class_name SlowMoController

signal time_scale_changed(new_time_scale: float)
signal hit_slowmo_finished  # 🟢 Hit stop 完成信號，讓 hitstun/knockback 在 hit stop 後開始

# ⚙️ 設置選項
# 注意：hitstop 的實際參數（frame 數、jitter、是否凍結攻擊者/受擊者）在
# World 子節點「HitStopController」上編輯；這裡只保留舊式總開關。
@export var enable_hitstop: bool = true  # 是否開啟 hitstop 功能
@export var sync_animation_speed: bool = true  # 是否同步動畫速度（解決連段時機問題）

# 🟢 専門 Hitstop 管理器（可視覺動畫與全域時間解耦）
# 用普通 var + 時查找，避免節點建立時序造成 _ready 連不到信號。
var hitstop_controller: HitStopController = null

# 時間縮放參數（只供 slow-mo / super freeze 相容使用；hitstop 不再修改 Engine.time_scale）
var normal_time_scale: float = 1
var slowmo_time_scale: float = 0.2
var hit_slowmo_time_scale: float = 0.02

# 追蹤受影響的玩家（用於同步動畫速度）
var affected_players: Array[Node] = []  
var slowmo_enter_time: float = 0.4   
var slowmo_exit_time: float = 0.4   
var slowmo_active: bool = false      
var hit_slowmo_time: float = 0.1333    # 擊中慢動作的持續時間（秒，真實時間）
var hit_slowmo_exit_time: float = 0  # 擊中慢動作的退出過渡時間（秒，真實時間）
var is_hit_slowmo: bool = false     # 標記是否處於擊中慢動作狀態
var pending_slowmo_request: bool = false  # 延遲在 hit stop 結束後啟動 slowmo

# Tween 用於平滑過渡
var tween: Tween

# 除錯：記錄擊中慢動作開始的真實時間（毫秒）
var hit_start_time: int = 0

func _ready():
	# 設置 process_mode 為始終運行
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 確保初始時間縮放為正常
	Engine.time_scale = normal_time_scale
	emit_signal("time_scale_changed", normal_time_scale)
	Debug.log("Debug: SlowMoController initialized, time_scale set to %s, process_mode set to ALWAYS" % normal_time_scale)

	# 🟢 連接 HitStopController：hitstop 完成後才廣播 hit_slowmo_finished
	_setup_hitstop_controller()

func _process(_delta):
	pass

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

# 🟢 延遲連接 / 重新查找 HitStopController
func _setup_hitstop_controller() -> void:
	if hitstop_controller == null:
		hitstop_controller = get_node_or_null("../HitStopController") as HitStopController
	if hitstop_controller and not hitstop_controller.hitstop_finished.is_connected(_on_hitstop_finished):
		hitstop_controller.hitstop_finished.connect(_on_hitstop_finished)

# 請求擊中定格（Hitstop）
# 現在走 HitStopController：只凍結角色動畫 + 視覺微震動，不再縮放 Engine.time_scale，
# 因此背景、粒子特效、UI 都會以正常速度繼續播放。
func request_hit_freeze(attacker: Node = null, target: Node = null):
	_setup_hitstop_controller()
	if not enable_hitstop:
		Debug.log("Debug: Hit stop request ignored (enable_hitstop=%s)" % enable_hitstop)
		# 🟢 即使跳過 hitstop，仍發送信號讓 hitstun/knockback 正常進行
		emit_signal("hit_slowmo_finished")
		return
	# 若旗標殘留（例如上一輪 finish signal 未接到），先做一次安全清除再開始新 hitstop。
	if is_hit_slowmo and (not hitstop_controller or not hitstop_controller.is_active):
		is_hit_slowmo = false
	if slowmo_active or is_hit_slowmo:
		Debug.log("Debug: Hit stop request ignored (slowmo_active=%s, is_hit_slowmo=%s)" % [slowmo_active, is_hit_slowmo])
		return  # 避免重複觸發

	if not hitstop_controller:
		Debug.log("Debug: HitStopController not found; skipping global time freeze (hitstop will be zero-frame).")
		emit_signal("hit_slowmo_finished")
		return

	if not hitstop_controller.begin_hitstop(attacker, target):
		# 參數無效（例如 hitstop_frames = 0）時不下拉長，直接結束。
		emit_signal("hit_slowmo_finished")
		return

	# 🟢 保持舊版旗標語義：Fighter / PushManager / FrameBar 都靠它凍結幀數遞減。
	is_hit_slowmo = true
	hit_start_time = Time.get_ticks_msec()
	Debug.log("Debug: Hit stop started (dedicated), frames=%s, time_scale kept=%s" % [
		hitstop_controller.hitstop_frames, Engine.time_scale
	])


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

# 擊中慢動作完成
func _on_hit_slowmo_finished():
	is_hit_slowmo = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)
	
	# 🟢 【新增】恢復幀計數器
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter:
		frame_counter.resume()
	
	# 🟢 【修正】恢復所有玩家的動畫速度
	if sync_animation_speed:
		_sync_player_animations(1.0)
	
	# 除錯：計算並打印真實持續時間（秒）
	var duration_sec = (Time.get_ticks_msec() - hit_start_time) / 1000.0
	# 🟢 發送信號通知所有 Fighter，hit stop 已完成，可以開始 hitstun/knockback/blockstun
	emit_signal("hit_slowmo_finished")
	if pending_slowmo_request:
		pending_slowmo_request = false
		enter_slowmo_animation()

# 🟢 HitStopController 完成後的回呼（新架構：僅改旗標和發信號，不再動 Engine.time_scale）
func _on_hitstop_finished() -> void:
	is_hit_slowmo = false
	Debug.log("Debug: Hit stop finished at %s ms, time_scale=%s" % [Time.get_ticks_msec(), Engine.time_scale])
	# 發送信號通知所有 Fighter，hit stop 已完成，可以開始 hitstun/knockback/blockstun
	emit_signal("hit_slowmo_finished")
	if pending_slowmo_request:
		pending_slowmo_request = false
		enter_slowmo_animation()

## 安全取消 hitstop（用於 reset / 離開場景）。不會發射 hit_slowmo_finished，
## 避免在重置時誤觸發 pending hitstun。
func cancel_hitstop() -> void:
	_setup_hitstop_controller()
	if hitstop_controller and hitstop_controller.has_method("cancel"):
		hitstop_controller.cancel()
	is_hit_slowmo = false
	pending_slowmo_request = false
	Engine.time_scale = normal_time_scale
	emit_signal("time_scale_changed", normal_time_scale)

# 手動切換慢動作開關（用於測試或手動控制）
func toggle_slowmo():
	request_slowmo_change()

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
			
			if Engine.is_editor_hint():
				continue
			
			if speed_scale < 1.0:
				pass
			else:
				pass
