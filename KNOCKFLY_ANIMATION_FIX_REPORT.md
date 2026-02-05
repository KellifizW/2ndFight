# Knockfly→Layground→Wakeup Animation Fix (Critical Fix)

## Problem Summary
After the timing system unification, the **layground and wakeup animations stopped playing** after knockfly knockdowns. Character would transition directly from knockfly to normal state, skipping the layground and wakeup animation sequences entirely.

## Root Cause Analysis

### The Core Issue: Mixed Timer Type and Dual Decrement Paths

`knockfly_timer` had **two different initialization types** across different code paths:

| Location | Init Type | Init Value | Decrement | Impact |
|----------|-----------|-----------|-----------|---------|
| `fighter.gd:333`<br>(take_knockfly_damage) | Seconds | `params.duration` (e.g., 0.5s) | PushManager `-= delta` | ✅ Correct flow |
| `fighter.gd:503`<br>(take_knockfly) | Frames @60 FPS | `knockfly_duration_frames` | KnockflyHandler `-= 1` | ❌ Conflict |
| `KnockflyHandler:40`<br>(was old code) | Variable | Same as init | `-= 1` (frame) | ❌ Double decrement |
| `PushManager:374` | Variable | Same as init | `-= delta` (seconds) | ✅ Correct for seconds |

### Why This Broke Animations

When `take_knockfly_damage()` was called (most common):
```gdscript
knockfly_timer = 0.5  # seconds
knockfly_duration = 0.5  # seconds
```

Then in `KnockflyHandler._physics_process()`:
```gdscript
knockfly_timer = max(0, knockfly_timer - 1)  # 0.5 - 1 = -0.5 (INSTANT TIMER DEATH!)
```

State check:
```gdscript
if movement_node.knockfly_timer <= 0:  # TRUE on first frame!
    movement_node.is_knockfly_animation_finished = true
    # Animation never transitions to layground!
```

**Result**: knockfly_timer became negative in a single frame, triggering the state transition logic prematurely and skipping the entire layground→wakeup sequence.

## Solution Applied

### Fix 1: Remove Duplicate Timer Decrement
**File**: `KnockflyHandler.gd:40`

```gdscript
# ❌ BEFORE (causing double decrement):
movement_node.knockfly_timer = max(0, movement_node.knockfly_timer - 1)

# ✅ AFTER (let PushManager handle it):
# 【重要】knockfly_timer 由 PushManager._physics_process() 管理（delta 遞減）
# 不在此處遞減以避免重複遞減
```

**Reason**: PushManager is already decrementing `knockfly_timer` with `delta`. KnockflyHandler should only check state, not modify the timer.

### Fix 2: Standardize knockfly_timer to Always Use Seconds
**File**: `fighter.gd:503` (take_knockfly function)

```gdscript
# ❌ BEFORE (using frames):
var knockfly_duration_frames: int = max(int(round(default_knockfly_duration * LOGIC_FPS)), int(round(min_hitstun_duration * LOGIC_FPS)))
knockfly_timer = knockfly_duration_frames

# ✅ AFTER (using seconds for PushManager compatibility):
knockfly_timer = max(default_knockfly_duration, min_hitstun_duration)
knockfly_duration = knockfly_timer  # Sync for PushManager's curve calculation
```

**Reason**: PushManager expects knockfly_timer in seconds and decrements it with `delta`. Both initialization paths must use seconds.

### Fix 3: Clean Up Unused Variable
**File**: `fighter.gd:332` (take_knockfly_damage function)

Removed the unused `knockfly_duration_frames` variable calculation that was left as a vestigial remnant.

## Updated Knockfly State Machine

```
                ┌─────────────────────────────────┐
                │   KNOCKFLY STATE (in air)        │
                │ knockfly_timer: 0.5s (seconds)   │
                │ PushManager: -= delta each frame │
                └──────────────┬────────────────────┘
                               │
                    Character touches floor
                               │
                ┌──────────────▼────────────────────┐
                │   LAYGROUND STATE (on floor)      │
                │ layground_timer: 24 frames        │
                │ KnockflyHandler: -= 1 each frame  │
                └──────────────┬────────────────────┘
                               │
                  layground_timer <= 0
                               │
                ┌──────────────▼────────────────────┐
                │   WAKEUP STATE (standing up)      │
                │ wakeup_timer: variable frames     │
                │ Player._physics_process: -= 1     │
                └──────────────┬────────────────────┘
                               │
                   wakeup_timer <= 0
                               │
                ┌──────────────▼────────────────────┐
                │   NORMAL STATE (back to idle)     │
                └─────────────────────────────────┘
```

