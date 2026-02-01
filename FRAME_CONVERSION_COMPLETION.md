# Frame Conversion System - Complete Implementation

## Overview
整個遊戲時間系統已全面轉換為邏輯幀（60 FPS 基準）格式。

## Architecture: Dual Frame Rate System

### Physical vs Logical Frame Rate
- **PHYSICS_FPS**: 120 FPS (實際引擎運行速度)
- **LOGIC_FPS**: 60 FPS (遊戲邏輯基準)
- **Conversion**: 1 logic frame = 2 physics frames

### Data Flow
```
Inspector (邏輯幀) 
    ↓
Storage (邏輯幀) 
    ↓
Conversion Function (取決於系統)
    ↓
Runtime Use (物理幀 或 秒數)
```

## System Status: ✅ COMPLETE

### 1. AttackData.gd (Normal Attacks)
**Status**: ✅ FULLY CONVERTED
- All attacks use `_frames` suffix
- Values are in logic frames (60 FPS base)
- Examples:
  - `st_lp_hitstun_frames: int = 18` (0.30s)
  - `st_mp_blockstun_frames: int = 16` (0.267s)
  - `st_hp_hitstun_frames: int = 33` (0.55s)

### 2. Fighter.gd (Base Combat System)
**Status**: ✅ FULLY CONVERTED
- `logic_frames_to_physics_frames()`: Converts logic frames to physics frames (×2 ratio)
- `logic_seconds_to_physics_frames()`: Converts seconds to physics frames
- `take_hit()` signature: Receives logic frame integers
- Conversion occurs immediately on entry to maintain internal consistency

### 3. HitResponseHandler.gd (Hit Detection)
**Status**: ✅ FULLY CONVERTED
- `_get_hit_parameters()` returns frame integers
- Values in logic frames: hitstun (39), blockstun (27), etc.
- Debug output confirms conversion

### 4. fireball.gd (Projectile System)
**Status**: ✅ FULLY CONVERTED
- `blockstun_duration_frames: int = 14` (0.233s)
- Uses frame-based duration for blockstun calculation

### 5. MoveSet.gd (Special Moves)
**Status**: ✅ FULLY CONVERTED

#### Move Library Durations (Logic Frames)
```gdscript
move_library["powerkk"]  = duration: 56.0   (0.933s)
move_library["super"]    = duration: 156.0  (2.6s)
move_library["dp"]       = duration: 54.0   (0.9s)
move_library["spnk"]     = duration: 72.0   (1.2s)
move_library["hdk"]      = duration: 66.0   (1.1s)
move_library["fireball"] = duration: 18.0   (0.3s)

move_library["super"].jump_delay  = 54.0   (0.9s)
move_library["dp"].jump_delay     = 4.0    (0.0667s)
```

#### Conversion in _start_special()
```gdscript
# Convert logic frames to seconds for delta-based timer system
current_move_state.timer = move_data.duration / 60.0
current_move_state.jump_timer = move_data.jump_delay / 60.0
current_move_state.total_duration = move_data.duration / 60.0
```

#### Timer Decrement in process_move()
```gdscript
current_move_state.timer -= delta  # Delta-based countdown
```

**Export Variables** (Remain in seconds for delta timing):
- `fireball_spawn_delay: float = 0.2667` (16 frames)
- `super_freeze_time: float = 0.3` (18 frames)

### 6. Resource Files
**Status**: ✅ FULLY CONVERTED
- `p1_attack_data.tres`: Frame values
- `p2_attack_data.tres`: Frame values

## Verification: Frame Math

### Test Case: 60 Logic Frames
```
Input: 60 logic frames (at 60 FPS base)
  ↓
AttackData: st_lp_hitstun_frames = 18 (Inspector input)
  ↓
Fighter.take_hit(18): 
  physics_frames = 18 × (120/60) = 36 physics frames
  ↓
Duration: 36 physics frames / 120 FPS = 0.3 seconds ✓
```

### Test Case: Super (156 Logic Frames)
```
Move duration: 156 logic frames
  ↓
_start_special("super"):
  current_move_state.timer = 156 / 60.0 = 2.6 seconds
  ↓
process_move() delta countdown:
  timer -= delta until timer <= 0
  ↓
Total duration: 2.6 seconds (matches original) ✓
```

## Time Value Standards

| System | Storage Format | Input Format | Runtime Format | Example |
|--------|---|---|---|---|
| Normal Attacks | Logic frames (60 FPS) | Inspector: frames | Physics frames | 18 frames = 0.3s |
| Special Moves | Logic frames (60 FPS) | Inspector: frames | Seconds (delta) | 156 frames = 2.6s |
| Projectiles | Logic frames | Inspector: frames | Physics frames | 14 frames = 0.233s |
| Delta Timers | Seconds | Inspector: seconds | Seconds (delta) | 0.2667s = 16 frames |

## Implementation Checklist

- ✅ AttackData.gd - All attacks converted to logic frames
- ✅ Fighter.gd - Conversion functions and frame-based hitstun/blockstun
- ✅ Player.gd - take_hit() signature updated
- ✅ HitResponseHandler.gd - Returns frame integers
- ✅ fireball.gd - Frame-based durations
- ✅ MoveSet.gd - Move library durations + conversion in _start_special()
- ✅ Resource files (p1/p2_attack_data.tres) - Frame values
- ✅ Debug output - Confirms conversions and timings

## Console Output Format

When hits connect:
```
[HitResponseHandler] PlayerA → PlayerB | Hitstun: 18 frames (0.30s) | Blockstun: 16 frames (0.27s)
[TAKE_HIT] Input: hitstun=18 (logic frames) → physics_hitstun=36 (physics frames)
[HITSTUN START] Duration: 36 physics frames (0.30 seconds)
```

## Future Considerations

- Animation length still drives move duration (via `anim.length` override in _start_special())
- All acceleration curves now use converted durations consistently
- Three-phase movement (stationary → acceleration → deceleration) uses percentage-based ratios
- No further changes needed unless new time-based systems are added

---

**Date**: Frame conversion system fully implemented and verified.
**Status**: Ready for production use and testing.
