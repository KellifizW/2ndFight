# Documentation Index

Complete navigation guide for 2ndFight fighting game documentation.

---

## 🟢 Core Architecture (Essential References)

Read these first to understand core systems:

- [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md) — Handler architecture overview (Movement → 11 handlers)
- [MOVESET_REFACTORING_SUMMARY.md](MOVESET_REFACTORING_SUMMARY.md) — Data-driven move system (MoveData class, attack tables)
- [INPUT_BUFFER_IMPLEMENTATION.md](INPUT_BUFFER_IMPLEMENTATION.md) — 18-frame input buffer, motion input detection
- [FRAME_SYSTEM_SUMMARY.md](FRAME_SYSTEM_SUMMARY.md) — Frame conversion system, SIMULATION_SCALE, fixed-point math
- [AI_SYSTEM_README.md](AI_SYSTEM_README.md) — AI architecture, 5-layer decision system

---

## 📚 GUIDES/ (How to Add/Modify Features)

Operational manuals for implementing features:

- [GUIDES/ATTACK_MOVEMENT.md](GUIDES/ATTACK_MOVEMENT.md) — How to add attack displacement (lunges, forward steps)
- [GUIDES/COMBO_CANCEL.md](GUIDES/COMBO_CANCEL.md) — How to configure combo cancellation windows
- [GUIDES/FIREBALL_TUNING.md](GUIDES/FIREBALL_TUNING.md) — How to tune projectile parameters
- [GUIDES/FRAME_QUICKSTART.md](GUIDES/FRAME_QUICKSTART.md) — 5-minute introduction to frame system
- [GUIDES/HITBOX_SYSTEM.md](GUIDES/HITBOX_SYSTEM.md) — How hitboxes work and configuration

---

## ⚙️ SYSTEMS/ (Completed Feature Documentation)

Detailed documentation of major systems:

- [SYSTEMS/KNOCKBACK.md](SYSTEMS/KNOCKBACK.md) — Knockback physics, velocity decay, hitstun sync
- [SYSTEMS/KNOCKFLY.md](SYSTEMS/KNOCKFLY.md) — Knockfly state machine, layground/wakeup animations
- [SYSTEMS/FRAME_ADVANTAGE.md](SYSTEMS/FRAME_ADVANTAGE.md) — Frame advantage calculation and UI display
- [SYSTEMS/FRAMEBAR_DISPLAY.md](SYSTEMS/FRAMEBAR_DISPLAY.md) — FrameBar UI component, duration display
- [SYSTEMS/DP_FIXES.md](SYSTEMS/DP_FIXES.md) — DP jump height, gravity parameters, mechanics
- [SYSTEMS/GRAVITY.md](SYSTEMS/GRAVITY.md) — Unified gravity system, knockfly vs normal fall gravity
- [SYSTEMS/HITSTOP.md](SYSTEMS/HITSTOP.md) — Hit stop/delay timing, freeze frame implementation
- [SYSTEMS/ADVANTAGE_FIX_LEGACY.md](SYSTEMS/ADVANTAGE_FIX_LEGACY.md) — Legacy frame advantage fix details (reference)
- [SYSTEMS/POWERKK_FIX.md](SYSTEMS/POWERKK_FIX.md) — PowerKK special move fix documentation (reference)

---

## 🤖 AI System Documentation

AI behavior, decision making, and optimization:

- [AI_SYSTEM_README.md](AI_SYSTEM_README.md) — Main AI architecture (bilingual: English/中文)
- [AI_FIREBALL_FIX_SUMMARY.md](AI_FIREBALL_FIX_SUMMARY.md) — Fireball spam prevention, decision system
- [AI_ATTACK_DIVERSITY_FIX.md](AI_ATTACK_DIVERSITY_FIX.md) — Balanced attack type selection (light/medium/heavy)
- [AI_HEAVY_ATTACK_FIX.md](AI_HEAVY_ATTACK_FIX.md) — Heavy attack integration into decision layers
- [AI_ACTION_COMMITMENT_SUMMARY.md](AI_ACTION_COMMITMENT_SUMMARY.md) — Action commitment system prevents spam
- [AI_MOVE_RESTRICTION_FIX_SUMMARY.md](AI_MOVE_RESTRICTION_FIX_SUMMARY.md) — Character-specific move restrictions
- [AI_PERFORMANCE_OPTIMIZATION.md](AI_PERFORMANCE_OPTIMIZATION.md) — Performance tuning and optimization

