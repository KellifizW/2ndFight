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
| ~34 boolean state flags | `is_hit`, `is_knockfly`, `is_blocking`, `is_attacking`, `is_dashing`… combinations are unenforceable, so illegal states are reachable. Stage 2 slice 1 added a state layer that makes the remainder testable and deleted 6 dead flags; slice 2 ported the attack subsystem onto it and deleted one more; slice 3 ported the movement subsystem onto it (no further deletions, 32 held). Reproducible count (member-level `var x: bool` in `Movement`/`fighter`/`player`, excluding `@export` config and locals): **33 → 32** |
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
| **1** | **Unify the time domain** — all gameplay logic in integer physics frames | ✅ Done (all 6 timer families migrated + conversions consolidated) |
| **2** | **Explicit state machine** — replace the boolean flags | 🔄 In progress — slices 1–3 landed (read-only state layer, attack subsystem ported, movement subsystem ported, AI `attack_type` parity fixed; 7 dead flags deleted, 33 → 32, test count 30 → 32) |
| **3** | **Consolidate frame data** — one source of truth, fix corrupt entries | ⏳ Planned |
| **4** | **Converge input handling** — a single `ActionMapper` | 🔄 Partial — parity fix #1 landed (AI `attack_type` restored via shared `PlayerController.resolve_attack_type`); `InputManager` / `PlayerController` collapse to a single `ActionMapper` still pending |
| **5** | **Cleanup** — dead code, docs, scene splitting | ⏳ Planned |
| — | **CI** — run frame tests on every push/PR | ✅ Active (`.github/workflows/frame-tests.yml`) |

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

### Stage 2 — Explicit state machine 🔄

Replace the booleans with one explicit state enum plus a transition table, so
illegal combinations become unrepresentable rather than merely discouraged.
Migrate subsystem by subsystem; during the transition, flags and states run in
parallel and the tests keep them aligned.

**Slice 1 — the state layer exists and is pinned (landed)**

The order matters here: writing a state machine *first* and porting the control
flow to it *second* is what makes each later slice reviewable. So slice 1 adds
the state layer as a **read-only derivation** and changes no behavior at all.

- ✅ **`FighterState`** (`scripts/core/FighterState.gd`) — a 19-value `State`
  enum plus `resolve(fighter)`, a **pure function** that derives "exactly one
  active state" from today's flags. It writes nothing; the control flow still
  reads flags. Entry points: `Fighter.get_fighter_state()` /
  `get_fighter_state_name()`.
- ✅ **The priority order is now written down.** `resolve()` deliberately
  replicates the two existing animation chains
  (`Player._compute_target_state` → `AnimationManager.compute_target_state`),
  because those chains *are* this game's de-facto state priority. Previously
  that order lived only as an implicit convention split across two files; now
  `test_26` fails the moment they drift apart.
- ✅ **14 dead flags/variables deleted**, each proven unread by a
  comment-stripped read/write analysis over every `.gd`/`.tscn`/`.tres`
  (checking for dynamic `get`/`set` and scene overrides too):
  - Flags: `is_crouch_transition_played`, `is_crouch_held`, `is_airborne`,
    `_landing_timer_initialized`, `is_being_pushed`, `is_air_hit_knockfly`
  - Variables: `current_mode`, `cancel_window_duration`, `powerkk_blockstun`,
    `knockback_start_x`, `last_hit_attack_name`, `initial_blockstun_frames`,
    `initial_hitstun`, `knockback_total_time`, `hit_push_timer`,
    `hit_push_offset`, `dash_direction`, `pending_jump_b_seek`,
    `air_hit_backjump_up_speed`, and the `@deprecated` seconds-domain push pair
    `initial_blockstun` / `block_push_velocity`
- ✅ **Two unreachable code paths removed** (this is the part that was actually
  hiding bugs, not just noise):
  - The whole **`is_push_back` family** (`push_back_velocity` / `push_back_frames`
    / `initial_push_back_frames` / `push_back_timer`). Its only assignment
    repo-wide was `= false`, inside the very branch it guards — so the
    "push-apart deceleration" path was dead from the start, yet `is_push_back`
    still appeared as a fake mutual-exclusion term in **five** guard conditions
    (Dash / Jump / Walk ×2 / AI-dash). Removing it leaves those conditions
    identically valued.
  - The **linear knockfly decay branch** in `PushManager`, selected by
    `is_air_hit_knockfly` — a flag never set to `true` anywhere, so the
    quadratic curve was always the one running.
