extends Node

@onready var parent: Node = get_parent()
var ai_enabled: bool = false
var current_state: String = "idle"
var state_timer: float = 0.0

func _ready() -> void:
    if parent:
        state_timer = randf() * 0.3 + 0.3
        if OS.is_debug_build():
            Debug.log("Debug: AIBehavior ready for %s!" % parent.name)
    else:
        if OS.is_debug_build():
            Debug.log("Warning: No parent Player found for AIBehavior")

func set_ai_enabled(enabled: bool) -> void:
    ai_enabled = enabled
    if enabled:
        current_state = "approach" if randf() > 0.2 else "idle"
        state_timer = randf() * 0.3 + 0.3
    if OS.is_debug_build():
        if parent:
            Debug.log("Debug: AI %s for %s" % ["enabled" if enabled else "disabled", parent.name])

func _process(delta: float) -> void:
    if not ai_enabled or not parent:
        return
        
    state_timer -= delta
    if state_timer <= 0:
        match current_state:
            "idle":
                current_state = "approach" if randf() > 0.3 else "idle"
                state_timer = randf() * 0.5 + 0.5
                
            "approach":
                var roll = randf()
                if roll < 0.6:
                    current_state = "attack"
                    state_timer = 0.4
                elif roll < 0.8:
                    current_state = "idle"
                    state_timer = randf() * 0.3 + 0.3
                else:
                    state_timer = randf() * 0.4 + 0.2
                    
            "attack":
                var roll = randf()
                if roll < 0.5:
                    current_state = "backoff"
                    state_timer = 0.5
                elif roll < 0.8:
                    current_state = "approach"
                    state_timer = randf() * 0.3 + 0.2
                else:
                    current_state = "idle"
                    state_timer = randf() * 0.4 + 0.3
                    
            "backoff":
                current_state = "approach" if randf() > 0.3 else "idle"
                state_timer = randf() * 0.4 + 0.3
                
        if OS.is_debug_build():
            Debug.log("Debug: AI State changed to %s for %s" % [current_state, parent.name])

func get_current_state() -> String:
    return current_state
