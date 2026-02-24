---
mode: ask
description: Review recently changed code for correctness and fighting-game discipline
---

# Code Review

Review the specified file(s) or recent changes against the project's non-negotiable rules.

## Review Checklist

### Fixed-Point Discipline
- [ ] All positions/velocities use `Vector2i` — no `Vector2` for physics
- [ ] Pixel values multiplied by `SIMULATION_SCALE` (1000)
- [ ] No `float` arithmetic for physics-critical paths
- [ ] Large velocity values clamped before assignment (overflow risk)

### Frame Timing
- [ ] Durations use frame counters (`hitstun_frames`), not `delta` timers
- [ ] Logic frames (60 FPS) converted to physics frames (120 FPS) with 2× ratio
- [ ] Hit stop respected — frame counters check `is_in_hitstop` before decrement

### Handler Boundaries
- [ ] Logic lives in the correct handler (no dash logic in JumpHandler, etc.)
- [ ] Movement.gd and Player.gd not modified directly when a handler should own it
- [ ] Handler files stay under ~400 lines

### Input & Buffer
- [ ] Buffer consumption called after every attack execution (no double-fire)
- [ ] Motion inputs AND button buffers consumed together for specials

### Animation Integration
- [ ] Hitboxes activated via animation timeline events, not code timers
- [ ] AnimationTree conditions reset before transitioning to new state
- [ ] Callbacks registered in `player_anim_resets` dictionary

### Code Quality
- [ ] No magic numbers — use constants from `world.gd` or `Fighter.gd`
- [ ] Seat system used (`"player_a"` / `"player_b"`), not numeric player_id
- [ ] Functions under 50 lines; files under 400 lines

## Output Format
For each issue found: **[SEVERITY: CRITICAL/WARN/INFO]** file path → specific line → what's wrong → one-line fix.
