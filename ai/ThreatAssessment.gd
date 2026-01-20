class_name ThreatAssessment extends Node

enum ThreatLevel { NONE, LOW, MEDIUM, HIGH, CRITICAL }

class ThreatInfo:
	var level: ThreatLevel = ThreatLevel.NONE
	var source: String = ""
	var frames_until_hit: int = 999
	var recommended_response: String = ""

var attack_ranges: Dictionary = {
	"st_mp": 75.0, "st_mk": 95.0, "cr_mp": 70.0, "cr_mk": 90.0,
	"fireball": 600.0, "dp": 85.0, "powerkk": 120.0, "spnk": 95.0, "hdk": 90.0
}

var startup_frames: Dictionary = {
	"st_mp": 5, "st_mk": 7, "cr_mp": 4, "cr_mk": 6,
	"fireball": 15, "dp": 3, "powerkk": 12, "spnk": 10, "hdk": 12
}

func evaluate_threats(ai_player: Player, opponent: Player) -> ThreatInfo:
	var threat = ThreatInfo.new()
	
	# 檢查地面攻擊
	if opponent.is_attacking:
		var attack_threat = _evaluate_attack_threat(ai_player, opponent)
		if attack_threat.level > threat.level:
			threat = attack_threat
	
	# 檢查火球
	var projectile_threat = _evaluate_projectile_threat(ai_player, opponent)
	if projectile_threat.level > threat.level:
		threat = projectile_threat
	
	# 檢查空中攻擊
	if not opponent.is_on_floor() and opponent.get("is_air_attacking"):
		var air_threat = _evaluate_air_attack_threat(ai_player, opponent)
		if air_threat.level > threat.level:
			threat = air_threat
	
	return threat

func _evaluate_attack_threat(ai_player: Player, opponent: Player) -> ThreatInfo:
	var threat = ThreatInfo.new()
	var attack_type = opponent.attack_type if "attack_type" in opponent else "st_mp"
	threat.source = attack_type
	
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	var attack_range = attack_ranges.get(attack_type, 100.0)
	
	if distance > attack_range:
		return threat
	
	threat.frames_until_hit = _calculate_frames_to_hit(ai_player, opponent, attack_type)
	
	if threat.frames_until_hit < 8:
		threat.level = ThreatLevel.CRITICAL
		threat.recommended_response = _get_optimal_defense(attack_type)
	elif threat.frames_until_hit < 15:
		threat.level = ThreatLevel.HIGH
		threat.recommended_response = "stand_block"
	elif threat.frames_until_hit < 25:
		threat.level = ThreatLevel.MEDIUM
		threat.recommended_response = "backdash"
	
	return threat

func _evaluate_projectile_threat(ai_player: Player, opponent: Player) -> ThreatInfo:
	var threat = ThreatInfo.new()
	var projectiles = get_tree().get_nodes_in_group("fireball")
	
	for proj in projectiles:
		# 檢查火球是否屬於對手
		var proj_owner_id = proj.get("owner_character_id") if "owner_character_id" in proj else ""
		var ai_character_id = ai_player.character_id if "character_id" in ai_player else ""
		
		if proj_owner_id == ai_character_id:
			continue
		
		# 檢查火球是否活躍
		var is_active = proj.get("is_active") if "is_active" in proj else true
		if not is_active:
			continue
		
		var distance = abs(proj.global_position.x - ai_player.global_position.x)
		var velocity = proj.get("velocity") if "velocity" in proj else Vector2(300, 0)
		var speed_value = proj.get("speed") if "speed" in proj else 800.0
		
		# 使用實際速度計算衝擊幀數
		var actual_speed = speed_value if velocity.x == 0 else abs(velocity.x)
		var frames_to_impact = int((distance / actual_speed) * 60.0) if actual_speed > 0 else 999
		
		# 檢查火球方向（是否朝向AI玩家）
		var proj_direction = proj.get("direction") if "direction" in proj else 1
		var relative_dir = sign(ai_player.global_position.x - proj.global_position.x)
		
		# 如果火球不是朝向AI玩家，跳過
		if proj_direction != relative_dir:
			continue
		
		if frames_to_impact < threat.frames_until_hit:
			threat.frames_until_hit = frames_to_impact
			threat.source = "fireball"
			
			# 根據距離和時間選擇最佳應對策略
			if frames_to_impact < 15:  # 非常接近（<0.25秒）
				threat.level = ThreatLevel.CRITICAL
				# 近距離：格擋是最安全的選擇
				threat.recommended_response = "stand_block"
			
			elif frames_to_impact < 30:  # 接近（0.25-0.5秒）
				threat.level = ThreatLevel.HIGH
				if distance < 150:
					# 近距離：格擋
					threat.recommended_response = "stand_block"
				elif distance < 250:
					# 中距離：向前跳躍穿過火球
					threat.recommended_response = "jump_forward"
				else:
					# 較遠：向前跳躍接近
					threat.recommended_response = "jump_forward"
			
			elif frames_to_impact < 50:  # 中等距離（0.5-0.83秒）
				threat.level = ThreatLevel.MEDIUM
				if distance < 200:
					# 中近距離：跳躍避開
					threat.recommended_response = "jump_forward" if randf() > 0.3 else "jump_neutral"
				else:
					# 較遠距離：發射火球對抗或跳躍接近
					if ai_player and ai_player.move_set and not ai_player.move_set.is_spmove:
						# 有機會發波對抗
						threat.recommended_response = "fireball" if randf() > 0.4 else "jump_forward"
					else:
						threat.recommended_response = "jump_forward"
			
			else:  # 遠距離（>0.83秒）
				threat.level = ThreatLevel.LOW
				if distance > 300:
					# 超遠距離：發波對抗或向前移動
					if ai_player and ai_player.move_set and not ai_player.move_set.is_spmove:
						threat.recommended_response = "fireball" if randf() > 0.5 else "dash_forward"
					else:
						threat.recommended_response = "dash_forward"
				else:
					# 一般遠距離：跳躍接近
					threat.recommended_response = "jump_forward"
	
	return threat

func _evaluate_air_attack_threat(ai_player: Player, opponent: Player) -> ThreatInfo:
	var threat = ThreatInfo.new()
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	
	# 空中攻擊威脅判定
	if distance < 100.0:
		threat.source = "air_attack"
		threat.level = ThreatLevel.MEDIUM
		threat.recommended_response = "stand_block"
		
		# 如果對手很接近，提升威脅等級
		if distance < 50.0:
			threat.level = ThreatLevel.HIGH
	
	return threat

func _calculate_frames_to_hit(ai_player: Player, opponent: Player, attack_type: String) -> int:
	var attack_range = attack_ranges.get(attack_type, 100.0)
	var distance = abs(ai_player.global_position.x - opponent.global_position.x)
	
	if distance > attack_range:
		return 999
	
	var startup = startup_frames.get(attack_type, 10)
	var current_frame = _get_current_animation_frame(opponent)
	return max(0, startup - current_frame)

func _get_current_animation_frame(player: Player) -> int:
	if not player.animation_player:
		return 0
	var anim_length = player.animation_player.current_animation_length
	if anim_length <= 0:
		return 0
	var progress = player.animation_player.current_animation_position / anim_length
	return int(progress * 30)

func _get_optimal_defense(attack_type: String) -> String:
	if attack_type in ["cr_mk", "cr_mp"]:
		return "crouch_block"
	if attack_type.begins_with("jump_"):
		return "dp"
	return "stand_block"