## Critical Implementation Details

### 1. Timer Types (MUST NOT MIX)
- **`knockfly_timer`**: Seconds (float)
  - Initialized in `fighter.gd`
  - Decremented by PushManager (delta-based)
  - Checked in KnockflyHandler for state transition

- **`layground_timer`**: Frames @120 FPS (int)
  - Initialized in KnockflyHandler
  - Decremented in KnockflyHandler (`-= 1` per frame)
  - Triggers wakeup when `<= 0`

### 2. Decrement Location Responsibility
| Timer | Location | Method | Unit |
|-------|----------|--------|------|
| `knockfly_timer` | PushManager._physics_process() | `-= delta` | Seconds |
| `layground_timer` | KnockflyHandler._physics_process() | `-= 1` | Physics frames |
| `wakeup_timer` | Player._physics_process() | `-= 1` | Physics frames |

### 3. State Transition Checks (Order Matters)
1. KnockflyHandler checks `if is_knockfly and is_on_floor()` → set `is_layground = true`
2. KnockflyHandler checks `if is_layground and layground_timer <= 0` → call `reset_layground_with_health_check()`
3. `reset_layground_with_health_check()` sets `is_wakeup = true` and `is_wakeup_locked = true`
4. AnimationManager sees `is_wakeup` and plays wakeup animation

## Animation Sequence Flow

```gdscript
# 1. Get hit → Knockfly starts
take_knockfly_damage() 
  knockfly_timer = 0.5  # seconds

# 2. Character in air, knockfly timer counting down
PushManager._physics_process(delta)
  knockfly_timer -= delta  # 0.5 → 0.483 → 0.466...

# 3. Character lands
KnockflyHandler._physics_process()
  if is_knockfly and is_on_floor():  # TRUE
    is_knockfly = false
    is_layground = true  
    layground_timer = 24  # frames @120 FPS
    animation_state.travel("layground")  ← Animation triggers here!

# 4. Layground timer counts down (24 frames ≈ 200ms)
KnockflyHandler._physics_process()
  if is_layground:
    layground_timer -= 1  # 24 → 23 → 22 → ... → 0
    if layground_timer <= 0:
      reset_layground_with_health_check()
        is_wakeup = true
        is_wakeup_locked = true
        animation_state.travel("wakeup")  ← Animation triggers here!

# 5. Wakeup timer counts down
Player._physics_process()
  if wakeup_timer > 0:
    wakeup_timer -= 1
    if wakeup_timer <= 0:
      is_wakeup = false
      is_wakeup_locked = false
      # Character returns to normal state
```

## Verification Debugging

### Using KnockflyAnimationDebugger
1. Attach `KnockflyAnimationDebugger.gd` to a Node in the scene
2. It will monitor and log:
   - When knockfly starts (with timer value)
   - When layground starts (with duration stats)
   - When wakeup starts (with duration stats)
   - Complete sequence timing

Output example:
```
🔴 [Player A] KNOCKFLY STARTED (Frame 1200)
  📍 knockfly_timer: 0.500 seconds

🟡 [Player A] LAYGROUND STARTED (Frame 1260)
  ⏱️  Knockfly lasted: 60 frames
  ⏱️  layground_timer: 24 frames

🟢 [Player A] WAKEUP STARTED (Frame 1284)
  ⏱️  Layground lasted: 24 frames

✅ [Player A] SEQUENCE COMPLETE (Frame 1308)
  ⏱️  Total knockdown duration: 108 frames (0.900 seconds @ 120 FPS)
```

## Files Modified
1. ✅ `KnockflyHandler.gd` Line 40 - Removed duplicate timer decrement
2. ✅ `fighter.gd` Line 331-332 - Cleaned up unused variable
3. ✅ `fighter.gd` Line 500 - Standardized knockfly() to use seconds

## Testing Criteria
- [ ] Character gets knocked down by hit
- [ ] Knockfly animation plays (in air)
- [ ] Character transitio to layground animation on floor contact
- [ ] Layground animation plays for expected duration (~200ms)
- [ ] Wakeup animation plays after layground ends
- [ ] Character returns to normal state
- [ ] Both Player A and Player B animations work
- [ ] No console errors or warnings
- [ ] Animation sequence timing is consistent

## Summary
The knockfly timer system now has **single initialization type (seconds), single decrement location (PushManager), and clear state transition logic**. This ensures the complete knockfly→layground→wakeup animation sequence plays correctly without premature state transitions or animation skips.
