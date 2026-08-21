extends FrameTestCase
## 命中判定：P1 st_mp 打中 P2
##
## 幾何（DAV st_mp, 動畫驅動 hitbox）:
##   - st_mp hitbox: 動畫第 5~7 邏輯幀激活，size 145x40 @ (+75, -70)
##   - P1 在 x=550 → hitbox 前緣到 x≈698
##   - P2 hurtbox: 120x290 以 P2 為中心 → P2 放 x=680 時左緣 620，重疊 OK
##   - 距離 130px > pushbox 分離距離 (45+45)，不會被 PushManager 推開
##
## 期望（DAV attack_data = p1_attack_data.tres, st_mp 未覆蓋 → 用預設值）:
##   - damage = 6.0 → P2 血量 94.0
##   - hitstun = 24 邏輯幀 = 48 物理幀（hitstun_frames）
##   - 無 knockfly（damage < 10）
##   - hitstun 結束後 P2 恢復

func run() -> bool:
	await await_frames(10)
	teleport_x(p2, 680.0)
	await await_frames(5)

	check(p2.is_on_floor(), "P2 teleport 後應在地面")
	check(p2.is_attacking == false, "P2 初始不應該在攻擊")

	Input.action_press("st_mp")
	await await_frames(1)
	Input.action_release("st_mp")

	# hitstop 會把 Engine.time_scale 壓到 0.02 ~0.13s（真實時間），
	# 物理幀推進變慢，所以用足夠長的等待窗口
	var seen_hitstun_48: bool = false
	var took_damage: bool = false
	var saw_knockfly: bool = false
	for i in 300:  # 最多 2.5 秒（真實時間）
		await await_frames(1)
		if p2.hitstun_frames == 48:
			seen_hitstun_48 = true
		if p2.healthbar and p2.healthbar.current_health < 100.0:
			took_damage = true
		if p2.is_knockfly:
			saw_knockfly = true
		if seen_hitstun_48 and took_damage and p2.hitstun_frames < 48:
			# 已觀察到 48 幀且開始遞減 → 命中事件已完整
			break

	check(took_damage, "P2 應該受到 st_mp 傷害")
	if p2.healthbar:
		check(abs(p2.healthbar.current_health - 94.0) < 0.001, "P2 血量應為 94.0（-6.0），實為 %s" % p2.healthbar.current_health)
	check(seen_hitstun_48, "P2 hitstun_frames 應為 48（24 邏輯幀 × 2）")
	check(saw_knockfly == false, "damage=6 不應觸發 knockfly")

	# 恢復：hitstun 遞減到 0
	var check_recovered := func():
		var t = p2
		return t.hitstun_frames == 0 and not t.is_hit
	var recovered: bool = await wait_until(check_recovered, 900)
	check(recovered, "P2 應從 hitstun 恢復")

	return not has_failures()
