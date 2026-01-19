# 2D Fighting Game - Godot 4.x Codebase Instructions

## Architecture Overview

This is a **Godot 4.x 2D fighting game** using a **fixed-point physics system** and **data-driven architecture** for precise, deterministic combat. The game follows AAA fighting game patterns (Street Fighter, Tekken) with modular handler-based design.

### Core Class Hierarchy
```
Movement (Node2D) → Fighter → Player
```
- **Movement**: Base physics, handlers (11 specialized handlers), fixed-point math
- **Fighter**: Damage, hitstun/blockstun (frame-based), collision detection
- **Player**: Attack systems, combos, AI/human input integration

### Critical Systems

#### 1. Fixed-Point Physics System
**Everything uses integer fixed-point math** (SIMULATION_SCALE = 1000):
```gdscript
// World constants (world.gd)
const SIMULATION_SCALE: int = 1000  // 1 pixel = 1000 units
const TICKS_PER_SECOND: int = 60    // Fixed 60 FPS physics
const GRAVITY: int = 6000000        // Gravity in fixed-point units
const FLOOR_Y: int = 570000         // Floor position

// Players use fixed_position/fixed_velocity (Vector2i)
player.fixed_position = Vector2i(x * 1000, y * 1000)
player.fixed_velocity.x = int(speed * world.SIMULATION_SCALE)
```

**Why**: Ensures deterministic physics for online play and replays. Never use float arithmetic for position/velocity.

#### 2. Handler-Based Movement Architecture
Movement.gd delegates to **11 specialized handlers** (see [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md)):
- `InputHandler`: Input retrieval
- `AnimationManager`: Animation tree state management
- `DashHandler`, `JumpHandler`, `WalkHandler`: Movement mechanics
- `BlockingHandler`, `FacingHandler`: Defensive/orientation logic
- `KnockflyHandler`, `GravityHandler`, `LandingHandler`: Physics states
- `TimerHandler`: All timer decrements

**When modifying movement**: Edit the appropriate handler, not Movement.gd directly.

#### 3. Data-Driven Move System
**All attacks/specials use resource-based data** (see [MOVESET_REFACTORING_SUMMARY.md](MOVESET_REFACTORING_SUMMARY.md)):

```gdscript
// MoveSet.gd - Centralized move library
class MoveData:
    var name: String
    var character_requirement: String  // "DAV", "DEN", "*"
    var damage, knockback, duration: float
    var move_distance, jump_speed: float
    // ...

// Normal attacks: AttackData/*.tres resources
@export var attack_data: AttackData
ATTACK_TABLE = {
    "st_mp": attack_data.st_mp,  // Each attack is a .tres resource
    "cr_mk": attack_data.cr_mk,
}
```

**To add new moves**: Create MoveData entry in move_library, don't add scalar variables.

#### 4. Dual-Player System ("Seat" Architecture)
Players distinguished by **seat** (`"player_a"` or `"player_b"`), NOT by ID:
```gdscript
// PlayerController.gd
var player_seat: String = "player_a"  // Set by Player._ready()
var suffix = "_p2" if player_seat == "player_b" else ""
Input.is_action_just_pressed("st_mp" + suffix)
```

#### 5. Input Buffer System
**5-frame input buffer** for lenient execution (see [INPUT_BUFFER_IMPLEMENTATION.md](INPUT_BUFFER_IMPLEMENTATION.md)):
```gdscript
// PlayerController records inputs
input_buffer.record_input("st_mp")

// Player consumes buffered inputs
if input_data.st_mp_pressed:
    player_controller.consume_button_input("st_mp")
```

**Buffer window**: 5 frames (~83ms). Adjust `BUFFER_FRAMES` in InputBuffer.gd if needed.

#### 6. Special Move Detection
**InputManager.gd** detects motion inputs (quarter-circles, DPs, etc.):
```gdscript
// Sequence matching with frame-perfect timing
const FIREBALL_SEQUENCE = [
    {"directional": DOWN, "buttons": NONE, ...},
    {"directional": DOWN_FORWARD, ...},
    {"directional": FORWARD, "buttons": ST_MP, ...}
]
```

Directional inputs use **relative to facing** (auto-mirrored for player_b).

### Key File Map

| File | Purpose |
|------|---------|
| `world.gd` | Main game loop, player spawning, physics constants |
| `Movement.gd` | Base physics, handler orchestration |
| `Fighter.gd` | Hitstun/blockstun (frame-based), damage system |
| `Player.gd` | Attack execution, combo logic, AI integration |
| `MoveSet.gd` | Special moves library (data-driven) |
| `PlayerController.gd` | Input handling, buffer management, seat system |
| `InputManager.gd` | Motion input detection (quarter-circles, DPs) |
| `InputBuffer.gd` | 5-frame input buffer implementation |
| `PushManager.gd` | Pushbox collision, corner push physics |

