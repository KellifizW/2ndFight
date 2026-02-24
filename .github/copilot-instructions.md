# 2D Fighting Game - Godot 4.x Codebase Instructions

## Architecture Overview

This is a **Godot 4.x 2D fighting game** using a **fixed-point physics system** and **data-driven architecture** for precise, deterministic combat. The game follows AAA fighting game patterns (Street Fighter, Tekken) with modular handler-based design.

### Core Class Hierarchy
```
Movement (Node2D) → Fighter → Player
```
- **Movement**: Base physics, 11 specialized handlers (see handlers/ section), fixed-point math
- **Fighter**: Damage, hitstun/blockstun (frame-based), collision detection, health system
- **Player**: Attack systems, combos, 5 combat handlers, AI/human input integration

**Combat Handlers** (scripts/combat/handlers/):
- `AttackExecutor`: Attack state machine and execution
- `AttackMovementHandler`: Forward/backward movement during attacks
- `CancelWindowHandler`: Combo cancel timing windows
- `HitResponseHandler`: Hit/block reactions and frame advantage
- `ShadowSyncHandler`: Visual shadow positioning

### Critical Systems

#### 1. Fixed-Point Physics System
**Everything uses integer fixed-point math** (SIMULATION_SCALE = 1000):
```gdscript
// World constants (world.gd)
const SIMULATION_SCALE: int = 1000  // 1 pixel = 1000 units
const TICKS_PER_SECOND: int = 120   // Fixed 120 FPS physics
const GRAVITY: int = 7400000        // Gravity in fixed-point units
const FLOOR_Y: int = 550000         // Floor position

// Players use fixed_position/fixed_velocity (Vector2i)
player.fixed_position = Vector2i(x * 1000, y * 1000)
player.fixed_velocity.x = int(speed * world.SIMULATION_SCALE)
```

**Why**: Ensures deterministic physics for online play and replays. Never use float arithmetic for position/velocity.

#### 2. Handler-Based Movement Architecture
Movement.gd delegates to **11 specialized handlers** (root-level files):
- `InputHandler`: Input state retrieval (not processing)
- `AnimationManager`: AnimationTree state management
- `DashHandler`, `JumpHandler`, `WalkHandler`: Movement mechanics
- `BlockingHandler`, `FacingHandler`: Defensive/orientation logic
- `KnockflyHandler`, `GravityHandler`, `LandingHandler`: Physics states
- `TimerHandler`: Centralized timer decrements (landing, dash, cancel_window)

**Additional Combat Handlers** (scripts/combat/handlers/):
- `AttackExecutor`: Attack lifecycle (startup, active, recovery frames)
- `AttackMovementHandler`: Character displacement during attacks (forward steps, lunges)
- `CancelWindowHandler`: Frame-perfect combo cancels
- `HitResponseHandler`: Damage application, frame advantage calculation
- `ShadowSyncHandler`: Shadow sprite positioning

**When modifying movement/combat**: Edit the appropriate handler, not Movement.gd or Player.gd directly. Each handler is self-contained with clear responsibilities.

#### 3. Data-Driven Move System
**All attacks/specials use resource-based data** (see [MOVESET_REFACTORING_SUMMARY.md](MOVESET_REFACTORING_SUMMARY.md)):

```gdscript
// MoveSet.gd - Loads special moves from .tres resource files
const SPECIAL_MOVE_RESOURCES: Array[String] = [
    "res://data/specials/dav_powerkk.tres",
    "res://data/specials/dav_super.tres",
    "res://data/specials/dav_dp.tres",
    "res://data/specials/den_spnk.tres",
    "res://data/specials/den_hdk.tres",
    "res://data/specials/dav_fireball.tres",
    "res://data/specials/den_fireball.tres"
]

// Normal attacks: AttackData/*.tres resources (data/ folder)
@export var attack_data: AttackData  // Loaded in Player.gd
ATTACK_TABLE = {
    "st_mp": attack_data.st_mp,  // Each attack references a .tres resource
    "cr_mk": attack_data.cr_mk,  // Contains damage/hitstun/blockstun/knockback
}

// Attack movement data (forward lunges, backward steps)
@export var st_mp_movement: AttackMovement  // Optional per-attack displacement
```

