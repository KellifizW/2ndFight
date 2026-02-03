# Knockback 調試快速參考

## 🎯 三個調試開關位置

**PushManager Inspector** → **Debug Settings**

```
☑️ debug_knockback_velocity_calc   → 反推速度計算輸出
☑️ debug_knockback_execution       → 每幀執行進度輸出  
☑️ debug_position_tracking         → 位置坐標變化輸出
```

## 📊 調試輸出流程

```
受擊事件發生
    ↓
┌─────────────────────────────────────────┐
│ KNOCKBACK VELOCITY CALCULATION           │ ← 計算所需初始速度
│ (反推速度計算)                           │
│                                         │
│ 📏 Target distance: 100 pixels          │
│ ∑️  Deceleration sum: 6.143             │
│ ⚡ Required velocity: 16275.67 units    │
│                                         │
│ 📈 Frame decay pattern                  │
│    Frame 1: 0.996794                    │
│    Frame 2: 0.975609                    │
│    ...                                  │
└─────────────────────────────────────────┘
    ↓ (0.3 秒後)
┌─────────────────────────────────────────┐
│ BLOCK KNOCKBACK INITIALIZATION           │ ← 格擋時推擊初始化
│ 或                                       │
│ HIT KNOCKBACK INITIALIZATION             │ ← 普通受擊推擊初始化
│                                         │
│ 🎮 Player: Player_A                     │
│ 📍 Position: (280.75, 570.00)           │
│ ⚡ Initial velocity: 16275.67 units     │
└─────────────────────────────────────────┘
    ↓ (下一幀)
┌─────────────────────────────────────────┐
│ KNOCKBACK EXECUTION START               │ ← 推擊執行開始
│                                         │
│ 📍 Initial Position: (280.75, 570.00)   │
│ ⚡ Initial Velocity: 16275.67 units     │
│ ⏱️  Total Frames: 18                    │
└─────────────────────────────────────────┘
    ↓ (每 6 幀)
┌─────────────────────────────────────────┐
│ KNOCKBACK PROGRESS (Frame 6/18)         │ ← 進度更新
│                                         │
│ 📍 Position: (276.50, 570.00)           │
│ ⚡ Velocity: -13200 units               │
│ 📊 Speed Multiplier: 0.694580           │
│ 📏 Distance Moved: 4.25 pixels          │
└─────────────────────────────────────────┘
    ↓ (每 6 幀 × 3 次)
┌─────────────────────────────────────────┐
│ KNOCKBACK EXECUTION END                 │ ← 推擊執行結束
│                                         │
│ 📍 Final Position: (180.50, 570.00)     │
│ ⏱️  Expected Duration: 0.300s           │
│ ✓ Sync Status: ✅ 同步                  │
│                                         │
│ 📊 實際距離 = 280.75 - 180.50 = 100.25 px
└─────────────────────────────────────────┘
```

## 🔍 關鍵數值檢查清單

### 計算階段
- [ ] **Deceleration sum**: 應該在 **3-10** 之間
  - 太小 (<3): 距離會過遠
  - 太大 (>10): 距離會過短
  - 目標: ~6-7

- [ ] **Required velocity**: 應該是 **正數**
  - 計算: Target distance × 1000 / Deceleration sum
  - 範圍: 10,000-100,000 units

- [ ] **Frame decay pattern**: 應該 **逐漸下降**
  - Frame 1: ~1.0
  - Frame N/2: ~0.25-0.5
  - Frame N: ~0.01

### 初始化階段
- [ ] **Position**: 角色應在 **正確位置**
  - 檢查 x, y 座標是否在合理範圍

- [ ] **Initial Velocity**: 應與計算階段 **一致**
  - ±100 單位誤差內可接受

- [ ] **Facing Direction**: **1.0** (右) 或 **-1.0** (左)

### 執行階段
- [ ] **Position 變化**: 應 **逐漸向後**
  - x 坐標應遞減（如果向左）
  - 每次變化應越來越小

- [ ] **Velocity 變化**: 應 **逐漸減小**
  - 絕對值應每幀下降
  - 最後應接近 0

- [ ] **Speed Multiplier**: 應從 **1.0 → 0.0**
  - 每幀下降應逐漸變慢

### 結束階段
- [ ] **Final Position**: 距初始位置 **≈ 目標距離**
  - 誤差: ±5% 以內

- [ ] **Sync Status**: 應為 **✅ 同步**
  - 時間誤差: ±50ms 以內

## 🚨 常見問題快速診斷

| 現象 | 可能原因 | 檢查方式 |
|------|--------|--------|
| 最終距離太短 | Deceleration sum 太大 | 查看計算輸出中的 Deceleration sum |
| 最終距離太遠 | Deceleration sum 太小 | 調整衰減曲線參數 (power/strength) |
| 角色沒有後退 | fixed_velocity 未應用 | 確認 PushManager.is_physics_process 執行 |
| 速度沒有衰減 | Speed Multiplier 計算錯誤 | 檢查衰減模式是否正確 |
| 輸出為空 | 調試開關未啟用 或 skip_push=true | 開啟調試開關，檢查 skip_push 值 |
| 時間不同步 | time_scale 改變 或 幀率不穩 | 檢查 Engine.time_scale，監控 FPS |