### Animation System
Uses **AnimationTree with StateMachine**:
```gdscript
animation_state.travel("st_mp")  // Transition to state
animation_tree.set("parameters/conditions/Walk", true)

// Animation resets via callbacks
player_anim_resets = {
    "st_mp": func(): reset_attack_state(),
    "landing": func(): reset_landing_state(),
}
```

**Critical**: Animations drive frame data (hitboxes, cancels). Always sync animation_player events with gameplay logic.

## Development Workflows

### Running the Game
```powershell
# Launch Godot editor
& "C:\Users\t-way\Desktop\Godot.exe" --path "c:\Users\t-way\Documents\2ndFight\2ndfight\2ndFight"

# Stop all Godot instances
Stop-Process -Name "Godot*" -Force
```

### Common Tasks

**Add new normal attack**:
1. Create attack data resource in `data/*.tres`
2. Add to Player.ATTACK_TABLE
3. Create animation in AnimationPlayer
4. Add hitbox activation in animation timeline
5. Add buffer consumption in Player.gd attack section

**Add new character**:
1. Create `characters/XXX.character.tres` (CharacterData)
2. Create character scene `characters/XXX.tscn` with animations
3. Set character_data.short_id (e.g., "WOO")
4. Add character-specific moves to MoveSet with character_requirement

**Debug input buffer**:
1. Attach InputBufferDebug.gd to a Label node
2. Enable in Inspector: `Enabled ☑️`, `Show Both Players ☑️`, `Show Statistics ☑️`
3. Shows buffered input counts and timing (see INPUT_BUFFER_IMPLEMENTATION.md lines 173-196)

### Frame-Based Timing Convention
**All durations use frame counts** converted at runtime:
```gdscript
const FPS: int = 60
func sec_to_frames(seconds: float) -> int:
    return int(round(seconds * PHYSICS_FPS))

// Hitstun/blockstun use frame counters
hitstun_frames = sec_to_frames(0.4)  // 24 frames
blockstun_frames -= 1  // Decrement per frame
```

**Never use delta-based timers for gameplay-critical timing** (hitboxes, combos, invincibility).

## Project-Specific Conventions

### Naming Patterns
- **Attacks**: `st_mp` (standing medium punch), `cr_mk` (crouching medium kick), `jump_mp`
- **States**: `is_knockfly`, `is_dashing`, `is_landing`, `is_air_attacking`
- **Timers**: Suffix `_timer` for delta-based, `_frames` for frame counters
- **Handlers**: Suffix `Handler` (e.g., `DashHandler.gd`)

### State Management Rules
1. **Hitstun/blockstun**: Use `hitstun_frames`/`blockstun_frames` (Fighter.gd), NOT timers
2. **Landing lock**: Prevents input during landing_duration (default 0.2s)
3. **Facing lock**: Special moves lock facing via `is_facing_locked` flag
4. **Cancel windows**: Use `cancel_window_timer` for combo cancels

### Animation Condition Management
**Always reset animation conditions** after state changes:
```gdscript
// Set all animation conditions to false, then enable target
for condition in animation_conditions:
    animation_tree.set("parameters/conditions/" + condition, false)
animation_tree.set("parameters/conditions/Walk", true)
```

See `animation_conditions` array in Movement.gd for full list.

### Special Move Integration
Special moves consume **both motion input AND button buffer**:
```gdscript
// MoveSet._handle_input()
if input_manager.detect_fireball(input_history):
    player_controller.consume_button_input("st_mp")  // Prevent normal attack
    execute_special("fireball")
```

### Debugging Tools
- **FrameBar** (FrameBar.tscn): Visual frame advantage display
- **InputBufferDebug**: Real-time buffer visualization (statistics mode recommended)
- **Debug labels**: `position_label`, `animation_label`, `combo_label` in world.gd

## Critical Gotchas

1. **SIMULATION_SCALE is 1000, not 100**: Always multiply pixel values by 1000 for fixed_position
2. **Seat system, not player_id**: Use `player_seat` ("player_a"/"player_b") for input mapping
3. **Animation drives gameplay**: Hitboxes activate via animation timeline, not code timers
4. **Buffer consumption is mandatory**: Failing to consume buffers causes double-execution
5. **Fixed-point velocity wrapping**: Large velocities (>MAX_INT/1000) will overflow - clamp before assignment
6. **Facing direction**: Always relative (1.0 = right, -1.0 = left), mirrored automatically for player_b

## External Dependencies
- **Godot State Charts** plugin (addons/godot_state_charts) - Currently unused, kept for future AI work
- **GPU Noise Texture** plugin - Used for VFX effects

---

**Recent Major Changes**:
- Input buffer system (5 frames, see INPUT_BUFFER_IMPLEMENTATION.md)
- Movement handler refactoring (11 handlers, see REFACTORING_SUMMARY.md)
- Data-driven moveset (MoveData class, see MOVESET_REFACTORING_SUMMARY.md)
- Frame-based hitstun/blockstun (replaced delta timers)
- Seat-based player system (replaced numeric player_id)
