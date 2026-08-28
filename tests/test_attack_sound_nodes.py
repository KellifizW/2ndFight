#!/usr/bin/env python3
"""
Test suite for the per-attack-type sound wiring in 2ndFight.

驗證 scripts/combat/AttackSoundResolver.gd 的映射表，與角色場景
(characters/DAV.tscn, characters/DEN.tscn) 內實際存在的 AudioStreamPlayer
節點一致：

  1. 6 個按鈕擊中音效節點  LP/MP/HP/LK/MK/HK SoundPlayer
  2. 3 個揮空音效節點      L/M/H WhooshSoundPlayer
  3. 3 個普通攻擊喊聲節點  AttackGrunt_l1/m1/h1
  4. player.gd 的 _ATTACK_NAMES（18 個普通攻擊）全部能解析出
     對應的擊中音效節點、揮空音效節點與攻擊喊聲節點
  5. 重拳（*_hp）一律 HPSoundPlayer、重踢（*_hk）一律 HKSoundPlayer，絕不對調
  6. 特殊招式 / 摔投不會被誤判為普通攻擊（會回退到舊有音效節點）
  7. 攻擊喊聲機率改為 @export（預設 50%）、出招呼叫、被打中中斷接線

不需要 Godot，純文字解析，可直接執行：
    python3 tests/test_attack_sound_nodes.py
"""

import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOLVER = os.path.join(ROOT, "scripts", "combat", "AttackSoundResolver.gd")
PLAYER_GD = os.path.join(ROOT, "scripts", "core", "player.gd")
FIGHTER_GD = os.path.join(ROOT, "scripts", "core", "fighter.gd")

# 已加設新音效節點的角色場景（WOO 尚未加設，靠回退機制運作）
CHARACTER_SCENES = [
    os.path.join(ROOT, "characters", "DAV.tscn"),
    os.path.join(ROOT, "characters", "DEN.tscn"),
]


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def parse_dict(source, const_name):
    """從 GDScript 抽出 `const NAME: Dictionary = { "k": "v", ... }`。"""
    match = re.search(
        r"const\s+%s\s*:\s*Dictionary\s*=\s*\{(.*?)\}" % const_name,
        source,
        re.DOTALL,
    )
    assert match, "找不到常數 %s" % const_name
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', match.group(1)))


def parse_export_float(source, var_name):
    """從 GDScript 抽出 `@export* var NAME: float = 值`（含 @export_range 等變體）。"""
    match = re.search(
        r"@export[^\n]*var\s+%s\s*:\s*float\s*=\s*([0-9.]+)" % var_name,
        source,
    )
    assert match, "找不到 @export 變數 %s" % var_name
    return float(match.group(1))


def parse_attack_names(source):
    """從 player.gd 抽出 _ATTACK_NAMES 陣列。"""
    match = re.search(r"const\s+_ATTACK_NAMES\s*:\s*Array\s*=\s*\[(.*?)\]", source, re.DOTALL)
    assert match, "找不到 player.gd 的 _ATTACK_NAMES"
    return re.findall(r'"([^"]+)"', match.group(1))


def scene_audio_players(scene_source):
    """回傳場景內所有 AudioStreamPlayer 節點名稱 → 是否有指定 stream。"""
    players = {}
    blocks = re.split(r"\n(?=\[node )", scene_source)
    for block in blocks:
        header = re.match(r'\[node name="([^"]+)" type="AudioStreamPlayer"', block)
        if header:
            players[header.group(1)] = "stream = " in block
    return players


# ── 迷你版 AttackSoundResolver（與 GDScript 邏輯一致）───────────────
def get_button_id(attack_type, hit_players):
    if not attack_type or attack_type == "none":
        return ""
    parts = [p for p in attack_type.lower().split("_") if p]
    if len(parts) < 2:
        return ""
    button = parts[-1]
    return button if button in hit_players else ""


