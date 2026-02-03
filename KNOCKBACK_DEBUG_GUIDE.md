# Knockback 調試指南

## 概述

新的 knockback 反推速度計算系統包含了詳細的調試信息，可以幫助你快速定位和解決問題。所有調試輸出都可以通過 Inspector 中的開關輕鬆啟用/禁用。

---

## 調試開關位置

在 **PushManager** 節點的 Inspector 中：

```
PushManager
├─ Debug Settings (分組)
│  ├─ debug_knockback_velocity_calc (Boolean) ☑️
│  ├─ debug_knockback_execution (Boolean) ☑️
│  └─ debug_position_tracking (Boolean) ☑️
```

### 調試開關說明

| 開關 | 功能 | 預設值 |
|-----|------|-------|
| `debug_knockback_velocity_calc` | 反推速度計算的詳細輸出（初始化時） | ✅ ON |
| `debug_knockback_execution` | Knockback 執行的每幀詳細輸出 | ✅ ON |
| `debug_position_tracking` | 位置追蹤的詳細輸出 | ✅ ON |

**建議**：
- 🎮 遊戲測試時：全部關閉（提高性能）
- 🐛 調試時：全部開啟（獲得完整信息）
- 📊 性能分析時：只開啟 `debug_knockback_execution`

---

## 調試信息說明

### 1️⃣ 反推速度計算（KNOCKBACK VELOCITY CALCULATION）

**觸發時機**: 角色受到 hit/block 時

**輸出示例**:
```
╔════════════════════════════════════════════════════════════════╗
║ KNOCKBACK VELOCITY CALCULATION (反推初始速度)              ║
╚════════════════════════════════════════════════════════════════╝
  🎮 Player: Player_A
  📏 Target distance: 100000 units (100.00 pixels)
  ⏱️  Hitstun frames: 18 (0.300s @ 60 FPS)
  📊 Deceleration Mode: POWER (power: 2.0)
  ∑️  Deceleration sum: 6.143450
  ⚡ Required initial velocity: 16275.67 units
  ⚡ Required initial velocity: 16.28 px/frame

  📈 Frame decay pattern (first 5 & last 5):
    Frame 1 (5.6%): 0.996794
    Frame 2 (11.1%): 0.975609
    Frame 3 (16.7%): 0.944876
    Frame 4 (22.2%): 0.901235
    Frame 5 (27.8%): 0.842639
    ...
    Frame 14 (77.8%): 0.050539
    Frame 15 (83.3%): 0.034404
    Frame 16 (88.9%): 0.020879
    Frame 17 (94.4%): 0.009669
    Frame 18 (100.0%): 0.001235
```

**關鍵數值解析**:
- **Target distance**: 目標 knockback 距離（像素）
- **Deceleration sum**: 所有衰減倍數的總和（越大表示衰減越明顯）
- **Required initial velocity**: 反推出的初始速度
- **Frame decay pattern**: 每幀的衰減倍數（顯示衰減曲線是否合理）

**調試技巧**:
- 如果 Deceleration sum 太大（>10），最終距離會很短
- 如果 Deceleration sum 太小（<3），最終距離會很長
- 衰減倍數應該從 ~1.0 逐漸降到 ~0.0

---

### 2️⃣ Block Knockback 初始化

**觸發時機**: 角色受到 block 攻擊時

**輸出示例**:
```
╔════════════════════════════════════════════════════════════════╗
║ BLOCK KNOCKBACK INITIALIZATION                               ║
╚════════════════════════════════════════════════════════════════╝
  🎮 Player: Player_B
  📍 Position: (340.50, 570.00)
  📏 Block knockback distance: 80.0 pixels
  ⏱️  Blockstun frames: 10 (0.167s @ 60 FPS)
  ⚡ Block knockback initial velocity: 12456.78 units
```

**監控要點**:
- Position 應該是合理的（檢查角色是否在正確位置）
- Block knockback distance 應該小於 hit knockback distance
- Initial velocity 應該是正數且合理

---

### 3️⃣ Hit Knockback 初始化（普通受擊）

**觸發時機**: 角色受到普通攻擊時（非 knockfly）

**輸出示例**:
```
╔════════════════════════════════════════════════════════════════╗
║ HIT KNOCKBACK INITIALIZATION (普通受擊推擊)                 ║
╚════════════════════════════════════════════════════════════════╝
  🎮 Player: Player_A
  📍 Position: (280.75, 570.00)
  📏 Hit knockback distance: 100.0 pixels
  ⏱️  Hitstun frames: 18 (0.300s @ 60 FPS)
  ⚡ Hit knockback initial velocity: 16275.67 units (16.28 px/frame)
  ⏳ Knockback status: Active (started immediately)
```

