#!/usr/bin/env python3
"""Stage 2 切片 8：`is_wakeup` 摺進 `wakeup_timer` 的等價證明。

這不是 CI gate（跟 `verify_animation_chain.py` 一樣是獨立的證明產物），
用來在「沙箱跑不動 Godot」的前提下把這刀的兩個前提變成可重跑的檢查：

  Part 1 — 靜態讀寫普查（前提：旗標與計時器真的永遠同步）
    1. 全倉庫執行期代碼裡不得再出現 `is_wakeup` / `is_wakeup_locked` 識別字
       （註解與說明文字允許，因為它們在記錄這次的刪除）。
    2. `wakeup_timer` 的每一個寫入點都必須被分類，且分類結果符合預期：
       種子點（2 處，皆為正值）、倒數點（1 處）、reset 歸零點（1 處）。
    3. 種子值必須 > 0：三個角色的 `wakeup` 動畫長度都從 `.tscn` 讀出來驗證
       （0.5s → 60 物理幀），fallback 常數也必須是正的。

  Part 2 — 生命週期窮舉（前提：摺疊後逐幀等價）
    把「舊模型」（`is_wakeup` 旗標 + `wakeup_timer`）與「新模型」
    （只有 `wakeup_timer`，`is_wakeup := wakeup_timer > 0`）寫成兩個小狀態機，
    窮舉「種子值 × reset 時機 × reset 後再起身 × hitstop 凍結時機」，
    逐幀比對兩者的起身狀態**以及**倒數收尾副作用是否發動。

用法：
    python3 ci/verify_wakeup_fold.py            # 靜態普查 + 生命週期窮舉
    python3 ci/verify_wakeup_fold.py --quiet    # 只印結論
"""

from __future__ import annotations

import argparse
import itertools
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 執行期代碼的搜尋範圍（不含 addons/ 與 backup/，與先前切片的普查口徑一致）
CODE_DIRS = ["scripts", "ai", "tests", "characters", "data", "scenes"]

# 只允許出現在註解/文件裡的名字（執行期不得再有識別字）
DEAD_FLAG_NAMES = ("is_wakeup", "is_wakeup_locked")

SEEDS = (1, 2, 3, 7, 24, 60, 120)


def strip_code(line: str) -> str:
    """去掉字串字面值與註解，只留下可以判斷「有沒有讀寫某個識別字」的代碼。

    順序：先拿掉 `"..."`（Debug.log 的訊息裡常出現 `wakeup_timer = 120` 這種
    純說明文字），再拿掉 `#` 之後的內容。
    """
    return re.sub(r'"[^"]*"', '""', line).split("#", 1)[0]


def iter_code_files():
    for d in CODE_DIRS:
        root = os.path.join(REPO_ROOT, d)
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [n for n in dirnames if n not in ("addons", "backup")]
            for name in sorted(filenames):
                if name.endswith((".gd", ".tscn", ".tres")):
                    yield os.path.join(dirpath, name)


