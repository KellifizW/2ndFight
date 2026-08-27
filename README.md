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
| **1** | **Unify the time domain** — all gameplay logic in integer physics frames | ✅ Done (all 6 timer families migrated + conversions consolidated; frame tests 24, local acceptance pending) |
| **2** | **Explicit state machine** — replace the ~34 boolean flags | ⏳ Planned |
| **3** | **Consolidate frame data** — one source of truth, fix corrupt entries | ⏳ Planned |
| **4** | **Converge input handling** — a single `ActionMapper` | ⏳ Planned |
| **5** | **Cleanup** — dead code, docs, scene splitting | ⏳ Planned |
| — | **CI** — run frame tests on every push/PR | 🟡 Written, needs activation (see below) |

---

## Roadmap

### Stage 1 — Unify the time domain ✅

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
- ✅ PushManager stun-lock family: `knockfly_timer` / `hit_timer` / `block_timer` / `block_push_timer` (`float` seconds, `-= delta`) → `knockfly_frames` / `hit_lock_frames` / `block_lock_frames` / `block_push_frames` (`int` physics frames, `-1` per tick). PushManager still owns the decrement so knockfly velocity interpolation stays atomic, but it now **freezes during hitstop** — the old `-= delta` path kept advancing while `fighter.gd` returned early.
- ✅ Knockfly duration conversion goes through `Movement.start_knockfly_timer()` → `seconds_to_lock_frames()` (0.4s → 49). Hit/block locks seed from the already-converted physics-frame counts (`hitstun_frames` / `blockstun_frames`), so they stay aligned.
- ✅ `floor_snap_immunity_timer` type corrected to `int` (it was already decremented by 1).
- ✅ New frame tests `test_18` / `test_19` / `test_20` pin the conversion formula and the hitstop freeze.
- ✅ **Closing slice** — the remaining timer families, all landed:
  - Every designer-seconds seed now flows through `Movement.seconds_to_frames_nearest()`,
    replacing the ~12 scattered `int(round(sec * 120))` sites (jump delay 0.1→12, double-tap
    window 0.3→36, dash 0.35→42, layground 0.2→24, wake-up, attack movement, air-hit backjump
    0.2→24, floor-snap immunity 0.1→12). Bit-identical values at 120 Hz.
  - `air_hit_backjump_timer` / `floor_snap_immunity_timer` seeds no longer spell
    `* LOGIC_FPS * 2`; the split is gone.
  - Logic↔physics conversion consolidated to **one** function,
    `Movement.logic_frames_to_physics_frames()`. Duplicates removed: Fighter's two unused
    second-based helpers deleted (one kept as a thin delegate), ThrowHandler's private copy
    deleted, `HitResponseHandler` and `world.gd` inline `×2`/`×FPS_RATIO` formulas routed here.
  - `combo_reset_timer` (float seconds, `-= delta`) → `combo_reset_frames` (int ticks):
    seeded as `hitstun_logic × 2 + seconds_to_lock_frames(0.2)` (24-frame hitstun → 48+25 = 73),
    −1 per tick, immune to `time_scale`.
  - AI pacing timers → physics frames: `decision_cooldown` → `decision_cooldown_frames`,
    `commitment_timer` → `commitment_frames`, `opponent_search_timer` → `opponent_search_frames`
    (with `AIBehavior` moving from `_process` to `_physics_process`). Seeds 0.033s→4 ticks,
    0.016s→2, 0.05s→6 — exactly the "2/1/3 logical frames" the original comments *intended*;
    previously the real tick count drifted with render framerate and `time_scale`.
    The blockstun clamp also simplified: `min(commitment_frames, blockstun_frames)` — same
    integer domain, no more `÷120` round-trip.
  - `PlayerController` double-tap window: `double_tap_timer: float` decremented in `_process`
    (real-time!) → `double_tap_frames: int` in `_physics_process`, exactly 36 ticks, matching
    the `neutral_timer` window it feeds. `Movement.double_tap_timer` (a *duration*, not a
    countdown) renamed to `double_tap_window_seconds` to kill the name collision.
  - Dead class `SpecialMoveBase` (zero references repo-wide; hosted the leftover
    `jump_timer`/`timer` second-domain paths) removed.

**Conversion boundaries (the only ones that remain in gameplay logic)**

| Function (`static`, all on `Movement`) | Semantics | Families |
|---|---|---|
| `seconds_to_lock_frames(sec)` | `floor(sec×fps)+1` — reproduces the legacy `-= delta` float countdown | landing lock, knockfly duration, combo buffer |
| `seconds_to_frames_nearest(sec)` | `round(sec×fps)` — legacy *seed* arithmetic, values unchanged | dash / jump delay / double-tap / layground / wake-up / attack movement / air-hit backjump / AI intervals |
| `logic_frames_to_physics_frames(f)` | logic (60 FPS) → physics frames, single ×2 implementation | hitstun / blockstun / move durations / throw windows |

