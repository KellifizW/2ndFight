# Debugging Tools & Analysis Index

Quick reference guide for debugging and analysis tools available in the project.

---

## 🔍 System Analysis Tools

### Frame & Timing Analysis
- **[DEBUGGING/HITSTUN_ANALYSIS.md](../DEBUGGING/HITSTUN_ANALYSIS.md)** — Analyze hitstun durations, frame calculations, verify frame system conversions
- **[DEBUGGING/LANDING_LESSONS.md](../DEBUGGING/LANDING_LESSONS.md)** — Landing state debugging patterns and lessons learned from past issues

### Performance & Speed
- **[DEBUGGING/GAMESPEED_DIAGNOSTICS.md](../DEBUGGING/GAMESPEED_DIAGNOSTICS.md)** — Monitor game speed, check frame rates, diagnose timing issues
- **[DEBUGGING/PROFILER_SETUP.md](../DEBUGGING/PROFILER_SETUP.md)** — Set up Godot profiler, measure CPU/memory usage, identify bottlenecks
- **[DEBUGGING/LOG_OPTIMIZATION.md](../DEBUGGING/LOG_OPTIMIZATION.md)** — Optimize logging system, reduce console spam, improve debug output clarity

### Resource Management
- **[DEBUGGING/RESOURCE_PRELOADING.md](../DEBUGGING/RESOURCE_PRELOADING.md)** — Resource preloading optimization, asset caching, load time improvement

---

## 🎮 Gameplay Testing Tools

### Collision & Hitbox Testing
- **[DEBUGGING/HITBOX_TESTING.md](../DEBUGGING/HITBOX_TESTING.md)** — Hitbox testing methodology, visual debugging, collision verification

---

## 📊 Debugging Checklist by Problem Type

### "Game runs slow"
1. Launch profiler ([DEBUGGING/PROFILER_SETUP.md](../DEBUGGING/PROFILER_SETUP.md))
2. Check AI performance ([AI_PERFORMANCE_OPTIMIZATION.md](../AI_PERFORMANCE_OPTIMIZATION.md))
3. Review logging overhead ([DEBUGGING/LOG_OPTIMIZATION.md](../DEBUGGING/LOG_OPTIMIZATION.md))
4. Check resource preloading ([DEBUGGING/RESOURCE_PRELOADING.md](../DEBUGGING/RESOURCE_PRELOADING.md))

### "Frame advantage shows wrong number"
→ [SYSTEMS/FRAME_ADVANTAGE.md](../SYSTEMS/FRAME_ADVANTAGE.md) + [DEBUGGING/HITSTUN_ANALYSIS.md](../DEBUGGING/HITSTUN_ANALYSIS.md)

### "Hitstun/blockstun timing is off"
→ [FRAME_SYSTEM_SUMMARY.md](../FRAME_SYSTEM_SUMMARY.md) + [DEBUGGING/HITSTUN_ANALYSIS.md](../DEBUGGING/HITSTUN_ANALYSIS.md)

### "Landing state issues"
→ [DEBUGGING/LANDING_LESSONS.md](../DEBUGGING/LANDING_LESSONS.md) + [LANDING_SYSTEM_VERIFICATION.md](../LANDING_SYSTEM_VERIFICATION.md)

### "Hitbox not detecting collision"
→ [DEBUGGING/HITBOX_TESTING.md](../DEBUGGING/HITBOX_TESTING.md)

### "Game speed/FPS inconsistent"
→ [DEBUGGING/GAMESPEED_DIAGNOSTICS.md](../DEBUGGING/GAMESPEED_DIAGNOSTICS.md)

---

## 🛠️ Development Tools & Utilities

### Built-in VS Code/Debug Tools
- InputBufferDebug.gd — Enable on Label node to visualize input buffer
- FrameBar.tscn — Visual frame advantage display
- InputHistoryDisplayIcon.gd — Icon-based input history visualization

### Recommended Extensions
- Godot Tools (syntax highlighting, debugging)
- GDScript Toolkit (linting, formatting)

---

## 📋 Analysis Document Details

| Document | Size | Focus | Best For |
|----------|------|-------|----------|
| HITSTUN_ANALYSIS | Medium | Frame calculations | Understanding frame system |
| GAMESPEED_DIAGNOSTICS | Medium | Performance metrics | Identifying slowdowns |
| LANDING_LESSONS | Medium | Debugging patterns | Landing state troubleshooting |
| PROFILER_SETUP | Small | Tool configuration | Setting up profiler |
| HITBOX_TESTING | Small | Testing methodology | Collision debugging |
| RESOURCE_PRELOADING | Small | Asset optimization | Memory/load optimization |
| LOG_OPTIMIZATION | Small | Logging tuning | Reducing console spam |

---

## ⚡ Common Debug Commands (PowerShell)

```powershell
# Kill all Godot instances
Stop-Process -Name "Godot*" -Force

# Launch Godot with project
& "C:\Users\t-way\Desktop\Godot.exe" --path "c:\Users\t-way\Documents\2ndFight\2ndfight\2ndFight"

# Check for common issues in logs
# (Redirect Godot output to file)
& "C:\Users\t-way\Desktop\Godot.exe" --path "C:\path\to\project" 2>&1 | Tee-Object debug.log
```

---

## 🎯 Quick Problem Solver

**Symptom** → **Solution**

| Symptom | Primary Doc | Secondary Doc |
|---------|-------------|---------------|
| Wrong frame count displayed | SYSTEMS/FRAME_ADVANTAGE.md | HITSTUN_ANALYSIS.md |
| Knockback too short/long | SYSTEMS/KNOCKBACK.md | FRAME_SYSTEM_SUMMARY.md |
| Gravity feels wrong | SYSTEMS/GRAVITY.md | DP_FIXES.md |
| Knockfly animation skips | SYSTEMS/KNOCKFLY.md | LANDING_LESSONS.md |
| FrameBar shows 15F instead of 14F | SYSTEMS/FRAMEBAR_DISPLAY.md | HITSTUN_ANALYSIS.md |
| Game runs at 30 FPS instead of 60 | GAMESPEED_DIAGNOSTICS.md | PROFILER_SETUP.md |
| Input buffer not working | INPUT_BUFFER_IMPLEMENTATION.md | AI system docs |
| Hitbox not colliding | HITBOX_TESTING.md | GUIDES/HITBOX_SYSTEM.md |

---

## 📖 Related Core Systems

For understanding underlying systems before debugging:

- [FRAME_SYSTEM_SUMMARY.md](../FRAME_SYSTEM_SUMMARY.md) — Fixed-point math, SIMULATION_SCALE
- [INPUT_BUFFER_IMPLEMENTATION.md](../INPUT_BUFFER_IMPLEMENTATION.md) — Input buffer internals
- [SYSTEMS/KNOCKBACK.md](../SYSTEMS/KNOCKBACK.md) — Knockback physics
- [SYSTEMS/GRAVITY.md](../SYSTEMS/GRAVITY.md) — Gravity system unified
- [SYSTEMS/HITSTOP.md](../SYSTEMS/HITSTOP.md) — Hit stop timing

---

**Last Updated**: February 8, 2026
