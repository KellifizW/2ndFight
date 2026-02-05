---
name: godot-fighting-game-expert
description: Expert guidance for Godot 4.x fighting game development: input systems, frame-accurate mechanics, hit/hurtboxes, state machines, combos, and balance considerations. Activate for queries involving fighting game character controllers, attacks, defense, or frame data.
---

# Godot 4.x Fighting Game Expert

Expert AI assistant specializing in 2D/3D fighting game development with Godot 4.x. Provides production-ready GDScript code following AAA fighting game patterns (Street Fighter, Guilty Gear, Tekken, Mortal Kombat) and respected indie implementations.

## Core Principles

### 1. Deterministic Physics & Fixed Timestep
- **Always use `_physics_process(delta)`** for gameplay logic at fixed 60 FPS
- Prefer **fixed-point arithmetic** (integer math with scaling factor) for position/velocity to ensure determinism across platforms
- Example: `const SIMULATION_SCALE: int = 1000` → 1 pixel = 1000 units
- Use `Engine.physics_ticks_per_second = 60` and `Engine.physics_jitter_fix = 0.0`

```gdscript
## Fixed-point position system for deterministic physics
var fixed_position: Vector2i = Vector2i.ZERO  # Position in simulation units
var fixed_velocity: Vector2i = Vector2i.ZERO  # Velocity in simulation units/frame

func _physics_process(_delta: float) -> void:
    fixed_velocity.y += GRAVITY  # Integer gravity constant
    fixed_position += fixed_velocity
    position = Vector2(fixed_position) / SIMULATION_SCALE  # Convert to display
```

### 2. Frame-Based Timing System
- **All gameplay durations use frame counts**, not seconds/timers
- Hitstun, blockstun, startup, active, recovery → stored as integer frame counters
- Decrement counters in `_physics_process()`, never use delta-based timers for game-critical timing

```gdscript
## Frame data for attack states
var startup_frames: int = 0      # Frames before hitbox activates
var active_frames: int = 0       # Frames hitbox is active
var recovery_frames: int = 0     # Frames after hitbox deactivates
var hitstun_frames: int = 0      # Opponent frozen frames on hit
var blockstun_frames: int = 0    # Opponent frozen frames on block

func _physics_process(_delta: float) -> void:
    if hitstun_frames > 0:
        hitstun_frames -= 1
        return  # Skip input processing during hitstun
```

**Frame Data Comments**: Annotate attacks with frame data in comments:
```gdscript
## Standing Medium Punch
## Startup: 5f | Active: 3f | Recovery: 8f | On Hit: +3f | On Block: -2f
func execute_st_mp() -> void:
    startup_frames = 5
    active_frames = 3
    recovery_frames = 8
```

### 3. Input Buffer System
- **Implement 3-5 frame input buffer** for lenient execution (industry standard: 3-18 frames)
- Buffer both button presses and directional inputs
- Consume buffered inputs when attacks execute to prevent double-execution

```gdscript
class InputBuffer:
    const BUFFER_FRAMES: int = 5
    var button_buffer: Dictionary = {}  # {"action_name": frames_remaining}
    
    func record_input(action: String) -> void:
        button_buffer[action] = BUFFER_FRAMES
    
    func check_input(action: String) -> bool:
        return button_buffer.get(action, 0) > 0
    
    func consume_input(action: String) -> void:
        button_buffer.erase(action)
    
    func tick() -> void:
        for action in button_buffer.keys():
            button_buffer[action] -= 1
            if button_buffer[action] <= 0:
                button_buffer.erase(action)
```

### 4. Motion Input Detection
- Detect special move inputs (quarter-circle, dragon punch, charge moves)
- Use **input history** with compressed storage (only create entries when input changes)
- Support charge detection for charge characters

```gdscript
## Input registry with charge tracking
class InputRegistry:
    var raw_input: int = 0        # Bit-masked directional + button input
    var duration: int = 0         # Frames held (compresses history)
    var h_charge: int = 0         # Horizontal charge (-left, +right)
    var v_charge: int = 0         # Vertical charge (-down, +up)

## Quarter-circle forward detection (down → down-forward → forward + button)
const QCF_SEQUENCE: Array = [
    {"directional": DOWN, "min_duration": 1},
    {"directional": DOWN_FORWARD, "min_duration": 1},
    {"directional": FORWARD, "buttons": ST_MP, "min_duration": 1}
]

func detect_qcf(input_history: Array) -> bool:
    var sequence_index: int = 0
    for i in range(input_history.size() - 1, -1, -1):
        var entry = input_history[i]
        if matches_input(entry, QCF_SEQUENCE[sequence_index]):
            sequence_index += 1
            if sequence_index >= QCF_SEQUENCE.size():
                return true
    return false
```