- ✅ Boolean state flags in the three core scripts: **37 → 31**.

**Disclosed divergences (found, not introduced)**

Brute-forcing `resolve()` against both animation chains over 55k+ flag
combinations turned up exactly two places where they disagree. Both are gaps in
the *animation* layer, not transcription errors — and fixing them would change
behavior, which slice 1 is not allowed to do (ground rule 2). They are modeled
honestly in the state layer, documented in `FighterState.gd`, and skipped **by
explicit state condition** in `test_26` (skips are counted and printed, so a
genuinely new divergence can't hide inside the exemption):

1. **`is_being_thrown` has no animation branch at all.** The victim keeps
   playing whatever animation was active when grabbed (walk/attack/crouch);
   `ThrowHandler` takes over position to paper over it. The state layer reports
   `BEING_THROWN`, which is what the frame actually means (input is discarded,
   position is externally driven).
2. **Airborne with both `is_jumping` and `is_air_attacking` false** falls
   through to `return "Walk"` — a walk animation while off the ground. Reachable
   e.g. for the few frames after an air-hit backjump ends before landing. The
   state layer reports `JUMP`.

**Slice 2 — the attack subsystem reads the state layer (landed)**

Slice 1 built the state layer; slice 2 is the first slice that actually *routes
control flow through it*. The attack subsystem goes first because its boundary is
the cleanest (`plan_game.md` §6 migration order: attacks → movement → hit
reactions).

- ✅ **One attack entry point, not two.** `Fighter._physics_process` still
  carried the pre-refactor attack check (`st_mp_pressed or st_mk_pressed` →
  `is_attacking = true`). It ran *earlier* every frame than `AttackExecutor`,
  used a **different** guard set (extra `not is_crouching`, missing
  landing/wakeup/layground), ignored button priority, and never consumed the
  input buffer. Its three observable effects were checked one by one before
  removal:
  | Effect | Verdict |
  |---|---|
  | `current_damage = 10.0` | Unobservable — the only reader (`HitResponseHandler._get_hit_parameters`) uses it as a default and then always overwrites it from `ATTACK_TABLE[attack_type].damage` / `active_move.damage`. Its `input_data.has("damage")` branch has no producer anywhere in the repo |
  | `is_attacking = true` on a frame where `AttackExecutor` also fires | Duplicate write, same value |
  | `is_attacking = true` on a frame where it does **not** | The only real difference — and it is a bug (see below) |
- ✅ **The "orphan attack" state is now structurally impossible.** That third row
  left `is_attacking = true` with `attack_type` still `"none"`: the animation
  layer plays `"Walk"`, `MoveSet` refuses to start a special, the jump/dash
  guards all block, and `attack_duration_timer` stays `0`, so no timer ever
  reclaims it. Two windows reach it — the physics frame right after a no-input
  touchdown (`landing_lock_frames` 5→4 with `_landing_forced_frames` still `1`,
  so the landing-attack cancel cannot fire yet), and the frame an attack
  animation ends (`reset_attack_state` just cleared `attack_type` while the
  same-attack dedup lock blocks re-execution). Both are one frame wide and the
  30-frame `InputBuffer` usually self-heals them on the next frame — narrow, but
  not legal. With the entry point gone, `is_attacking = true` has exactly two
  writers left (`Player._execute_attack`, `ThrowHandler` entering `throw_seq`),
  and **both** write a valid `attack_type` in the same block; every
  `attack_type = "none"` writer clears `is_attacking` in the same block. So
  `FighterState.check_invariants()` gained a new rule — *attacking requires a
  legal `attack_type`* — that holds **by construction**, not by convention, and
  `test_25`/`test_29` assert it every frame.
- ✅ **Attack gates consolidated 3 → 1.** "Can I attack right now" had three
  non-identical copies: `Player.is_valid_ground_state`, the recomputed copy
  inside the landing-attack-cancel branch (landing term dropped), and
  `Fighter`'s legacy `is_valid_state`. The first two are now
  `FighterState.can_start_ground_attack()`; the third is gone with its entry
  point. `Player.is_valid_air_state` became `FighterState.can_start_air_attack()`.
  All three new predicates are **value-identical** to the expressions they
  replaced, verified by enumerating all 16,384 combinations of the 14 flags they
  read (0 mismatches) and pinned per-frame in-engine by `test_30`.
  The landing-cancel copy turned out to be provably redundant: it dropped the
  landing term, but `is_landing`/`landing_lock_frames` are cleared two lines
  earlier, so that term was already constant-true.
- ✅ **Attack ids have one definition.** `st_*`/`cr_*`/`jump_*` lived in three
  overlapping lists in `player.gd` (`_ATTACK_NAMES`, `GROUND_ATTACK_ANIMS`,
  `AIR_ATTACK_ANIMS`) plus a fourth inline literal list in `AnimationManager`.
  The three in `player.gd` are now `FighterState.GROUND_ATTACK_IDS` /
  `AIR_ATTACK_IDS`; `AnimationManager`'s copy belongs to Stage 3 (it is an
  animation-layer table and should move with the frame data).