### AI Subdirectory
- [ai/README.md](ai/README.md) — AI folder index
- [ai/MOVE_RESTRICTIONS_GUIDE.md](ai/MOVE_RESTRICTIONS_GUIDE.md) — Move restriction configuration

---

## 🔧 DEBUGGING/ (Tools & Analysis)

Debugging utilities and analysis documents:

- [DEBUGGING/TOOLS_INDEX.md](DEBUGGING/TOOLS_INDEX.md) — Quick reference to all debugging tools
- [DEBUGGING/GAMESPEED_DIAGNOSTICS.md](DEBUGGING/GAMESPEED_DIAGNOSTICS.md) — Game speed monitoring and diagnostics
- [DEBUGGING/HITSTUN_ANALYSIS.md](DEBUGGING/HITSTUN_ANALYSIS.md) — Frame-based hitstun calculations
- [DEBUGGING/LANDING_LESSONS.md](DEBUGGING/LANDING_LESSONS.md) — Landing state debugging lessons learned
- [DEBUGGING/PROFILER_SETUP.md](DEBUGGING/PROFILER_SETUP.md) — How to set up and use profiler
- [DEBUGGING/RESOURCE_PRELOADING.md](DEBUGGING/RESOURCE_PRELOADING.md) — Resource preloading optimization
- [DEBUGGING/LOG_OPTIMIZATION.md](DEBUGGING/LOG_OPTIMIZATION.md) — Logging system optimization
- [DEBUGGING/HITBOX_TESTING.md](DEBUGGING/HITBOX_TESTING.md) — Hitbox testing methodology

---

## 📱 UI Documentation

User interface components and setup:

- [ui/ICON_QUICK_START.md](ui/ICON_QUICK_START.md) — Icon-based input history display setup
- [ui/INPUT_HISTORY_GUIDE.md](ui/INPUT_HISTORY_GUIDE.md) — Input history visualization system
- [ui/README.md](ui/README.md) — UI folder index

---

## 🛠️ Other System References

- [PHASE3_ASSESSMENT_REPORT.md](PHASE3_ASSESSMENT_REPORT.md) — Active decision tree for Phase 3 work
- [LANDING_SYSTEM_VERIFICATION.md](LANDING_SYSTEM_VERIFICATION.md) — Landing state system verification

---

## 📂 External Resources

- [ai_specs/](ai_specs/) — AI specification files for Copilot
- [addons/](addons/) — Third-party Godot extensions

---

## 📖 Quick Navigation by Task

### I want to... add a new normal attack
→ Read [GUIDES/ATTACK_MOVEMENT.md](GUIDES/ATTACK_MOVEMENT.md) and [GUIDES/HITBOX_SYSTEM.md](GUIDES/HITBOX_SYSTEM.md)

### I want to... add a new special move
→ Read [MOVESET_REFACTORING_SUMMARY.md](MOVESET_REFACTORING_SUMMARY.md) and [INPUT_BUFFER_IMPLEMENTATION.md](INPUT_BUFFER_IMPLEMENTATION.md)

### I want to... understand/debug frame advantage
→ Read [SYSTEMS/FRAME_ADVANTAGE.md](SYSTEMS/FRAME_ADVANTAGE.md)

### I want to... fix AI behavior
→ Read [AI_SYSTEM_README.md](AI_SYSTEM_README.md) and AI-specific docs

### I want to... debug physics/movement
→ Read [FRAME_SYSTEM_SUMMARY.md](FRAME_SYSTEM_SUMMARY.md) and [SYSTEMS/GRAVITY.md](SYSTEMS/GRAVITY.md)

### I want to... debug UI display issues
→ Read [SYSTEMS/FRAMEBAR_DISPLAY.md](SYSTEMS/FRAMEBAR_DISPLAY.md) and [ui/ICON_QUICK_START.md](ui/ICON_QUICK_START.md)

### I want to... optimize performance
→ Read [DEBUGGING/PROFILER_SETUP.md](DEBUGGING/PROFILER_SETUP.md) and [AI_PERFORMANCE_OPTIMIZATION.md](AI_PERFORMANCE_OPTIMIZATION.md)

---

## 📊 Documentation Statistics

**Total Files**: ~55 markdown files (down from 102)
**Reduction**: 46% fewer files via consolidation

**Organized into**:
- 1 root DOCUMENTATION_INDEX.md
- 5 core reference files at root
- 5 AI-related files at root
- 7 system guides in `/GUIDES/`
- 7 completed systems in `/SYSTEMS/`
- 8 debugging tools in `/DEBUGGING/`
- 3 UI docs in `/ui/`
- 2 AI reference docs in `/ai/`

---

**Last Updated**: February 8, 2026