**To add new normal attacks**:
1. Add properties to AttackData.gd (e.g., `@export var new_attack_damage: float`)
2. Create/update attack data resource in `data/p1_attack_data.tres` and `data/p2_attack_data.tres`
3. Add to Player.ATTACK_TABLE dictionary
4. Create animation in character's AnimationPlayer

**To add new special moves**:
1. Create a new SpecialMoveData resource file in `data/specials/` (e.g., `new_move.tres`)
2. Add the resource path to MoveSet.SPECIAL_MOVE_RESOURCES array
3. Create input sequence resource in `data/specials/inputs/` if needed
4. Add input detection in InputManager.gd for the motion input
5. Create animation in character's AnimationPlayer

#### 4. Dual-Player System ("Seat" Architecture)
Players distinguished by **seat** (`"player_a"` or `"player_b"`), NOT by ID:
```gdscript
// PlayerController.gd
var player_seat: String = "player_a"  // Set by Player._ready()
var suffix = "_p2" if player_seat == "player_b" else ""
Input.is_action_just_pressed("st_mp" + suffix)
```

#### 5. Input Buffer System
**30-frame input buffer** for lenient execution (see [INPUT_BUFFER_IMPLEMENTATION.md](INPUT_BUFFER_IMPLEMENTATION.md)):
```gdscript
// PlayerController records inputs
input_buffer.record_input("st_mp")

// Player consumes buffered inputs
if input_data.st_mp_pressed:
    player_controller.consume_button_input("st_mp")
```

**Buffer window**: 30 frames (0.25 seconds at 120 FPS). Adjust `BUFFER_FRAMES` in InputBuffer.gd if needed.

**Special moves are also buffered**: InputManager detects motion inputs and automatically records them into the buffer (e.g., "fireball", "dp", "powerkk").

#### 6. Special Move Detection
**InputManager.gd** detects motion inputs (quarter-circles, DPs, etc.):
```gdscript
// Sequence matching with frame-perfect timing
const FIREBALL_SEQUENCE = [
    {"directional": DOWN, "buttons": NONE, ...},
    {"directional": DOWN_FORWARD, ...},
    {"directional": FORWARD, "buttons": ST_MP, ...}
]

// Optimized InputRegistry with charge tracking (inspired by Sakuga-Engine)
class InputRegistry:
    var raw_input: int = 0        # Bit-masked input
    var duration: int = 0         # Frames held (compresses history)
    var h_charge: int = 0         # Horizontal charge (-left, +right)
    var v_charge: int = 0         # Vertical charge (-down, +up)
    var b_charge: int = 0         # Button charge
```

**Direction encoding**: Uses **absolute direction** (actual key pressed), NOT relative to facing.
- `move_right` always encodes as FORWARD(3) → displays →
- `move_left` always encodes as BACK(5) → displays ←
- This ensures both players see the same direction for the same key press

**Input history compression**: Only creates new entry when input changes, accumulating `duration` for repeated inputs (saves ~70% memory).

### Key File Map

| File | Purpose |
|------|---------|
| `world.gd` | Main game loop, player spawning, physics constants (120 FPS) |
| `Movement.gd` | Base physics, handler orchestration |
| `Fighter.gd` | Hitstun/blockstun (frame-based), damage system, hit stop integration |
| `Player.gd` | Attack execution, combo logic, AI integration |
| `MoveSet.gd` | Special moves library (loads .tres resources from data/specials/) |
| `PlayerController.gd` | Input handling, buffer management, seat system |
| `InputManager.gd` | Motion input detection (240-frame history, charge tracking) |
| `InputBuffer.gd` | 30-frame input buffer implementation (0.25s at 120 FPS) |
| `PushManager.gd` | Pushbox collision, corner push physics |
| `HitboxCache` | Hitbox caching system for performance optimization |
| `ResourcePreloadManager` | VFX resource preloading system |
| `HitStopTimingDebugger` | Hit stop timing diagnostics tool |
| **AI System (ai/ folder)** | |
| `ai_behavior.gd` | AI main controller, action commitment system |
| `AIDecisionLayers.gd` | 5-layer decision system (survival→punish→tactical→positioning→idle) |
| `ThreatAssessment.gd` | Threat detection (ground attacks, projectiles, air attacks) |
| `AIComboSystem.gd` | Pre-defined combo execution and tracking |
| `FrameDataManager.gd` | Frame data for moves (startup/active/recovery) |
| `SpaceControl.gd` | Zone control, corner escapes, ideal distance |
| `cpu_controller.gd` | Toggle AI on/off (C key for P1, V key for P2) |
| **Data Resources** | |
| `data/AttackData.gd` | Normal attack properties (damage/stun/knockback) |
| `data/AttackMovement.gd` | Attack displacement data (forward lunges, etc.) |
| `characters/CharacterData.gd` | Character metadata (name, short_id, stats) |

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
5. Create character-specific attack data resources if needed (data/XXX_attack_data.tres)

