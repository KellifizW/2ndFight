# 🔧 多段Hit參數驗證腳本
# 確保DAVMoveSet中的多段招式參數正確加載和應用

extends Node

func verify_multihit_data():
	"""驗證100p和其他多段招式是否正確配置"""
	Debug.log("\n" + "=".repeat(70))
	Debug.log("🔧 多段Hit參數驗證")
	Debug.log("=".repeat(70))
	
	# 查找DAV角色和MoveSet
	var world = get_tree().root.get_child(0)  # 主場景
	var dav_player = null
	var den_player = null
	
	for child in world.get_children():
		if child.name == "Player":
			if "seat" in child and child.seat == "player_a":
				dav_player = child
		elif child.name == "Player2":
			if "seat" in child and child.seat == "player_b":
				den_player = child
	
	if dav_player == null:
		Debug.log("❌ 無法找到DAV角色 (Player/player_a)")
		return
	
	var move_set = dav_player.move_set if "move_set" in dav_player else null
	if move_set == null:
		Debug.log("❌ 無法找到MoveSet")
		return
	
	# 檢查100p招式
	if move_set.move_library.has("100p"):
		var move_100p = move_set.move_library["100p"]
		Debug.log("\n✅ 找到 100p 招式:")
		Debug.log("  - 招式名稱: %s" % move_100p.name)
		Debug.log("  - 是否多段: %s" % move_100p.is_multi_hit)
		Debug.log("  - Hit段數: %d" % move_100p.hit_phases.size())
		
		if move_100p.is_multi_hit and move_100p.hit_phases.size() > 0:
			Debug.log("  - ✅ 多段參數已加載")
			for i in move_100p.hit_phases.size():
				var phase = move_100p.hit_phases[i]
				Debug.log("    [段%d] frame=%d, damage=%.1f, hitstun=%d, blockstun=%d, knockback=%.1f" % [
					i + 1,
					phase.frame,
					phase.damage,
					phase.hitstun,
					phase.blockstun,
					phase.knockback
				])
		else:
			Debug.log("  - ❌ 多段參數缺失或為空")
	else:
		Debug.log("\n❌ 未找到 100p 招式在move_library中")
	
	# 檢查powerkk
	if move_set.move_library.has("powerkk"):
		var move_powerkk = move_set.move_library["powerkk"]
		Debug.log("\n✅ 找到 powerkk 招式:")
		Debug.log("  - 招式名稱: %s" % move_powerkk.name)
		Debug.log("  - 是否多段: %s" % move_powerkk.is_multi_hit)
		Debug.log("  - Hit段數: %d" % move_powerkk.hit_phases.size())
	
	Debug.log("\n" + "=".repeat(70))
	Debug.log("驗證完成")
	Debug.log("=".repeat(70) + "\n")

func _ready():
	call_deferred("verify_multihit_data")
