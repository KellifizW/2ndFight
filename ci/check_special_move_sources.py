#!/usr/bin/env python3
"""Check the runtime source selected for every scene-configured special move.

Stage 3 is deliberately migrating one source at a time.  The move-set scripts
still provide fallback paths for backwards compatibility, but an Inspector
value wins whenever the scene assigns ``smd_*``.  This check makes that rule
visible in CI and prevents an externalized move from accidentally pointing at
a different resource than its fallback.

This is a routing check, not a second frame-data database: it does not copy
combat numbers into Python.  The frame harness remains the authority for
behavioral equivalence.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SCENE_SPECS = {
    "characters/DAV.tscn": "scripts/combat/movesets/DAVMoveSet.gd",
    "characters/DEN.tscn": "scripts/combat/movesets/DENMoveSet.gd",
    "characters/WOO.tscn": "scripts/combat/movesets/WOOMoveSet.gd",
}

# Once a slice moves a resource out of a scene, keep that routing decision
# explicit.  Add entries here as later Stage 3 slices are completed.
REQUIRED_EXTERNAL_SOURCES = {
    ("characters/DEN.tscn", "smd_fireball"): "res://data/specials/den_fireball.tres",
}

EXT_RESOURCE_RE = re.compile(
    r'^\[ext_resource\b.*?\bpath="([^"]+)"\s+id="([^"]+)"\]$'
)
SUB_RESOURCE_RE = re.compile(r'^\[sub_resource\b.*?\bid="([^"]+)"\]$')
LOAD_SMD_RE = re.compile(
    r'_load_smd\(\s*(smd_[A-Za-z0-9_]+)\s*,\s*"([^"]+)"\s*\)'
)
# DAV keeps variant fallbacks in ``for entry in [[smd_dpL, "..."]]`` arrays.
# Capture those pairs too; they are the same runtime _load_smd contract.
PAIR_RE = re.compile(r'\[\s*(smd_[A-Za-z0-9_]+)\s*,\s*"([^"]+)"\s*\]')
ASSIGNMENT_RE = re.compile(
    r'^(smd_[A-Za-z0-9_]+)\s*=\s*(SubResource|ExtResource)\("([^"]+)"\)$'
)
SCRIPT_RE = re.compile(r'^script\s*=\s*ExtResource\("([^"]+)"\)$')


def parse_ext_resources(lines: list[str]) -> dict[str, str]:
    resources: dict[str, str] = {}
    for line in lines:
        match = EXT_RESOURCE_RE.match(line)
        if match:
            path, resource_id = match.groups()
            resources[resource_id] = path
    return resources


def parse_subresource_scripts(lines: list[str]) -> dict[str, str]:
    scripts: dict[str, str] = {}
    current_id: str | None = None
    for line in lines:
        match = SUB_RESOURCE_RE.match(line)
        if match:
            current_id = match.group(1)
            continue
        if line.startswith("["):
            current_id = None
            continue
        if current_id is not None:
            match = SCRIPT_RE.match(line)
            if match:
                scripts[current_id] = match.group(1)
    return scripts


def parse_moveset_assignments(lines: list[str]) -> dict[str, tuple[str, str]]:
    assignments: dict[str, tuple[str, str]] = {}
    in_moveset = False
    for line in lines:
        if line.startswith('[node name="MoveSet"'):
            in_moveset = True
            continue
        if line.startswith("[node "):
            in_moveset = False
        if not in_moveset:
            continue
        match = ASSIGNMENT_RE.match(line)
        if match:
            export_name, ref_kind, ref_id = match.groups()
            assignments[export_name] = (ref_kind, ref_id)
    return assignments


def parse_loads(script_path: Path) -> dict[str, str]:
    text = script_path.read_text(encoding="utf-8")
    loads: dict[str, str] = {}
    for pattern in (LOAD_SMD_RE, PAIR_RE):
        for match in pattern.finditer(text):
            export_name, fallback = match.groups()
            loads[export_name] = fallback
    return loads


def check_scene(scene_rel: str, script_rel: str) -> tuple[list[str], int]:
    errors: list[str] = []
    scene_path = ROOT / scene_rel
    script_path = ROOT / script_rel
    lines = scene_path.read_text(encoding="utf-8").splitlines()
    ext_resources = parse_ext_resources(lines)
    subresource_scripts = parse_subresource_scripts(lines)
    assignments = parse_moveset_assignments(lines)
    loads = parse_loads(script_path)
    embedded_count = 0

    if not loads:
        errors.append(f"{script_rel}: no _load_smd calls found")
        return errors, embedded_count

    for export_name, fallback in loads.items():
        fallback_path = ROOT / fallback.removeprefix("res://")
        if not fallback_path.is_file():
            errors.append(f"{scene_rel}: {export_name} fallback does not exist: {fallback}")
            continue

        assignment = assignments.get(export_name)
        if assignment is None:
            source = f"fallback {fallback}"
        else:
            ref_kind, ref_id = assignment
            if ref_id not in ext_resources and ref_kind == "ExtResource":
                errors.append(f"{scene_rel}: {export_name} uses unknown ExtResource {ref_id}")
                continue
            if ref_kind == "ExtResource":
                source_path = ext_resources[ref_id]
                if source_path != fallback:
                    errors.append(
                        f"{scene_rel}: {export_name} external source {source_path} "
                        f"does not match fallback {fallback}"
                    )
                    continue
                source = f"external {source_path}"
            else:
                script_id = subresource_scripts.get(ref_id)
                if script_id is None or ext_resources.get(script_id) != "res://data/SpecialMoveData.gd":
                    errors.append(
                        f"{scene_rel}: {export_name} SubResource {ref_id} is not SpecialMoveData"
                    )
                    continue
                embedded_count += 1
                source = f"embedded SubResource {ref_id}"

        required = REQUIRED_EXTERNAL_SOURCES.get((scene_rel, export_name))
        if required is not None and source != f"external {required}":
            errors.append(
                f"{scene_rel}: {export_name} must use external {required}; selected {source}"
            )
        print(f"  {scene_rel}: {export_name} -> {source}")

    return errors, embedded_count


def main() -> int:
    errors: list[str] = []
    embedded_count = 0
    print("Special-move source routing:")
    for scene_rel, script_rel in SCENE_SPECS.items():
        scene_errors, scene_embedded_count = check_scene(scene_rel, script_rel)
        errors.extend(scene_errors)
        embedded_count += scene_embedded_count

    if errors:
        print("\nERRORS:")
        for error in errors:
            print(f"  - {error}")
        return 1

    print(
        "\nOK: source routing is valid "
        f"({embedded_count} embedded SpecialMoveData source(s) remain for later Stage 3 slices)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