**監控要點**:
- **Hit knockback status**：
  - `Active (started immediately)` ✅ 正常，立即開始
  - `Pending (waiting for hitstop)` ⏳ 正常，等待 hitstop 結束
- Initial velocity 應該比 block knockback 更大

---

### 4️⃣ Knockback 執行開始（KNOCKBACK EXECUTION START）

**觸發時機**: 角色在第一幀的 knockback 執行時

**輸出示例**:
```
╔════════════════════════════════════════════════════════════════╗
║ KNOCKBACK EXECUTION START                                    ║
╚════════════════════════════════════════════════════════════════╝
  🎮 Player: Player_A
  📍 Initial Position: (280.75, 570.00)
  📍 Initial Fixed Position: (280750, 570000)
  ⚡ Initial Knockback Velocity: 16275.67 units (16.28 px/frame)
  ⏱️  Total Knockback Frames: 18 (0.300s @ 60 FPS)
  📊 Facing Direction: Right (1.0)
  ⏰ Time: 1234.567
```

**監控要點**:
- **Initial Fixed Position**: 應該是 Initial Position × 1000
- **Facing Direction**: 應該是 1.0（右）或 -1.0（左）
- **Initial Knockback Velocity**: 應該與計算階段的值一致

---

### 5️⃣ Knockback 執行進度（KNOCKBACK PROGRESS）

**觸發時機**: 每 6 幀顯示一次進度（或結束時）

**輸出示例**:
```
[KNOCKBACK PROGRESS] Player_A - Frame 6/18 (33.3%)
  📍 Position: (276.50, 570.00)
  ⚡ Velocity: -13200 units (-13.20 px/frame)
  📊 Speed Multiplier: 0.694580
  📏 Distance Moved: 4.25 pixels
```

**監控要點**:
- **Position**: 應該逐漸向後移動
- **Velocity**: 應該逐漸減小（絕對值變小）
- **Speed Multiplier**: 應該從 1.0 逐漸降到 0.0
- **Distance Moved**: 應該逐漸變小

**問題排查**:
- 🚫 Position 沒有改變 → fixed_velocity 可能沒有正確應用
- 🚫 Velocity 沒有減小 → 衰減倍數計算可能有問題
- 🚫 Distance Moved 太大 → 初始速度可能過大

---

### 6️⃣ Knockback 執行結束（KNOCKBACK EXECUTION END）

**觸發時機**: Knockback 完全結束時

**輸出示例**:
```
╔════════════════════════════════════════════════════════════════╗
║ KNOCKBACK EXECUTION END                                      ║
╚════════════════════════════════════════════════════════════════╝
  🎮 Player: Player_A
  📍 Final Position: (180.50, 570.00)
  ⏱️  Expected Duration: 0.300s (18 frames @60 FPS)
  ⏱️  Actual Duration (by frames): 0.300s
  ⏱️  Actual Duration (by clock): 0.301s (可能因 time_scale 而異)
  ✓ Sync Status: ✅ 同步
```

**關鍵計算**:
```
實際向後距離 = Initial Position.x - Final Position.x
           = 280.75 - 180.50
           = 100.25 pixels ✓ (目標: 100 pixels)
```

**同步狀態解析**:
- ✅ 同步：執行時間符合預期（差異 < 50ms）
- ❌ 不同步：執行時間異常（可能因 time_scale、lag 等原因）

---

## 常見調試場景

### 場景 1: 最終距離不符合預期

**現象**: 輸入 knockback=100pixels，實際只移動 60pixels

**調試步驟**:

1. **檢查 Deceleration Sum**
   ```
   預期距離 ≈ 初始速度 / Deceleration Sum
   實際速度 = 預期距離 × Deceleration Sum
   ```

2. **檢查衰減曲線**
   - 打開 `debug_knockback_velocity_calc`
   - 查看 "Frame decay pattern"
   - 確認衰減倍數是否合理

3. **檢查衰減模式參數**
   - 到 PushManager Inspector
   - 檢查 Knockback Deceleration Curve 設定
   - 確認 power/strength/threshold 是否正確

### 場景 2: Knockback 沒有執行

**現象**: 角色受擊但沒有後退

**調試步驟**:

1. **檢查計算階段**
   - 打開 `debug_knockback_velocity_calc`
   - 確認是否輸出 "KNOCKBACK VELOCITY CALCULATION"

2. **檢查執行階段**
   - 打開 `debug_knockback_execution`
   - 確認是否輸出 "KNOCKBACK EXECUTION START"

3. **檢查 PushManager**
   - 確認 PushManager 節點存在
   - 確認在 "push_manager" group 中
   - 檢查是否有腳本錯誤

### 場景 3: 性能下降

**現象**: 有 knockback 時 FPS 下降

