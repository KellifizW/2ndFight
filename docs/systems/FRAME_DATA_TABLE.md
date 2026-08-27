# Frame Data 表（Stage 0 行為基準）

> 建立日期: 2026-08-21。本表是 Stage 0 產物，用途:
> 1. 重構（Stage 1 統一時間域、Stage 2 狀態機）前後比對「遊戲手感是否改變」的基準
> 2. frame 測試（`tests/frame_tests/`）斷言值的來源
>
> **單位慣例**: 所有幀數為 **60 FPS 邏輯幀**（業界 frame data 慣例）。
> 物理執行為 120 FPS → **1 邏輯幀 = 2 物理幀**。
>
> **欄位**:
> - `total` = 動畫總長（tscn 動畫 `length`）
> - `startup` = hitbox 開啟幀（動畫 `Hitbox/HitShape:disabled` 由 true→false 的 key 時間）
> - `active` = hitbox 有效窗口 `[on, off)`；`-` 表持續到動畫結束
> - `recovery` = `total - active_off`（可被取消/受擊的恢復期）
> - 傷害/hitstun/blockstun/knockback 來自 `AttackData`（普通攻擊）或 `SpecialMoveData`（特殊招式）
>
> **數據來源（注意優先級）**:
> - 普通攻擊: `characters/<X>.tscn` 的 `attack_data` → `data/p1_attack_data.tres`（DAV/WOO）、`data/p2_attack_data.tres`（DEN）覆蓋 `data/AttackData.gd` 預設值
> - 特殊招式: **場景內嵌 smd_* 資源優先**（`_load_smd` 的 export 優先於 `data/specials/*.tres` fallback）

---

## DAV（attack_data = p1_attack_data.tres）

### 站姿攻擊

| 招式 | total | startup | active | recovery | 傷害 | hitstun | blockstun | knockback |
|---|---|---|---|---|---|---|---|---|
| st_lp | 13 | 3 | 3–6 | 7 | 3.0 | 14 | 12 | 60 |
| st_mp | 24 | 5 | 5–7 | 17 | 6.0 | 24 | 16 | 70 ←p1覆蓋 |
| st_hp | 30 | 9 | 9–13 | 17 | 9.0 | 27 ←p1覆蓋 | 20 | 100 ←p1覆蓋 |
| st_lk | 12 | 5 | 5–7 | 5 | 3.0 | 11 ←p1覆蓋 | 8 ←p1覆蓋 | 60 ←p1覆蓋 |
| st_mk | 28 | 9 | 9–13 | 15 | 6.0 | 33 | 18 | 130 |
| st_hk | 42 | 12 | 12–15 | 27 | 9.0 | 20 | 22 | 110 |

### 蹲姿攻擊

| 招式 | total | startup | active | recovery | 傷害 | hitstun | blockstun | knockback |
|---|---|---|---|---|---|---|---|---|
| cr_lp | 12 | 3 | 3–5 | 7 | 2.0 | 15 | 10 | 70 |
| cr_mp | 24 | 8 | 8–12 | 12 | 6.0 | 21 | 14 | 80 |
| cr_hp | 24 | 8 | 8–（至結束） | — | 9.0 | 30 | 18 | 80 |
| cr_lk | 17 | 4 | 4–6 | 11 | 2.0 | 15 | 12 | 100 |
| cr_mk | 29 | 8 | 8–11 | 18 | 6.0 | 30 | 16 | 140 |
| cr_hk | 30 | 8 | 8–11 | 19 | 9.0 | 39 | 20 | 150 |

### 空中攻擊

| 招式 | total | startup | active | 傷害 | hitstun | blockstun | knockback |
|---|---|---|---|---|---|---|---|
| jump_lp | 14 | 4 | 4–（至結束） | 3.0 | 18 | 12 | 80 |
| jump_mp | 24 | 8 | 8–（至結束） | 6.0 | 24 | 16 | 110 |
| jump_hp | 24 | 8 | 8–（至結束） | 9.0 | 30 | 20 | 120 |
| jump_lk | 18 | 4 | 4–（至結束） | 2.0 | 24 | 14 | 60 |
| jump_mk | 30 | 6 | 6–（至結束） | 5.0 | 30 | 18 | 60 |
| jump_hk | 30 | 6 | 6–（至結束） | 9.0 | 36 | 22 | 70 |

### 特殊招式（生效值 = DAV.tscn 內嵌 smd_*，覆蓋 data/specials/*.tres）

