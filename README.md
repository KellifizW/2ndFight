# 2ndFight

A 2D fighting game built in **Godot 4.7.2**, with deterministic fixed-point physics
running at a 120 Hz tick and frame data authored in 60 FPS logical frames.

Three characters are playable — **DAV**, **DEN**, and **WOO** (incomplete) — with
normals, specials, throws, dashes, blocking, juggle/knockfly states, and a
scripted AI opponent.

> **This README is a roadmap.** It documents where the codebase is heading and
> which optimizations remain. The authoritative, detailed plan lives in
> [`plan_game.md`](plan_game.md); this file is the executive summary.

---

## Why there is a roadmap

The game works, but it grew organically. An architecture review identified four
structural problems that make every new feature more expensive than the last:

| Problem | Symptom |
|---|---|
| Four coexisting time domains | Seconds, 60 FPS logical frames, 120 FPS physics frames, and a `FrameCounter` all mixed together, with dozens of scattered `*2` / `*120` / `/2.0` conversions |
| ~34 boolean state flags | `is_hit`, `is_knockfly`, `is_blocking`, `is_attacking`, `is_dashing`… combinations are unenforceable, so illegal states are reachable |
| Frame data spread across sources | The same numbers live in scripts, scenes, and tables, so they drift apart |
| Two overlapping input paths | `InputManager` and `PlayerController` both interpret input, with different buffering rules |

The work is organized into six stages. **The guiding rule is that the game must
play identically after each refactor** — behavior changes are a separate concern
from structural changes.

---

## Ground rules for this refactor

These are non-negotiable and apply to every contribution:

1. **Safety net first.** No refactor without tests covering the behavior being changed.
2. **Behavior must not change.** Verified by frame tests, not by eyeballing.
3. **No big-bang rewrites.** One timer family, one subsystem, one slice at a time.
4. **No purely cosmetic cleanup.** Reformatting untouched code creates review noise
   and hides real changes. (This is why `gdlint`'s ~2400 existing line-length
   warnings are deliberately *not* treated as a gate — fixing them would touch
   every file and obscure genuine diffs.)
5. New moves go through the existing data pipeline; they don't add new logic paths.

---

## Stage status

| Stage | Goal | Status |
|---|---|---|
| **0** | Stop the bleeding: `DebugLogger`, frame-test harness, frame data table, contributor rules | ✅ Done |
| **1** | **Unify the time domain** — all gameplay logic in integer physics frames | 🔄 In progress |
| **2** | **Explicit state machine** — replace the ~34 boolean flags | ⏳ Planned |
| **3** | **Consolidate frame data** — one source of truth, fix corrupt entries | ⏳ Planned |
| **4** | **Converge input handling** — a single `ActionMapper` | ⏳ Planned |
| **5** | **Cleanup** — dead code, docs, scene splitting | ⏳ Planned |
| — | **CI** — run frame tests on every push/PR | 🟡 Written, needs activation (see below) |

---

## Roadmap

### Stage 1 — Unify the time domain 🔄

**Target invariants**

- Every gameplay timer is an `int` counted in physics frames, decremented by `1` per `_physics_process`.
- Frame data (hitstun / blockstun / durations) is stored in 60 FPS logical frames and converted **once**, at the data-loading boundary.
- Seconds only survive in UI, camera, BGM, and visual tweens.
- Exactly **one** logical-frame ↔ physics-frame conversion point remains in the codebase.

**Why it matters beyond tidiness:** during hitstop the engine sets
`Engine.time_scale = 0.02`, which scales `delta`. Any timer still counting in
seconds silently stretches by up to 50×. Frame-counted timers are immune.

**Done**

- ✅ `landing` timer family: `landing_lock_timer: float` (seconds) → `landing_lock_frames: int` (physics frames), across all 26 read/write sites.
- ✅ Removed the write-only dead flag `_landing_interrupted_by_input`.
- ✅ Extracted `Player._enter_landing_state()`, collapsing three byte-identical copies of the landing-entry block.

**Remaining timer families**

- `knockfly_timer`, `hit_timer`, `block_timer`, `block_push_timer` — the `-= delta` group in `PushManager.gd`. These are the clearest instance of the hitstop bug above: `fighter.gd` returns early during hitstop, but `PushManager` runs outside that guard.
- `jump_delay_timer`, `neutral_timer`, `floor_snap_immunity_timer`
- `dash_time` / `backdash_time`, `combo_reset_timer`
- `decision_cooldown` (AI), `double_tap_timer` (`PlayerController`), `jump_timer` (`SpecialMoveBase`)
- `air_hit_backjump_timer` — currently an `int`, but seeded via `* LOGIC_FPS * 2`; needs splitting.

