---
mode: ask
description: Verify frame data correctness for an attack or system
---

# Frame Data Verification

Verify that frame timing is correct across animation, physics, and game logic.

## What to Verify
Specify the attack or system: [e.g., "st_mp for Player A"]

## Calculation Reference

| Value | Formula | Example |
|-------|---------|---------|
| Seconds → Physics frames | `int(round(s × 120))` | 0.4s = 48F |
| Logic frames → Physics frames | `logic_f × 2` | 18 logic = 36 physics |
| Animation frames → Physics frames | `anim_f × 2` | 8 anim = 16 physics |
| Frame advantage | `hitstun_f − blockstun_f` | 48 − 40 = +8 |
| Cancel window | `recovery_frames − cancel_window_timer` | varies |

## Verification Checklist

### Animation
- [ ] Animation designed at 60 FPS baseline
- [ ] Total animation frames × 2 = total physics frames
- [ ] Startup frames: before hitbox active
- [ ] Active frames: hitbox enabled in animation timeline
- [ ] Recovery frames: after hitbox disabled, before animation_reset callback

### Physics / Game Logic
- [ ] `hitstun_frames` value in `.tres` resource matches expected
- [ ] `blockstun_frames` = `hitstun_frames − N` (typically N = 8–12F advantage)
- [ ] Knockback velocity in fixed-point (not raw pixels)
- [ ] Hit stop frames (if any) pause both players' frame counters

### Input Buffer
- [ ] Cancel window opens at correct recovery frame
- [ ] 30-frame buffer window (0.25s) doesn't allow unintended chains

## Output
List: startup / active / recovery in both animation frames AND physics frames, frame advantage on hit and block.