def run_all_tests():
    resolver_src = read(RESOLVER)
    player_src = read(PLAYER_GD)
    fighter_src = read(FIGHTER_GD)
    hit_players = parse_dict(resolver_src, "HIT_SOUND_PLAYERS")
    whoosh_players = parse_dict(resolver_src, "WHOOSH_SOUND_PLAYERS")
    grunt_players = parse_dict(resolver_src, "GRUNT_SOUND_PLAYERS")
    grunt_chance = parse_export_float(player_src, "attack_grunt_chance")

    print("=======================================================")
    print("Attack sound wiring tests")
    print("=======================================================")

    # 1. 映射表本身
    assert set(hit_players) == {"lp", "mp", "hp", "lk", "mk", "hk"}, hit_players
    assert set(whoosh_players) == {"l", "m", "h"}, whoosh_players
    assert set(grunt_players) == {"l", "m", "h"}, grunt_players
    for button, node_name in hit_players.items():
        assert node_name == button.upper() + "SoundPlayer", (button, node_name)
    for strength, node_name in whoosh_players.items():
        assert node_name == strength.upper() + "WhooshSoundPlayer", (strength, node_name)
    for strength, node_name in grunt_players.items():
        assert node_name == "AttackGrunt_%s1" % strength, (strength, node_name)
    print("✅ 1. 映射表命名正確（6 擊中節點 + 3 揮空節點 + 3 喊聲節點）")

    # 2. 角色場景真的有這些節點，而且有指定 stream
    expected_nodes = sorted(
        set(hit_players.values()) | set(whoosh_players.values()) | set(grunt_players.values())
    )
    for scene_path in CHARACTER_SCENES:
        players = scene_audio_players(read(scene_path))
        name = os.path.basename(scene_path)
        for node_name in expected_nodes:
            assert node_name in players, "%s 缺少音效節點 %s" % (name, node_name)
            assert players[node_name], "%s 的 %s 沒有指定 stream" % (name, node_name)
        # 回退用的舊節點仍需保留（特殊招式 / 火球擊中時使用）
        for legacy in ("HitSoundPlayer", "HeavyHitSoundPlayer",
                       "BlockSoundPlayer", "HeavyBlockSoundPlayer"):
            assert legacy in players, "%s 缺少回退音效節點 %s" % (name, legacy)
        print("✅ 2. %s 具備全部 %d 個新音效節點與回退節點" % (name, len(expected_nodes)))

    # 3. 18 個普通攻擊全部可解析
    attack_names = parse_attack_names(player_src)
    assert len(attack_names) == 18, attack_names
    for attack in attack_names:
        button = get_button_id(attack, hit_players)
        assert button, "%s 無法解析出按鈕代號" % attack
        assert hit_players[button].startswith(button.upper())
        assert button[0] in whoosh_players, "%s 無法解析出強度代號" % attack
        assert button[0] in grunt_players, "%s 無法解析出喊聲強度" % attack
    print("✅ 3. player.gd 的 18 個普通攻擊全部對應到擊中 + 揮空 + 喊聲音效")

    # 4. 重拳 / 重踢絕不可對調（無論角色、無論站蹲跳）
    for stance in ("st", "cr", "jump"):
        hp_button = get_button_id("%s_hp" % stance, hit_players)
        hk_button = get_button_id("%s_hk" % stance, hit_players)
        assert hp_button == "hp", stance
        assert hk_button == "hk", stance
        assert hit_players[hp_button] == "HPSoundPlayer"
        assert hit_players[hk_button] == "HKSoundPlayer"
        assert hit_players[hp_button] != hit_players[hk_button]
    print("✅ 4. 重拳 → HPSoundPlayer、重踢 → HKSoundPlayer（站/蹲/跳皆然，絕不對調）")

    # 5. 非普通攻擊必須回退（不得誤判）
    for non_normal in ("throw_enter", "throw_seq", "fireballL", "fireballM",
                       "fireballH", "dpL", "dpM", "dpH", "powerkk", "spnk",
                       "hdk", "none", ""):
        assert get_button_id(non_normal, hit_players) == "", non_normal
    print("✅ 5. 摔投與特殊招式維持舊有回退音效（不會誤判為普通攻擊）")

    # 6. 攻擊喊聲機制接線
    assert grunt_chance == 0.5, grunt_chance
    assert "play_attack_grunt" in player_src
    assert "attack_grunt_chance" in player_src  # player.gd 把機率傳入 resolver
    assert "play_whoosh_sound" in player_src
    assert "stop_attack_grunts" in fighter_src
    assert "func stop_attack_grunts" in resolver_src
    assert "func play_attack_grunt" in resolver_src
    assert "GRUNT_PLAY_CHANCE" not in resolver_src  # 寫死的 const 已移除
    print("✅ 6. 攻擊喊聲機率改為 @export（預設 50%）、出招播放、被打中中斷均已接線")

    print("\n=======================================================")
    print("🎉 ALL ATTACK SOUND WIRING TESTS PASSED! 🎉")
    print("=======================================================")


if __name__ == "__main__":
    run_all_tests()
