# Knockback 時長同步 - 完整修復分析

## 問題描述

**原始報告**: knockback 的時長 (0.181s) 遠短於 hitstun (0.550s)，導致角色被擊飛時立即停止移動，但仍然無法行動。

### 日誌證據
```
[KNOCKBACK SETUP] DEN
  - Knockback Duration: 0.55s (66 frames)  ✅ 設定正確
  - knockback_frames: 66, knockback_delay_frames: 0

[KNOCKBACK END] DEN
  - Expected Duration: 1.100s (66 frames)  ❌ 不符！應為 0.55s
  - Actual Duration: 0.181s  ❌ 遠短於預期
  - Sync Status: ❌ 不同步
```

---

## 根本原因分析

### 問題 1️⃣: Hitstun 和 Knockback 時間系統不同步

**發現經過**:
1. Hitstun 使用 **固定幀數系統**: `hitstun_frames` (整數，每幀 -1)
2. Knockback 原本使用 **Delta計時系統**: `hit_push_timer` (浮點數，累加 delta)
3. Delta 系統不可靠，因為 `Σ(delta) ≠ expected_time` 當 physics_fps 變化時

**修復方案**: 改為 **固定幀數系統** (`knockback_frames`)

---

### 問題 2️⃣: Expected Duration 計算使用硬編碼 FPS

**發現**: PushManager.gd 行 108 原為:
```gdscript
print("  - Expected Duration: %.3fs (%d frames)" % [expected_frames / 60.0, expected_frames])
```

**問題**: 硬編碼 `60.0` 而實際 PHYSICS_FPS 為 120
- 計算: 66 / 60.0 = 1.100s ❌ (應為 66 / 120.0 = 0.550s)

**修復**: 使用動態 FPS
```gdscript
var physics_fps = Engine.physics_ticks_per_second
print("  - Expected Duration: %.3fs (%d frames @%d FPS)" % [expected_frames / float(physics_fps), expected_frames, physics_fps])
```

---

### 問題 3️⃣: Initial Knockback 值保存不一致

**發現**: 當計算衰減曲線時，使用的 `hitstun_frames` 在 hitstun 執行中不斷遞減:
```gdscript
var remaining_ratio: float = player.knockback_frames / float(hitstun_frames)  // ❌ hitstun_frames 在變！
```

**修復**: 保存初始值，不使用實時遞減的值
```gdscript
var initial_knockback_frames: int = 0  // ✅ 新增
// 在 take_hit() 中
initial_knockback_frames = hit_frames  // 保存初始值
// 在 PushManager 中
var remaining_ratio: float = player.knockback_frames / float(player.initial_knockback_frames)  // ✅ 使用初始值
```

---

### 問題 4️⃣: **【最關鍵】Knockback 被 hitstun 結束中斷**

**根本原因** 🔴:

PushManager 中的 knockback 執行被嵌套在 `if player.is_hit:` 檢查內:

```gdscript
// ❌ 原有結構
if player.is_hit:                    // ← 當 hitstun 結束時，is_hit = false
    if player.hit_timer > 0:
        if player.knockback_frames > 0:  // ← 無法執行！
            // knockback 邏輯
```

**執行流程**:
1. Frame 1-66: hitstun 執行，`is_hit = true`，knockback 也執行
2. Frame 66: hitstun_frames 達到 0，fighter.gd 設置 `is_hit = false`
3. Frame 67: PushManager 檢查 `if player.is_hit:` → **false** → 整個 knockback 塊被跳過！
4. 結果: knockback 在 66 幀時立即停止 (實際只執行了 ~0.181s)

**修復方案**: 將 knockback 移出 `is_hit` 檢查，使其獨立執行

```gdscript
// ✅ 新結構 - knockback 獨立執行
if player.knockback_frames > 0:
    // knockback 邏輯 - 不受 is_hit 影響
    player.knockback_frames -= 1

if player.is_hit:
    if player.hit_timer > 0:
        // hitstun 邏輯 - 獨立管理
```

---

## 修復清單

### fighter.gd 修改

**1. 新增固定幀數變數**:
```gdscript
var knockback_frames: int = 0              # 當前 knockback 剩餘幀數
var initial_knockback_frames: int = 0      # 保存初始值（計算用）
var knockback_delay_frames: int = 0        # Knockback 延遲幀數
var knockback_start_time: float = 0.0      # 計時用（毫秒 → 秒）
```

**2. 在 _physics_process() 中新增 knockback_delay 處理**:
```gdscript
if knockback_delay_frames > 0:
    knockback_delay_frames -= 1
    if knockback_delay_frames <= 0:
        knockback_frames = hitstun_frames
        initial_knockback_frames = hitstun_frames
        hit_push_velocity = hit_push_initial_velocity
        knockback_start_time = Time.get_ticks_msec() / 1000.0
```

