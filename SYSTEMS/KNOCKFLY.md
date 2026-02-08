# Knockfly System - Complete Reference

## Quick Summary

**What works**: Knockfly → Layground → Wakeup → Normal State ✅

**Key concept**: Knockfly timer is in seconds (not frames), decremented by PushManager with delta each physics frame.

---

## Problem & Root Causes

### Issue 1: Duration Unit Mismatch

**The Bug**: Character stays knocked up for 39 **seconds** instead of 0.65 seconds

**Root Cause Chain**:
1. HitResponseHandler sets `duration: params.hitstun` (39 **frames**)
2. fighter.gd assigns to knockfly_timer (treated as **seconds**)
3. PushManager decrements with delta, taking 39 actual seconds to reach 0

**The Fix**: Convert frames to seconds in HitResponseHandler
```gdscript
# ❌ BEFORE:
"duration": params.hitstun  # 39 frames → treated as 39 seconds!

# ✅ AFTER:
"duration": params.hitstun / 60.0  # 39 frames / 60 = 0.65 seconds ✓
```

**File**: [scripts/combat/handlers/HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd#L162)

### Issue 2: Timer Unit Mixing

**The Bug**: knockfly_timer was being decremented as frames in KnockflyHandler while PushManager expected seconds

**Root Cause**: Two different decrement paths with conflicting unit expectations
- fighter.gd initialized as seconds
- KnockflyHandler decremented it as frames (`-= 1` per frame)
- PushManager expected to decrement it as seconds

**The Fix**: Remove duplicate decrement from KnockflyHandler

```gdscript
# ❌ BEFORE (KnockflyHandler.gd:40):
movement_node.knockfly_timer = max(0, movement_node.knockfly_timer - 1)

# ✅ AFTER:
# 【重要】knockfly_timer 由 PushManager._physics_process() 管理（delta 遞減）
# 不在此處遞減以避免重複遞減
```

**Why**: PushManager is already decrementing `knockfly_timer` with `delta`. KnockflyHandler should only check state, not modify the timer.

**File**: [KnockflyHandler.gd](KnockflyHandler.gd#L40)

### Issue 3: Missing Layground Animation

**The Bug**: After knockfly, character skips layground and wakeup animations

**Root Cause**: knockfly_timer became negative in a single frame due to unit mismatch (39 - 1 = -38), triggering state transition prematurely

**The Fix**: Ensure knockfly_timer is in seconds and only PushManager decrements it

---

## Current Implementation (Post-Fix)

### Timer Types (MUST NOT MIX)

| Timer | Type | Unit | Init | Decrement | Location |
|-------|------|------|------|-----------|----------|
| `knockfly_timer` | Float | Seconds | fighter.gd | PushManager `-= delta` | PushManager |
| `layground_timer` | Int | Frames @120 | KnockflyHandler | KnockflyHandler `-= 1` | KnockflyHandler |
| `wakeup_timer` | Int | Frames @120 | KnockflyHandler | Player `-= 1` | Player._physics_process |

### Initialization Rules

**In fighter.gd take_knockfly_damage():**
```gdscript
knockfly_timer = max(default_knockfly_duration, min_hitstun_duration)  # Seconds!
knockfly_duration = knockfly_timer  # Sync for PushManager's curve calculation
```

**In fighter.gd take_knockfly():**
```gdscript
# Use seconds for PushManager compatibility
knockfly_timer = max(default_knockfly_duration, min_hitstun_duration)
knockfly_duration = knockfly_timer
```

### State Machine Flow

```
                ┌─────────────────────────────────┐
                │   KNOCKFLY STATE (in air)        │
                │ knockfly_timer: 0.65s (seconds)  │
                │ PushManager: -= delta each frame │
                │ Duration: ~0.65 seconds @120fps  │
                └──────────────┬────────────────────┘
                               │
                    Character touches floor
                               │
                ┌──────────────▼────────────────────┐
                │   LAYGROUND STATE (on floor)      │
                │ layground_timer: 24 frames        │
                │ KnockflyHandler: -= 1 each frame  │
                │ Duration: ~0.2 seconds @120fps    │
                └──────────────┬────────────────────┘
                               │
                  layground_timer <= 0
                               │
                ┌──────────────▼────────────────────┐
                │   WAKEUP STATE (standing up)      │
                │ wakeup_timer: variable frames     │
                │ Player._physics_process: -= 1     │
                │ Duration: animation length        │
                └──────────────┬────────────────────┘
                               │
                   wakeup_timer <= 0
                               │
                ┌──────────────▼────────────────────┐
                │   NORMAL STATE (back to idle)     │
                └─────────────────────────────────┘
```

---

## Verification & Testing

### Manual Test Sequence
1. Get hit by DP (or knockfly-inducing move)
2. Character goes into knockfly (in air)
3. Character lands and immediately plays **layground** animation
4. After layground (~0.2s), character plays **wakeup** animation
5. Character returns to normal state
6. **Total knockdown duration**: ~0.85 seconds (0.65 knockfly + 0.2 layground)

### Debug Verification
```
🔴 [Player A] KNOCKFLY STARTED (Frame 1200)
🟡 [Player A] LAYGROUND STARTED (Frame 1260)
🟢 [Player A] WAKEUP STARTED (Frame 1284)
✅ [Player A] SEQUENCE COMPLETE
```

### Both Players Check
- [ ] Player A knockfly sequence works
- [ ] Player B knockfly sequence works
- [ ] No state machine conflicts
- [ ] Animations play in correct order

---

## Critical Rules (Don't Break These)

### Rule 1: knockfly_timer is ALWAYS in seconds
```gdscript
❌ knockfly_timer: frame-based decrement
❌ knockfly_timer: frame-based initialization
✅ knockfly_timer: seconds init, delta decrement (ONLY THIS)
```

### Rule 2: PushManager is the ONLY place knockfly_timer is decremented
```gdscript
❌ KnockflyHandler: knockfly_timer -= 1
❌ fighter.gd: knockfly_timer -= delta
✅ PushManager: knockfly_timer -= delta (ONLY THIS)
```

### Rule 3: Decrement location must match unit type
```gdscript
# knockfly_timer (seconds) → decremented by PushManager with delta
# layground_timer (frames) → decremented by KnockflyHandler with -= 1
# wakeup_timer (frames) → decremented by Player with -= 1
```

---

## Related Files
- [scripts/combat/handlers/HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd#L162) - Duration conversion
- [KnockflyHandler.gd](KnockflyHandler.gd) - Layground state management
- [fighter.gd](fighter.gd) - Knockfly initialization
- [PushManager.gd](PushManager.gd#L374) - knockfly_timer decrement

**Status**: ✅ Fixed and verified
