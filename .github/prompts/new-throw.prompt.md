```prompt
---
mode: agent
description: Add or modify a throw (摔投) for a character
---

# New / Modified Throw

Throws use the same data-driven resource pattern as attacks. Follow this sequence exactly.

## Inputs Needed
- **Character**: Player A (Dav) / Player B (Den) / Both
- **Throw damage**: (reference: default 8.0)
- **Hitstun frames** (logic frames @60FPS): (reference: default 36 = 0.6s)
- **Launch vertical speed** (pixels/frame, negative = up): (reference: -2200.0 = high arc)
- **Launch horizontal speed** (pixels/frame): (reference: 0.0 = no extra push)
- **Gravity during knockfly** (fixed-point units): (reference: 1900000.0)

## Implementation Steps

1. **Read existing throw data** — read `data/ThrowData.gd` for all available fields, read `data/p1_throw_data.tres` as a template
2. **Edit the throw resource** — modify `data/p1_throw_data.tres` and/or `data/p2_throw_data.tres` in Inspector (or directly edit `.tres`)
3. **Verify throw_data is wired** — open `DAV.tscn` / `DEN.tscn`, confirm Player node has `throw_data` export set to the correct `.tres`
4. **Check animation durations** — `throw_enter_duration` and `throw_seq_duration` must match the AnimationPlayer animation lengths (logic frames @60FPS)
5. **Verify in-game** — test throw execution for both Player A and Player B seats

## Key Parameters

| Parameter | Unit | Notes |
|-----------|------|-------|
| `throw_hitstun_frames` | Logic frames @60FPS | Converted to physics frames (×2) internally |
| `throw_knockback_horizontal` | Pixels/frame (unscaled) | Multiplied by SIMULATION_SCALE in code |
| `throw_launch_vertical_speed` | Pixels/frame (negative = up) | Set negative for upward arc |
| `throw_gravity` | Fixed-point units | 1900000 ≈ standard knockfly gravity |
| `throw_enter_duration` | Logic frames @60FPS | Must match `throw_enter` animation length |
| `throw_seq_duration` | Logic frames @60FPS | Must match `throw_seq` animation length |

## Animation Requirements
- `throw_enter` — grab / startup animation
- `throw_seq` — the throw execution / victim animation
- Both must exist in character's AnimationPlayer AND AnimationTree

## Non-Negotiables
- All values stored in `.tres` resource (NOT hardcoded in player.gd)
- Duration values are logic frames @60FPS — the system converts to physics frames internally
- Horizontal/vertical speed values are unscaled pixels/frame — SIMULATION_SCALE applied in code
- Test both seats: Player A throwing Player B AND Player B throwing Player A

## Reference
- Data definition: `data/ThrowData.gd`
- Usage in code: `scripts/core/player.gd` → `_on_thrown()` method
- Full guide: `docs/guides/throwdata_guide.md`
```