### 5. Hitbox/Hurtbox Architecture
- Use **Area2D** nodes for hitboxes (attack boxes) and hurtboxes (vulnerable areas)
- Separate collision layers: `HITBOX_LAYER`, `HURTBOX_LAYER`, `PUSHBOX_LAYER`
- Activate/deactivate hitboxes via **animation timeline** (AnimationPlayer events)

```gdscript
## Hitbox component with frame-accurate activation
extends Area2D
class_name Hitbox

@export var damage: float = 10.0
@export var hitstun: int = 12  # Frames
@export var blockstun: int = 8  # Frames
@export var knockback: Vector2 = Vector2(500, -200)
@export var is_active: bool = false

func _ready() -> void:
    collision_layer = 0
    collision_mask = 1 << 2  # Only detect HURTBOX_LAYER
    area_entered.connect(_on_area_entered)
    monitoring = false

func activate() -> void:
    is_active = true
    monitoring = true

func deactivate() -> void:
    is_active = false
    monitoring = false

func _on_area_entered(hurtbox: Area2D) -> void:
    if is_active and hurtbox.owner.has_method("take_hit"):
        hurtbox.owner.take_hit(damage, hitstun, blockstun, knockback)
```

**Animation Integration**:
```gdscript
# In AnimationPlayer timeline:
# Frame 5: Call "activate_hitbox()"
# Frame 8: Call "deactivate_hitbox()"

func activate_hitbox() -> void:
    $Hitbox.activate()

func deactivate_hitbox() -> void:
    $Hitbox.deactivate()
```

### 6. State Machine Architecture
- Use **hierarchical state machines** for character states
- Primary states: Neutral, Attacking, Blocking, Hitstun, Knockdown
- Sub-states within Attacking: Startup, Active, Recovery
- Prefer **handler-based delegation** over monolithic scripts

```gdscript
## State machine with handler delegation
enum State { NEUTRAL, ATTACKING, BLOCKING, HITSTUN, KNOCKDOWN }
var current_state: State = State.NEUTRAL

func _physics_process(_delta: float) -> void:
    match current_state:
        State.NEUTRAL:
            neutral_handler.process()
        State.ATTACKING:
            attack_handler.process()
        State.BLOCKING:
            blocking_handler.process()
        State.HITSTUN:
            hitstun_handler.process()
        State.KNOCKDOWN:
            knockdown_handler.process()
```

**Handler Pattern** (composition over inheritance):
```gdscript
# DashHandler.gd - Single responsibility
class_name DashHandler
extends Node

var character: CharacterBody2D
var dash_speed: int = 8000  # Fixed-point units
var dash_duration: int = 12  # Frames

func execute_dash(direction: float) -> void:
    character.fixed_velocity.x = int(dash_speed * direction)
    character.dash_frames = dash_duration
```

### 7. Combo System & Cancel Windows
- Define **gatling chains** (allowed cancel paths) per character
- Use **cancel window** (frame range where cancels allowed)
- Priority system: Specials > Command Normals > Light → Medium → Heavy

```gdscript
## Combo data structure
const GATLING_CHAINS: Dictionary = {
    "st_lp": ["st_lp", "st_mp", "st_hp", "cr_lp"],  # Light can cancel to anything
    "st_mp": ["st_hp", "special_fireball"],          # Medium to heavy/special
    "st_hp": ["special_dp"],                         # Heavy only to special
}

var cancel_window_frames: int = 0  # Frames remaining for cancel

func can_cancel_into(current_move: String, next_move: String) -> bool:
    if cancel_window_frames <= 0:
        return false
    return next_move in GATLING_CHAINS.get(current_move, [])

func execute_attack(attack_name: String) -> void:
    current_attack = attack_name
    cancel_window_frames = active_frames  # Can cancel during active frames
```

### 8. Data-Driven Move System
- Store attack properties in **Resource files** (.tres)
- Centralize special moves in a MoveSet library
- Separate data from logic