| 招式 | total | startup | active | 傷害 | hitstun | blockstun | knockback | 備註 |
|---|---|---|---|---|---|---|---|---|
| powerkk | 56 | 18 | 18–（至結束） | 12.0 | 39 | 23 | 600 | three_phase 位移 150px；來源 dav_powerkk.tres（smd 未設定） |
| super | 156 | 16 | 16–10 ⚠️ | 5.0 | 27 | 18 | 200 | freeze；hitbox 窗口解析異常，需人工核對 |
| dpL | 47 | 5 | 5–15 | 8.0 | 24 | 14 | 100 | launcher（force_knockfly）；jump_delay 8f, jump -1500 |
| dpM | 56 ⚠️ | 5 | 5–15 | 8.0 | 24 | 14 | 100 | launcher；⚠️ 動畫長 0f，timer 用 smd duration_frames=56 |
| dpH | 56 ⚠️ | 5 | 5–15 | 10.0 | 39 | 23 | 0 ⚠️ | launcher；⚠️ 動畫長 0f；⚠️ smd 未設 knockback |
| fireballL | 47 | — | — | 11.0 | 18(預設) | 10(預設) | 30 | 投射物；caster 位移 120px；16f 時生成 |
| fireballM | 47 | — | — | 6.0 | 18(預設) | 10(預設) | 30 | 投射物；16f 時生成 |
| fireballH | 47 | — | — | 7.0 | 18(預設) | 10(預設) | 40 | 投射物；16f 時生成 |
| 100p | 74 | 10 | 多段 | 3.0×4 | 見下 | 見下 | 50/120 | multi-hit；位移 200px |

**100p 多段 phases**（每段獨立 hitstun/blockstun）:

| phase | 幀 | 傷害 | hitstun | blockstun | knockback | 備註 |
|---|---|---|---|---|---|---|
| 1 | 10 | 3.0 | 18 | 12 | 50 | |
| 2 | 24 | 3.0 | 18 | 12 | 50 | |
| 3 | 40 | 3.0 | 18 | 12 | 50 | |
| 4 | 54 | 3.0 | 30 | 20 | 120 | force_knockfly（launcher 收尾） |

### 其他動畫（DAV）

| 動畫 | 長度 |
|---|---|
| hit / cr_hit | 27 / 16.8f |
| knockfly | 25f |
| layground | 12f |
| wakeup | 30f |
| landing | 12f |
| throw_enter / throw_seq | 30 / 0 ⚠️ |
| block / cr_block | 15 / 15f |
| dash / backdash | 21 / 24f |

---

## DEN（attack_data = p2_attack_data.tres）

### 站姿攻擊（除 st_hp knockback=120 覆蓋外，其餘為 AttackData.gd 預設）

| 招式 | total | startup | active | recovery | 傷害 | hitstun | blockstun | knockback |
|---|---|---|---|---|---|---|---|---|
| st_lp | 13 | 3 | 3–5 | 8 | 3.0 | 14 | 12 | 60 |
| st_mp | 23 | 6 | 6–9 | 14 | 6.0 | 24 | 16 | 120 |
| st_hp | 31 | 10 | 10–15 | 16 | 9.0 | 33 | 20 | 120 ←p2覆蓋 |
| st_lk | 20 | 6 | 6–（至結束） | — | 3.0 | 30 | 14 | 130 |
| st_mk | 30 | 9 | 9–12 | 18 | 6.0 | 33 | 18 | 130 |
| st_hk | 33 | 14 | 14–18 | 15 | 9.0 | 20 | 22 | 110 |

### 蹲姿攻擊

| 招式 | total | startup | active | recovery | 傷害 | hitstun | blockstun | knockback |
|---|---|---|---|---|---|---|---|---|
| cr_lp | 14 | 3 | 3–6 | 8 | 2.0 | 15 | 10 | 70 |
| cr_mp | 18 | 4 | 4–6 | 12 | 6.0 | 21 | 14 | 80 |
| cr_hp | 18 | 4 | 4–6 | 12 | 9.0 | 30 | 18 | 80 |
| cr_lk | 21 | 8 | 8–14 | 7 | 2.0 | 15 | 12 | 100 |
| cr_mk | 24 | 7 | 7–13 | 11 | 6.0 | 30 | 16 | 140 |
| cr_hk | 40 | 12 | 12–20 | 20 | 9.0 | 39 | 20 | 150 |

### 空中攻擊

| 招式 | total | startup | active | 傷害 | hitstun | blockstun | knockback |
|---|---|---|---|---|---|---|---|
| jump_lp | 18 | 4 | 4–（至結束） | 3.0 | 18 | 12 | 80 |
| jump_mp | 30 | 6 | 6–（至結束） | 6.0 | 24 | 16 | 110 |
| jump_hp | 30 | 12 | 12–18 | 9.0 | 30 | 20 | 120 |
| jump_lk | 30 | 5 | 5–11 | 2.0 | 24 | 14 | 60 |
| jump_mk | 28 | 6 | 6–（至結束） | 5.0 | 30 | 18 | 60 |
| jump_hk | 36 | 10 | 10–16 | 9.0 | 36 | 22 | 70 |

### 特殊招式

