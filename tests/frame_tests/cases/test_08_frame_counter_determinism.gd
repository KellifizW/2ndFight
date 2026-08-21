extends FrameTestCase
## FrameCounter 確定性：60 物理幀後應精確推進 ~60 幀
## （驗證固定 120 FPS tick 與幀計數器的一致性——後續 Stage 1 統一時間域的基準）

func run() -> bool:
	var fc = world.frame_counter
	check(fc != null, "world.frame_counter 不存在")
	if fc == null:
		return false

	check(fc.is_paused == false, "FrameCounter 初始不應是暫停狀態")

	var f0: int = fc.get_current_frame()
	await await_frames(60)
	var f1: int = fc.get_current_frame()
	var diff: int = f1 - f0
	check(diff >= 58 and diff <= 62, "60 物理幀後 FrameCounter 應推進 60±2，實為 %d" % diff)

	# 邏輯幀換算：60 物理幀 = 30 邏輯幀
	var logic_diff: int = fc.get_logic_frame_difference(f0, f1)
	check(abs(logic_diff - 30) <= 1, "60 物理幀 = 30 邏輯幀，實為 %d" % logic_diff)

	return not has_failures()
