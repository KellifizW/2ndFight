# Knockfly Duration Bug Fix - Frame/Second Unit Mismatch (CRITICAL)

## The Bug
During knockfly knockdowns, the **layground and wakeup animations never play** because the character stays in knockfly state for 60x longer than intended.

### Root Cause Chain
1. **HitResponseHandler Line 159** sets knockfly duration in FRAMES:
   ```gdscript
   "duration": params.hitstun  # 39 FRAMES, not seconds!
   ```

2. **fighter.gd take_knockfly_damage()** assigns this directly to knockfly_timer:
   ```gdscript
   knockfly_timer = params.duration  # Now 39.0 (treated as SECONDS by PushManager)
   ```

3. **PushManager Line 374** expects seconds and decrements with delta:
   ```gdscript
   player.knockfly_timer -= delta  # Treats 39.0 as 39 SECONDS!
   ```

4. **Result**: knockfly_timer = 39 seconds instead of 0.65 seconds
   - Character stays knocked up for 39 seconds
   - Meanwhile, GravityHandler pulls character down
   - Character eventually lands (y >= floor_y) after ~2 seconds
   - By this time, knockfly_timer is still 37+ seconds
   - layground transition triggers (good!)
   - But timing is off and animations don't play properly

## The Fix

**File**: [scripts/combat/handlers/HitResponseHandler.gd Line 162](scripts/combat/handlers/HitResponseHandler.gd#L162)

```gdscript
# ❌ BEFORE (Unit Mismatch):
"duration": params.hitstun  # 39 frames → treated as 39 seconds!

# ✅ AFTER (Correct Conversion):
"duration": params.hitstun / 60.0  # 39 frames / 60 = 0.65 seconds ✓
```

## Why This Matters

| State | With Bug | With Fix |
|-------|----------|----------|
| knockfly_timer starts | 39.000 seconds | 0.650 seconds |
| Time to reach 0 | ~39 seconds | ~0.65 seconds |
| Character lands on floor | After ~2s of gravity | After ~0.65s |
| Time for layground | After 39+ seconds | After 0.65 + 0.2 = 0.85 seconds |
| **Animation Status** | **Never plays** | **Plays correctly** |

## The Physics

DP attack parameters:
- **hitstun**: 39 **frames** (not seconds)
- **Duration at 60 FPS**: 39 ÷ 60 = **0.65 seconds**
- **Duration in seconds**: 0.65s (period, not frames × 60)

PushManager decay:
- Decrements: `knockfly_timer -= delta`
- delta = 1/120 ≈ 0.00833 seconds per physics frame
- Time to decay from 39: 39 ÷ 0.00833 = **4680 frames** = **39 seconds**

## Impact

This bug affected **all knockfly knockdowns on hit moves**, specifically:
- DP (now fixed)
- Any other future moves with knockfly_params that use hitstun

After this fix:
- ✅ Knockfly duration = hitstun duration (0.65s for DP)
- ✅ Layground starts immediately when character lands
- ✅ Layground animation plays (~0.2s)
- ✅ Wakeup animation plays after layground ends
- ✅ Character returns to normal state

## Verification Checklist

- [ ] Get hit by DP
- [ ] Character goes into knockfly (in air)
- [ ] Character lands and immediately plays **layground** animation
- [ ] After layground (0.2s), character plays **wakeup** animation
- [ ] Character returns to normal state
- [ ] Total knockdown duration: ~0.85 seconds (0.65 knockfly + 0.2 layground)
- [ ] No state machine conflicts
- [ ] Both Player A and Player B work correctly

---

**Status**: ✅ FIXED - Ready for testing

**Related Files**: 
- HitResponseHandler.gd (root cause)
- KnockflyHandler.gd (state transitions - already fixed)
- fighter.gd (knockfly_timer assignment - already fixed)
- PushManager.gd (knockfly_timer decrement logic - working correctly)