| 招式 | total | startup | active | 傷害 | hitstun | blockstun | knockback | 備註 |
|---|---|---|---|---|---|---|---|---|
| spnk | 0 ⚠️ | 14 | 14–16 | 5.0(內嵌) / 12.0(.tres) | 20(內嵌) / 27(.tres) | 10(預設) / 23(.tres) | 70(內嵌) / 280(.tres) | ⚠️ 內嵌 smd 無 duration、動畫長 0f，疑似損毀 |
| hdk | 66 | 6 | 6–10 | 3.0 | 27 | 23 | 290 | 來源 den_hdk.tres（smd 未設定）；位移 200px |
| fireball | 42 | — | — | 5.0(內嵌) / 10.0(.tres) | 20(內嵌) / 24(.tres) | 10(預設) / 14(.tres) | 70(內嵌) / 80(.tres) | ⚠️ 內嵌無 projectile_speed（→800 fallback）；內嵌多餘 move_distance=200 |

### 其他動畫（DEN）

| 動畫 | 長度 |
|---|---|
| hit / cr_hit | 16.8 / 16.8f |
| knockfly | 26f |
| layground | 12f |
| wakeup | 30f |
| landing | 12f |
| throw_enter / throw_seq | 30.1 / 60.1f（throw_seq 15f 時 throw_release） |
| dash / backdash | 18 / 24f |

---

## WOO（WIP 角色）

- **MoveSet 用的是 base `MoveSet.gd`（無 WOOMoveSet）**：move_library 只有通用 `fireball` 一條，
  dp/powerkk/super 動畫存在但**無對應招式資料 → 特殊招式無法觸發**。
- attack_data 引用的是 `p1_attack_data.tres`（DAV 的），數值與 DAV 相同。
- 主要動畫長度: st_mk 40f、cr_mp 24f、cr_mk 18f、powerkk 56f、dp 54f、super 150f、jump_mp 24f、hit 16.8f、knockfly 23f、landing 12f、wakeup 30f。

---

## 系統狀態計時（非招式動畫）

| 狀態 | 時長（邏輯幀 / 物理幀） | 來源 |
|---|---|---|
| landing（無輸入） | 13f / 26 物理 | TimerHandler 幀鎖：著地 tick 種入 5f 強制鎖 → 第 2 個 timer tick checkpoint 換成 0.2s = 25f（`seconds_to_lock_frames`）→ 每物理幀 -1 歸零才清 `is_landing`（test_11/test_16） |
| landing（有輸入中斷） | 2f 強制 + checkpoint 設 1f 後同 tick 歸零 | TimerHandler checkpoint |

> 注意：landing「動畫」12f（0.2s）比狀態鎖先播完；動畫播完不再提前結束狀態
> （`_reset_landing_anim` 有 lock guard），狀態時長一律以幀鎖為準。

---

## ⚠️ 已知數據問題（重構時必須處理）

1. **特殊招式雙真相來源**: `data/specials/*.tres` 與場景內嵌 `smd_*` 數值不同，
   內嵌 export 優先生效。DAV 的 dpL/M/H、fireballL/M/H、100p 與 DEN 的 spnk、fireball
   兩套數值互相矛盾（例: dpM 傷害 5.0 vs 8.0、hitstun 39 vs 24）。
   → Stage 3 收攏為單一 FrameData 資源時，以**內嵌（生效中）數值**為準，.tres 對齊後刪除重複。
2. **動畫長 0f**: DAV dpM/dpH、DEN spnk（及 DEN fireball 的 `fw_mp`）動畫 length=0，
   但 hitbox 軌道 key 在 5–16f。dpM/dpH 靠 smd duration_frames 撐住 timer；DEN spnk 兩者皆無 → 疑似損毀。
3. **DAV super** hitbox disabled 軌道解析出 on=16 > off=10，需人工在編輯器核對。
4. **孤兒資源**: `data/attacks/st_mk_p1.tres` 等引用不存在的 `res://AttackData.gd`（舊格式 startup/active/recovery 欄位），已無代碼引用。
5. **DAV 動畫庫標籤**: `st_LP`（大寫）是 `st_lp` 動畫的顯示標籤；`st_mp` 狀態綁定的動畫標籤是 `davis_atk`。名稱混亂但功能正常（樹狀態名 → 動畫鍵映射正確）。
6. **hitbox 由動畫軌道驅動**: active 窗口 = 動畫 `Hitbox/HitShape:disabled` 的 key 時間，
   與 frame data（hitstun/damage）分開存放。Stage 3 的目標是把 active 窗口也收進 FrameData。

## 驗證方式

本表的命中相關數值（st_mp 傷害 6.0、hitstun 24 邏輯幀 = 48 物理幀、blockstun 16 邏輯幀 = 32 物理幀）
已由 `tests/frame_tests/cases/test_05_hit_damage_hitstun.gd` 與
`test_06_block_no_damage.gd` 自動化驗證（需 Godot 4.6 CLI 執行，見 `tests/frame_tests/README.md`）。