**Disclosed one-frame deltas (intentional, test-pinned)**

- The combo-label window used to be drained by a float loop whose last subtraction
  sometimes crossed zero a frame early (24-frame hitstun measured 72 ticks; other stun
  values 73). The frame-based seed is a constant `stun×2 + 25`. Only the label's lifetime
  moves ±1 tick (8 ms); combo *counting* is unaffected (it reads the fighters' actual stun
  frames). `test_13` / `test_21` pin the new value.
- AI decision cadence was previously measured in render-frame deltas — i.e. not
  deterministic across environments to begin with. It is now fixed in physics ticks.

**Deferred (explicitly beyond Stage 1)**: the three AI *subsystem* pacing timers
(`AIComboSystem.combo_timer`, `AIDecisionLayers.cache_timer`/`special_cooldown_timer`,
`ThreatAssessment.projectile_check_timer`) and the unused generic `TimerManager` fold
into Stage 4 (AI/input convergence). UI-only seconds domains (`FrameCounter`, labels,
camera, BGM, tweens) stay seconds per the ground rules.

> ⚠️ **Conversion gotcha, learned the hard way.** The legacy pattern
> `timer = max(0, timer - delta)` looping while `timer > 0` does **not** run
> `seconds × fps` times. At 120 Hz, `0.2s` runs **25** frames, not 24: after 24
> floating-point subtractions the residue is `5.2e-17`, still `> 0`, buying one
> extra frame. Converting with `round()` silently shortens the state by a frame.
> Use `Movement.seconds_to_lock_frames()` — `floor(sec * fps) + 1` — which
> reproduces the old counts exactly (`0.2→25`, `2/60→5`, `0.001→1`).
> The two families must **not** be swapped: `seconds_to_frames_nearest` exists because
> seed-based timers (dash!) were *born* rounding — using lock-style there makes dash 43.

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

Frame tests currently cover 24 cases (`test_01`–`test_24`), including the Stage 1
landing, PushManager stun-lock, and closing-slice families: `test_21` combo-window frame
counting, `test_22` the three conversion boundaries (including the "families must not be
swapped" guard), `test_23` AI decision/commitment tick semantics, and `test_24` the
36-tick double-tap window.

### Not yet covered (honest disclosure)

- Motion-input macros (Stage 4)
- Full air-attack / throw / knockfly flows (Stages 2–4)
- Corner-pushing and other extreme coordinate cases (after Stage 3)

### Why the agent sandbox cannot run the engine (and what it does instead)

Verified in-sandbox while landing the Stage 1 closing slice (PR #19) — recorded so
nobody re-litigates it, and so PR descriptions honestly say *how* they were checked.
A Linux agent sandbox cannot substitute for the harness; **only real CI (or your
machine) can**:

| Gate | Measured fact |
|---|---|
| Binary download | The sandbox egress allowlist permits `github.com` / `api.github.com` / `codeload` / PyPI / npm — nothing that serves the engine. Release-asset CDNs, `godotengine.org`, `downloads.tuxfamily.org`, Docker registries and apt mirrors all die mid-TLS (`SSL_ERROR_SYSCALL`). No PyPI/npm package ships a Godot binary either |
| Windows `.exe` | The sandbox is Linux x86_64 without Wine → an uploaded `Godot.exe` would *arrive* (repo files flow over the permitted git hosts) but could never *execute* |
| Linux build, committed to the repo | Deliverable inside GitHub's 100 MB per-file limit **only as the zip** (~60 MB; the ~150 MB binary does not qualify). It still will not start: `godot --headless` hard-links `libXcursor`, `libXinerama`, `libXi`, `libGL`, `libxkbcommon` (+ `libdrm`/`libgbm`/`libharfbuzz`), which this container lacks with no reachable package source to install them |
| Source build | No X11/Wayland dev headers, no `pkg-config`, apt sources dead |

**What automated review can honestly claim without CI**: full-project engine compile
via the *active* `deploy-web` workflow (`--export-release "Web"` parses/compiles every
non-excluded `.gd` with the real Godot 4.7.2) + `gdtoolkit` `gdparse`/`gdlint` +
float64-identical conversion simulations (Python doubles ≡ Godot floats; used in
PR #19 to prove every routed seed reproduces the old tick counts). **What only CI or
local runs can claim**: the 24 physics-frame assertions. This asymmetry is the whole
argument for activating the parked workflow above — after that, the sandbox's
inability stops mattering entirely.

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

- **Hitstop uses `Engine.time_scale`.** It works, and after Stage 1 every gameplay timer counts physics ticks instead of scaled `delta`, so the remaining exposure is UI-only (labels/`FrameCounter`). Documented as an accepted limitation rather than fixed.
- **WOO is incomplete** and its future is a Stage 3 decision.
- **Some frame data is wrong** — see the "known data issues" section of `FRAME_DATA_TABLE.md`.
