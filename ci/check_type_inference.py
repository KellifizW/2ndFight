#!/usr/bin/env python3
"""靜態檢查：抓出 GDScript「型別推導失敗」的編譯錯誤。

為什麼需要這支腳本
------------------
`gdparse` 只驗語法，看不見型別；`ci/check_signatures.py` 只看覆寫簽名。
但下面這種寫法語法完全合法，Godot 載入腳本時卻直接編譯失敗：

    var has_immediate_input := (
        input_data.get("input_dir", 0) != 0
        or input_data.get("jump_pressed", false)
    )
    # Parse Error: Cannot infer the type of "has_immediate_input" variable
    #              because the value doesn't have a set type.

原因是 `Dictionary.get()` 的靜態型別是 Variant，`and` / `or` 串起來還是 Variant，
`:=` 推導不出型別。player.gd 只要有一行這種錯誤，整個腳本載入失敗 —— 遊戲一開就壞。
CI 的 gdparse 卻是綠的，所以這類事故必須另外釘住。

檢查規則（刻意保守，只抓「一定推不出型別」的形狀）
--------------------------------------------------
對每一個 `var NAME := <expr>`（含跨行括號 / 反斜線續行）：

  規則 A：expr 裡出現 `.get(`
          → Dictionary/Object.get() 回傳 Variant，推導必失敗。

  規則 B：expr 裡有邏輯運算子（and / or / not）且其中含有
          「動態型別變數」的屬性存取（例如 `me.is_landing`，
          而 me 宣告為 Node / 無型別）
          → 屬性存取結果是 Variant，整條邏輯式同樣是 Variant。

修法一律是把型別寫明：`var NAME: bool = ...`（或改呼叫有回傳型別的函式）。

用法
----
    python ci/check_type_inference.py

建議掛進 CI（.github/workflows/frame-tests.yml 的 static-check job，
接在 `python ci/check_signatures.py` 後面）：

    - name: Type-inference (`:=`) safety check
      run: python ci/check_type_inference.py

（這一步需要由有 workflows 權限的帳號加入 workflow 檔。）

退出碼：0 = 沒問題，1 = 有可疑寫法。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# 掃描範圍與 .github/workflows/frame-tests.yml 的 gdparse 步驟一致
SCAN_DIRS = ["scripts", "ai", "tests", "characters", "data"]

# 這些型別的屬性存取結果是 Variant（沒有靜態成員資訊）
DYNAMIC_TYPES = {
    "Variant",
    "Object",
    "Node",
    "Node2D",
    "CanvasItem",
    "RefCounted",
    "Resource",
    "Dictionary",
    "Array",
}

VAR_INFER_RE = re.compile(r"^\s*var\s+([A-Za-z_]\w*)\s*:=\s*(.*)$")
VAR_DECL_RE = re.compile(r"^\s*(?:@onready\s+)?var\s+([A-Za-z_]\w*)\s*(:\s*([A-Za-z_]\w*))?\s*(:?=)\s*(.*)$")
PARAM_RE = re.compile(r"([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)")
MEMBER_RE = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\b")
LOGIC_RE = re.compile(r"(?:^|\s)(?:and|or|not)(?:\s|$)")


def strip_comment(line: str) -> str:
    """去掉行尾註解（忽略字串內的 #，夠用即可）。"""
    out = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                out.append(line[i : i + 2])
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def collect_expression(lines: list[str], start: int) -> tuple[str, int]:
    """把從 start 行開始的運算式（含跨行括號與反斜線續行）併成一行。"""
    expr = strip_comment(lines[start]).rstrip()
    idx = start
    depth = expr.count("(") + expr.count("[") + expr.count("{") \
        - expr.count(")") - expr.count("]") - expr.count("}")
    while (depth > 0 or expr.endswith("\\")) and idx + 1 < len(lines):
        idx += 1
        nxt = strip_comment(lines[idx]).rstrip()
        expr = expr.rstrip("\\").rstrip() + " " + nxt.strip()
        depth += nxt.count("(") + nxt.count("[") + nxt.count("{") \
            - nxt.count(")") - nxt.count("]") - nxt.count("}")
    return expr, idx


def dynamic_names(lines: list[str]) -> set[str]:
    """收集「屬性存取會退化成 Variant」的變數名（無型別標註或標成動態型別）。"""
    names: set[str] = set()
    for raw in lines:
        line = strip_comment(raw)
        m = VAR_DECL_RE.match(line)
        if m:
            name, _, declared, assign, rhs = m.groups()
            if assign == ":=":
                continue  # 推導型別，先不當作動態
            if declared is None:
                rhs = rhs.strip()
                # 明確的建構式 / 字面值不算動態
                if rhs and not re.match(r"^(\d|-|\"|'|\[|\{|true\b|false\b)", rhs):
                    names.add(name)
            elif declared in DYNAMIC_TYPES:
                names.add(name)
        if line.lstrip().startswith("func "):
            for pname, ptype in PARAM_RE.findall(line):
                if ptype in DYNAMIC_TYPES:
                    names.add(pname)
    return names


def check_file(path: Path, display: str | None = None) -> list[str]:
    label = display if display is not None else str(path)
    lines = path.read_text(encoding="utf-8").splitlines()
    dynamics = dynamic_names(lines)
    problems: list[str] = []
    i = 0
    while i < len(lines):
        line = strip_comment(lines[i])
        m = VAR_INFER_RE.match(line)
        if not m:
            i += 1
            continue
        name = m.group(1)
        expr, end = collect_expression(lines, i)
        rhs = expr.split(":=", 1)[1].strip()

        if ".get(" in rhs:
            problems.append(
                f"{label}:{i + 1}: `var {name} := ...` 的運算式含 .get()（回傳 Variant），"
                f"型別推導會失敗；請改寫成 `var {name}: <型別> = ...`"
            )
        elif LOGIC_RE.search(rhs):
            hits = [
                f"{obj}.{attr}"
                for obj, attr in MEMBER_RE.findall(rhs)
                if obj in dynamics
            ]
            if hits:
                problems.append(
                    f"{label}:{i + 1}: `var {name} := ...` 對動態型別做屬性存取"
                    f"（{', '.join(sorted(set(hits)))}）並參與 and/or/not 運算，"
                    f"結果是 Variant；請改寫成 `var {name}: <型別> = ...`"
                )
        i = end + 1
    return problems


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    files = sorted(
        p
        for d in SCAN_DIRS
        for p in (root / d).rglob("*.gd")
    )
    problems: list[str] = []
    for path in files:
        display = str(path.relative_to(root)) if path.is_relative_to(root) else str(path)
        problems.extend(check_file(path, display))
    print(f"scanned {len(files)} files")
    if problems:
        print("\n型別推導問題（Godot 載入腳本時會是 Parse Error）：")
        for p in problems:
            print("  ✗ " + p)
        return 1
    print("no type-inference problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