## 📋 調試工作流

### Step 1: 啟用所有調試開關
```
PushManager → Debug Settings
  debug_knockback_velocity_calc = TRUE ☑️
  debug_knockback_execution = TRUE ☑️
  debug_position_tracking = TRUE ☑️
```

### Step 2: 執行一次 hit/block 事件
- 讓 Player A 攻擊 Player B
- Player B 受擊或格擋

### Step 3: 收集輸出信息
```
Output Console 中應出現：
1. KNOCKBACK VELOCITY CALCULATION      ← 速度計算是否正確
2. HIT/BLOCK KNOCKBACK INITIALIZATION  ← 初始化是否正確
3. KNOCKBACK EXECUTION START           ← 開始位置是否正確
4. KNOCKBACK PROGRESS (×3)             ← 進度是否正常推進
5. KNOCKBACK EXECUTION END             ← 最終位置是否符合預期
```

### Step 4: 驗證關鍵數值
```
對照表:
✓ Deceleration sum:        6.14 (3-10 範圍內)
✓ Initial Position:        (280.75, 570.00)
✓ Final Position:          (180.50, 570.00)
✓ 實際距離:                100.25 pixels ≈ 100.0 (目標)
✓ Sync Status:             ✅ 同步
```

### Step 5: 關閉調試開關（性能優化）
```
完成調試後，在遊戲運行時關閉所有開關以提升性能
```

## 📱 關鍵輸出行示例解讀

### ✅ 正常的計算輸出
```
∑️  Deceleration sum: 6.143450
⚡ Required initial velocity: 16275.67 units

➜ 解釋: 要達到 100px 距離，需要 16275.67 units 初速
➜ 檢查: 6.14 在合理範圍內
```

### ✅ 正常的初始化輸出
```
📏 Hit knockback distance: 100.0 pixels
⚡ Hit knockback initial velocity: 16275.67 units (16.28 px/frame)

➜ 解釋: 初速約 16px/幀，共 18 幀
➜ 檢查: 初速與計算階段一致
```

### ✅ 正常的執行進度
```
Frame 6/18 (33.3%)
⚡ Velocity: -13200 units (-13.20 px/frame)
📊 Speed Multiplier: 0.694580

➜ 解釋: 6 幀後，速度衰減到 69% (原來的 16.28 × 0.695 ≈ 11.3)
➜ 檢查: 衰減倍數逐漸變小是正常的
```

### ✅ 正常的結束輸出
```
📍 Final Position: (180.50, 570.00)
✓ Sync Status: ✅ 同步

➜ 實際距離 = 280.75 - 180.50 = 100.25 pixels
➜ 目標距離 = 100.0 pixels
➜ 誤差 = 0.25 pixels (0.25%) ✓ 優秀
```

## ⚙️ 衰減模式參考表

| 模式 | 參數 | Deceleration Sum | 感受 |
|------|------|-----------------|------|
| POWER | power=1.0 | ~9.5 | 線性衰減，速度均勻 |
| POWER | power=2.0 | ~6.1 | 二次衰減，尾部快 |
| POWER | power=3.0 | ~4.5 | 三次衰減，尾部很快 |
| EASE_OUT | strength=1.5 | ~5.8 | 柔和衰減，舒適 |
| EASE_IN_OUT | strength=1.5 | ~6.2 | S 形衰減，自然 |
| LINEAR_THRESHOLD | threshold=0.3 | ~6.9 | 線性→快速衰減 |

## 📊 實例數據解析

**假設**: knockback=100px, hitstun=18frames, mode=POWER(2.0)

```
計算結果:
  Deceleration sum = 6.143450
  Required velocity = 16275.67 units

執行進度:
  Frame  1: Pos=280.75, Vel=-16275, Multiplier=0.996794, Distance=16.3px
  Frame  6: Pos=276.50, Vel=-13200, Multiplier=0.694580, Distance=13.2px (累計: 45px)
  Frame 12: Pos=183.75, Vel= -5200, Multiplier=0.197530, Distance= 5.2px (累計: 97px)
  Frame 18: Pos=180.50, Vel=   -20, Multiplier=0.001235, Distance= 0.02px (累計: 100.25px)

驗證:
  實際距離 = 280.75 - 180.50 = 100.25px ✓
  目標距離 = 100.00px ✓
  誤差 = 0.25px (0.25%) ✓✓✓ 完美!
```

## 🎓 學習資源

- 詳細說明: [KNOCKBACK_ALGORITHM_REFACTOR.md](KNOCKBACK_ALGORITHM_REFACTOR.md)
- 完整指南: [KNOCKBACK_DEBUG_GUIDE.md](KNOCKBACK_DEBUG_GUIDE.md)
- 代碼位置: [PushManager.gd](PushManager.gd) (L110-195)
- 代碼位置: [Fighter.gd](fighter.gd) (L220-440)

---

**最後更新**: 2026-02-03  
**狀態**: ✅ 完成並驗證  
**調試工具**: 完全集成到 PushManager Inspector
