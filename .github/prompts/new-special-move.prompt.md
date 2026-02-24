---
mode: agent
description: Add a new special move (quarter-circle, DP, charge, etc.)
---

# New Special Move

I want to add a new special move. Follow the data-driven pattern in `data/specials/`.

## Inputs Needed
- **Move name** (e.g., `dav_uppercut`, `den_spinKick`): [SPECIFY]
- **Character**: Dav / Den
- **Input motion**: quarter-circle forward / quarter-circle back / DP (↓↘→) / charge / other
- **Button**: LP / MP / HP / LK / MK / HK
- **Damage**, **hitstun** (physics frames), **blockstun** (physics frames)
- **Invincibility frames** (if any): startup frame X to frame Y

## Implementation Steps

1. **Read an existing special** — read a `.tres` file in `data/specials/` and `SpecialMoveData.gd` for structure
2. **Create `data/specials/[name].tres`** — fill all SpecialMoveData fields
3. **Add to MoveSet resources** — add path to `DAVMoveSet.gd` or `DENMoveSet.gd` SPECIAL_MOVE_RESOURCES array
4. **Add input detection** — add sequence constant in `InputManager.gd` (use absolute direction encoding)
5. **Add input sequence resource** — in `data/specials/inputs/` if using resource-based sequences
6. **Create animation** — note startup / active / recovery frames (design at 60 FPS baseline)
7. **Consume both buffers** — motion input AND button buffer consumed together
8. **Verify in-game** — both seats, both facing directions

## Direction Encoding Reminder
- `move_right` always encodes as FORWARD (3) — absolute, not relative to facing
- `move_left` always encodes as BACK (5)
- Both players use the SAME key-based encoding

## Non-Negotiables
- Move data in `.tres` resource — NOT hardcoded in Player.gd or MoveSet.gd
- Motion input AND button consumed atomically
- Facing lock (`is_facing_locked`) set during special execution if needed