# ── Part 1 ───────────────────────────────────────────────────────────────
def part1_static_census(quiet: bool) -> list[str]:
    errors: list[str] = []

    # 1. 執行期不得再有 is_wakeup / is_wakeup_locked 識別字
    live_hits = []
    for path in iter_code_files():
        if not path.endswith(".gd"):
            continue
        with open(path, encoding="utf-8") as fh:
            for lineno, raw in enumerate(fh, 1):
                code = strip_code(raw)
                for name in DEAD_FLAG_NAMES:
                    if re.search(r"\b%s\b" % re.escape(name), code):
                        live_hits.append(
                            "%s:%d %s" % (os.path.relpath(path, REPO_ROOT), lineno, name))
    if live_hits:
        errors.append("執行期代碼仍讀寫已刪除的旗標：\n    " + "\n    ".join(live_hits))

    # 2. wakeup_timer 的寫入點分類
    seeds, decrements, zeroes, other = [], [], [], []
    for path in iter_code_files():
        if not path.endswith(".gd"):
            continue
        rel = os.path.relpath(path, REPO_ROOT)
        with open(path, encoding="utf-8") as fh:
            for lineno, raw in enumerate(fh, 1):
                code = strip_code(raw)
                if not re.search(r"\bwakeup_timer\b", code):
                    continue
                where = "%s:%d" % (rel, lineno)
                if re.search(r"wakeup_timer\s*-=", code):
                    decrements.append(where)
                elif re.search(r"wakeup_timer\s*=\s*0\b", code):
                    zeroes.append(where)
                elif re.search(r"wakeup_timer\s*=", code):
                    seeds.append(where)
                else:
                    other.append(where)

    # 種子點：player.gd（動畫長度 / fallback 60）與 KnockflyHandler.gd
    # （動畫長度 / fallback 120）各兩行，且每一行都必須是正值來源。
    expected_seed_files = {"scripts/core/player.gd": 2,
                           "scripts/handlers/KnockflyHandler.gd": 2}
    seen_seed_files: dict[str, int] = {}
    for where in seeds:
        f = where.split(":")[0]
        seen_seed_files[f] = seen_seed_files.get(f, 0) + 1
    if seen_seed_files != expected_seed_files:
        errors.append("wakeup_timer 種子點分布不符預期：預期 %s，實測 %s（%s）"
                      % (expected_seed_files, seen_seed_files, seeds))
    if len(decrements) != 1:
        errors.append("預期 1 個 wakeup_timer 倒數點（player._physics_process），"
                      "實測 %d：%s" % (len(decrements), decrements))
    if len(zeroes) != 1:
        errors.append("預期 1 個 wakeup_timer 歸零點（world.reset_players），"
                      "實測 %d：%s" % (len(zeroes), zeroes))
    if not quiet:
        print("wakeup_timer 寫入點：種子 %s / 倒數 %s / reset 歸零 %s"
              % (seeds, decrements, zeroes))

    # 3. 種子值必須為正：三個角色的 wakeup 動畫長度 + fallback 常數
    char_dir = os.path.join(REPO_ROOT, "characters")
    lengths = {}
    for name in sorted(os.listdir(char_dir)):
        if not name.endswith(".tscn"):
            continue
        with open(os.path.join(char_dir, name), encoding="utf-8") as fh:
            lines = fh.read().splitlines()
        for i, line in enumerate(lines):
            if line.strip() == 'resource_name = "wakeup"':
                m = re.match(r"length\s*=\s*([0-9.]+)", lines[i + 1].strip())
                if m:
                    lengths[name] = float(m.group(1))
                break
    if not lengths:
        errors.append("找不到任何角色的 wakeup 動畫長度，普查無法成立")
    for name, length in sorted(lengths.items()):
        frames = int(round(length * 120))  # Movement.seconds_to_frames_nearest
        if frames <= 0:
            errors.append("%s 的 wakeup 動畫長度 %ss → %d 幀，種子非正值，"
                          "摺疊後會與舊旗標語意分岔" % (name, length, frames))
        elif not quiet:
            print("  %s wakeup 動畫 %.3fs → %d 物理幀" % (name, length, frames))

    # fallback 常數（player.gd = 60、KnockflyHandler.gd = 120）必須是正整數字面值
    with open(os.path.join(REPO_ROOT, "scripts", "core", "player.gd"), encoding="utf-8") as fh:
        player_src = fh.read()
    with open(os.path.join(REPO_ROOT, "scripts", "handlers", "KnockflyHandler.gd"),
              encoding="utf-8") as fh:
        knockfly_src = fh.read()
    for label, src, expected in (("player.gd", player_src, 60),
                                 ("KnockflyHandler.gd", knockfly_src, 120)):
        if not re.search(r"wakeup_timer\s*=\s*%d\b" % expected, strip_lines(src)):
            errors.append("%s 找不到 wakeup_timer fallback 常數 %d" % (label, expected))

    return errors


def strip_lines(src: str) -> str:
    return "\n".join(strip_code(line) for line in src.splitlines())


# ── Part 2 ───────────────────────────────────────────────────────────────
class OldModel:
    """舊模型：`is_wakeup` 旗標 + `wakeup_timer`（player.gd 摺疊前的行為）。"""

    def __init__(self) -> None:
        self.is_wakeup = False
        self.wakeup_timer = 0
        self.side_effects = 0

    def enter(self, seed: int) -> None:
        self.is_wakeup = True
        self.wakeup_timer = seed

    def tick(self) -> None:
        if self.wakeup_timer > 0:
            self.wakeup_timer -= 1
            if self.wakeup_timer <= 0 and self.is_wakeup:
                self.is_wakeup = False
                self.side_effects += 1

    def reset(self) -> None:
        self.is_wakeup = False  # world.reset_players()：只清旗標、留下過期計時器

    def wakeup(self) -> bool:
        return self.is_wakeup


class NewModel:
    """新模型：只有 `wakeup_timer`，`is_wakeup := wakeup_timer > 0`。"""

    def __init__(self) -> None:
        self.wakeup_timer = 0
        self.side_effects = 0

    def enter(self, seed: int) -> None:
        self.wakeup_timer = seed

    def tick(self) -> None:
        if self.wakeup_timer > 0:
            self.wakeup_timer -= 1
            if self.wakeup_timer <= 0:
                self.side_effects += 1

    def reset(self) -> None:
        self.wakeup_timer = 0  # 切片 8 在 reset_players() 補上的歸零

    def wakeup(self) -> bool:
        return self.wakeup_timer > 0


