# AI Fireball Behavior Fix - Summary

## Problem Statement
1. **AI only throws fireballs repetitively** - Characters spam fireballs without variety
2. **No fireballs instantiated for AI** - AI fireballs don't appear on screen
3. **Human fireballs work fine** - Player-controlled fireballs spawn correctly

## Root Causes Identified

### 1. AI Decision Spam (FIXED)
**Problem:** At distance > 250 pixels, AI returned "fireball" decision every single frame without checking if a fireball was already being executed.

**Solution:**
```gdscript
// Before: Always returned fireball at long range
if distance > 250:
    decisions.append(fireball_decision)

// After: Check if already doing special move
if distance > 250:
    var is_busy = ai_player.move_set and ai_player.move_set.is_spmove
    if not is_busy:
        decisions.append(fireball_decision)
```

### 2. Lack of Behavioral Variety (IMPROVED)
**Problem:** AI had no alternative behaviors at long range, only fireballs.

**Solution:** Added multiple decision options at each range with competitive priorities:
- **Long Range (>250):** Fireball (60/50 priority), Walk (52), Jump (48)
- **Mid Range (100-250):** Poke (65/58), Dash (60), Block (55)
- **Close Range (<100):** Combo (70), Attack (60), Backdash (55)

Priorities are randomized to create natural variation.

### 3. HDK Input Bug (FIXED)
**Problem:** DEN's HDK special move incorrectly used `spm2_pressed` (same as fireball) instead of `spm3_pressed`.

**Solution:**
```gdscript
// ai_behavior.gd - _action_to_input()
"hdk":
    input.spm3_pressed = true  // Was: spm2_pressed
```

## Implementation Details

### How Fireballs Actually Spawn

The fireball spawning flow is identical for both AI and human players:

1. **Decision/Input:** AI or PlayerController sets `spm2_pressed = true` in input dictionary
2. **Player Processing:** `player.get_input()` returns the input dictionary
3. **MoveSet Check:** `MoveSet.process_move()` checks `is_valid_ground_state`
4. **Input Handler:** `_handle_input()` detects `spm2_pressed` and calls `start_fireball()`
5. **Move Start:** `_start_special("fireball")` sets `is_spmove = true`, `spawn_timer = 0.2667`
6. **Animation:** Fireball animation plays
7. **Spawn Delay:** Each frame, `_process_projectile_spawn()` decrements spawn_timer
8. **Instantiation:** When timer expires, loads `res://[CHARACTER]_fireball.tscn` and spawns it

### Why AI Fireballs Might Not Spawn

With our fixes, fireballs SHOULD spawn. If they still don't, the debug logs will show exactly where it fails:

**Possible failure points (now logged):**
- AI doesn't make fireball decision → Check `[AI] decision: fireball`
- Input not set correctly → Check `[AI._action_to_input] Setting spm2_pressed=true`
- Invalid ground state → Check `[MoveSet.process_move] is_valid_state=false`
- Already attacking → Check `[MoveSet] Cannot start fireball - is_attacking=...`
- Scene loading fails → Check `Cannot load fireball scene: ...`
- Spawn timer issue → Check `[MoveSet._process_projectile_spawn] attempting to spawn`

## Testing Instructions

### Enable AI Mode
1. Run the game (`world.tscn` or through main menu)
2. Press **'C'** key to toggle AI for Player A (left side, typically Davis)
3. Press **'V'** key to toggle AI for Player B (right side, typically Dennis)
4. Console will show: `"Debug: Player A AI 啟用！（角色：DAV）"`

### What to Observe

**Expected Behavior:**
- AI moves around using walk, dash, jump
- AI throws fireballs occasionally (not constantly)
- Fireballs appear on screen and travel toward opponent
- AI uses other attacks at close/mid range
- Console shows varied decisions: "walk_forward", "fireball", "st_mk", etc.

**Console Logs (Sample):**
```
[AI] PlayerA decision: walk_forward (priority: 52.0) - Far range positioning
[AI] PlayerA decision: fireball (priority: 60.0) - Far range zoning
[AI._action_to_input] PlayerA: Setting spm2_pressed=true for action 'fireball'
[MoveSet._handle_input] PlayerA spm2_pressed detected (AI=true)
[MoveSet] PlayerA: Starting fireball (AI=true)
[MoveSet] Started fireball! Character: DAV, Duration: 0.300
[MoveSet._process_projectile_spawn] PlayerA attempting to spawn fireball
[MoveSet] PlayerA spawned fireball: res://DAV_fireball.tscn at position (X, Y)
Debug: Fireball initialized, owner_character_id: DAV, speed: 800, damage: 15, direction: 1
```

