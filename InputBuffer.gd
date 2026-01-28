class_name InputBuffer extends Node

# ============================================================
# INPUT BUFFER SYSTEM
# Fighting game input buffering for more lenient combo execution
# ============================================================

# Buffer window in frames (60 FPS)
const BUFFER_FRAMES: int = 30  

# Buffer entry structure
class BufferEntry:
	var action_name: String
	var timestamp: int  # Frame number when pressed
	var consumed: bool = false
	
	func _init(p_action: String, p_timestamp: int):
		action_name = p_action
		timestamp = p_timestamp

# Active buffered inputs
var buffered_inputs: Dictionary = {}  # action_name -> BufferEntry
var current_frame: int = 0

# ============================================================
# BUFFER MANAGEMENT
# ============================================================

func _physics_process(_delta: float) -> void:
	current_frame += 1
	_expire_old_inputs()

func record_input(action_name: String) -> void:
	"""Record a button press into the buffer"""
	if not buffered_inputs.has(action_name):
		buffered_inputs[action_name] = BufferEntry.new(action_name, current_frame)
		# Debug output (can be disabled in production)
		# print("Buffer: Recorded %s at frame %d" % [action_name, current_frame])

func is_input_buffered(action_name: String) -> bool:
	"""Check if an input is currently buffered and not consumed"""
	if not buffered_inputs.has(action_name):
		return false
	
	var entry: BufferEntry = buffered_inputs[action_name]
	if entry.consumed:
		return false
	
	var age = current_frame - entry.timestamp
	return age <= BUFFER_FRAMES

func consume_input(action_name: String) -> bool:
	"""Try to consume a buffered input. Returns true if successful."""
	if not is_input_buffered(action_name):
		return false
	
	var entry: BufferEntry = buffered_inputs[action_name]
	entry.consumed = true
	# print("Buffer: Consumed %s (age: %d frames)" % [action_name, current_frame - entry.timestamp])
	return true

func get_buffered_input(action_name: String) -> bool:
	"""Check and consume input in one call (most common usage)"""
	return consume_input(action_name)

func clear_input(action_name: String) -> void:
	"""Manually clear a specific buffered input"""
	buffered_inputs.erase(action_name)

func clear_all() -> void:
	"""Clear all buffered inputs (use on state transitions like getting hit)"""
	buffered_inputs.clear()

func _expire_old_inputs() -> void:
	"""Remove inputs that are too old or already consumed"""
	var to_remove: Array[String] = []
	
	for action_name in buffered_inputs.keys():
		var entry: BufferEntry = buffered_inputs[action_name]
		var age = current_frame - entry.timestamp
		
		# Remove if consumed or expired
		if entry.consumed or age > BUFFER_FRAMES:
			to_remove.append(action_name)
	
	for action_name in to_remove:
		buffered_inputs.erase(action_name)

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

func get_buffer_age(action_name: String) -> int:
	"""Get how many frames ago an input was pressed (-1 if not buffered)"""
	if not buffered_inputs.has(action_name):
		return -1
	
	var entry: BufferEntry = buffered_inputs[action_name]
	if entry.consumed:
		return -1
	
	return current_frame - entry.timestamp

func has_any_buffered() -> bool:
	"""Check if any inputs are currently buffered"""
	for entry in buffered_inputs.values():
		if not entry.consumed and (current_frame - entry.timestamp) <= BUFFER_FRAMES:
			return true
	return false

func get_active_buffers() -> Array[String]:
	"""Get list of all currently buffered (unconsumed) actions - for debugging"""
	var active: Array[String] = []
	for action_name in buffered_inputs.keys():
		if is_input_buffered(action_name):
			active.append(action_name)
	return active