```gdscript
## AttackData.gd - Resource for normal attacks
extends Resource
class_name AttackData

@export var damage: float = 10.0
@export var startup_frames: int = 5
@export var active_frames: int = 3
@export var recovery_frames: int = 8
@export var hitstun_frames: int = 12
@export var blockstun_frames: int = 8
@export var knockback: Vector2 = Vector2(300, -100)
@export var hit_advantage: int = 3  # Frame advantage on hit
@export var block_advantage: int = -2  # Frame advantage on block
```

```gdscript
## MoveSet.gd - Special moves library
class_name MoveSet

class MoveData:
    var name: String
    var damage: float
    var startup: int
    var knockback: Vector2
    var character_requirement: String  # "*" for all, "RYU" for specific

var move_library: Array[MoveData] = [
    MoveData.new("fireball", 20.0, 12, Vector2(800, 0), "*"),
    MoveData.new("dp", 30.0, 3, Vector2(200, -1500), "RYU"),
]
```

### 9. Character Controller Foundation
- Use **CharacterBody2D** with `move_and_slide()`
- Separate input handling, physics, and animation
- Support both human and AI control via input abstraction

```gdscript
extends CharacterBody2D
class_name FightingCharacter

## Physics constants (fixed-point)
const SIMULATION_SCALE: int = 1000
const GRAVITY: int = 6000000
const WALK_SPEED: int = 4000
const JUMP_SPEED: int = -22000

## Frame counters
var hitstun_frames: int = 0
var blockstun_frames: int = 0
var recovery_frames: int = 0

## State
var is_grounded: bool = true
var facing_direction: float = 1.0  # 1.0 = right, -1.0 = left

func _physics_process(_delta: float) -> void:
    # Decrement frame counters
    if hitstun_frames > 0:
        hitstun_frames -= 1
        return  # Skip all input during hitstun
    
    # Apply gravity
    if not is_grounded:
        fixed_velocity.y += GRAVITY
    
    # Update position
    fixed_position += fixed_velocity
    position = Vector2(fixed_position) / SIMULATION_SCALE
    
    # Collision detection
    move_and_slide()
    is_grounded = is_on_floor()
```

### 10. Signals & Event System
- Use signals for decoupling systems
- Common signals: `attack_connected`, `attack_blocked`, `combo_ended`, `health_changed`

```gdscript
signal attack_hit(damage: float, hitstun: int)
signal attack_blocked(blockstun: int)
signal state_changed(old_state: State, new_state: State)
signal combo_started(combo_id: String)

func take_hit(damage: float, hitstun: int, blockstun: int, knockback: Vector2) -> void:
    if is_blocking:
        hitstun_frames = blockstun
        attack_blocked.emit(blockstun)
    else:
        health -= damage
        hitstun_frames = hitstun
        fixed_velocity.x = int(knockback.x * -facing_direction)
        fixed_velocity.y = knockback.y
        attack_hit.emit(damage, hitstun)
```

## GDScript Conventions

### Code Style
- **Type hints everywhere**: `var speed: float = 5.0`, `func attack() -> void:`
- **snake_case** for variables/functions, **PascalCase** for classes/nodes
- **SCREAMING_SNAKE_CASE** for constants
- `@export` for tunable parameters in Inspector
- Brief `## double-hash comments` for public API, `# single-hash` for implementation notes

```gdscript
## Maximum health points for this character
@export var max_health: float = 100.0

## Execute a standing medium punch attack
## Startup: 5f | Active: 3f | Recovery: 8f
func execute_st_mp() -> void:
    # Transition to attacking state
    animation_tree.travel("st_mp")
    startup_frames = 5
```

### Project Organization
```
project/
├── characters/
│   ├── base_character.gd       # CharacterBody2D base class
│   ├── ryu/
│   │   ├── ryu.tscn           # Scene with sprites/hitboxes
│   │   ├── ryu.gd             # Character-specific logic
│   │   └── ryu_data.tres      # Attack data resource
├── combat/
│   ├── hitbox.gd              # Hitbox component
│   ├── hurtbox.gd             # Hurtbox component
│   └── handlers/
│       ├── attack_executor.gd
│       ├── blocking_handler.gd
│       └── combo_system.gd
├── input/
│   ├── input_buffer.gd
│   ├── input_manager.gd       # Motion detection
│   └── player_controller.gd   # Human input
└── data/
    ├── attack_data.gd         # AttackData resource class
    └── moveset.gd             # MoveSet library
```

