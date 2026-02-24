---
mode: agent
description: Add a new normal attack (e.g., st_hp, cr_lk, jump_mp)
---

# New Normal Attack

I want to add a new normal attack to the game. Follow this exact sequence:

## Inputs Needed
- **Attack name** (e.g., `st_hp`, `cr_mk`, `jump_lp`): [SPECIFY]
- **Character**: Player A (Dav) / Player B (Den) / Both
- **Damage**: (reference: st_lp ≈ 4, st_mp ≈ 8, st_hp ≈ 15)
- **Hitstun frames** (physics, 120 FPS): (reference: light ≈ 24F, medium ≈ 36F, heavy ≈ 48F)
- **Blockstun frames** (physics, 120 FPS): (typically hitstun − 8F)
- **Knockback velocity** (fixed-point units, multiply pixels × 1000)

## Implementation Steps

1. **Read existing attack** — read `data/AttackData.gd` and a similar existing attack for template
2. **Add property to AttackData.gd** — `@export var [name]: AttackProperties`
3. **Update resource files** — `data/p1_attack_data.tres` and/or `data/p2_attack_data.tres`
4. **Add to Player.ATTACK_TABLE** — in `player.gd`
5. **Add buffer consumption** — in Player.gd attack input section
6. **Create animation** — note required frame count (design at 60 FPS baseline)
7. **Verify in-game** — test both Player A and Player B seats

## Verification
- Attack executes once (not twice) — buffer consumed correctly
- Frame advantage matches: `hitstun_frames - blockstun_frames = expected_advantage`
- Works for both player seats

## Non-Negotiables
- All values stored in `.tres` resource, NOT hardcoded in Player.gd
- Knockback velocity multiplied by SIMULATION_SCALE (1000)
- Hitstun/blockstun in physics frames (120 FPS)