**Toggle AI control**:
- Press **C** to toggle Player A AI (player_a)
- Press **V** to toggle Player B AI (player_b)
- AI system uses 5-layer decision architecture (survival → punish → tactical → positioning → idle)

**Debug input buffer**:
1. Attach InputBufferDebug.gd to a Label node
2. Enable in Inspector: `Enabled ☑️`, `Show Both Players ☑️`, `Show Statistics ☑️`
3. Shows buffered input counts and timing (30-frame window at 120 FPS)
4. Buffer age displayed for troubleshooting input consumption issues

### Frame-Based Timing Convention
**All durations use frame counts** converted at runtime:
```gdscript
const PHYSICS_FPS: int = 120  // Actual physics tick rate
const LOGIC_FPS: int = 60     // Game logic/animation design baseline

func sec_to_frames(seconds: float) -> int:
    return int(round(seconds * PHYSICS_FPS))

func logic_frames_to_physics_frames(logic_frames: int) -> int:
    return int(round(logic_frames * float(PHYSICS_FPS) / float(LOGIC_FPS)))

// Hitstun/blockstun use frame counters at 120 FPS
hitstun_frames = sec_to_frames(0.4)  // 48 frames at 120 FPS
blockstun_frames -= 1  // Decrement per physics frame
```

**Never use delta-based timers for gameplay-critical timing** (hitboxes, combos, invincibility).

**Important**: The game runs at 120 physics FPS but animations/logic are designed around 60 FPS baseline. Always use conversion functions when dealing with frame data.

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
- **InputHistoryDisplayIcon** (ui/InputHistoryDisplayIcon.gd): Shows last 10 inputs with icon graphics
- **FrameBar** (FrameBar.tscn): Visual frame advantage display
- **InputBufferDebug**: Real-time buffer visualization (30-frame window at 120 FPS)
- **HitStopTimingDebugger**: Diagnoses hit stop timing issues and frame counter synchronization
- **HitboxCache**: Debug mode available for hitbox collision optimization verification
- **Debug labels**: `position_label`, `animation_label`, `combo_label`, `debug_label` in world.gd
- **FrameCounter**: Tracks physics frames for frame-perfect timing verification

## Critical Gotchas

1. **Physics runs at 120 FPS, not 60**: TICKS_PER_SECOND = 120, use PHYSICS_FPS constants
2. **SIMULATION_SCALE is 1000, not 100**: Always multiply pixel values by 1000 for fixed_position
3. **Seat system, not player_id**: Use `player_seat` ("player_a"/"player_b") for input mapping
4. **Animation drives gameplay**: Hitboxes activate via animation timeline, not code timers
5. **Buffer consumption is mandatory**: Failing to consume buffers causes double-execution (30-frame window)
6. **Fixed-point velocity wrapping**: Large velocities (>MAX_INT/1000) will overflow - clamp before assignment
7. **Facing direction**: Always relative (1.0 = right, -1.0 = left), mirrored automatically for player_b
8. **Frame conversion required**: Logic frames (60) → Physics frames (120) requires 2:1 multiplication
9. **Hit stop integration**: All frame counters must respect hit stop state (check is_in_hitstop)
10. **Special moves use .tres resources**: Load from data/specials/ directory, not hardcoded classes

## External Dependencies
- **Godot State Charts** plugin (addons/godot_state_charts) - Currently unused, kept for future AI work
- **GPU Noise Texture** plugin - Used for VFX effects

---

