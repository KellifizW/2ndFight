## 全局幀計數器 - 提供確定性的幀級時間追蹤
## 用於攻擊框架、優勢計算、hitstun/blockstun
class_name FrameCounter
extends Node

# 全局幀計數器（從遊戲開始累計，120 FPS 物理幀）
var global_frame: int = 0

# 暫停狀態（支持 slow-mo）
var is_paused: bool = false

# 🟢 【新增】FPS 轉換常數
const PHYSICS_FPS: int = 120  # 實際物理幀率
const LOGIC_FPS: int = 60     # 邏輯/顯示幀率（格鬥遊戲標準）
const FPS_RATIO: float = float(PHYSICS_FPS) / float(LOGIC_FPS)  # 2.0

func _ready() -> void:
	add_to_group("frame_counter")
	print("[FrameCounter] ✓ 幀計數器已初始化，開始於幀 0 (120 FPS 物理幀，自動轉換為 60 FPS 邏輯幀)")

func _physics_process(_delta: float) -> void:
	# 只在非暫停時遞增
	if not is_paused:
		global_frame += 1

## 取得當前幀數（120 FPS 物理幀）
func get_current_frame() -> int:
	return global_frame

## 🟢 【新增】取得當前邏輯幀數（60 FPS 基準，用於顯示）
func get_current_logic_frame() -> int:
	return int(global_frame / FPS_RATIO)

## 計算兩個幀數之間的差異（120 FPS 物理幀）
func get_frame_difference(start_frame: int, end_frame: int) -> int:
	return end_frame - start_frame

## 🟢 【新增】計算邏輯幀數差異（60 FPS 基準，用於顯示）
func get_logic_frame_difference(start_frame: int, end_frame: int) -> int:
	var physics_diff = end_frame - start_frame
	return int(physics_diff / FPS_RATIO)

## 將幀數轉換為秒數（基於 120 FPS 物理幀）
func frames_to_seconds(frames: int) -> float:
	return float(frames) / float(PHYSICS_FPS)

## 🟢 【新增】將邏輯幀數轉換為秒數（60 FPS 基準）
func logic_frames_to_seconds(logic_frames: int) -> float:
	return float(logic_frames) / float(LOGIC_FPS)

## 將秒數轉換為幀數（120 FPS 物理幀）
func seconds_to_frames(seconds: float) -> int:
	return int(round(seconds * float(PHYSICS_FPS)))

## 🟢 【新增】將秒數轉換為邏輯幀數（60 FPS 基準）
func seconds_to_logic_frames(seconds: float) -> int:
	return int(round(seconds * float(LOGIC_FPS)))

## 暫停計數器（slow-mo 使用）
func pause() -> void:
	if not is_paused:
		is_paused = true
		print("[FrameCounter] ⏸ 幀計數器已暫停（當前幀 %d 物理幀 / %d 邏輯幀）" % [global_frame, get_current_logic_frame()])

## 恢復計數器
func resume() -> void:
	if is_paused:
		is_paused = false
		print("[FrameCounter] ▶ 幀計數器已恢復（當前幀 %d 物理幀 / %d 邏輯幀）" % [global_frame, get_current_logic_frame()])

## 重置計數器（新遊戲/重新開始）
func reset() -> void:
	global_frame = 0
	is_paused = false
	print("[FrameCounter] 🔄 幀計數器已重置")

## 檢查是否超過指定幀數（物理幀）
func has_elapsed_frames(start_frame: int, duration: int) -> bool:
	return (global_frame - start_frame) >= duration

## 取得剩餘幀數（物理幀）
func get_remaining_frames(start_frame: int, duration: int) -> int:
	return max(0, duration - (global_frame - start_frame))

## 調試用：顯示當前幀數
func get_debug_info() -> String:
	var status = "暫停中" if is_paused else "執行中"
	return "幀 %d 物理 / %d 邏輯 (%s)" % [global_frame, get_current_logic_frame(), status]