> ⚠️ **Conversion gotcha, learned the hard way.** The legacy pattern
> `timer = max(0, timer - delta)` looping while `timer > 0` does **not** run
> `seconds × fps` times. At 120 Hz, `0.2s` runs **25** frames, not 24: after 24
> floating-point subtractions the residue is `5.2e-17`, still `> 0`, buying one
> extra frame. Converting with `round()` silently shortens the state by a frame.
> Use `Movement.seconds_to_lock_frames()` — `floor(sec * fps) + 1` — which
> reproduces the old counts exactly (`0.2→25`, `2/60→5`, `0.001→1`).

### Stage 2 — Explicit state machine ⏳

Replace the ~34 booleans with one explicit state enum plus a transition table, so
illegal combinations become unrepresentable rather than merely discouraged.
Migrate subsystem by subsystem; during the transition, flags and states run in
parallel and the tests keep them aligned.

### Stage 3 — Consolidate frame data ⏳

Make `docs/systems/FRAME_DATA_TABLE.md` generated rather than hand-maintained,
and fix the known-corrupt entries (DEN `spnk`, DAV `dpM`/`dpH` report 0-frame
animations). Decide whether WOO ships or is cut.

### Stage 4 — Converge input handling ⏳

Collapse `InputManager` and `PlayerController` into a single `ActionMapper` with
one buffering policy, then add motion-input tests (QCF, DP, throw windows) and an
AI-symmetry test.

### Stage 5 — Cleanup ⏳

Remove the `backup(for reference only do not change)/` tree, stale diagnosis
cards, a 284 KB stray `.patch`, the unused `godot_state_charts` plugin, and
duplicated AI scripts. Split the oversized character `.tscn` files. Consolidate
the 70 markdown files under `docs/`.

---

## Testing

The safety net is a headless frame-test harness: each case spawns its own world,
feeds synthetic input, and asserts on exact physics-frame counts.

```bash
# Run all frame tests (requires Godot 4.7.2 on PATH, or set GODOT_BIN)
bash tests/frame_tests/run_frame_tests.sh

# Static parse of every GDScript file
pip install "gdtoolkit==4.*"
find scripts ai tests characters data -name '*.gd' | sort | xargs gdparse
```

A ready-to-run GitHub Actions workflow lives at [`ci/frame-tests.yml`](ci/frame-tests.yml).
It runs both commands above on every push and pull request, inside the
`barichello/godot-ci:4.7.2` container.

> **It is parked, not active.** The automation that added it authenticates as a
> GitHub App without the `workflows` permission, so it could not write into
> `.github/workflows/`. To turn it on:
>
> ```bash
> git mv ci/frame-tests.yml .github/workflows/frame-tests.yml
> git commit -m "Activate frame-test CI"
> ```
>
> Until then, run the frame tests locally before merging anything.

**When writing new cases**, read [`tests/frame_tests/README.md`](tests/frame_tests/README.md) first.
The rules that bite hardest:

- `await` every coroutine helper — a missing `await` produces a silent false pass.
- Lambdas may only capture locals (`var me = p1`, then pass `me`).
- Measure in physics frames, never seconds. 1 logical frame = 2 physics frames.
- Leave generous wait windows around hits — hitstop slows physics-frame advance by 50×.

### Not yet covered (honest disclosure)

- Motion-input macros (Stage 4)
- Full air-attack / throw / knockfly flows (Stages 2–4)
- Corner-pushing and other extreme coordinate cases (after Stage 3)

---

## Project layout

```
scripts/core/        Player, Fighter, Movement, World, PushManager, TimerManager
scripts/handlers/    Per-concern handlers (timers, landing, dash, jump, gravity, animation…)
scripts/combat/      Move sets, attack execution, cancel windows, hit response, throws
scripts/input/       InputManager, PlayerController, InputBuffer
ai/                  Behavior tree, decision layers, combo system, threat assessment
characters/          DAV / DEN / WOO scenes
tests/frame_tests/   Deterministic frame-accurate test harness and cases
docs/                Design and system documentation
plan_game.md         The full six-stage refactor plan
```

---

## Known limitations

- **Hitstop uses `Engine.time_scale`.** It works, but it scales `delta` globally, which is exactly why second-based timers must go. Documented as an accepted limitation rather than fixed.
- **WOO is incomplete** and its future is a Stage 3 decision.
- **Some frame data is wrong** — see the "known data issues" section of `FRAME_DATA_TABLE.md`.
