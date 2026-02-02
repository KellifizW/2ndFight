extends Node

class_name SlowMoController

signal time_scale_changed(new_time_scale: float)
signal hit_slowmo_finished  # 🟢 Hit stop 完成信號，讓 hitstun/knockback 在 hit stop 後開始

# ⚙️ 設置選項
@export var enable_hitstop: bool = true  # 是否開啟 hitstop 功能
@export var sync_animation_speed: bool = true  # 是否同步動畫速度（解決連段時機問題）

# 時間縮放參數
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
	print("Debug: SlowMoController initialized, time_scale set to %s, process_mode set to ALWAYS" % normal_time_scale)

func _process(_delta):
	pass

# 請求切換慢動作狀態（手動切換）
func request_slowmo_change():
	if slowmo_active:
		exit_slowmo_animation()
	else:
		enter_slowmo_animation()

# 請求擊中慢動作效果
func request_hit_freeze():
	if not enable_hitstop:
		print("Debug: Hit slowmo request ignored (enable_hitstop=%s)" % enable_hitstop)
		# 🟢 即使跳過慢動作，仍發送信號讓 hitstun/knockback 正常進行
		emit_signal("hit_slowmo_finished")
		return
	if slowmo_active or is_hit_slowmo:
		print("Debug: Hit slowmo request ignored (slowmo_active=%s, is_hit_slowmo=%s)" % [slowmo_active, is_hit_slowmo])
		return  # 避免重複觸發
	is_hit_slowmo = true
	if tween and tween.is_running():
		tween.kill()  # 停止正在運行的 Tween
	
	# 🟢 【修正】同步所有玩家的動畫速度，確保動畫與物理同步暫停
	if sync_animation_speed:
		_sync_player_animations(hit_slowmo_time_scale)
	
	tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_ignore_time_scale(true)  # 使用真實時間計時
	# 立即進入擊中慢動作
	Engine.time_scale = hit_slowmo_time_scale
	emit_signal("time_scale_changed", hit_slowmo_time_scale)
	# 除錯：記錄開始真實時間
	hit_start_time = Time.get_ticks_msec()
	# 持續慢動作 0.09 秒（真實時間）
	tween.tween_interval(hit_slowmo_time)
	# 退出慢動作（0.01秒，真實時間）
	tween.tween_property(Engine, "time_scale", normal_time_scale, hit_slowmo_exit_time)
	tween.tween_callback(_on_hit_slowmo_finished)
	print("Debug: Hit slowmo triggered, set time_scale=%s instantly, sustaining for %s seconds, then transitioning to %s over %s seconds (real time)" % [hit_slowmo_time_scale, hit_slowmo_time, normal_time_scale, hit_slowmo_exit_time])

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
	print("Debug: Entering slow motion, transitioning to time_scale=%s over %s seconds" % [slowmo_time_scale, slowmo_enter_time])

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
	print("Debug: Exiting slow motion, transitioning to time_scale=%s over %s seconds" % [normal_time_scale, slowmo_exit_time])

# 進入慢動作完成
func _on_enter_slowmo_finished():
	slowmo_active = true
	print("Debug: Slow motion activated, slowmo_active=%s" % slowmo_active)

# 退出慢動作完成
func _on_exit_slowmo_finished():
	slowmo_active = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)
	print("Debug: Slow motion deactivated, slowmo_active=%s, time_scale=%s" % [slowmo_active, Engine.time_scale])

# 擊中慢動作完成
func _on_hit_slowmo_finished():
	is_hit_slowmo = false
	Engine.time_scale = normal_time_scale  # 確保時間縮放完全恢復
	emit_signal("time_scale_changed", normal_time_scale)
	
	# 🟢 【修正】恢復所有玩家的動畫速度
	if sync_animation_speed:
		_sync_player_animations(1.0)
	
	# 除錯：計算並打印真實持續時間（秒）
	var duration_sec = (Time.get_ticks_msec() - hit_start_time) / 1000.0
	print("Debug: Hit slowmo duration: %s seconds" % duration_sec)
	print("Debug: Hit slowmo finished, is_hit_slowmo=%s, time_scale=%s" % [is_hit_slowmo, Engine.time_scale])
	# 🟢 發送信號通知所有 Fighter，hit stop 已完成，可以開始 hitstun/knockback/blockstun
	emit_signal("hit_slowmo_finished")
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
		print("[SLOWMO] 註冊玩家：%s" % player.name)

func unregister_player(player: Node) -> void:
	"""取消註冊玩家"""
	if player in affected_players:
		affected_players.erase(player)
		if Engine.is_editor_hint():
			return
		print("[SLOWMO] 取消註冊玩家：%s" % player.name)

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
				print("[SLOWMO SYNC] %s 動畫減速：%.3f" % [player.name, speed_scale])
			else:
				print("[SLOWMO SYNC] %s 動畫恢復：%.3f" % [player.name, speed_scale])
