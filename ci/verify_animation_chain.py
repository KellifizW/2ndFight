#!/usr/bin/env python3
"""Stage 2 切片 6：動畫判定鏈收攏的**窮舉等價證明**。

背景
----
切片 6 之前，「這一幀該播哪個動畫」有兩份抄本：

  1. ``Player._compute_target_state()``      —— 攔截頭段，其餘 ``super`` 下去
  2. ``AnimationManager.compute_target_state()`` —— 把同樣八段又寫一次
     （順序還不同），後面再接尾段

因為所有角色場景（DAV / DEN / WOO）掛的都是 ``player.gd``，抄本 2 的頭段在
實機上不可達。切片 6 把兩份合成後**實際生效**的順序搬進
``FighterState.animation_for()``，刪掉兩份抄本。

本腳本把 **舊的合成鏈**（Player 頭段 + AnimationManager 尾段，含所有不可達
分支，原樣逐行轉寫）與 **新的單一鏈**（FighterState.animation_for 的等價
Python 轉寫）拿去對撞，窮舉所有旗標 × 參數組合，要求 0 分岔。

這是這個 repo 既有的證明方法（見 README「Why the agent sandbox cannot run the
engine」）：sandbox 跑不動 Godot，所以「純函數層」用窮舉在 Python 證，
「引擎層」交給 CI 的 frame tests（本切片為 test_40）。

用法::

    python3 ci/verify_animation_chain.py          # 完整窮舉
    python3 ci/verify_animation_chain.py --quick  # 快速抽樣（開發時用）

退出碼 0 = 逐值等價。
"""

from __future__ import annotations

import argparse
import itertools
import sys

GROUND_ATTACK_IDS = [
    "st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
    "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
]
AIR_ATTACK_IDS = ["jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk"]
THROW_ATTACK_TYPES = ["throw_enter", "throw_seq"]

# 動畫層舊抄本 2 內嵌的字面值清單（第四份攻擊 id 抄本，切片 6 消滅的那份）
LEGACY_INLINE_GROUND_LIST = [
    "st_lp", "st_mp", "st_hp", "st_lk", "st_mk", "st_hk",
    "cr_lp", "cr_mp", "cr_hp", "cr_lk", "cr_mk", "cr_hk",
    "throw_enter", "throw_seq",
]
LEGACY_INLINE_AIR_LIST = ["jump_lp", "jump_mp", "jump_hp", "jump_lk", "jump_mk", "jump_hk"]

# MoveSet.has_move_id() 對哪些 id 回傳 true（取樣一個有代表性的招式 id）
MOVE_LIBRARY = {"dp", "hdk", "powerkk"}

FLAG_NAMES = [
    "is_layground",
    "is_knockfly",
    "is_wakeup",
    "is_hit",
    "is_air_hit_backjump",
    "was_hit_while_crouching",
    "is_blocking",
    "is_crouch_blocking",
    "landing_lock_pos",   # = is_landing and landing_lock_frames > 0
    "is_jumping",
    "is_air_attacking",
    "is_proximity_blocking",
    "is_crouching",
    "is_attacking",
    "is_dashing",
    "is_backdashing",
    "is_spmove",
    "crouch_input",
    "on_floor",
]

ATTACK_TYPES = ["none", "st_mp", "jump_lp", "throw_enter", "dp", "bogus"]
ACTIVE_MOVES = ["", "dp"]
JUMP_DIRS = [-1.0, 0.0, 1.0]


def has_move_id(move_id: str) -> bool:
    return move_id in MOVE_LIBRARY


def legacy_chain(f: dict, attack_type: str, active_move: str, jump_dir: float) -> str:
    """Player._compute_target_state() + AnimationManager.compute_target_state()。

    逐行轉寫，**包含實機不可達的分支** —— 不可達是結論，不是前提。
    """
    on_floor = f["on_floor"]
    crouch_input = f["crouch_input"]

    # ── Player 頭段 ──
    if f["is_layground"]:
        return "layground"
    if f["is_knockfly"]:
        return "knockfly"
    if f["is_wakeup"]:
        return "wakeup"
    if f["is_hit"]:
        # 【AIR RESET 修正】空中重置期間 is_air_hit_backjump 與 is_hit 同時為真，
        # 優先回 air_reset（否則被下方 Jump_B 吃掉 → 空中被打播後跳）。
        if f["is_air_hit_backjump"]:
            return "air_reset"
        if on_floor:
            return "cr_hit" if f["was_hit_while_crouching"] else "hit"
        return "Jump_B"
    if f["is_spmove"] and active_move != "":
        return active_move
    if f["is_blocking"]:
        return "cr_block" if (f["is_crouch_blocking"] and crouch_input) else "block"
    if f["landing_lock_pos"]:
        return "landing"
    if not on_floor and (f["is_jumping"] or f["is_air_attacking"]):
        if f["is_air_attacking"] and attack_type in AIR_ATTACK_IDS:
            return attack_type
        return "Jump_F" if jump_dir > 0 else ("Jump_B" if jump_dir < 0 else "Jump_V")

    # ── AnimationManager 尾段（super）──
    if f["is_air_hit_backjump"]:
        return "air_reset"
    if f["is_hit"]:                                     # 不可達（頭段已攔）
        if not on_floor:
            return "Jump_B"
        return "cr_hit" if f["was_hit_while_crouching"] else "hit"
    if f["is_layground"]:                               # 不可達
        return "layground"
    if f["is_knockfly"]:                                # 不可達
        return "knockfly"
    if f["is_wakeup"]:                                  # 不可達
        return "wakeup"
    if f["landing_lock_pos"] and not f["is_spmove"]:    # 不可達
        return "landing"
    if f["is_spmove"] and active_move != "":            # 不可達
        return active_move
    if f["is_proximity_blocking"]:
        return "cr_block" if f["is_crouching"] else "block"
    if f["is_blocking"]:                                # 不可達
        return "cr_block" if (f["is_crouch_blocking"] and crouch_input) else "block"
    if f["is_attacking"]:
        if attack_type in LEGACY_INLINE_GROUND_LIST:
            return attack_type
        if attack_type not in ("", "none") and has_move_id(attack_type):
            return attack_type
        return "Walk"
    if f["is_dashing"]:
        return "Dash"
    if f["is_backdashing"]:
        return "Backdash"
    if crouch_input and on_floor and not f["is_blocking"]:
        return "cr_idle"
    if not on_floor and (f["is_jumping"] or f["is_air_attacking"]):   # 不可達
        if f["is_air_attacking"] and attack_type in LEGACY_INLINE_AIR_LIST:
            return attack_type
        return "Jump_F" if jump_dir > 0 else ("Jump_B" if jump_dir < 0 else "Jump_V")
    return "Walk"