**Enhanced input system with charge tracking and history compression (inspired by Sakuga-Engine)**
- Special moves now use input buffer (30 frames at 120 FPS) for lenient execution
- InputHistoryDisplayIcon UI component with icon graphics (arrow/circle/punch/kick)
- Direction display shows actual key presses (not relative to facing)
- Frame count capped at 99, displayed first without "f" suffix
- Input buffer system (30 frames, 0.25s at 120 FPS, see INPUT_BUFFER_IMPLEMENTATION.md)
- Input history tracking (240 frames, ~2 seconds at 120 FPS)
- Movement handler refactoring (11 handlers, see REFACTORING_SUMMARY.md)
- Data-driven moveset (SpecialMoveData resources in data/specials/, see MOVESET_REFACTORING_SUMMARY.md)
- Frame-based hitstun/blockstun (replaced delta timers)
- Seat-based player system (replaced numeric player_id)
- Hit stop system with timing debugger
- HitboxCache for performance optimization
- ResourcePreloadManager for VFX preloading

---

# AI Agent Workflow Guidelines

## Copilot Context Modes

Start your chat message with one of these modes for targeted behavior. Inspired by `everything-claude-code` context switching.

| Mode | Start message with | AI behavior |
|------|--------------------|-------------|
| **Implement** | (default) | Write code, follow handler boundaries, use fixed-point math |
| **Plan:** | `Plan: <task>` | List affected files/systems, no code yet — see `.github/prompts/plan.prompt.md` |
| **Debug:** | `Debug: <symptom>` | Diagnose root cause first, minimal repro — see `.github/prompts/debug.prompt.md` |
| **Review:** | `Review: <file/change>` | Audit fixed-point discipline, handler boundaries — see `.github/prompts/review.prompt.md` |
| **Research:** | `Research: <question>` | Explore without committing, compare approaches, report findings |
| **Frame:** | `Frame: <attack>` | Verify frame data across animation, physics, logic — see `.github/prompts/frame-data.prompt.md` |

**Game-specific prompt files** in `.github/prompts/`:
- `new-attack.prompt.md` — Add a new normal attack end-to-end
- `new-special-move.prompt.md` — Add a new special move with resource + input detection
- `ai-behavior.prompt.md` — Modify or debug AI decision behavior

Open any `.prompt.md` file and click **"Run in Copilot Chat"** (or use `@workspace /prompt new-attack`) to invoke.

## Session Management

Analogous to `/clear` and `/compact` in Claude Code CLI.

| When | Action |
|------|--------|
| Starting an **unrelated task** | Start a new Copilot Chat |
| Context growing stale (long debug session) | Start new chat, paste key findings as first message |
| After **completing a milestone** | Start new chat for next milestone |
| **Mid-implementation** | ⚠️ Do NOT start new chat — you'll lose variable names, file paths, in-flight state |

**Keep one chat per logical task.** Don't mix "add new attack" with "fix AI behavior" in the same session.

## Operating Principles (Non-Negotiable)

When working on this codebase:

1. **Correctness over cleverness**: Prefer boring, readable solutions that are easy to maintain. Fighting game code must be debuggable under pressure.

2. **Smallest change that works**: Minimize blast radius. Don't refactor adjacent handlers unless it meaningfully reduces complexity or fixes a bug.

3. **Leverage existing patterns**: Follow the handler-based architecture. Use data-driven resources (AttackData, MoveData) instead of hardcoding values.

4. **Prove it works**: "Seems right" is not done. For gameplay changes:
   - Launch the game and test the specific scenario
   - Verify frame counts match expectations (use FrameBar for frame advantage)
   - Test both Player A and Player B (seat system must work for both)
   - Check AI behavior if relevant (toggle with C/V keys)

5. **Be explicit about uncertainty**: If you cannot verify something (e.g., online play determinism), say so and explain what manual testing is needed.

## Workflow Orchestration

### 1. Plan Mode for Complex Changes

Enter plan mode for:
- Multi-handler changes (e.g., modifying both Movement.gd and a handler)
- New combat mechanics (attacks, special moves, combos)
- AI behavior modifications (decision layers, threat assessment)
- Frame timing changes (affect multiple systems)

**Plan structure**:
1. Identify affected handlers/systems
2. List required resource changes (AttackData, MoveData)
3. Note animation changes needed
4. Define verification steps (specific in-game scenarios to test)

### 2. Subagent Strategy

Use subagents to parallelize:
- **Pattern discovery**: "Find all places where hitstun_frames is modified"
- **Animation analysis**: "List all animations that use knockback parameters"
- **AI behavior research**: "Trace how AIDecisionLayers chooses between attacks"
- **Frame data verification**: "Calculate total frame count for st_mp animation"