- ✅ **Throw detection consolidated.** `is_attacking and attack_type in
  ["throw_enter", "throw_seq"]` was written out in 5 places (`Player` ×3,
  `AttackExecutor`, `PushManager` ×2 as a bare string pair). Now
  `FighterState.is_throw_in_progress(f)` / `is_throw_attack_id(id)`.
- ✅ **One more dead flag removed: `_was_in_hitstop`.** Its only reader was a
  hitstop edge-detector whose two branches were both no-ops (one assigned two
  never-used locals, the other was `pass`). Deleted with the block; the only
  live use of `is_in_hitstop` is the attack-duration freeze right below it.
- ✅ **One more dead flag removed: `_was_in_hitstop`** (its only reader was a
  hitstop edge-detector whose two branches were both no-ops).
- ✅ Boolean state flags in the three core scripts: **33 → 32**.
  > Counting rule, so the number is reproducible: member-level `var x: bool`
  > declarations in `scripts/core/Movement.gd` + `fighter.gd` + `player.gd`,
  > excluding `@export` config toggles (`is_ai_controlled`, `skip_pushbox`,
  > `startup_logs`) and function-local variables — i.e.
  > `grep -cE '^var [A-Za-z_]+: bool' <those three files>`.
  > Slice 1's "37 → 31" used a different, undocumented rule (it is not
  > reconstructible from the current tree), so the two series are **not**
  > directly comparable; from here on this is the rule.

**Disclosed findings (found while porting, deliberately *not* fixed here)**

Each of these is a behavior change or belongs to another stage, so ground rules
2 and 3 say hands off — but they are written down so they are not re-discovered:

1. **`current_damage` is effectively write-only.** Every read path overwrites it
   in the same expression. It should disappear when frame data becomes the
   single source of truth (Stage 3).
2. **`AttackBase` is a dead third attack entry point** — `class_name`, zero
   references repo-wide (no scene, no script, no `.tres`). It was *not* deleted:
   it carries exactly the `startup/active/recovery` counters `plan_game.md` §6
   wants the Attack states to own, so Stage 3 should decide between reviving it
   as that owner and deleting it.
3. **The cancel window is human-only.** `check_cancel()` reads
   `input_data.attack_type`, which `PlayerController.get_input_data()` provides
   but the AI's `get_ai_input()` merge does not — so hit-confirm cancels can
   never fire for a CPU fighter. That is Stage 4 (input convergence), where the
   two input paths merge.
4. **`get_input()` runs 3–4× per physics frame** (`Movement`, the `TimerHandler`
   landing checkpoint, `Player`). For humans it is idempotent (the input buffer
   is stateful, reads are not); for the AI each call re-queries
   `get_ai_input()`. Also Stage 4.

**Slice 3 — the movement subsystem reads the state layer (landed)**

Slice 2 ported attacks; slice 3 does the same for **Walk / Dash / Jump** (the
Landing system is already in the state layer via `is_landing` / `landing_lock_frames`).
Same three-step recipe: move the guard into `FighterState`, prove equivalence
by enumeration, pin it per-frame with a `test_30`-style comparison.

- ✅ **Three movement guards consolidated into one definition.**
  - `FighterState.can_walk(f, is_special_moving)` replaces
    `WalkHandler.handle_walk` 內聯展開的 `can_walk`（含 knockback / corner push /
    block knockback 幀計數器）
  - `FighterState.can_dash(f, is_special_moving)` replaces
    `DashHandler.handle_dash` 守衛，以及 `Movement._physics_process` 內
    AI 直接 dash 的**前衝**分支
  - `FighterState.can_jump(f, jump_pressed, is_special_moving)` replaces
    `JumpHandler.handle_jump` 開頭的兩個 if（`is_landing` / `is_being_thrown`）
    加上主守衛（`on_floor` + 跳躍輸入 + 戰鬥狀態清單 + `jump_delay_timer <= 0`）
  - 三份舊表達式**全 262,144 種旗標組合**（17 旗標 × 2 jump_pressed 值）
    與新守衛**逐值等價**（Python 暴力窮舉，0 分岔）
  - `test_31` 600 幀隨機輸入逐幀比對三組對照組 vs `FighterState`，並要求
    三種守衛各自至少為真一次（避免「永遠 false 假綠」）