**3. 在 take_hit() 中初始化 knockback**:
```gdscript
knockback_frames = hit_frames
initial_knockback_frames = hit_frames
hit_push_velocity = hit_push_initial_velocity
knockback_start_time = Time.get_ticks_msec() / 1000.0
```

### PushManager.gd 修改

**1. 【最關鍵】將 knockback 執行移出 is_hit 檢查**:

```gdscript
// ─────────────────────────────────────────────
// Knockback 執行 - 獨立於 hitstun
// ─────────────────────────────────────────────
if player.knockback_frames > 0:            # ← 獨立條件檢查！
    # 計算衰減倍數
    var total_knockback_frames = player.initial_knockback_frames
    var remaining_ratio: float = player.knockback_frames / float(total_knockback_frames)
    var speed_multiplier: float = remaining_ratio * remaining_ratio
    
    player.fixed_velocity.x = int(-player.hit_push_velocity * speed_multiplier * player.facing_direction)
    player.knockback_frames -= 1            # 每幀遞減 1
    
    if player.knockback_frames <= 0:
        # 結束邏輯
        player.knockback_frames = 0
        player.fixed_velocity.x = 0

// ─────────────────────────────────────────────
// Hitstun (舊的 Delta 系統，保留兼容)
// ─────────────────────────────────────────────
if player.is_hit:
    if player.hit_timer > 0:
        player.hit_timer -= delta
        if player.hit_timer <= 0:
            player.is_hit = false
```

**2. 更新 FPS 計算**:
```gdscript
var physics_fps = Engine.physics_ticks_per_second
print("  - Expected Duration: %.3fs (%d frames @%d FPS)" % [expected_frames / float(physics_fps), expected_frames, physics_fps])
```

---

## 預期效果

修復後，日誌應顯示:

```
[KNOCKBACK SETUP] DEN
  - Knockback Duration: 0.55s (66 frames)

[KNOCKBACK PROGRESS] DEN - 0.0% complete, remaining: 66 frames...
[KNOCKBACK PROGRESS] DEN - 9.1% complete, remaining: 60 frames...
[KNOCKBACK PROGRESS] DEN - 18.2% complete, remaining: 54 frames...
...
[KNOCKBACK PROGRESS] DEN - 100.0% complete, remaining: 0 frames

[KNOCKBACK END] DEN
  - Expected Duration: 0.55s (66 frames @120 FPS)  ✅
  - Actual Duration: 0.55s                         ✅
  - Sync Status: ✅ 同步
```

---

## 技術細節

### 固定幀數系統 vs Delta 計時系統

| 特性 | 固定幀數 | Delta 計時 |
|-----|--------|----------|
| 精度 | 完全精確 | 誤差累積 |
| 計算 | 整數運算 | 浮點運算 |
| 行為 | 確定性 | 不確定性 |
| 物理速率變化時 | 自動適應 | 需手動修正 |
| 用途 | **遊戲邏輯**✅ | UI 動畫、漸變效果 |

**結論**: 所有影響遊戲邏輯的計時（hitstun, blockstun, knockback, combo window）應使用固定幀數系統。

### sec_to_frames 轉換

```gdscript
static var PHYSICS_FPS: int = 60  // 初始值

func _enter_tree() -> void:
    PHYSICS_FPS = Engine.physics_ticks_per_second  // 讀取實際值

func sec_to_frames(seconds: float) -> int:
    return int(round(seconds * PHYSICS_FPS))

// 範例
sec_to_frames(0.550) = round(0.550 * 120) = 66 frames  ✅
sec_to_frames(0.20) = round(0.20 * 120) = 24 frames    ✅
```

---

## 驗證步驟

1. ✅ 編譯通過 (無語法錯誤)
2. ⏳ 運行遊戲，查看日誌輸出
3. ⏳ 驗證 `[KNOCKBACK END]` 顯示 Expected Duration ≈ Actual Duration (誤差 < 0.05s)
4. ⏳ 驗證角色被擊飛時完整執行整個 knockback 時間
5. ⏳ 測試邊界情況：空中受擊、多次連擊、blockstun 期間受擊

---

## 相關檔案

- `fighter.gd`: 固定幀數系統定義、take_hit() 初始化
- `PushManager.gd`: knockback 執行邏輯、速度計算
- `Movement.gd`: 保留舊 delta 計時變數（向後兼容）

---

## 總結

**四個層次的問題修復**:
1. ✅ 時間系統統一 (Delta → 固定幀數)
2. ✅ FPS 硬編碼移除 (60.0 → 動態 FPS)
3. ✅ 初始值保存 (使用 initial_knockback_frames)
4. ✅ **【最關鍵】結構分離** (knockback 獨立於 is_hit)

**預期結果**: knockback 時長將精確等於 hitstun 時長，角色被擊飛時會完整執行整個被擊時間。
