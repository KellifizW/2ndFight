---
mode: agent
description: Modify or debug AI decision behavior (5-layer decision system)
---

# AI Behavior Modification

The AI uses a 5-layer decision system. Changes must be verified by watching CPU for 60+ seconds.

## Decision Layer Priority (High → Low)
1. **Survival** — escape dangerous situations (low health, corner trap)
2. **Punish** — counter-attack on whiff/disadvantage
3. **Tactical** — combo extensions, mix-ups
4. **Positioning** — zone control, ideal distance
5. **Idle** — base poke / neutral game

## What I Want to Change
Describe the behavior:
- Current: [e.g., "AI spams st_hp repeatedly"]
- Target: [e.g., "AI mixes light/medium/heavy attacks and occasionally fireballs"]

## Key Files to Read First
- `ai/ai_behavior.gd` — action commitment system
- `ai/AIDecisionLayers.gd` — the 5-layer decision logic
- `ai/ThreatAssessment.gd` — incoming threat detection
- `ai/AIComboSystem.gd` — pre-defined combo chains
- `ai/SpaceControl.gd` — zone/distance preferences
- `ai/MOVE_RESTRICTIONS_GUIDE.md` — per-character move restrictions

## Implementation Rules
- Change ONE decision layer at a time — test before touching the next
- Action commitment system prevents spam — do NOT remove it
- Move restrictions enforce character identity — do NOT remove them
- Use `MOVE_RESTRICTIONS_GUIDE.md` before adding new moves to AI repertoire

## Verification Protocol
1. Toggle AI on: **C** key (Player A) or **V** key (Player B)
2. Observe for **60+ seconds minimum**
3. Check move variety (no single move > 40% of actions)
4. Verify all 5 decision layers activate (no stuck layer)
5. Confirm character restrictions respected (Dav ≠ Den moveset)
6. Disable AI and verify human control still works correctly

## Output Format
Report: move counts observed, decision layer activations, any spam behavior remaining.
