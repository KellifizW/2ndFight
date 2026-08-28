# 攻擊音效系統（按攻擊類型 / 強度分流）

> 改動日期：2026-08-28
> 相關檔案：`scripts/combat/AttackSoundResolver.gd`、`scripts/combat/handlers/HitResponseHandler.gd`、`scripts/core/player.gd`、`scripts/core/fighter.gd`

## 1. 改動前

角色場景（`characters/DAV.tscn`、`characters/DEN.tscn`）內只有一個 `HitSoundPlayer`
負責播放**所有**擊中對手的音效，另有 `HeavyHitSoundPlayer` 在傷害 >= 8 時取代它。
所有輕拳、重踢、跳躍攻擊聽起來都一樣，出招時亦沒有揮空聲。

## 2. 改動後

### 2.1 擊中音效：按攻擊按鈕分流

| 攻擊按鈕 | 音效節點 | 涵蓋的 `attack_type` |
| --- | --- | --- |
| 輕拳 LP | `LPSoundPlayer` | `st_lp` / `cr_lp` / `jump_lp` |
| 中拳 MP | `MPSoundPlayer` | `st_mp` / `cr_mp` / `jump_mp` |
| 重拳 HP | `HPSoundPlayer` | `st_hp` / `cr_hp` / `jump_hp` |
| 輕腳 LK | `LKSoundPlayer` | `st_lk` / `cr_lk` / `jump_lk` |
| 中腳 MK | `MKSoundPlayer` | `st_mk` / `cr_mk` / `jump_mk` |
| 重腳 HK | `HKSoundPlayer` | `st_hk` / `cr_hk` / `jump_hk` |

只在**真正打中**（未被格擋）時播放。格擋音效維持原狀：
`BlockSoundPlayer` / `HeavyBlockSoundPlayer`（傷害 >= 8 用強力版本）。

**重拳 / 重踢不可對調**：無論 DAV 或 DEN、無論站立 / 蹲下 / 跳躍，
`*_hp` 一律播該角色場景的 `HPSoundPlayer`，`*_hk` 一律播 `HKSoundPlayer`。
節點上綁的音檔由場景決定，程式只按節點名稱播放，不會因傷害高低改播對方的節點。

### 2.2 揮空音效：按攻擊強度分流

| 強度 | 音效節點 |
| --- | --- |
| 輕 L | `LWhooshSoundPlayer` |
| 中 M | `MWhooshSoundPlayer` |
| 重 H | `HWhooshSoundPlayer` |

在 `Player._execute_attack()`（出招當下）播放，**不論有否打中對手**。
摔投（`throw_enter` / `throw_seq`）不播放揮空音效。

### 2.3 普通攻擊喊聲：按攻擊強度分流

| 強度 | 音效節點 |
| --- | --- |
| 輕 L | `AttackGrunt_l1` |
| 中 M | `AttackGrunt_m1` |
| 重 H | `AttackGrunt_h1` |

同樣在 `Player._execute_attack()` 出招當下播放，**不論有否打中對手**。
摔投與特殊招式不播放。

兩條額外規則：

1. **50% 機率**：每次出普通攻擊擲一次骰，只有一半機會真正播放。
   RNG 獨立於 AI 決策用的全域 `randf()`，避免影響戰鬥確定性。
2. **被打中斷**：若喊聲還在播、角色被對方真正打中（非格擋），
   `Fighter.take_hit()` 會立刻 `stop()` 三個喊聲節點。

## 3. 解析規則

`AttackSoundResolver.get_button_id()` 取 `attack_type` 以 `_` 分割後的最後一段：

- `st_lp` → `lp`、`cr_hk` → `hk`、`jump_mp` → `mp`
- 之後新增的指令技（例如 `f_hp`）只要沿用 `<前綴>_<按鈕>` 命名就自動生效
- 沒有 `_` 或尾段不是 6 個按鈕之一（`fireballL`、`dpM`、`powerkk`、`throw_enter` …）→ 回傳 `""`，代表不是普通攻擊

## 4. 回退（向後兼容）

| 情況 | 行為 |
| --- | --- |
| 特殊招式擊中（`fireballL`、`dp`、`powerkk` …） | 回退到 `HeavyHitSoundPlayer`（傷害 >= 8）或 `HitSoundPlayer` |
| 角色場景未加設新節點（例如 `WOO.tscn`） | 擊中音效回退到 `HitSoundPlayer` / `HeavyHitSoundPlayer`；揮空音效與攻擊喊聲靜默略過 |
| 招式語音（`SpecialCallPlayer`、`FireballCallPlayer`、`dpCallPlayer`） | 不受影響，仍由 `MoveSet` 的 `sound_type` 控制 |
| 火球飛行道具自身的 `HitSoundPlayer` | 不受影響（在 `scenes/projectiles/*.tscn` 內） |

因此 `HitSoundPlayer` / `HeavyHitSoundPlayer` 節點**必須保留**在角色場景中。

## 5. 為新角色接線

1. 在角色 `.tscn` 的根節點下加入 12 個 `AudioStreamPlayer`：
   `LPSoundPlayer`、`MPSoundPlayer`、`HPSoundPlayer`、`LKSoundPlayer`、`MKSoundPlayer`、`HKSoundPlayer`、
   `LWhooshSoundPlayer`、`MWhooshSoundPlayer`、`HWhooshSoundPlayer`、
   `AttackGrunt_l1`、`AttackGrunt_m1`、`AttackGrunt_h1`
2. 各自指定 `stream`（可用同一個檔案配不同 `pitch_scale`）
3. 保留 `HitSoundPlayer` / `HeavyHitSoundPlayer` 作回退
4. 無需改任何 GDScript

## 6. 驗證

```bash
python3 tests/test_attack_sound_nodes.py
```

檢查映射表命名、DAV/DEN 場景是否具備全部 9 個新節點（且有指定 stream）、
18 個普通攻擊是否全部解析成功，以及特殊招式 / 摔投是否正確回退。