- ✅ **One disclosed bug held, not fixed (ground rule #2).**
  `Movement._physics_process` 裡 AI 的 `has_backdash_pressed` 分支缺
  `not is_crouching` 守衛，與前衝分支 / `DashHandler` 都不一致 —— 那是
  真的 bug（蹲下時 AI 仍會後衝），但改它會改變行為，所以本切片把
  `_ai_backdash_can_dash` 保留為舊版略寬鬆的展開並在註解標記，
  留給 Stage 2 切片 4 與受擊子系統一併修。
- ✅ **Stage 4 收攏 #1：AI 取消窗口的「死路徑」修掉。** Stage 2 切片 2
  披露的 finding #3 —— `check_cancel(input_data.attack_type, ...)` 對
  CPU 永遠是 "none"（AI 的 `_neutral_input()` / `_compute_ai_input()` 完全
  沒帶 `attack_type` 鍵）—— 已修。把 `PlayerController.get_input_data()`
  內聯的 17 行優先級鏈抽成 `static func resolve_attack_type(d)`，
  `Player.get_input()` 在 AI merge 之後補上正確的 `attack_type` 與
  `character_id`（65,536 種按鍵 × 角色組合與舊鏈值等價）。人類路徑
  (`PlayerController.get_input_data()`) 也改用同一份 helper，行為一幀不變。
  - 新增 `test_32`：p1=AI / p2=人類，600 幀隨機按鍵，逐幀斷言
    `input.has("attack_type")` 兩條路徑都成立，且 `attack_type` 值與
    `resolve_attack_type()` 對照組一致；要求出現 ≥ 3 種 attack_type
    且 AI 路徑至少一次非 `"none"`（否則測試在「AI 永遠不攻擊」時會假綠）。
- ✅ **No flags removed this slice.** 切片 3 與 Stage 4 收攏 #1 都**只**改
  控制流讀什麼，不改旗標數。核心三檔 bool 旗標仍為 **32**（見 §Stage 2 切片 2
  的計數規則）。旗標真正消失仍要等切片 4（受擊族）把守衛搬完。

**Disclosed findings (found while porting, deliberately *not* fixed here)**

1. **AI 直接 backdash 缺 `not is_crouching` 守衛**（見上） —— 切片 4 與受擊
   守衛一起收攏時統一修，因為它屬於「舊守衛彼此不一致」這類。
2. **`_compute_ai_input()` 內聯設定的 17 種按鍵仍是散落狀態**，等 Stage 4
   真正把 `InputManager` / `PlayerController` / `MoveSet._handle_input` 三條
   輸入路徑收攏到 `ActionMapper` 時一併結構化。本切片只是讓 AI 路徑**形狀**
   與人類路徑一致（`attack_type` 鍵存在且正確），沒碰背後的按鍵邏輯。

**Next slices**: hit reactions (Hitstun / Blockstun / Knockfly / Knockdown / Wakeup),
same method — move the guard into `FighterState`, prove equivalence by enumeration,
pin it per-frame with a `test_30`-style comparison. Only then do the flags actually
disappear.

### Stage 3 — Consolidate frame data ⏳

Make `docs/systems/FRAME_DATA_TABLE.md` generated rather than hand-maintained,
and fix the known-corrupt entries (DEN `spnk`, DAV `dpM`/`dpH` report 0-frame
animations). Decide whether WOO ships or is cut.

### Stage 4 — Converge input handling 🔄 (收攏 #1 已落地)

Collapse `InputManager` and `PlayerController` into a single `ActionMapper` with
one buffering policy, then add motion-input tests (QCF, DP, throw windows) and an
AI-symmetry test.

**收攏 #1（已落地, 2026-08-30）: AI 取消窗口恢復**
Stage 2 切片 2 披露的 finding #3 —— `check_cancel(input_data.attack_type, ...)`
對 CPU 永遠是 "none"（AI 的 `_neutral_input()` / `_compute_ai_input()` 完全
沒帶 `attack_type` 鍵），導致命中確認取消（hit-confirm cancel）對 AI 失效。
修法：把 `PlayerController.get_input_data()` 內聯的 17 行優先級鏈抽成
`static func resolve_attack_type(d)`，`Player.get_input()` 在 AI merge 之後
補上正確的 `attack_type` 與 `character_id`（65,536 種按鍵 × 角色組合與
舊鏈值等價，Python 暴力窮舉）。人類路徑也改用同一份 helper，行為一幀不變。
新增 `test_32` 釘住「AI 與人類兩條路徑的 input 字典都帶 `attack_type` 且值正確」。
**未動**: `InputManager` 與 `PlayerController` 的拆分、`MoveSet._handle_input`
的 150 行 if 鏈、方向指令宏的輸入合成 —— 等後續切片。

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

**CI is active.** [`.github/workflows/frame-tests.yml`](.github/workflows/frame-tests.yml)
runs on every push and pull request, in two jobs:

| Job | What it runs |
|---|---|
| `static-check` | `gdparse` over every `.gd`, plus `ci/check_signatures.py` — a parent/child override signature check that catches the class of hard compile error `gdparse` cannot see (see PR #20) |
| `frame-tests` | The full harness on real Godot 4.7.2 headless, in `barichello/godot-ci:4.7.2` |

This is what makes the agent-sandbox limitation below stop mattering: the
physics-frame assertions now get verified by the engine on every push, not by
hand.

**When writing new cases**, read [`tests/frame_tests/README.md`](tests/frame_tests/README.md) first.
The rules that bite hardest:

- `await` every coroutine helper — a missing `await` produces a silent false pass.
- Lambdas may only capture locals (`var me = p1`, then pass `me`).
- Measure in physics frames, never seconds. 1 logical frame = 2 physics frames.
- Leave generous wait windows around hits — hitstop slows physics-frame advance by 50×.

Frame tests currently cover 32 cases (`test_01`–`test_32`). Stage 1 contributed
the landing, PushManager stun-lock and conversion-boundary families (`test_21`
combo-window frame counting, `test_22` the three conversion boundaries including
the "families must not be swapped" guard, `test_23` AI decision/commitment tick
semantics, `test_24` the 36-tick double-tap window). Stage 2 adds:

- **`test_25`** — 600 frames of seeded random input (`seed=20260827`, so a
  failure is reproducible). Every frame it asserts the resolver is a pure
  function, returns a defined state, and that the structural invariants hold
  (dash/backdash mutually exclusive; `is_landing` always accompanied by lock
  frames; `is_wakeup_locked` always accompanied by a running `wakeup_timer`;
  since slice 2, `is_attacking` always accompanied by a legal `attack_type`).
  It also prints the observed state distribution and requires ≥4 distinct
  states — otherwise "standing still" would pass it trivially.
- **`test_26`** — frame-by-frame comparison of the state layer against the
  animation layer, so the two priority chains cannot silently drift.
- **`test_27`** / **`test_28`** — landing behavior regressions: cross-up facing
  must not flip until the landing animation finishes, and landing while holding
  an action must skip the landing lock entirely (zero stun).
- **`test_29`** (slice 2) — the attack state must be *paired*. Part 1 reproduces
  the removed legacy entry point's exact window: jump, land with no input, then
  put `st_mp` in the buffer on the very next physics frame (it is seeded
  directly into `InputBuffer` because a child node's `_physics_process` runs
  after its parent's, so a same-frame keypress would land one frame late and
  miss the window). It asserts no orphan attack appears and that the press still
  produces the attack — removing the second entry point must not eat input.
  Part 2 runs 600 frames of seeded random input (`seed=20260829`) asserting
  `check_invariants()` is clean every frame, and prints the attack distribution
  (≥3 distinct attacks required, so a green run cannot mean "never attacked").
- **`test_30`** (slice 2) — the consolidated attack gates must stay
  **value-identical** to the flag expressions they replaced. The legacy
  expressions are rewritten verbatim in the test as a control group and compared
  every frame against `FighterState.can_start_ground_attack()` /
  `can_start_air_attack()` / `is_throw_in_progress()`; it also requires the
  ground and air gates to be true at least once, so "both always false" cannot
  pass. The control group must *not* be refactored to call `FighterState` —
  that would make the test compare itself against itself.
- **`test_31`** (slice 3) — the consolidated movement gates (`can_walk` /
  `can_dash` / `can_jump`) must stay **value-identical** to the flag expressions
  they replaced. Same `test_30` pattern: 600 frames of seeded random input
  (`seed=20260831`), the legacy expressions are rewritten verbatim as a control
  group and compared every frame against `FighterState.can_walk` /
  `can_dash` / `can_jump`. The control group is exhaustive-verified in Python
  (262,144 combinations of 17 relevant flags × 2 jump_pressed values, 0
  mismatches) **and** pinned per-frame in-engine by `test_31`. All three
  predicates must be true at least once, so "all always false" cannot pass.
- **`test_32`** (Stage 4 parity fix) — the AI input path must now produce
  `attack_type` in the same shape as the human path (the key used to be
  missing for AI, breaking hit-confirm cancels on CPU fighters — the
  finding #3 disclosed in slice 2). The test sets `p1.is_ai_controlled = true`
  / `p2.is_ai_controlled = false`, runs 600 frames of random button presses
  on both, asserts every frame that (a) `p1.get_input().has("attack_type")` and
  `p2.get_input().has("attack_type")` are both true, and (b) the value of
  `attack_type` matches `PlayerController.resolve_attack_type(input_data)` for
  both paths. The same attack_type is observed on both paths ≥ 3 times, and
  the AI path's `attack_type` is non-`"none"` at least once — otherwise the
  test would silently pass on inputs that never trigger an attack.

### Not yet covered (honest disclosure)

- Motion-input macros (Stage 4)
- Full air-attack / throw / knockfly flows (Stages 2–4)
- Corner-pushing and other extreme coordinate cases (after Stage 3)
- The two disclosed state/animation divergences above are *documented and
  skipped*, not fixed — they are behavior changes, so they belong to a later
  Stage 2 slice

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

**What automated review can honestly claim in-sandbox**: `gdtoolkit`
`gdparse`/`gdlint`, `ci/check_signatures.py`, and exhaustive *logic simulations*
in Python — float64-identical conversion checks (Python doubles ≡ Godot floats,
used in PR #19 to prove every routed seed reproduces the old tick counts), and
in Stage 2 a brute-force of the state resolver against both animation chains
across 55k+ flag combinations, which is what surfaced the two divergences
disclosed above. **What only the engine can claim**: the physics-frame
assertions themselves.

Since the workflow was activated that gap is closed automatically — every push
runs the 30 cases on real Godot 4.7.2, so the sandbox's inability no longer
gates correctness.

---

## Project layout

```
scripts/core/        Player, Fighter, Movement, FighterState, World, PushManager, TimerManager
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
- **The state layer drives the attack subsystem only, so far.** Since slice 2 the
  attack gates ("can I start a ground/air attack", "is a throw in progress",
  "is this `attack_type` legal") live in `FighterState`, and the orphan-attack
  state is structurally impossible. Everything else still branches on flag
  combinations: movement and hit reactions wait for slices 3–4, so their illegal
  states remain *detectable* (and are detected by `test_25`) rather than
  *unrepresentable*.
- **Two state/animation divergences are known and unfixed** — `is_being_thrown`
  has no animation branch, and being airborne without `is_jumping` falls through
  to the walk animation. Documented in `FighterState.gd`, skipped-with-counting
  in `test_26`; fixing them changes behavior, so they wait for their own slice.
- **Some flag overlaps are still reachable** — e.g. `hitstun_frames` and
  `blockstun_frames` can both be non-zero (getting hit during blockstun).
  `FighterState.known_illegal_overlaps()` enumerates these as a Stage 2 to-do
  list rather than pretending they are already impossible.
- **`current_damage` is effectively write-only** — every read overwrites it in
  the same expression, so the field only looks like a source of truth. It goes
  away with Stage 3's frame-data consolidation.
- **Hit-confirm cancels** ✅ (fixed in Stage 4 收攏 #1) — `check_cancel()` reads
  `input_data.attack_type`, which `PlayerController` now shares with the AI path
  via `PlayerController.resolve_attack_type()` (see Stage 2 切片 3 / Stage 4 收攏 #1).
- **`get_input()` runs 3–4× per physics frame**, and for AI-controlled fighters
  each call re-queries `get_ai_input()`. Harmless for the buffered human path,
  unverified for the AI path. Stage 4.
- **WOO is incomplete** and its future is a Stage 3 decision.
- **Some frame data is wrong** — see the "known data issues" section of `FRAME_DATA_TABLE.md`.
