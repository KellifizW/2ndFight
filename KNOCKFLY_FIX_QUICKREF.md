# Knockfly Animation Fix - Quick Reference

## What Was Broken
```
knockfly → (missing layground & wakeup) → normal state ❌
```

## What's Fixed  
```
knockfly → layground → wakeup → normal state ✅
```

## The Bug in 3 Lines

```gdscript
knockfly_timer = 0.5  # seconds from take_knockfly_damage()
knockfly_timer -= 1   # KnockflyHandler: instant becomes -0.5 ❌
if knockfly_timer <= 0: skip_layground()  # Triggered on frame 1!
```

## The Fix in 3 Lines

```gdscript
knockfly_timer = 0.5  # seconds from take_knockfly_damage()
# knockfly_timer -= delta  # Only PushManager does this ✅
if knockfly_timer <= 0: transition_to_layground()  # Correct timing
```

## Key Changes

| File | Line | Change | Why |
|------|------|--------|-----|
| `KnockflyHandler.gd` | 40 | ✂️ Removed `knockfly_timer -= 1` | PushManager already decrements it |
| `fighter.gd` | 503 | 📝 `take_knockfly()`: Use seconds not frames | Unify with PushManager's expectation |
| `fighter.gd` | 332 | 🗑️ Removed unused variable | Code cleanup |

## State Chart (Now Working)

```
Knockfly (0.5s)
    ↓ [character lands]
Layground (24 frames @120fps ≈ 200ms)
    ↓ [layground_timer reaches 0]
Wakeup (variable duration)
    ↓ [wakeup_timer reaches 0]
Normal State ✅
```

## How to Verify

1. **Manual Test**:
   - Get hit hard enough to knockfly
   - Observe character playing layground animation on floor
   - Observe character playing wakeup animation
   
2. **Debug Output** (check console):
   ```
   🔴 [Player A] KNOCKFLY STARTED (Frame 1200)
   🟡 [Player A] LAYGROUND STARTED (Frame 1260)
   🟢 [Player A] WAKEUP STARTED (Frame 1284)
   ✅ [Player A] SEQUENCE COMPLETE
   ```

3. **Attach KnockflyAnimationDebugger.gd** to scene for detailed frame logs

## Timer Type Rules (Not to Break!)

| Timer | Init Type | Decrement Unit | Decrement Location |
|-------|-----------|----------------|--------------------|
| `knockfly_timer` | Float (seconds) | delta | PushManager |
| `layground_timer` | Int (frames @120) | frame (-1) | KnockflyHandler |
| `wakeup_timer` | Int (frames @120) | frame (-1) | Player._physics_process |

## Never Mix These

```gdscript
❌ knockfly_timer: seconds init, frame decrement
❌ knockfly_timer: frame init, delta decrement
✅ knockfly_timer: seconds init, delta decrement (ONLY THIS)
```

---

**Status**: ✅ FIXED - Ready for testing
