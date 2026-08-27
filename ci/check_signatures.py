#!/usr/bin/env python3
"""Scan GDScript class hierarchies for parent/child method signature mismatches.

Mimics Godot 4's "The function signature doesn't match the parent" check:
an override must keep the same parameter count, the same parameter types,
a compatible return type, and the same static-ness.

This catches what `gdparse` cannot: gdtoolkit only validates syntax, while a
signature mismatch (e.g. `int` param where the parent declares `float`, or a
non-`static` override of a `static` func) is a hard compile error in the real
Godot editor/runtime that breaks the whole game (see PR fixing fighter.gd:52).

Exit code: 0 = clean, 1 = mismatches found.
"""
import re
import sys
from pathlib import Path
from collections import defaultdict

ROOT = Path(".").resolve()
EXCLUDE = ("/.git/", "/backup", "/godot_state_charts_examples/")

def norm_sig(param_types, ret, is_static):
    return (tuple(param_types), ret, is_static)

def parse_type(tok: str) -> str:
    tok = tok.strip()
    if not tok:
        return "Variant"
    return tok

files = []
for p in ROOT.rglob("*.gd"):
    s = str(p)
    if any(x in s for x in EXCLUDE):
        continue
    files.append(p)

# class_name -> file
class_defs = {}          # class_name -> path
extends_rel = {}         # path -> parent path (res:// relative) or None
extends_class = {}       # path -> parent class_name or engine class
class_file_of = {}       # path -> its own class_name

func_re = re.compile(
    r"^\t*(?:(static)\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?:->\s*([^\s:]+))?",
    re.M,
)

sig_by_file = {}  # path -> {name: (params, ret, static)}
for p in files:
    text = p.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", text, re.M)
    if m:
        class_defs[m.group(1)] = p
        class_file_of[p] = m.group(1)
    em = re.search(r'^\s*extends\s+(.+)$', text, re.M)
    em_inline = re.search(r'^\s*class_name\s+[A-Za-z_][A-Za-z0-9_]*\s+extends\s+(.+)$', text, re.M)
    target = None
    if em:
        target = em.group(1).strip()
    elif em_inline:
        target = em_inline.group(1).strip()
    if target:
        if target.startswith('"'):
            extends_rel[p] = target.strip('"')
        else:
            extends_class[p] = target
    sigs = {}
    for fm in func_re.finditer(text):
        is_static = bool(fm.group(1))
        name = fm.group(2)
        params_raw = fm.group(3).strip()
        params = []
        if params_raw:
            depth = 0
            current = ""
            parts = []
            for ch in params_raw:
                if ch in "([":
                    depth += 1
                elif ch in ")]":
                    depth -= 1
                if ch == "," and depth == 0:
                    parts.append(current); current = ""
                else:
                    current += ch
            parts.append(current)
            for part in parts:
                part = part.strip()
                if not part:
                    continue
                pname_type = part.split(":", 1)
                if len(pname_type) == 2:
                    ptype = parse_type(re.sub(r"=.*$", "", pname_type[1]))
                else:
                    ptype = "Variant"
                params.append((pname_type[0].split("=")[0].strip(), ptype))
        ret = fm.group(4) if fm.group(4) else "Variant"
        sigs.setdefault(name, []).append((params, ret, is_static))
    sig_by_file[p] = sigs

def types_compatible(child_t: str, parent_t: str) -> bool:
    # Godot requires typed parts of an override signature to MATCH the parent
    # exactly ("The function signature doesn't match the parent"); no widening
    # or narrowing — not even int -> float. Untyped (Variant) members are
    # compatible with anything, mirroring the GDScript analyzer.
    if child_t == "Variant" or parent_t == "Variant":
        return True
    return child_t == parent_t

def parent_of(p: Path, seen=None):
    seen = seen or set()
    if p in seen:
        return None
    seen.add(p)
    if p in extends_rel:
        rel = extends_rel[p]
        cand = ROOT / rel.replace("res://", "")
        if cand.exists():
            return cand
        return None
    if p in extends_class:
        base = extends_class[p]
        # resolve through project root too
        cand = ROOT / (base + ".gd")
        if cand.exists():
            return cand
        if base in class_defs:
            return class_defs[base]
    return None

issues = []
for p in files:
    par = parent_of(p)
    chain = []
    while par is not None:
        chain.append(par)
        par = parent_of(par, seen=set(chain))
    my = sig_by_file.get(p, {})
    for name, overloads in my.items():
        for (params, ret, is_static) in overloads:
            for anc in chain:
                anc_sigs = sig_by_file.get(anc, {})
                if name in anc_sigs:
                    for (ap, ar, astatic) in anc_sigs[name]:
                        # skip engine overridables commonly redeclared
                        if name.startswith("_") and not name.startswith("__"):
                            pass
                        probs = []
                        if is_static != astatic:
                            probs.append(f"static mismatch (child={is_static}, parent={astatic})")
                        if len(params) != len(ap):
                            probs.append(f"param count {len(params)} vs parent {len(ap)}")
                        else:
                            for (cn, ct), (pn, pt) in zip(params, ap):
                                if not types_compatible(ct, pt):
                                    probs.append(f"param '{cn}' type {ct} vs parent '{pn}' {pt}")
                        if not types_compatible(ret, ar):
                            probs.append(f"return {ret} vs parent {ar}")
                        if probs:
                            rel = str(p.relative_to(ROOT))
                            arel = str(anc.relative_to(ROOT))
                            issues.append(f"[SIGNATURE] {rel}: func {name}({', '.join(n+': '+t for n,t in params)}) -> {ret}"
                                          f"  vs parent {arel}: ({', '.join(n+': '+t for n,t in ap)}) -> {ar}  => {'; '.join(probs)}")
                    break  # nearest ancestor wins

print(f"scanned {len(files)} files")
if issues:
    print(f"\n{len(issues)} signature mismatch(es) found:")
    for i in issues:
        print(" -", i)
    sys.exit(1)
else:
    print("no signature mismatches found")