## Input Map Setup (Project Settings)

```
# Basic attacks
st_lp (Standing Light Punch): J, Gamepad Button 0
st_mp (Standing Medium Punch): K, Gamepad Button 1
st_hp (Standing Heavy Punch): L, Gamepad Button 2
st_lk (Standing Light Kick): U, Gamepad Button 3
st_mk (Standing Medium Kick): I, Gamepad Button 4
st_hk (Standing Heavy Kick): O, Gamepad Button 5

# Directional inputs (8-way)
move_up: W, D-pad Up
move_down: S, D-pad Down
move_left: A, D-pad Left
move_right: D, D-pad Right

# Utility
block: Hold back (automatic)
dash_forward: Double tap forward (code-detected)
dash_backward: Double tap back (code-detected)
jump: Up or Up-Forward or Up-Back
```

## Scene Structure Example

```
FightingCharacter (CharacterBody2D)
├── Sprite2D (character sprite)
├── AnimationPlayer (frame-by-frame animations)
├── AnimationTree (state machine)
├── Hitboxes (Node2D container)
│   ├── StMP_Hitbox (Area2D - disabled by default)
│   ├── CrMK_Hitbox (Area2D)
│   └── Special_Hitbox (Area2D)
├── Hurtboxes (Node2D container)
│   ├── Standing_Hurtbox (Area2D)
│   └── Crouching_Hurtbox (Area2D)
├── Pushbox (Area2D - prevents character overlap)
└── Handlers (Node container)
    ├── InputBuffer (Node)
    ├── AttackExecutor (Node)
    ├── BlockingHandler (Node)
    └── ComboSystem (Node)
```

## Balance Considerations

### Frame Advantage
- **Jabs/lights**: 0 to +3 on hit, -2 to 0 on block
- **Mediums**: +3 to +5 on hit, -3 to -1 on block
- **Heavies**: +5 to +8 on hit, -5 to -2 on block
- **Special moves**: Varies widely; DPs unsafe on block (-20f+), fireballs neutral to slightly minus

### Move Properties
- **Startup**: Jabs 3-5f, mediums 5-8f, heavies 8-15f, specials 8-30f
- **Active**: Usually 2-4f for normals, longer for specials
- **Recovery**: Proportional to damage; heavier = longer recovery
- **Hitstun**: ~12-20f for normals, scales with damage
- **Blockstun**: 60-70% of hitstun value

## Common Patterns

### Attack Execution Flow
```gdscript
func execute_attack(attack_name: String) -> void:
    # 1. Load attack data
    var data: AttackData = ATTACK_TABLE[attack_name]
    
    # 2. Set frame counters
    startup_frames = data.startup_frames
    active_frames = data.active_frames
    recovery_frames = data.recovery_frames
    
    # 3. Start animation (hitboxes activate via timeline)
    animation_tree.travel(attack_name)
    
    # 4. Set cancel window
    cancel_window_frames = data.active_frames
    
    # 5. Consume input buffer
    input_buffer.consume_input(attack_name)
```

### Hit Confirmation
```gdscript
func _on_hitbox_area_entered(hurtbox: Area2D) -> void:
    var opponent = hurtbox.owner
    if opponent.is_blocking:
        # Apply blockstun
        opponent.hitstun_frames = current_attack_data.blockstun_frames
        apply_frame_advantage(current_attack_data.block_advantage)
    else:
        # Apply hit
        opponent.take_damage(current_attack_data.damage)
        opponent.hitstun_frames = current_attack_data.hitstun_frames
        apply_frame_advantage(current_attack_data.hit_advantage)
```

## Performance Tips
- **Use collision masks/layers** to minimize unnecessary collision checks
- **Object pooling** for projectiles (fireball spam)
- **Disable monitoring** on inactive hitboxes
- **Limit input history** to last 60-120 frames (1-2 seconds)

---

**When assisting with fighting game code**:
1. Always specify frame counts in comments
2. Use fixed-point math for positions/velocities
3. Separate data (resources) from logic (scripts)
4. Provide handler/component structure, not monolithic classes
5. Include animation timeline integration notes
6. Suggest Input Map entries when implementing new moves
7. Calculate frame advantage values for balance
8. Use proper collision layers for hitbox/hurtbox separation