**調試步驟**:

1. **關閉所有調試開關**
   ```
   debug_knockback_velocity_calc = FALSE
   debug_knockback_execution = FALSE
   debug_position_tracking = FALSE
   ```

2. **逐個啟用調試開關找出瓶頸**
   - 先啟用 `debug_knockback_velocity_calc`
   - 再啟用 `debug_knockback_execution`
   - 最後啟用 `debug_position_tracking`

3. **監控輸出頻率**
   - "KNOCKBACK VELOCITY CALCULATION" 只在初始時出現一次
   - "KNOCKBACK PROGRESS" 每 6 幀出現一次
   - 總輸出量應該不會很大

---

## 快速檢查清單

在進行調試時，使用以下清單確保所有要素都正確：

### ✅ 初始化檢查
- [ ] 受擊時出現 "KNOCKBACK VELOCITY CALCULATION"
- [ ] Deceleration sum 在 3-10 範圍內
- [ ] Required initial velocity 是正數
- [ ] Player 名稱正確顯示

### ✅ 執行檢查
- [ ] 出現 "KNOCKBACK EXECUTION START"
- [ ] Initial Position 和 Initial Fixed Position 一致（×1000）
- [ ] 出現多個 "KNOCKBACK PROGRESS"
- [ ] Position 逐漸改變，Velocity 逐漸減小

### ✅ 結束檢查
- [ ] 出現 "KNOCKBACK EXECUTION END"
- [ ] Final Position 與初始位置的差距接近目標距離
- [ ] Sync Status 顯示 ✅ 同步

### ✅ 性能檢查
- [ ] 關閉所有調試開關後 FPS 正常
- [ ] 沒有多餘的輸出（例如重複的 "KNOCKBACK START"）
- [ ] 控制台不會被淹沒

---

## 調試技巧

### 1. 同時監控兩個角色
- 在一個受擊/格擋事件中，會有兩份調試輸出
- 分別代表攻擊者和被擊者的 knockback
- 可以對比他們的參數差異

### 2. 使用 Godot 的搜索功能
在 Output Console 中搜索關鍵詞：
- `KNOCKBACK VELOCITY CALCULATION` - 查找所有速度計算
- `KNOCKBACK EXECUTION START` - 查找所有執行開始
- `KNOCKBACK PROGRESS` - 查找所有進度記錄
- `Frame decay pattern` - 查找衰減曲線

### 3. 對比不同的 hitstun 值
```
17 frames (0.283s) vs 18 frames (0.300s)
↓
Deceleration sum 會不同
↓
Required velocity 會自動調整
↓
但最終距離應該相同（都是 100px）
```

### 4. 測試不同的衰減模式
逐一測試 4 種衰減模式，比較：
- Deceleration sum 大小
- Frame decay pattern 曲線
- 最終距離準確度

---

## 數據導出（進階）

如果需要詳細分析，可以將輸出複製到 Excel 進行分析：

```
Frame  | Time(%) | Decay  | Velocity | Position | Distance
-------|---------|--------|----------|----------|----------
1      | 5.6%    | 0.9968 | 16260    | 280.75   | 0.00
2      | 11.1%   | 0.9756 | 15859    | 280.00   | 0.75
3      | 16.7%   | 0.9449 | 15363    | 279.00   | 1.75
...
18     | 100.0%  | 0.0012 | 20       | 180.50   | 100.25
```

使用 Excel 繪製曲線圖，可以清楚看到：
- 速度衰減曲線
- 位置變化曲線
- 是否符合預期的衰減模式

---

## 常見問題 (FAQ)

**Q: 為什麼 Position 的小數位這麼多？**
A: 內部使用 fixed-point 計算，需要轉換回顯示坐標。小數位多是正常的。

**Q: Deceleration sum 應該是多少？**
A: 這取決於衰減模式和 hitstun 幀數。一般在 3-10 範圍內。

**Q: 為什麼 Knockback 執行 START 和最後的 PROGRESS 時間戳不同？**
A: 中間可能跳過了幀，或者有其他邏輯延遲。檢查遊戲的 time_scale。

**Q: 如何加快 knockback 的執行速度？**
A: 不要直接改初始速度，而是減少 hitstun 幀數或調整衰減曲線參數。

**Q: 調試輸出太多怎麼辦？**
A: 關閉 `debug_knockback_execution`，只保留 `debug_knockback_velocity_calc` 和 `debug_position_tracking`。

---

## 相關檔案

- [PushManager.gd](PushManager.gd) - 核心實現
- [Fighter.gd](fighter.gd) - 受擊處理
- [KNOCKBACK_ALGORITHM_REFACTOR.md](KNOCKBACK_ALGORITHM_REFACTOR.md) - 演算法詳細說明