Give subagents concrete deliverables:
- ✅ "List files where SIMULATION_SCALE is used and verify multiplication consistency"
- ❌ "Look at the physics system" (too vague)

### 3. Incremental Delivery

For fighting game changes, prefer thin slices:
- Add one attack → test → verify frame data → add next attack
- Implement AI decision layer → test with CPU toggle → tune parameters
- Add special move detection → test input buffer → add execution logic

Keep changes testable at each step. Don't implement full combo system in one pass.

### 4. Verification Before "Done"

A gameplay change is done when:
- ✅ Tested in-game with both Player A and Player B
- ✅ Frame counts verified (FrameBar, debug output, animation lengths)
- ✅ No GDScript errors in debug console
- ✅ Input buffer behavior correct (test with InputBufferDebug if relevant)
- ✅ Fixed-point math verified (no float arithmetic for physics)
- ✅ Handler responsibilities respected (no logic leaking into Movement.gd)

**For AI changes**:
- ✅ Toggle AI on (C/V keys) and observe behavior for 30+ seconds
- ✅ Verify decision variety (not spamming one move)
- ✅ Check frame logs show correct decision layer activation

**For animation changes**:
- ✅ Animation plays correctly for both characters
- ✅ Hitbox activation aligns with visual animation
- ✅ AnimationTree transitions work (no stuck states)

### 5. Multi-Perspective Analysis

For complex architectural decisions (new input system, AI overhaul, physics changes), explicitly request multiple viewpoints by asking:

> "Analyze [X] from these perspectives:
> 1. Frame determinism impact (fixed-point, 120 FPS)
> 2. Performance at 120 FPS physics tick
> 3. Handler boundary cleanliness
> 4. Input buffer interaction"

This surfaces hidden tradeoffs that single-angle analysis misses.

## Task Management

### Use manage_todo_list for Multi-Step Work

For complex features, break into actionable tasks:

```
1. [ ] Read existing attack implementation patterns (Player.gd, AttackData)
2. [ ] Create new attack resource in data/p1_attack_data.tres
3. [ ] Add to Player.ATTACK_TABLE
4. [ ] Create animation in AnimationPlayer
5. [ ] Add hitbox activation event in animation timeline
6. [ ] Test attack execution in-game
7. [ ] Verify frame advantage with FrameBar
8. [ ] Test for Player B (seat system)
```

Mark tasks complete individually as you finish them. Don't batch.

### Document Discoveries

When you find important constraints during work:
- Fixed-point overflow limits for knockback velocity
- Animation frame counts that affect cancel windows
- AI decision thresholds that cause spam behavior
- Input buffer edge cases

Add these to relevant system documentation (GUIDES/, SYSTEMS/, DEBUGGING/).

## Communication Guidelines

### 1. Be Concise and Specific

**Good**:
> Updated st_mp damage from 8.0 to 10.0 in [data/p1_attack_data.tres](data/p1_attack_data.tres). Tested both players, frame advantage unchanged at +2F.

**Bad**:
> I've modified the attack system to adjust damage values and tested everything.

### 2. Reference Concrete Artifacts

Always link:
- File paths with line numbers: `[Player.gd](Player.gd#L245)`
- Specific handlers: `DashHandler.gd`, `AttackExecutor`
- Animation names: `st_mp`, `knockfly`, `layground`
- Frame counts: "14F startup", "24F hitstun"
- Resource files: `data/p1_attack_data.tres`

### 3. Ask Questions Only When Blocked

If you must ask:
- Ask ONE targeted question
- Provide a recommended default
- State what changes based on the answer

**Example**:
> The new heavy punch needs a damage value. Based on existing heavy attacks (st_hp: 15.0, cr_hp: 14.0), I recommend 15.0. Should I use 15.0 or a different value? This only affects the damage parameter in AttackData.

### 4. Show Verification Evidence

For gameplay changes, include:
- "Tested in-game: Player A threw fireball at frame 180, hit Player B at frame 195 (15F travel time)"
- "FrameBar shows +3F advantage on block (expected +3F from hitstun 18F - blockstun 15F)"
- "AI CPU toggled on for 45 seconds: used 5 st_mp, 4 st_lp, 3 fireballs, 2 DPs (good variety)"