def part2_lifecycle(quiet: bool) -> list[str]:
    """窮舉「種子 × reset 時機 × reset 後再起身 × 凍結時機」，逐幀比對兩模型。"""
    errors: list[str] = []
    cases = 0
    wakeup_frames = 0

    for seed, reset_at, re_enter_at, freeze_at in itertools.product(
            SEEDS,
            [None] + list(range(0, max(SEEDS) + 3)),
            [None, 0, 1, 5],
            [None, 1, 2]):
        if reset_at is not None and reset_at > seed + 2:
            continue
        old, new = OldModel(), NewModel()
        old.enter(seed)
        new.enter(seed)
        cases += 1

        horizon = seed + 8
        for frame in range(horizon):
            # 起身狀態在「倒數之前」被讀取（player._physics_process 的讀點都在前半段）
            if old.wakeup() != new.wakeup():
                errors.append("frame %d 分岔：seed=%d reset_at=%s re_enter=%s "
                              "freeze=%s → old=%s new=%s"
                              % (frame, seed, reset_at, re_enter_at, freeze_at,
                                 old.wakeup(), new.wakeup()))
                break
            if old.wakeup():
                wakeup_frames += 1

            if frame == reset_at:
                old.reset()
                new.reset()
            if reset_at is not None and re_enter_at is not None \
                    and frame == reset_at + re_enter_at:
                old.enter(seed)
                new.enter(seed)
            if frame == freeze_at:
                continue  # hitstop：Player._physics_process 開頭 return，不倒數
            old.tick()
            new.tick()

        if old.side_effects != new.side_effects:
            errors.append("倒數收尾副作用次數分岔：seed=%d reset_at=%s re_enter=%s "
                          "freeze=%s → old=%d new=%d"
                          % (seed, reset_at, re_enter_at, freeze_at,
                             old.side_effects, new.side_effects))

    if wakeup_frames == 0:
        errors.append("窮舉裡從未出現「處於起身狀態」的幀 —— 覆蓋度不足，等價結論無意義")

    if not quiet:
        print("生命週期窮舉：%d 條序列、%d 個起身狀態樣本，兩模型逐幀一致"
              % (cases, wakeup_frames))
    return errors


def part2_selftest(quiet: bool) -> list[str]:
    """反向驗證：故意把新模型改壞，證明上面的窮舉**抓得到**分岔（不是假綠）。"""
    errors: list[str] = []

    # 變體 A：reset 時不清 wakeup_timer（切片 8 如果忘了在 reset_players 補歸零）
    class NoZeroReset(NewModel):
        def reset(self) -> None:
            pass

    # 變體 B：倒數變成 `wakeup_timer <= 1` 就收尾（提早一幀結束起身）
    class EarlyClear(NewModel):
        def tick(self) -> None:
            if self.wakeup_timer > 0:
                self.wakeup_timer -= 1
                if self.wakeup_timer <= 1:
                    self.side_effects += 1

    for label, broken in (("reset 未歸零", NoZeroReset), ("提早一幀收尾", EarlyClear)):
        found = False
        for seed, reset_at in itertools.product(SEEDS, [None] + list(range(0, max(SEEDS) + 3))):
            if reset_at is not None and reset_at > seed + 2:
                continue
            old, new = OldModel(), broken()
            old.enter(seed)
            new.enter(seed)
            for frame in range(seed + 8):
                if old.wakeup() != new.wakeup() \
                        or old.side_effects != new.side_effects:
                    found = True
                    break
                if frame == reset_at:
                    old.reset()
                    new.reset()
                old.tick()
                new.tick()
            if found:
                break
        if not found:
            errors.append("變體「%s」沒有被窮舉抓到 —— 證明本身是假綠" % label)
        elif not quiet:
            print("  反向驗證：變體「%s」如期被抓到分岔" % label)

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    print("Stage 2 切片 8 — `is_wakeup` 摺進 `wakeup_timer > 0` 的等價證明")
    print("-" * 70)

    errors = part1_static_census(args.quiet)
    errors += part2_lifecycle(args.quiet)
    if not args.quiet:
        print("反向驗證（證明窮舉不是假綠）:")
    errors += part2_selftest(args.quiet)

    if errors:
        print("\nFAILED:")
        for e in errors:
            print("  ✗ %s" % e)
        return 1

    print("\nOK: 靜態普查 + 生命週期窮舉皆通過 —— 摺疊為逐幀等價的純刪除")
    return 0


if __name__ == "__main__":
    sys.exit(main())
