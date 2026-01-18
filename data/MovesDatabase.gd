# res://data/MovesDatabase.gd
# Data-driven move definitions - loads from .tres files
# Users can edit the .tres files in res://data/moves/ to change move properties
extends Node

static func get_all_moves() -> Dictionary:
	var moves = {}
	var move_names = ["powerkk", "spnk", "super", "dp", "hdk", "fireball"]
	
	for move_name in move_names:
		var path = "res://data/moves/%s.tres" % move_name
		var move_data = load(path)
		
		if move_data and move_data is SpecialMoveData:
			moves[move_name] = move_data
			print("[MovesDatabase] Loaded %s" % move_name)
		else:
			print("[MovesDatabase] WARNING: Could not load %s from %s" % [move_name, path])
			# Fallback to hardcoded defaults if file not found
			moves[move_name] = _get_default_move(move_name)
	
	return moves

# Fallback defaults if .tres files not found
static func _get_default_move(move_name: String) -> SpecialMoveData:
	match move_name:
		"powerkk":
			return SpecialMoveData.new("powerkk", "DAV", 12.0, 300.0, 0.933, 300.0, 0.0, 0.0, false, 0.3, false, 0.0, false, "special", 0.0, 0.0, 0.0)
		"spnk":
			return SpecialMoveData.new("spnk", "DEN", 12.0, 280.0, 1.2, 250.0, 0.0, 0.0, false, 0.3, false, 0.0, true, "special", 0.0, 0.0, 0.0)
		"super":
			return SpecialMoveData.new("super", "DAV", 5.0, 200.0, 2.6, 200.0, 0.9, -210.0, true, 0.3, false, 200000.0, false, "special", 0.0, 0.0, 0.0)
		"dp":
			return SpecialMoveData.new("dp", "DAV", 5.0, 320.0, 0.9, 100.0, 0.0667, -2000.0, false, 0.3, false, 6000000.0, true, "special", 6000000.0, -2500.0, 100.0)
		"hdk":
			return SpecialMoveData.new("hdk", "DEN", 15.0, 290.0, 1.1, 200.0, 0.0, 0.0, false, 0.3, false, 0.0, false, "special", 0.0, 0.0, 0.0)
		"fireball":
			return SpecialMoveData.new("fireball", "*", 10.0, 150.0, 0.3, 0.0, 0.0, 0.0, false, 0.3, true, 0.0, true, "fireball", 0.0, 0.0, 0.0)
		_:
			push_error("Unknown move: %s" % move_name)
			return SpecialMoveData.new()
