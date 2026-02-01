# Knockback 與 Hitstun 同步修復

## 問題分析

**日誌顯示的不同步情況：**
```
預期 knockback 持續時間: 0.55秒 (55 幀)
實際 knockback 持續時間: 0.319秒 (約 19 幀)
```

### 根本原因
存在**兩個獨立的時間系統**造成不同步：

1. **Hitstun 系統 (固定幀數)**：
   - 使用 `hitstun_frames` (frame counter)
   - 在 `fighter.gd` 的 `_physics_process()` 中每幀遞減 1
   - 精確控制，與物理幀完全同步

2. **Knockback 系統 (Delta Time)** ❌ **過時**
   - 使用 `hit_push_timer` (delta-based timer)
   - 在 `PushManager.gd` 中用 `delta` 遞減
   - Delta 值不一定等於 1/60（取決於幀率波動）
   - 導致實際持續時間 != 預期持續時間

### 為什麼會造成 0.55s → 0.319s 的差異？
- 設置: `hit_push_timer = 0.55s`
- 但實際 delta sum 小於 0.55s（可能只累積約 0.32s）
- 導致 knockback 提前結束

## 解決方案

### 修改 1: 在 `fighter.gd` 中添加固定幀變數

```gdscript
# ── 固定幀數控制（hitstun & blockstun & knockback 都使用）──
var hitstun_frames: int = 0          # hitstun 固定幀數
var blockstun_frames: int = 0        # blockstun 固定幀數
var knockback_frames: int = 0        # knockback 固定幀數（與 hitstun 同步）❌ NEW
var knockback_delay_frames: int = 0  # knockback 延遲幀數 ❌ NEW
```

### 修改 2: 在 `fighter.gd` 的 `_physics_process()` 中添加 knockback_delay_frames 處理

```gdscript
# ── 【固定幀數 knockback_delay】──
if knockback_delay_frames > 0:
    knockback_delay_frames -= 1
    # 延遲期間不移動
    if knockback_delay_frames <= 0:
        # 延遲結束，啟動 knockback
        knockback_frames = hitstun_frames  # 同步 knockback 幀數與當前 hitstun 幀數
```

### 修改 3: 在 `fighter.gd` 的 `take_hit()` 中設置固定幀 knockback

```gdscript
# 以前（有問題）:
knockback_total_time = hitstun_duration  # ❌ 基於秒數，不精確
hit_push_delay_timer = knockback_delay_duration  # ❌ Delta-based

# 現在（修正）:
knockback_frames = hit_frames  # ✅ 基於幀數，精確
knockback_delay_frames = sec_to_frames(knockback_delay_duration)  # ✅ 轉換為幀數
```

### 修改 4: 在 `PushManager.gd` 中用固定幀系統替換舊的 delta-based 系統

**舊系統：**
```gdscript
# ❌ 問題: hit_push_timer 使用 delta 遞減，不精確
if player.hit_push_timer > 0 and player.knockback_total_time > 0:
    player.hit_push_timer -= delta  # ❌ 不精確
    var remaining_ratio: float = player.hit_push_timer / player.knockback_total_time
```

**新系統：**
```gdscript
# ✅ 精確: knockback_frames 基於幀計數
if player.knockback_frames > 0:
    var total_knockback_frames = player.hitstun_frames
    var remaining_ratio: float = player.knockback_frames / float(total_knockback_frames)
    var speed_multiplier: float = remaining_ratio * remaining_ratio  # 二次方衰減
    player.fixed_velocity.x = int(-player.hit_push_velocity * speed_multiplier * player.facing_direction)
    
    player.knockback_frames -= 1  # ✅ 每幀精確遞減 1
```

## 驗證步驟

測試時應該看到：

1. **KNOCKBACK SETUP** 日誌：
   ```
   - Knockback Duration: 0.55s (66 frames)
   - knockback_frames: 66, knockback_delay_frames: 0
   ```

2. **KNOCKBACK END** 日誌：
   ```
   - Expected Duration: 0.550s (66 frames)
   - Actual Duration: 0.550s  ✅ 應該相等
   - Frames Duration: 0.550s
   ```

3. **日誌對比**：
   ```
   [FIXED-FRAME HITSTUN START] DEN 進入 hit，66 幀 (0.550秒)
   [FIXED-FRAME HITSTUN END] DEN 完全結束！
   [KNOCKBACK END] DEN
     - Expected Duration: 0.550s (66 frames)
     - Actual Duration: 0.550s  ✅ 精確相等
   ```

## 修改文件列表

1. **fighter.gd**
   - 添加 `knockback_frames`, `knockback_delay_frames` 變數
   - 在 `_physics_process()` 中添加 knockback_delay_frames 處理
   - 在 `take_hit()` 中改用固定幀系統設置 knockback

2. **PushManager.gd**
   - 移除舊的 `hit_push_delay_timer` delta-based 邏輯
   - 改用 `knockback_frames` 的固定幀系統
   - 更新日誌輸出格式

## 向後兼容性

- 保留舊的 delta-based 變數（`hit_push_timer`, `knockback_total_time` 等）以避免破壞其他代碼
- 新的固定幀系統優先被使用，舊系統自動被忽略
- 不影響其他模組（blockstun, AI 等）

## 相關概念

- **Hitstun**: 被擊中後的受擊時間（固定幀數控制）
- **Blockstun**: 格擋時的受擊時間（固定幀數控制）
- **Knockback**: 被擊推動的水平位移（現已改用固定幀數控制） ✅
- **Knockback Delay**: 延遲後再開始 knockback（現已改用固定幀數控制） ✅

---

**修復日期**: 2026-02-01
**修復人**: Copilot
**驗證方式**: 遊戲日誌對比 + 幀計數驗證
