extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1 收尾：world 連段視窗 combo_reset_frames 必須是 int 物理幀、
## 每個 _physics_process 剛好 -1、歸零的那一幀呼叫 reset_combo。
##
## 舊版是 float 秒 + `-= delta`：hitstop 期間 delta 被 Engine.time_scale
## 縮放，視窗計數會被拉長最多 50×。本用例把幀制語義釘死，防止回退。

func run() -> bool:
	await await_frames(5)
	world.reset_combo()

	# 24 邏輯 hitstun → 24×2 + seconds_to_lock_frames(0.2) = 48 + 25 = 73 物理幀
	world._on_hit_detected(p2.name, 24, false, false)
	check(world.current_combo == 1, "命中應起始 combo=1，實為 %d" % world.current_combo)
	check(typeof(world.combo_reset_frames) == TYPE_INT,
		"combo_reset_frames 必須是 int，實為 %s" % type_string(typeof(world.combo_reset_frames)))
	check(world.combo_reset_frames == 73,
		"種子應為 73 物理幀，實為 %d" % world.combo_reset_frames)

	# 逐幀追蹤：單調遞減、步長恆為 1，最後恰好落在 0。
	var seen: Array[int] = []
	var guard: int = 0
	while world.combo_reset_frames > 0 and guard < 200:
		guard += 1
		seen.append(world.combo_reset_frames)
		await await_frames(1)
	seen.append(world.combo_reset_frames)

	check(seen.size() == 74, "應觀測 73→0 共 74 個值，實為 %d" % seen.size())
	for i in range(1, seen.size()):
		check(seen[i] == seen[i - 1] - 1,
			"第 %d 個樣本應恰好 -1（%d→實為 %d）" % [i, seen[i - 1], seen[i]])

	check(world.combo_reset_frames == 0, "計數歸零後不應變成負數")
	check(world.current_combo == 0, "視窗耗盡當幀應 reset_combo，實為 %d" % world.current_combo)
	return not has_failures()