## Context Management

### 1. Read Handlers Before Modifying

Before editing movement/combat:
- Read the specific handler responsible for that behavior
- Check Movement.gd to understand handler orchestration
- Look at related handlers (e.g., JumpHandler + GravityHandler)

Don't modify Movement.gd directly if a handler should handle it.

### 2. Fixed-Point Math Discipline

Always remember:
- Positions/velocities are `Vector2i` (not Vector2)
- Multiply pixel values by SIMULATION_SCALE (1000)
- Never use float arithmetic for physics
- Use `int()` conversions explicitly

**Bad**: `velocity.x = speed * 1.5`  
**Good**: `velocity.x = int(speed * 1.5)`

### 3. Respect Handler Boundaries

Each handler has a specific responsibility:
- `DashHandler`: Dash initiation, duration, cooldown
- `JumpHandler`: Jump state, velocity application
- `GravityHandler`: Gravity application (unified system)
- `AttackExecutor`: Attack state machine, frame tracking

Don't add dash logic to JumpHandler or gravity logic to DashHandler.

### 4. Animation-Driven Gameplay

Key rule: **Animations drive hitboxes**, not code timers.

When adding attacks:
1. Create animation with correct frame count
2. Add hitbox activation event in animation timeline
3. Code responds to animation events, doesn't drive timing

Don't use code timers for "hitbox active between frame 5-8." Use animation events.

## Error Handling and Recovery

### 1. "Stop-the-Line" Rule for Fighting Games

If you encounter:
- Frame advantage calculations showing wrong numbers
- Attacks executing twice (buffer consumption failure)
- Animation stuck states (AnimationTree issues)
- Fixed-point overflow (velocity wrapping)
- Determinism breaks (float arithmetic introduced)

**Stop immediately**:
- Preserve error logs and repro steps
- Don't add more features
- Return to diagnosis mode

### 2. Triage Checklist for Gameplay Bugs

1. **Reproduce**: Specific inputs at specific frame/game state
2. **Localize**: Which handler/system? (Movement, Fighter, Player, AI?)
3. **Check frame logs**: Enable debug output for that system
4. **Reduce case**: Simplest scenario that fails
5. **Fix root cause**: Usually in handler logic or resource data
6. **Add prevention**: Update relevant SYSTEMS/ doc with gotcha
7. **Verify**: Test original repro scenario + edge cases

### 3. Safe Fallbacks

For risky changes (AI behavior, physics tweaks):
- Keep old values commented out for easy rollback
- Use intermediate steps (change from 100 → 120 → 150, not 100 → 150)
- Test with both characters and multiple scenarios

## Engineering Best Practices (Fighting Game Edition)

### 1. Data-Driven Design

**Prefer**: AttackData resources with damage/hitstun/knockback parameters  
**Over**: Hardcoded values in Player.gd

**Prefer**: MoveData entries in MoveSet.move_library  
**Over**: Scattered special move logic

### 2. Testing Strategy

For fighting games, testing is:
- **Manual gameplay testing** (primary verification method)
- **Frame data verification** (FrameBar, debug output)
- **AI behavior observation** (toggle CPU, watch for 30+ seconds)
- **Input buffer testing** (InputBufferDebug visualization)

Unit tests are rare in this codebase. Manual testing is king.

### 3. Frame-Perfect Discipline

All gameplay timing uses frame counts at 120 FPS physics rate:
- Hitstun: 48 physics frames (0.4 seconds × 120 FPS)
- Blockstun: 36 physics frames (0.3 seconds × 120 FPS)
- Cancel windows: tracked with frame counters (not delta timers)
- Logic frames (60 FPS) convert to physics frames (120 FPS) with 2:1 ratio

Convert at initialization:
```gdscript
hitstun_frames = int(round(0.4 * 120))  # 48 physics frames
# OR use conversion function:
hitstun_frames = sec_to_frames(0.4)     # 48 physics frames
```

Decrement per physics frame:
```gdscript
hitstun_frames -= 1  # Every _physics_process (120 times per second)
```

### 4. Determinism Requirements

