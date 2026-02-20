# Adding a New Special Move (Checklist)

This guide avoids the animation and timing pitfalls we hit with 100p.

## 1) Data Resources
- Create a SpecialMoveData resource under res://data/specials/.
- Set move_id and character_requirement.
- Set duration_frames (0 = follow animation length).
- If you want movement to end before the animation ends, set movement_duration_frames.
- For multi-hit moves, set is_multi_hit = true and fill hit_phases.

Example hit_phases entry:
- frame: 8
- damage: 5.0
- hitstun: 18
- blockstun: 12
- knockback: 50.0
- force_knockfly: true
- knockfly_gravity: 1900000.0
- knockfly_vertical_speed: -400.0
- knockfly_horizontal_speed: 6000.0

## 2) Input Sequence
- Add a SpecialInputSequence in res://data/specials/inputs/.
- Ensure buttons match InputManager ButtonInputs (e.g., ST_MK = 16).
- Add the resource path to InputManager.SPECIAL_INPUT_RESOURCES.

## 3) Move Registration
- Add the .tres to MoveSet.special_moves_data (preferred), or
- Add to MoveSet.LEGACY_SPECIAL_MOVE_RESOURCES (fallback).

## 4) Animation Setup (Critical)
- AnimationPlayer: add an animation with the exact move_id name.
- AnimationTree: add a state with the same name.
- Movement.gd: add move_id to animation_conditions list.
- AnimationManager.gd:
  - Add move_id to special move whitelist in compute_target_state().
  - Add move_id to attack_type whitelist in compute_target_state().

## 5) Multi-Hit Knockfly (Industry Standard)
- Only set force_knockfly in the last hit phase.
- Earlier hits should have force_knockfly = false or omit the field.
- This matches common fighting game behavior: launch only on the finisher.

## 6) Test Checklist
- Test both player_a and player_b (seat system).
- Verify animation plays (AnimationTree state changes).
- Verify movement ends at movement_duration_frames, not full animation length.
- Use FrameBar or logs to confirm timing.