def unified_chain(f: dict, attack_type: str, active_move: str, jump_dir: float) -> str:
    """FighterState.animation_for() 的等價 Python 轉寫。"""
    on_floor = f["on_floor"]
    crouch_input = f["crouch_input"]

    if f["is_layground"]:
        return "layground"
    if f["is_knockfly"]:
        return "knockfly"
    if f["is_wakeup"]:
        return "wakeup"
    if f["is_hit"]:
        # 【AIR RESET 修正】空中重置優先於泛用 HITSTUN（見 animation_for 註解）。
        if f["is_air_hit_backjump"]:
            return "air_reset"
        if not on_floor:
            return "Jump_B"
        return "cr_hit" if f["was_hit_while_crouching"] else "hit"
    if f["is_spmove"] and active_move != "":
        return active_move
    if f["is_blocking"]:
        return "cr_block" if (f["is_crouch_blocking"] and crouch_input) else "block"
    if f["landing_lock_pos"]:
        return "landing"
    if not on_floor and (f["is_jumping"] or f["is_air_attacking"]):
        if f["is_air_attacking"] and attack_type in AIR_ATTACK_IDS:
            return attack_type
        return "Jump_F" if jump_dir > 0 else ("Jump_B" if jump_dir < 0 else "Jump_V")
    if f["is_air_hit_backjump"]:
        return "air_reset"
    if f["is_proximity_blocking"]:
        return "cr_block" if f["is_crouching"] else "block"
    if f["is_attacking"]:
        if attack_type in GROUND_ATTACK_IDS or attack_type in THROW_ATTACK_TYPES:
            return attack_type
        if attack_type not in ("", "none") and has_move_id(attack_type):
            return attack_type
        return "Walk"
    if f["is_dashing"]:
        return "Dash"
    if f["is_backdashing"]:
        return "Backdash"
    if crouch_input and on_floor:
        return "cr_idle"
    return "Walk"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true",
                        help="只跑 2^12 旗標子集（開發用），完整證明請不要加")
    args = parser.parse_args()

    flag_names = FLAG_NAMES
    bits = len(flag_names)
    total = 0
    mismatches = []
    dead_branch_hits = 0

    combos = range(1 << bits)
    if args.quick:
        combos = range(0, 1 << bits, 97)

    for mask in combos:
        f = {name: bool(mask >> i & 1) for i, name in enumerate(flag_names)}
        for attack_type, active_move, jump_dir in itertools.product(
                ATTACK_TYPES, ACTIVE_MOVES, JUMP_DIRS):
            total += 1
            old = legacy_chain(f, attack_type, active_move, jump_dir)
            new = unified_chain(f, attack_type, active_move, jump_dir)
            if old != new and len(mismatches) < 10:
                mismatches.append((dict(f), attack_type, active_move, jump_dir, old, new))
            elif old != new:
                pass
            # 覆蓋度：air_reset 分支（空中重置；is_air_hit_backjump）必須真的被
            # 走到過，否則「air_reset 在 HITSTUN 內優先於 Jump_B」沒有被證明。
            if old == "air_reset" and f["is_air_hit_backjump"] \
                    and not f["is_knockfly"] and not f["is_layground"] \
                    and not f["is_wakeup"]:
                dead_branch_hits += 1

    print("combinations checked : %d (%d flag masks × %d parameter tuples)"
          % (total, len(list(combos)) if args.quick else 1 << bits,
             len(ATTACK_TYPES) * len(ACTIVE_MOVES) * len(JUMP_DIRS)))
    print("air_reset (air-hit-backjump) branch reached: %d" % dead_branch_hits)

    if mismatches:
        print("\nMISMATCHES (first %d):" % len(mismatches))
        for f, atk, mv, jd, old, new in mismatches:
            active = sorted(k for k, v in f.items() if v)
            print("  flags=%s attack_type=%s active_move=%r jump_dir=%s : legacy=%s new=%s"
                  % (active, atk, mv, jd, old, new))
        return 1

    if dead_branch_hits == 0:
        print("\nERROR: air_reset 分支從未被走到 —— 覆蓋度不足，等價結論無意義")
        return 1

    print("\nOK: 舊合成鏈與 FighterState.animation_for() 逐值等價（0 分岔）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
