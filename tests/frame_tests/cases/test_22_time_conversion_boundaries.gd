extends "res://tests/frame_tests/frame_test_case.gd"
## Stage 1 轉換邊界公式釘選。
##
## 全代碼只允許三個秒↔幀 / 邏輯↔物理邊界（都在 Movement）：
##   1. seconds_to_lock_frames —— 舊「float 倒數」族（landing/knockfly/combo 緩衝）：
##      floor(s×120)+1，重現舊迴圈的實際格數。
##   2. seconds_to_frames_nearest —— 設計者秒數「種子」族（dash/jump-delay/
##      double-tap/layground/wakeup/attack-movement/air-hit-backjump）：round(s×120)。
##   3. logic_frames_to_physics_frames —— 邏輯幀（60FPS）×2。
## 本用例同時釘住「兩族不可互換」：若有人「好心」把 dash 種子改用 lock 式，
## 42→43 的單幀漂移會立刻爆掉。

func run() -> bool:
	# ── nearest 族：舊 int(round(sec*120)) 的每個站點都要逐位元一致 ──
	check(Movement.seconds_to_frames_nearest(0.35) == 42, "dash 0.35s 應 42 幀，實為 %d" % Movement.seconds_to_frames_nearest(0.35))
	check(Movement.seconds_to_frames_nearest(0.1) == 12, "jump delay 0.1s 應 12 幀，實為 %d" % Movement.seconds_to_frames_nearest(0.1))
	check(Movement.seconds_to_frames_nearest(0.3) == 36, "double-tap 0.3s 應 36 幀，實為 %d" % Movement.seconds_to_frames_nearest(0.3))
	check(Movement.seconds_to_frames_nearest(0.2) == 24, "layground/air-hit 0.2s 應 24 幀，實為 %d" % Movement.seconds_to_frames_nearest(0.2))
	check(Movement.seconds_to_frames_nearest(0.016) == 2, "AI critical interval 0.016s 應 2 幀（1 邏輯幀），實為 %d" % Movement.seconds_to_frames_nearest(0.016))
	check(Movement.seconds_to_frames_nearest(0.033) == 4, "AI decision interval 0.033s 應 4 幀（2 邏輯幀），實為 %d" % Movement.seconds_to_frames_nearest(0.033))
	check(Movement.seconds_to_frames_nearest(0.05) == 6, "AI relaxed interval 0.05s 應 6 幀（3 邏輯幀），實為 %d" % Movement.seconds_to_frames_nearest(0.05))
	check(Movement.seconds_to_frames_nearest(0.0) == 0, "0 秒必須是 0 幀")
	check(Movement.seconds_to_frames_nearest(-1.0) == 0, "負值須鉗為 0")

	# ── lock 族（不可與 nearest 混用）──
	check(Movement.seconds_to_lock_frames(0.2) == 25, "0.2s lock 應 25 幀，實為 %d" % Movement.seconds_to_lock_frames(0.2))
	check(Movement.seconds_to_lock_frames(0.35) == 43, "0.35s lock 應 43 幀 —— 这正是 dash 種子禁止改用 lock 式的原因")

	# ── 邏輯↔物理：×2 邊界，整數邏輯幀無捨入歧義 ──
	check(Movement.logic_frames_to_physics_frames(24) == 48, "24 邏輯幀應 48 物理幀，實為 %d" % Movement.logic_frames_to_physics_frames(24))
	check(Movement.logic_frames_to_physics_frames(10) == 20, "10 邏輯幀應 20 物理幀")
	check(Movement.logic_frames_to_physics_frames(1) == 2, "1 邏輯幀應 2 物理幀")
	check(Movement.logic_frames_to_physics_frames(0) == 0, "0 幀應為 0")
	# Fighter 上的委托入口必須與邊界同值（舊三套實作已收攏）
	check(p2.logic_frames_to_physics_frames(24) == 48, "Fighter 委托入口應與 Movement 邊界一致")

	# ── 角色身上的設計秒數種子與轉換結果相符 ──
	check(p1.double_tap_window_seconds == 0.3, "double-tap 種子應為 0.3 秒（改名自 double_tap_timer）")
	check(Movement.seconds_to_frames_nearest(p1.dash_time) == 42, "dash_time 種子換算應維持 42 幀")
	check(Movement.seconds_to_frames_nearest(p1.air_hit_backjump_duration) == 24, "空中受擊後跳應為 24 物理幀（舊 dur×60×2 同值）")
	check(Movement.seconds_to_frames_nearest(p1.floor_snap_immunity_duration) == 12, "floor snap 免疫應為 12 物理幀")
	return not has_failures()
