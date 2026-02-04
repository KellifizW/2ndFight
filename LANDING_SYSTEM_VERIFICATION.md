# Landing System 2-Frame Lock - Verification Guide

## Objective
**Enforce 2-frame minimum landing animation before any input can interrupt**

### Expected Behavior
```
Frame 0: Landing triggered
  ├─ is_landing = true
  ├─ timer = 2/60 = 0.033333s
  └─ _landing_forced_frames = 0

Frame 1 (first TimerHandler call)
  ├─ _landing_forced_frames = 1
  ├─ timer decrements: 0.033333 → 0.025000 (loses ~8.3ms = 1 frame)
  └─ checkpoint NOT executed (frame < 2)

Frame 2 (second TimerHandler call)
  ├─ _landing_forced_frames = 2
  ├─ CHECKPOINT EXECUTES
  ├─ Check input: has_input?
  │   ├─ YES: timer = 0.001 (exits immediately after 2 frames)
  │   └─ NO: timer = 0.2 (continues full animation)
  └─ Do NOT decrement timer (return early from checkpoint)

Frame 3+ (only if no input case)
  ├─ timer continues decrementing: 0.2 → 0.1 → 0.0
  ├─ _landing_forced_frames continues incrementing
  └─ When timer == 0: landing state resets
```

## Log Sequence to Verify

### 1. Landing Trigger Phase
```
[LANDING_TRIGGERED_START] player_b | setting is_landing=true and timer=2/60
[LANDING_TRIGGERED_AFTER_SET] player_b | timer now=0.033333 | is_landing=true
[LANDING_TRIGGERED] player_b | ... | FORCED 2-FRAME LANDING | has_input=true/false
```

### 2. Frame 1 Phase
```
[LANDING_FRAME] player_b | frame=1 timer=0.033333 (before decrement)
  (no checkpoint since frame < 2)
  (timer decremented: 0.033333 → 0.025000)
```

### 3. Frame 2 Phase (Checkpoint)
```
[LANDING_FRAME] player_b | frame=2 timer=0.025000 (before decrement)
[LANDING_CHECKPOINT_EXECUTE] player_b | frame=2
[LANDING_CHECKPOINT_INPUT] player_b | has_input=true/false

IF has_input=true:
  [LANDING_INTERRUPT] player_b | setting timer=0.001
  (return early, no timer decrement)

IF has_input=false:
  [LANDING_CONTINUE] player_b | extending timer to 0.200
  (return early, no timer decrement)
```

### 4. Frame 3+ Phase (Decrement Only)
```
[LANDING_FRAME] player_b | frame=3 timer=0.001/0.200 (before decrement)
  (no checkpoint since already executed)
  (timer decremented: 0.001 → 0.000 OR 0.200 → 0.191)

(Repeat until timer == 0)

When timer reaches 0:
  [STATE_CHANGE] player_b: 'landing' → 'Walk'
```

## Key System Files

| File | Responsibility |
|------|-----------------|
| `LandingHandler.gd` | Detects landing and initializes 2-frame lock |
| `TimerHandler.gd` | Manages frame counting and checkpoint execution |
| `Movement.gd` | Stores landing state variables |
| `Player.gd` | Protected: guards prevent modification during landing |

## Protected Locations in Player.gd

✅ **Guards Added** - These functions now skip execution if landing is in progress:

1. `reset_air_state()` (line 99)
   - Guard: `if is_landing and landing_lock_timer > 0: return`

2. `reset_landing_state()` (line 90)
   - Guard: `if _landing_forced_frames < 2: return`

3. `_reset_jump_state()` (line 474)
   - Guard: `if is_landing and landing_lock_timer > 0: return`

4. `_reset_landing_anim()` (line 494)
   - Guard: `if _landing_forced_frames < 2: return`

5. Air attack landing (line 251)
   - Guard: `and not is_landing` in condition

6. Double timer decrement (line 338)
   - **REMOVED** - TimerHandler exclusively manages landing_lock_timer

## Expected Console Output Sequence

### With Input (Interrupt Case)
```
[LANDING_TRIGGERED_START] player_b | setting is_landing=true and timer=2/60
[LANDING_TRIGGERED_AFTER_SET] player_b | timer now=0.033333 | is_landing=true
[LANDING_TRIGGERED] player_b | ... | has_input=true
[LANDING_FRAME] player_b | frame=1 timer=0.033333
[LANDING_FRAME] player_b | frame=2 timer=0.025000
[LANDING_CHECKPOINT_EXECUTE] player_b | frame=2
[LANDING_CHECKPOINT_INPUT] player_b | has_input=true
[LANDING_INTERRUPT] player_b | setting timer=0.001
[STATE_CHANGE] player_b: 'landing' → 'Walk'
```

### Without Input (Full Animation Case)
```
[LANDING_TRIGGERED_START] player_b | setting is_landing=true and timer=2/60
[LANDING_TRIGGERED_AFTER_SET] player_b | timer now=0.033333 | is_landing=true
[LANDING_TRIGGERED] player_b | ... | has_input=false
[LANDING_FRAME] player_b | frame=1 timer=0.033333
[LANDING_FRAME] player_b | frame=2 timer=0.025000
[LANDING_CHECKPOINT_EXECUTE] player_b | frame=2
[LANDING_CHECKPOINT_INPUT] player_b | has_input=false
[LANDING_CONTINUE] player_b | extending timer to 0.200
[LANDING_FRAME] player_b | frame=3 timer=0.200
[LANDING_FRAME] player_b | frame=4 timer=0.191
...
[STATE_CHANGE] player_b: 'landing' → 'Idle'
```

## Verification Checklist

- [ ] Landing triggered with correct timer (2/60)
- [ ] Frame 1: Timer decrements, checkpoint NOT executed
- [ ] Frame 2: Checkpoint executes, input checked
- [ ] With input: Timer set to 0.001, exits immediately
- [ ] Without input: Timer extended to 0.2, continues animation
- [ ] No Player.gd interference during landing lock
- [ ] Both consecutive landings behave identically

## Debugging Tips

If logs don't match expected sequence:

1. **Missing [LANDING_FRAME] logs**
   - Check if `landing_lock_timer > 0` condition is satisfied
   - Verify TimerHandler is being called

2. **Checkpoint never executes**
   - Check if `_landing_forced_frames` is being incremented
   - Verify frame counter is 0-indexed correctly

3. **Player.gd functions still interfering**
   - Check guard conditions in `reset_air_state()`, `reset_landing_state()`, etc.
   - Add temporary logs to those functions to verify they're being skipped

4. **Timer modified unexpectedly**
   - Search for all `landing_lock_timer =` assignments (should only be in LandingHandler, TimerHandler, and guards)
   - Check if any Player.gd modifications are executing

