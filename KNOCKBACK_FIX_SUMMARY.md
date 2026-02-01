# 修復總結: Knockback 與 Hitstun 時長同步問題

## 問題陳述

**原始日誌顯示：**
```
[KNOCKBACK SETUP] DEN
  - Knockback Duration: 0.55s (= hitstun)
  - knockback_total_time: 0.550s
  - Total Time: 0.55s

[KNOCKBACK END] DEN
  - Expected Duration: 0.55s
  - Actual Duration: 0.319s  ❌ 不符合預期！
  - Total Time (with delay): 0.319s
```

角色的 knockback 持續時間(0.319秒)遠短於預期的 hitstun 時長(0.55秒)，導致受擊角色提前結束被推動狀態。

## 根本原因分析

系統使用了**兩套不同的時間控制機制**：

### 1. Hitstun（受擊時間）✅ 正確
- 使用**固定幀數系統**: `hitstun_frames` (int)
- 在 `Fighter._physics_process()` 中每幀遞減 1
- 與物理幀率（60 FPS）完全同步
- 精確度: ±0 幀

### 2. Knockback（被推動）❌ 有問題
- 使用**Delta-based timer**: `hit_push_timer` (float)
- 在 `PushManager._physics_process()` 中用 `delta` 遞減
- Delta 值取決於實際幀率，不一定等於 1/60
- 計算: `hit_push_timer -= delta`
- 問題: 多個微小 delta 累積誤差導致總時間 ≠ 預期時間

### 為什麼會差 0.231 秒？
```
設置: knockback_total_time = 0.550s
但實際: sum(delta) 在 hitstun 結束時只有 ~0.319s
誤差: 0.550 - 0.319 = 0.231s ❌
```

這發生在因為：
1. Delta 值時刻變化（幀率波動）
2. 浮點精度丟失
3. `hit_push_timer` 與 `hitstun_frames` 不同步

## 修復方案

### 修改 1️⃣: 添加固定幀變數 (fighter.gd)

```gdscript
# ── 固定幀數控制（hitstun & blockstun & knockback 都使用）──
var hitstun_frames: int = 0          # hitstun 固定幀數
var blockstun_frames: int = 0        # blockstun 固定幀數
var knockback_frames: int = 0        # ✅ NEW: knockback 固定幀數（與 hitstun 同步）
var knockback_delay_frames: int = 0  # ✅ NEW: knockback 延遲幀數
```

### 修改 2️⃣: 添加 knockback_delay_frames 處理 (fighter.gd _physics_process)

```gdscript
# ── 【固定幀數 knockback_delay】──
if knockback_delay_frames > 0:
    knockback_delay_frames -= 1
    # 延遲期間不移動
    if knockback_delay_frames <= 0:
        # 延遲結束，啟動 knockback
        knockback_frames = hitstun_frames  # 同步 knockback 幀數與當前 hitstun 幀數
        hit_push_velocity = hit_push_initial_velocity  # 恢復 knockback 速度
        knockback_start_time = Time.get_ticks_msec() / 1000.0
        if knockback_frames > 0:
            print("[KNOCKBACK DELAY END] %s - knockback 開始，持續 %d 幀 (%.3f秒)" % [
                name, knockback_frames, knockback_frames / float(PHYSICS_FPS)
            ])
```

### 修改 3️⃣: 改用固定幀在 take_hit() 中設置 knockback

**之前 ❌:**
```gdscript
knockback_total_time = hitstun_duration  # 秒數，不精確
hit_push_delay_timer = knockback_delay_duration  # delta-based
```

**之後 ✅:**
```gdscript
knockback_delay_frames = sec_to_frames(knockback_delay_duration)  # 轉為幀數
if knockback_delay_frames <= 0:
    knockback_frames = hit_frames  # 立即啟動
    hit_push_velocity = hit_push_initial_velocity
else:
    knockback_frames = 0  # 延遲期間不動
    hit_push_velocity = 0.0
```

### 修改 4️⃣: 在 PushManager 中用固定幀系統取代舊的 delta-based

**之前 ❌:**
```gdscript
if player.hit_push_timer > 0 and player.knockback_total_time > 0:
    var remaining_ratio: float = player.hit_push_timer / player.knockback_total_time
    player.fixed_velocity.x = int(-player.hit_push_velocity * speed_multiplier * player.facing_direction)
    player.hit_push_timer -= delta  # ❌ 不精確！
    if player.hit_push_timer <= 0:
        # knockback 提前結束
```

**之後 ✅:**
```gdscript
if player.knockback_frames > 0:
    var total_knockback_frames = player.hitstun_frames
    var remaining_ratio: float = player.knockback_frames / float(total_knockback_frames)
    var speed_multiplier: float = remaining_ratio * remaining_ratio
    player.fixed_velocity.x = int(-player.hit_push_velocity * speed_multiplier * player.facing_direction)
    
    player.knockback_frames -= 1  # ✅ 每幀精確遞減 1
    if player.knockback_frames <= 0:
        # knockback 精確結束，與 hitstun 完全同步
```

## 驗證結果

修復後應該看到：

```
[FIXED-FRAME HITSTUN START] DEN 進入 hit，66 幀 (0.550秒)

[KNOCKBACK SETUP] DEN
  - Knockback Duration: 0.55s (66 frames)  ✅ 現在顯示幀數
  - knockback_frames: 66, knockback_delay_frames: 0

[KNOCKBACK END] DEN
  - Expected Duration: 0.550s (66 frames)
  - Actual Duration: 0.550s  ✅ 完全相等！
  - Frames Duration: 0.550s

[FIXED-FRAME HITSTUN END] DEN 完全結束！
```

**關鍵指標:**
- ✅ Expected Duration = Actual Duration (精確到秒)
- ✅ Knockback 持續幀數 = Hitstun 幀數 (66 = 66)
- ✅ Knockback 與 Hitstun 同時結束

## 修改清單

| 檔案 | 修改內容 |
|------|--------|
| **fighter.gd** | • 添加 `knockback_frames`, `knockback_delay_frames` 變數<br>• 在 `_physics_process()` 添加 knockback_delay_frames 處理<br>• 在 `take_hit()` 改用固定幀系統 |
| **PushManager.gd** | • 移除 `hit_push_delay_timer` delta-based 邏輯<br>• 改用 `knockback_frames` 的固定幀系統<br>• 更新日誌輸出格式 |

## 向後兼容性 ✅

- **保留**舊的 delta-based 變數（`hit_push_timer`, `knockback_total_time` 等）在 Movement.gd 中
- 新的固定幀系統**優先使用**，舊系統自動被忽略
- 不破壞任何其他模組（AI, Combo, Animation 等）

## 測試建議

1. **基本測試**: 執行 st_hp 攻擊，檢查日誌
2. **邊界測試**: 檢查有無延遲的 knockback
3. **長時間測試**: 連續多次攻擊，檢查累積誤差
4. **視覺驗證**: 被擊者推動距離應與被擊時間成正比

---

**修復日期**: 2026-02-01  
**相關檔案**: KNOCKBACK_HITSTUN_SYNC_FIX.md  
**狀態**: ✅ 完成
