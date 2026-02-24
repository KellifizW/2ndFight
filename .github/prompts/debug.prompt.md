---
mode: ask
description: Diagnose a gameplay bug with fighting-game-specific triage
---

# Debug Session

Follow the Stop-the-Line protocol. Diagnose before fixing.

## Bug Report Template

Fill in before proceeding:
- **Repro inputs**: (exact button sequence, e.g., "↓↘→ + MP while dashing")
- **Game state**: (e.g., "Player A in hitstun, Player B landing")
- **Expected**: (e.g., "+3F advantage on block")
- **Actual**: (e.g., "attack executes twice")
- **Frequency**: (always / sometimes / only after X)

## Triage Checklist

**Step 1 — Localize the system**
Which handler/system is responsible?
- Frame counting bug → `Fighter.gd` hitstun/blockstun
- Input executing twice → `InputBuffer.gd` consumption failure
- Wrong animation → `AnimationManager.gd` or AnimationTree conditions
- Physics jitter → `GravityHandler`, `KnockflyHandler`, fixed-point overflow
- AI spamming → `AIDecisionLayers.gd`, action commitment

**Step 2 — Check the frame math**
- Are frame counters decrementing once per physics frame (120 FPS)?
- Is hit stop (`is_in_hitstop`) pausing the right counters?
- Is there a logic-frame (60) vs physics-frame (120) mismatch?

**Step 3 — Check input buffer**
- Is `consume_button_input()` called after execution?
- Buffer window: 30 frames = 0.25 seconds — is the window too wide?

**Step 4 — Minimal reproduction**
Simplest game state that triggers the bug. Describe steps, don't guess fix yet.

**Step 5 — Root cause**
State the root cause precisely before proposing any code change.

---
> Do NOT write fixes until root cause is confirmed.
