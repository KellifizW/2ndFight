extends FrameTestCase
## 火球生成（直接呼叫 MoveSet.start_fireball()，不模擬方向指令）
##
## DAV fireballM: 動畫 0.267s（16 邏輯幀 = 32 物理幀）時 Call Method
## 觸發 _spawn_fireball → execute_fireball_spawn → p1.active_fireball 設定
##
## 註: 輸入宏（QCF 等）的模擬測試留待後續階段，本測試驗證生成機制本身

func run() -> bool:
	await_frames(10)

	var ms = p1.move_set
	check(ms != null, "P1 MoveSet 節點不存在")
	if ms == null:
		return false

	ms.start_fireball()

	check(ms.is_spmove == true, "start_fireball 後 is_spmove 應為 true")

	# 等 fireball 節點生成（Call Method 在 16 邏輯幀後觸發）
	var spawned: bool = await wait_until(
		func():
			var pl = p1
			return pl.active_fireball != null and is_instance_valid(pl.active_fireball), 120)
	check(spawned, "fireball 應該在動畫 Call Method 時間點生成")
	if spawned:
		var fb = p1.active_fireball
		check(fb.global_position.x > p1.global_position.x, "fireball 應在 P1 前方（朝右）")
		# 特殊招式動畫播完後 is_spmove 應恢復 false（fireballM 動畫 47 邏輯幀 = 94 物理幀）
		var reset: bool = await wait_until(
			func():
				var m = ms
				return m.is_spmove == false, 300)
		check(reset, "fireball 動畫結束後 is_spmove 應恢復 false")

	return not has_failures()
