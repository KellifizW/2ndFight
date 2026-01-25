# CancelWindowHandler.gd
# 職責: 管理取消窗口系統（Gatling/Cancel system）
# 遷移自 Player.gd 的取消窗口相關邏輯

class_name CancelWindowHandler extends Node

signal cancel_triggered(from_attack: String, to_attack: String)

var parent_player: Player = null

# 取消窗口狀態
var is_window_open: bool = false
var allowed_targets: Array = []
var pending_targets: Array = []  # 待開啟的取消目標（等待擊中確認）

func _ready() -> void:
	parent_player = get_parent() as Player
	if not parent_player:
		push_error("[CancelWindowHandler] Must be child of Player node!")
		return

func open_window(allowed_moves: Array = []) -> void:
	"""準備取消窗口（由動畫軌道調用，等待擊中確認）"""
	pending_targets = allowed_moves.duplicate()
	print("[CancelWindowHandler] %s 準備取消窗口（等待擊中確認），允許: %s" % [
		parent_player.attack_type if parent_player else "UNKNOWN",
		allowed_moves
	])

func close_window() -> void:
	"""關閉取消窗口（由動畫軌道調用）"""
	is_window_open = false
	allowed_targets = []
	# 保留 pending_targets，因為擊中確認可能在窗口關閉後才觸發（slowmo延遲）
	print("[CancelWindowHandler] 取消窗口關閉（pending targets 保留給擊中確認）")

func on_hit_confirm() -> void:
	"""擊中確認取消（Hit-Confirm Cancel）：只有在擊中對手時才真正開啟取消窗口"""
	if pending_targets.size() > 0:
		is_window_open = true
		allowed_targets = pending_targets.duplicate()
		print("[CancelWindowHandler] ✓ 擊中確認！開啟取消窗口，允許: %s" % allowed_targets)
		# 使用後立即清空，避免重複觸發
		pending_targets = []
	else:
		print("[CancelWindowHandler] ✗ 擊中但無待開啟的取消窗口（pending_targets 為空）")

func check_cancel(input_move: String, current_attack: String) -> bool:
	"""
	檢查是否可以執行取消
	返回 true 表示允許取消，false 表示不允許
	"""
	if not is_window_open or allowed_targets.size() == 0:
		return false
	
	if input_move == "none":
		return false
	
	if input_move in allowed_targets:
		print("[CancelWindowHandler] ✓ 取消 %s → %s" % [current_attack, input_move])
		cancel_triggered.emit(current_attack, input_move)
		return true
	else:
		print("[CancelWindowHandler] ✗ %s 不能取消成 %s（允許: %s）" % [
			current_attack, input_move, allowed_targets
		])
		return false

func reset() -> void:
	"""重置取消窗口狀態（攻擊結束時調用）"""
	is_window_open = false
	allowed_targets = []
	pending_targets = []

func get_state() -> Dictionary:
	"""獲取當前狀態（用於調試）"""
	return {
		"is_open": is_window_open,
		"allowed": allowed_targets,
		"pending": pending_targets
	}
