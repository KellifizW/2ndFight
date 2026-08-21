extends Node
## 【DEBUG SCRIPT】 Monitors knockfly→layground→wakeup animation sequence
## Verifies timer values and state transitions during knockdown flow

class_name KnockflyAnimationDebugger

var player_a: Node = null
var player_b: Node = null
var enabled: bool = true
var show_all_states: bool = false  # Set to true to see all state checks
var verbose_mode: bool = false  # Enables detailed frame-by-frame logs

# Tracking flags
var _last_knockfly_state: bool = false
var _last_layground_state: bool = false
var _last_wakeup_state: bool = false
var _knockfly_entered_frame: int = 0
var _layground_entered_frame: int = 0
var _wakeup_entered_frame: int = 0

func _ready() -> void:
	var world = get_tree().root.get_child(0)  # Assumes world is first scene
	if world and "player_a" in world:
		player_a = world.player_a
		player_b = world.player_b
		Debug.log("[KNOCKFLY DEBUGGER] ✅ Initialized - Monitoring both players")
	else:
		enabled = false
		Debug.log("[KNOCKFLY DEBUGGER] ❌ Could not find players")

func _physics_process(_delta: float) -> void:
	if not enabled or not player_a:
		return
	
	_check_player_state(player_a, "Player A")
	_check_player_state(player_b, "Player B")

func _check_player_state(player: Node, name: String) -> void:
	if not player or not ("is_knockfly" in player):
		return
	
	var is_knockfly: bool = player.is_knockfly
	var is_layground: bool = player.is_layground if "is_layground" in player else false
	var is_wakeup: bool = player.is_wakeup if "is_wakeup" in player else false
	
	var knockfly_timer: float = player.knockfly_timer if "knockfly_timer" in player else 0
	var layground_timer: int = player.layground_timer if "layground_timer" in player else 0
	var wakeup_timer: int = player.wakeup_timer if "wakeup_timer" in player else 0
	
	var curr_anim: String = ""
	if "animation_state" in player and player.animation_state:
		var travel_path = player.animation_state.states.travel_path if "states" in player.animation_state else []
		curr_anim = travel_path[-1] if travel_path.size() > 0 else "unknown"
	
	# ── Detect state transitions ──
	if is_knockfly and not _last_knockfly_state:
		_knockfly_entered_frame = Engine.get_physics_frames()
		Debug.log("\n🔴 [%s] KNOCKFLY STARTED (Frame %d)" % [name, _knockfly_entered_frame])
		Debug.log("  📍 knockfly_timer: %.3f seconds" % knockfly_timer)
		Debug.log("  🎬 Animation: %s" % curr_anim)
	
	elif is_layground and not _last_layground_state and not is_knockfly:
		_layground_entered_frame = Engine.get_physics_frames()
		var knockfly_duration = _layground_entered_frame - _knockfly_entered_frame
		Debug.log("\n🟡 [%s] LAYGROUND STARTED (Frame %d)" % [name, _layground_entered_frame])
		Debug.log("  ⏱️  Knockfly lasted: %d frames" % knockfly_duration)
		Debug.log("  ⏱️  layground_timer: %d frames" % layground_timer)
		Debug.log("  🎬 Animation: %s" % curr_anim)
	
	elif is_wakeup and not _last_wakeup_state and not is_layground:
		_wakeup_entered_frame = Engine.get_physics_frames()
		var layground_duration = _wakeup_entered_frame - _layground_entered_frame
		Debug.log("\n🟢 [%s] WAKEUP STARTED (Frame %d)" % [name, _wakeup_entered_frame])
		Debug.log("  ⏱️  Layground lasted: %d frames" % layground_duration)
		Debug.log("  ⏱️  wakeup_timer: %d frames" % wakeup_timer)
		Debug.log("  🎬 Animation: %s" % curr_anim)
	
	elif not is_knockfly and not is_layground and not is_wakeup and (_last_knockfly_state or _last_layground_state or _last_wakeup_state):
		var total_sequence = Engine.get_physics_frames() - _knockfly_entered_frame
		Debug.log("\n✅ [%s] SEQUENCE COMPLETE (Frame %d)" % [name, Engine.get_physics_frames()])
		Debug.log("  ⏱️  Total knockdown duration: %d frames (%.3f seconds @ 120 FPS)" % [total_sequence, total_sequence / 120.0])
		Debug.log("  🎬 Animation: %s" % curr_anim)
	
	# Verbose frame-by-frame logging
	if verbose_mode and (is_knockfly or is_layground or is_wakeup):
		Debug.log("[%s-Frame%d] KF:%s LG:%s WU:%s | KF_timer:%.3f LG_timer:%d WU_timer:%d | Anim:%s" % [
			name, Engine.get_physics_frames(),
			"✓" if is_knockfly else "✗",
			"✓" if is_layground else "✗",
			"✓" if is_wakeup else "✗",
			knockfly_timer, layground_timer, wakeup_timer,
			curr_anim
		])
	
	# Update tracking flags
	_last_knockfly_state = is_knockfly
	_last_layground_state = is_layground
	_last_wakeup_state = is_wakeup

func enable() -> void:
	enabled = true
	Debug.log("[KNOCKFLY DEBUGGER] Enabled")

func disable() -> void:
	enabled = false
	Debug.log("[KNOCKFLY DEBUGGER] Disabled")

func toggle() -> void:
	enabled = not enabled
	Debug.log("[KNOCKFLY DEBUGGER] %s" % ("Enabled" if enabled else "Disabled"))
