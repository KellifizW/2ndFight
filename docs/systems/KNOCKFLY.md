# Knockfly System - Complete Reference

## Quick Summary

**What works**: Knockfly → Layground → Wakeup → Normal State

**Key concept (Stage 1)**: Knockfly remaining time is an `int` physics-frame
counter (`knockfly_frames`). PushManager decrements it by 1 each physics tick
and **freezes the decrement during hitstop**. Designer values stay in seconds
(`default_knockfly_duration`) and convert once through
`Movement.start_knockfly_timer()` → `seconds_to_lock_frames()`.

---

## Stage 1 change (2026-08-26)

The previous implementation stored `knockfly_timer` as seconds and did
`-= delta` in PushManager. That had two problems:

1. `fighter.gd` returns early during hitstop, but PushManager kept running, so
   the timer still advanced (stretched by `Engine.time_scale = 0.02`).
2. The same leftover-float issue as landing: `0.4s` at 120 Hz actually ran
   **49** frames, not 48.

The replacement:

| Old | New |
|---|---|
| `knockfly_timer: float` (seconds) | `knockfly_frames: int` (physics frames) |
| `knockfly_duration: float` (seconds, ratio denominator) | `knockfly_duration_frames: int` |
| `PushManager: timer -= delta` | `PushManager: frames -= 1` unless hitstop |

`start_knockfly_timer(0.4)` seeds both remaining and duration to 49 so the
velocity-curve ratio still starts at 1.0.

---

## Timer Types (MUST NOT MIX)

| Timer | Type | Unit | Init | Decrement | Location |
|---|---|---|---|---|---|
| `knockfly_frames` | Int | Physics frames @120 | `start_knockfly_timer()` | PushManager `-1` (frozen in hitstop) | PushManager |
| `knockfly_duration_frames` | Int | Physics frames @120 | same helper | never | PushManager (ratio denominator) |
| `layground_timer` | Int | Frames @120 | KnockflyHandler | KnockflyHandler `-= 1` | KnockflyHandler |
| `wakeup_timer` | Int | Frames @120 | KnockflyHandler | Player `-= 1` | Player._physics_process |

Designer exports (`default_knockfly_duration`, `layground_duration`) stay in
**seconds**. Convert at the seed site; do not decrement them.

---

## Initialization

```gdscript
# fighter.gd take_hit / take_knockfly, ThrowHandler.release_opponent
start_knockfly_timer(duration_seconds)
# → knockfly_frames = seconds_to_lock_frames(duration_seconds)
# → knockfly_duration_frames = knockfly_frames
```

`HitResponseHandler._make_knockfly_params` still publishes `duration` in
seconds (`hitstun / 60.0`). The conversion happens at the fighter boundary.

---

## State Machine Flow

```
                ┌─────────────────────────────────┐
                │   KNOCKFLY STATE (in air)        │
                │ knockfly_frames: 49 @ 0.4s seed  │
                │ PushManager: -1 / physics tick   │
                │ (frozen while is_hit_slowmo)     │
                └──────────────┬────────────────────┘
                               │
                    Character touches floor (vel_y >= 0)
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
                │ wakeup_timer: animation length    │
                └──────────────┬────────────────────┘
```

---

## Critical Rules

### Rule 1: knockfly_frames is ALWAYS physics frames

```gdscript
❌ knockfly_frames = 0.4          # seconds
❌ knockfly_frames -= delta
✅ start_knockfly_timer(0.4)
✅ PushManager: knockfly_frames -= 1
```

### Rule 2: PushManager is the ONLY place knockfly_frames is decremented

KnockflyHandler reads the remaining count to decide layground / anim-finished.
It must not decrement. Clearing to 0 on layground enter is allowed.

### Rule 3: Freeze during hitstop

PushManager must not decrement `knockfly_frames` (or the sibling
`hit_lock_frames` / `block_lock_frames`) while
`SlowMoController.is_hit_slowmo` is true. Velocity interpolation may still
run against the frozen remaining ratio.

### Rule 4: Conversion formula

Use `Movement.seconds_to_lock_frames()` (`floor(sec * fps) + 1`), not
`round(sec * fps)`. `0.4 → 49`, `8/60 → 17`. See landing family notes in
`Movement.gd`.

---

## Related Files

- `scripts/core/Movement.gd` — `start_knockfly_timer()`, conversion helper
- `scripts/core/fighter.gd` — seed on take_hit / take_knockfly
- `scripts/core/PushManager.gd` — decrement + velocity curve
- `scripts/handlers/KnockflyHandler.gd` — layground / wakeup
- `scripts/combat/handlers/ThrowHandler.gd` — throw release seed
- `tests/frame_tests/cases/test_18_stun_lock_is_frame_based.gd`
