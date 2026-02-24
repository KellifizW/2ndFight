---
mode: ask
description: Plan a new feature or change before writing any code
---

# Feature Planning

Before writing any code, analyze the request and produce a structured implementation plan.

## Required Output

**1. Affected Systems**
List every handler / system touched (e.g., `AttackExecutor`, `Fighter.gd`, `InputManager.gd`).

**2. Resource Changes**
List `.tres` files that need creating or editing (AttackData, MoveSet, SpecialMoveData, etc.).

**3. Animation Requirements**
List animations to create, their expected frame count at 60 FPS baseline, and any hitbox events needed.

**4. Fixed-Point Math Audit**
Flag any new values that need `× SIMULATION_SCALE (1000)` conversion.

**5. Frame Timing Audit**
Flag any durations — convert to physics frames: `int(round(seconds × 120))`.

**6. Implementation Order**
Numbered steps, smallest testable slice first. Each step must be independently verifiable in-game.

**7. Verification Steps**
Concrete in-game scenarios to test (e.g., "Player A dash-cancel into st_mp at frame 10 → expect +2F advantage").

---
> Do NOT write any code yet. Return the plan only.
