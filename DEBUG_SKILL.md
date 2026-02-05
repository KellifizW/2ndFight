---
name: godot-gdscript-debug-guard
description: Strict GDScript debugging guard for Godot 4.x. Use when debugging, fixing bugs, refactoring, or suggesting code changes. Always check for new errors before suggesting fixes. Prioritize static analysis, type safety, Godot node patterns, and IDE-visible issues.
---

# GDScript Debug Guard

**Activate for**: Debugging, bug fixes, refactoring, or any code change in Godot 4.x GDScript files.

## Core Principles

1. **Static analysis FIRST** - Check syntax, types, node paths, signals before runtime
2. **New errors are worse than old bugs** - Never introduce IDE-visible errors
3. **Minimal changes** - Keep existing patterns, avoid over-engineering
4. **Verification is mandatory** - Provide explicit check steps

## Workflow (Mandatory Order)

### 1. Observed Issue
- State the exact error/bug from user report or IDE
- What file/line? What symptom? (crash, wrong behavior, error message?)

### 2. Static Risk Analysis
**Before suggesting ANY fix**, list potential new errors:
- ❌ **Type mismatches**: Does change break type hints? (int → float, Node → Node2D, etc.)
- ❌ **@onready/@export misuse**: Are node references valid? (@onready requires _ready(), @export needs exported type)
- ❌ **Node path errors**: Does `$NodePath` or `get_node()` exist in scene tree?
- ❌ **Signal connection errors**: Does signal exist? Correct signature? Connected properly?
- ❌ **Deprecated Godot 4.x patterns**: Using Godot 3.x methods? (e.g., `get_node()` vs `%UniqueNode`)
- ❌ **Scope/access errors**: Accessing variables/methods from wrong context?
- ❌ **Null reference risks**: Can any variable be null? Add null checks?

### 3. Suggested Change
```gdscript
# Code change with inline comments
# Explain WHY each line is safe
```

**Why this fix is safe**:
- Preserves existing type contracts
- No new node dependencies
- Follows project conventions (refer to copilot-instructions.md if available)
- Minimal scope change

### 4. Verification Checklist
**Before running game**:
- [ ] **VS Code**: No red squiggles/LSP warnings in changed files
- [ ] **Godot Editor**: Open script → Check for hard error indicators (top-right error icon)
- [ ] **Scene validation**: If node paths changed, open scene and verify node still exists
- [ ] **Type check**: Hover over changed variables in VS Code → confirm types match

**Multi-file changes**:
- List all affected files explicitly
- Provide per-file verification steps

**After running**:
- [ ] Test original bug scenario
- [ ] Test edge cases (null, empty, boundary values)
- [ ] Check console for new errors/warnings

## Red Flags (Stop and Reconsider)

- Changing type hints without verifying ALL usages
- Adding node dependencies without scene verification
- Refactoring beyond the immediate bug
- Using dynamic typing (`Variant`, no hints) without justification
- Assuming "it should work" without verification path

## Type Safety Rules

```gdscript
# GOOD: Explicit, safe
var player: Player = get_node("Player") as Player
if player:
    player.take_damage(10)

# BAD: Assumes node exists, no null check
var player = $Player
player.take_damage(10)  # Crash if Player missing

# GOOD: Type-safe signal
signal health_changed(old_value: int, new_value: int)

# BAD: Untyped signal
signal health_changed
```

## Common Godot 4.x Pitfalls

1. **Node access**: Use `%UniqueNode` for unique nodes (more robust than `$NodePath`)
2. **@onready timing**: Runs before `_ready()` - don't use for complex initialization
3. **Type inference**: `var x := 5` (infers int) vs `var x = 5` (Variant)
4. **Signal binding**: `signal_name.connect(_on_signal)` not `connect("signal_name", ...)`
5. **Fixed-point math**: In this project, use `Vector2i` and `SIMULATION_SCALE = 1000`

## Example Output Format

---

### 1. Observed Issue
`Player.gd:42` - `hitstun_timer` undefined (can't be found in object)

### 2. Static Risk Analysis
- ❌ **Undefined variable**: `hitstun_timer` never declared in Player or parent classes
- ❌ **Potential typo**: Likely meant `hitstun_frames` (Fighter.gd has this)
- ✅ **Safe if**: Change to `hitstun_frames` and verify it's a frame counter (int), not Timer node

### 3. Suggested Change
```gdscript
# Fighter.gd:89 (existing code - no change needed)
var hitstun_frames: int = 0

# Player.gd:42 (CHANGE)
if hitstun_frames > 0:  # Was: hitstun_timer
    hitstun_frames -= 1
```

**Why safe**: `hitstun_frames` is declared in Fighter.gd (parent class), Player inherits it. Type matches (int), used in frame-decrement pattern per project conventions.

### 4. Verification Checklist
- [ ] VS Code: No red squiggle on `hitstun_frames` in Player.gd
- [ ] Godot: Open Player.gd → top-right shows no errors
- [ ] Test: Hit player → verify hitstun decrements correctly
- [ ] Console: No "Invalid get index" errors

---

**Activate this skill for every debugging/refactoring task. Verification is non-negotiable.**