For online play and replays:
- ✅ Fixed-point math (Vector2i, int arithmetic, SIMULATION_SCALE = 1000)
- ✅ Frame-based timing at 120 FPS physics rate (not delta-based)
- ✅ Consistent RNG if needed (seeded Random)
- ✅ Use Engine.physics_ticks_per_second for dynamic FPS detection
- ❌ Float arithmetic for physics (positions, velocities)
- ❌ Delta-based timers for gameplay-critical timing
- ❌ Time.get_ticks_msec() for logic (only for timestamps)
- ❌ Hardcoded FPS values (use PHYSICS_FPS constants instead)

### 5. Animation Integration

Always verify:
- Animation length matches expected frame count (animations designed at 60 FPS baseline)
- Physics runs at 120 FPS, so 1 animation frame = 2 physics frames
- Hitbox events placed at correct frames in AnimationPlayer timeline
- AnimationTree conditions reset properly (see animation_conditions array)
- Animation callbacks registered in player_anim_resets dictionary
- Hit stop system pauses animations correctly (SlowMoController integration)

### 6. AI Behavior Balance

When modifying AI:
- Test for 60+ seconds to verify move variety
- Check decision layer balance (not stuck in one layer)
- Verify action commitment prevents spam
- Ensure character move restrictions work (ai/MOVE_RESTRICTIONS_GUIDE.md)

### 7. GDScript Code Quality Checklist

Before marking any file edit complete:

**Structure**
- [ ] Handler file < 400 lines — extract to new handler if larger
- [ ] Functions < 50 lines — extract helpers if longer
- [ ] No magic numbers — use constants from `world.gd` / `Fighter.gd`
- [ ] No hardcoded player_id — use `player_seat` (`"player_a"` / `"player_b"`)

**Physics Discipline**
- [ ] All position/velocity uses `Vector2i` (not `Vector2`)
- [ ] Pixel values multiplied by `SIMULATION_SCALE` (1000)
- [ ] No `float` arithmetic for physics-critical values
- [ ] Large velocity values clamped before assignment (overflow guard)

**Timing Discipline**
- [ ] Durations use frame counters, not `delta` timers
- [ ] Logic frames → physics frames conversion applied (× 2)
- [ ] Hit stop state respected (`is_in_hitstop` checked before decrement)

**Input / Buffer**
- [ ] `consume_button_input()` called after every attack execution
- [ ] Motion input AND button buffer consumed atomically for specials

**Animation**
- [ ] Hitboxes activated via animation timeline events, not code timers
- [ ] All animation conditions reset before transitioning
- [ ] Callback registered in `player_anim_resets` dictionary

## Definition of Done (Fighting Game)

A change is done when:

**Core Criteria**:
- ✅ Behavior matches intended design
- ✅ Tested in-game with both Player A and Player B
- ✅ No GDScript errors in console
- ✅ Handler responsibilities respected

**Gameplay Criteria**:
- ✅ Frame counts verified (animations, hitstun, blockstun)
- ✅ Fixed-point math used (no float arithmetic)
- ✅ Input buffer behavior correct
- ✅ Animation integration working (hitboxes, transitions)

**AI Criteria (if applicable)**:
- ✅ AI behavior tested (CPU toggle on for 30+ seconds)
- ✅ Move variety observed (not spamming)
- ✅ Decision layers functioning

**Documentation Criteria**:
- ✅ If adding new system: update relevant GUIDES/ or SYSTEMS/ doc
- ✅ If fixing complex bug: add note to SYSTEMS/ doc's gotchas section

## Quick Reference: Verification Checklist

Before marking any gameplay change complete, verify:

```
Physical Testing:
[ ] Launched game and tested specific scenario
[ ] Tested with Player A (seat: player_a)
[ ] Tested with Player B (seat: player_b)
[ ] No GDScript errors in console

Frame Data:
[ ] Frame counts match expected values
[ ] FrameBar shows correct advantage (if applicable)
[ ] Animation lengths correct (at 60 FPS)

Systems:
[ ] Fixed-point math used (no float for physics)
[ ] Input buffer behavior correct
[ ] Handler boundaries respected
[ ] Animation events sync with gameplay

AI (if applicable):
[ ] CPU toggle tested (C or V key)
[ ] Observed for 30+ seconds
[ ] Move variety verified (not spamming)
```

---

**Remember**: This is a frame-perfect fighting game. "Close enough" creates bugs that only appear in high-level play. Be precise with frame counts, fixed-point math, and timing systems.