## Files Modified

### ai_behavior.gd
- Fixed HDK input mapping (`spm3_pressed` instead of `spm2_pressed`)
- Added `spm3_pressed` to neutral input dictionary
- Improved decision logging (periodic + special moves)
- Added debug log when `spm2_pressed` is set

### AIDecisionLayers.gd
- Added `is_spmove` check before adding fireball decision
- Randomized fireball priority (60% high, 40% medium)
- Added walk behaviors at long range
- Added jump behaviors at long range
- Added blocking at mid range
- Improved priority competition at all ranges
- Added backdash at close range

### MoveSet.gd
- Added state logging to `start_fireball()`
- Added detection logging to `_handle_input()`
- Added spawn attempt logging to `_process_projectile_spawn()`
- Added invalid state logging to `process_move()`

## Known Limitations

1. **No AI vs AI Fireball Collision:** If both AIs throw fireballs simultaneously, they may pass through each other (this is a fireball collision issue, not an AI issue)

2. **Priority Tuning:** The decision priorities are initial values. You may want to adjust them based on play-testing:
   - Increase fireball priority if AI is too passive
   - Decrease if AI still spams too much
   - Adjust walk/jump priorities for movement variety

3. **Character-Specific Moves:** AI uses generic moves for all characters. Character-specific special moves (powerkk for DAV, spnk for DEN) are selected based on distance but could be smarter.

## Future Improvements (Optional)

- Add cooldown timer for fireballs (prevent spam even if priority wins)
- Add reaction to opponent's fireballs (jump over, block, or counter-fireball)
- Improve punish detection for better combos
- Add difficulty scaling (easier AI = lower priorities for optimal moves)
- Character-specific AI personalities (aggressive, defensive, zoner)

## Quick Reference: Key Bindings

| Action | Key | Purpose |
|--------|-----|---------|
| Toggle P1 AI | **C** | Enable/disable AI for Player A (left) |
| Toggle P2 AI | **V** | Enable/disable AI for Player B (right) |
| P1 Fireball | **O** | Quarter-circle forward + O (human control) |
| P2 Fireball | **8** (numpad) | Quarter-circle forward + 8 (human control) |
| Reset | **R** | Reset match positions |
| Slow-mo | **M** | Toggle slow motion |

## Troubleshooting

**Q: AI still only throws fireballs**
A: Check console logs. If you see "fireball" decision every other line, the `is_spmove` check might not be working. Verify `move_set` exists on the AI player.

**Q: No fireballs spawn at all for AI**
A: Check for errors in console. Look for the exact failure point using the log messages. Common causes:
- Character scene missing `MoveSet` child node
- Fireball animation not found
- Scene file path incorrect (`res://DAV_fireball.tscn` or `res://DEN_fireball.tscn`)

**Q: Human fireballs work but AI fireballs don't**
A: This suggests the MoveSet code is fine but AI input isn't reaching it. Check:
- Is AI actually enabled? (Look for "AI 啟用" message)
- Is `spm2_pressed` being set? (Look for "_action_to_input" log)
- Is `_handle_input` detecting it? (Look for "spm2_pressed detected" log)

**Q: Too much console spam**
A: The debug logs are verbose by design. Once you confirm everything works, you can:
1. Remove the print statements from `ai_behavior.gd` and `MoveSet.gd`
2. Or comment out specific ones you don't need
3. Keep the error messages (`push_error`, `push_warning`)

## Success Criteria

✅ **AI makes varied decisions** - Not just fireballs, but walks, jumps, attacks
✅ **Fireballs spawn for AI** - Visual confirmation on screen
✅ **Console logs show complete flow** - From decision to spawn
✅ **No spamming** - Fireballs appear occasionally, not constantly
✅ **Both characters work** - DAV and DEN can both throw AI fireballs

---

*If you still experience issues after applying these fixes, please share the console log output for analysis.*
