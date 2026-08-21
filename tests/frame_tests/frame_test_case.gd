class_name FrameTestCase
extends RefCounted
## Frame 測試用例基類
##
## 每個測試用例:
##   1. extends FrameTestCase
##   2. 實作 run() -> bool（coroutine）
##   3. 用 check() 記錄失敗、await_frames() 等待物理幀、hold()/tap() 餵輸入
##
## 規則:
## - 用例之間 world 完全重新生成（狀態隔離）
## - 所有計時以「物理幀」為單位（120 FPS），1 邏輯幀 = 2 物理幀
## - 不依賴真實秒數（headless 環境下用 await physics_frame 推進）

var world: Node = null
var p1: Node = null
var p2: Node = null

var _failures: Array[String] = []

const FLOOR_Y_PX: float = 550.0
const SIM_SCALE: int = 1000

## 測試主體。回傳 true = 通過。必須 await 完所有步驟再回傳。
func run() -> bool:
	push_error("FrameTestCase.run() 必須被子類別覆寫")
	return false

## 等待 n 個物理幀
func await_frames(n: int) -> void:
	for i in n:
		await world.get_tree().physics_frame

## 按住輸入 action 共 n 個物理幀後釋放
func hold(action: String, n_frames: int) -> void:
	Input.action_press(action)
	await await_frames(n_frames)
	Input.action_release(action)

## 按下 1 個物理幀後立即釋放
func tap(action: String) -> void:
	Input.action_press(action)
	await await_frames(1)
	Input.action_release(action)

## 記錄一次斷言。cond 為 false 時累積失敗訊息（不中斷，跑完整個用例）。
func check(cond: bool, msg: String) -> bool:
	if not cond:
		_failures.append(msg)
	return cond

## 把 player 瞬移到 x 位置（px），y 固定在地面
func teleport_x(player: Node, x_px: float) -> void:
	player.fixed_position = Vector2i(int(x_px * float(SIM_SCALE)), int(FLOOR_Y_PX * float(SIM_SCALE)))
	player.global_position = player.world.to_scaled_vector2(player.fixed_position)
	player.fixed_velocity = Vector2i.ZERO

## player 的 x 座標（px）
func px(player: Node) -> float:
	return float(player.fixed_position.x) / float(SIM_SCALE)

## 在最多 max_frames 物理幀內等待條件成立（每幀檢查一次）
func wait_until(cond_fn: Callable, max_frames: int) -> bool:
	for i in max_frames:
		await await_frames(1)
		if cond_fn.call():
			return true
	return false

func has_failures() -> bool:
	return not _failures.is_empty()

func failure_report() -> String:
	if _failures.is_empty():
		return ""
	return "\n" + "\n".join(["  ✗ " + f for f in _failures])
