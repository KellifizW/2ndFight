extends Node

class_name SlowMoController

signal time_scale_changed(new_time_scale: float)
signal hit_slowmo_finished  # 🟢 Hit stop 完成信號，讓 hitstun/knockback 在 hit stop 後開始

# ⚙️ 設置選項
@export var enable_hitstop: bool = true  # 是否開啟 hitstop 功能（主開關）
@export var sync_animation_speed: bool = true  # @deprecated 舊版用全域 time_scale 凍結時需要的手動同步開關；新架構（HitStopManager）動畫凍結是核心機制、恆常生效，此欄位保留僅供舊除錯腳本（HitStopTestScript 的 O 鍵）相容

# 時間縮放參數 —— 只用於「手動慢動作 / KO 慢動作」（整場拖慢的戲劇效果）。
# hitstop 不再使用 Engine.time_scale：那會連 VFX 粒子、火花、UI、音效一起凍住，
# 產生「遊戲當機」的死亡感（參見 HitStopManager 的註解）。
var normal_time_scale: float = 1
var slowmo_time_scale: float = 0.2

# 追蹤受影響的玩家（保留為空以維持舊 API；新架構直接從 "players" group 取）
var affected_players: Array[Node] = []
var slowmo_enter_time: float = 0.4
var slowmo_exit_time: float = 0.4
var slowmo_active: bool = false
var is_hit_slowmo: bool = false     # 標記是否處於擊中定格狀態（角色層凍結的開關，Fighter/Player/PushManager/FrameBar 都讀它）
var pending_slowmo_request: bool = false  # 延遲在 hit stop 結束後啟動 slowmo

# 專門的 HitStop 管理器（World/SlowMoController/HitStopManager）
# 所有 hitstop 參數（時長 / jitter）都是 @export，在編輯器直接調。
var hit_stop_manager: HitStopManager = null

# Tween 用於平滑過渡（手動慢動作專用）
var tween: Tween

func _ready():
	# 設置 process_mode 為始終運行
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 確保初始時間縮放為正常
	Engine.time_scale = normal_time_scale
	emit_signal("time_scale_changed", normal_time_scale)
	hit_stop_manager = get_node_or_null("HitStopManager")
	if hit_stop_manager:
		hit_stop_manager.hitstop_ended.connect(_on_hitstop_ended)
		Debug.log("Debug: SlowMoController initialized, time_scale set to %s, process_mode set to ALWAYS, HitStopManager attached" % normal_time_scale)
	else:
		Debug.log("Debug: SlowMoController initialized (⚠️ HitStopManager 節點缺失，hitstop 將無效果)")

# 請求切換慢動作狀態（手動切換 / KO 戲劇效果）
func request_slowmo_change():
	if is_hit_slowmo:
		pending_slowmo_request = true
		Debug.log("Debug: Slowmo request deferred until hit stop ends")
		return
	if slowmo_active:
		exit_slowmo_animation()
	else:
		enter_slowmo_animation()

## 請求擊中定格（HitStop）—— 由 HitResponseHandler / fireball.gd 在命中時調用。
##
## 新架構（解耦式 hitstop）：不再把 Engine.time_scale 壓到 0.02 做全域凍結
## （那會連背景特效、火花粒子、UI 計時器、音效一起凍住，畫面死寂、打擊感喪失）。
## 現在委派給 HitStopManager：
##   - 只凍結角色動畫（speed_scale=0）與角色物理（Movement/Player 早退）
##   - 定格期間對角色 sprite 疊加像素級微震抖（Frame Jitter）
##   - VFX 粒子 / 音效 / UI / 鏡頭全程正常速度播放
##   - 經固定邏輯幀數後自動還原，並發 hit_slowmo_finished 讓 hitstun/knockback 開始
##
## attack_type: 攻擊型別（st_mp / jump_hk / powerkk / fireball...），用於選擇 @export 時長。
## is_blocked:  格擋命中用更短的定格（block_hit_frames）。
func request_hit_freeze(attack_type: String = "", is_blocked: bool = false):
	if not enable_hitstop:
		Debug.log("Debug: Hit stop request ignored (enable_hitstop=%s)" % enable_hitstop)
		# 🟢 即使跳過定格，仍發送信號讓 hitstun/knockback 正常進行
		emit_signal("hit_slowmo_finished")
		return
	if slowmo_active or is_hit_slowmo:
		Debug.log("Debug: Hit stop request ignored (slowmo_active=%s, is_hit_slowmo=%s)" % [slowmo_active, is_hit_slowmo])
		return  # 避免重複觸發
	is_hit_slowmo = true
	
	# 🟢 暫停幀計數器（frame 數據 / 優勢計算基準，與舊版一致）
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter:
		frame_counter.pause()
	
	if hit_stop_manager == null:
		push_error("SlowMoController: HitStopManager 節點缺失（World/SlowMoController/HitStopManager），hitstop 跳過")
		# 沒有管理器的退化路徑：立即「結束」，讓 hitstun/knockback 不受阻
		_on_hitstop_ended()
		return
	
	hit_stop_manager.request_hitstop(attack_type, is_blocked)
	if not hit_stop_manager.is_active:
		# 安全網：時長參數全為 0 時管理器不會啟動 —— 立即「結束」，
		# 避免 is_hit_slowmo 卡住 true 把角色永久癱瘓
		_on_hitstop_ended()

# 進入慢動作的動畫（手動切換 / KO）
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

# 退出慢動作的動畫（手動切換 / KO）
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

# 擊中定格完成（HitStopManager 的 hitstop_ended 回調）
func _on_hitstop_ended():
	is_hit_slowmo = false
	# 安全性：新架構 hitstop 完全不動 Engine.time_scale，這裡只確保回到正常值
	# （若 KO 慢動作正在進行，pending_slowmo_request 分支會重新 tween 到 slowmo）
	if not pending_slowmo_request:
		Engine.time_scale = normal_time_scale
		emit_signal("time_scale_changed", normal_time_scale)
	
	# 🟢 恢復幀計數器
	var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
	if frame_counter:
		frame_counter.resume()
	
	# 🟢 發送信號通知所有 Fighter，hit stop 已完成，可以開始 hitstun/knockback/blockstun
	emit_signal("hit_slowmo_finished")
	if pending_slowmo_request:
		pending_slowmo_request = false
		enter_slowmo_animation()

# 手動切換慢動作開關（用於測試或手動控制）
func toggle_slowmo():
	request_slowmo_change()

## 強制清除 hitstop 狀態（world.reset_players 用）：
## 還原被凍結的動畫 / sprite 偏移、清計數器，並同步 is_hit_slowmo 旗標。
func clear_hitstop():
	if hit_stop_manager:
		hit_stop_manager.hard_reset()
	is_hit_slowmo = false

# ═══════════════════════════════════════════════════════════════════════
# 舊版 register_player / _sync_player_animations 已移除：
# 那套「手動同步所有玩家 AnimationPlayer.speed_scale」是全域 time_scale 凍結的
# 補救措施。新架構由 HitStopManager 直接對每個角色做 speed_scale=0 凍結 +
# jitter，不需要這層同步（affected_players 保留空陣列維持舊 API）。
# ═══════════════════════════════════════════════════════════════════════

func register_player(player: Node) -> void:
	"""註冊玩家（保留舊 API；新架構不需手動註冊）"""
	if player not in affected_players:
		affected_players.append(player)

func unregister_player(player: Node) -> void:
	"""取消註冊玩家（保留舊 API）"""
	if player in affected_players:
		affected_players.erase(player)
