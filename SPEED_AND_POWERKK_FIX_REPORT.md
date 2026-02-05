# 🎮 遊戲速度和 powerkk 問題 - 完整修復指南

## 📋 已應用的修復

### ✅ 已完成的改動

1. **MoveSet.gd - powerkk 計算修正** (Line 235-241)
   ```gdscript
   var duration_seconds = move_data.duration / 60.0  // ✓ 正確轉換
   var base_speed = (move_data.move_distance / duration_seconds) * world.SIMULATION_SCALE
   ```
   - 確保 duration（56 幀）正確轉換為秒數（0.933s）
   - 計算出正確的基礎速度

2. **MoveSet.gd - 移動參數詳細日誌** (Line 250-262)
   ```gdscript
   [MOVE DEBUG] 移動距離: 150 px, 時長: 56 frm (0.933 s), 速度: 160.7 px/s (2.67 px/frame @60FPS)
   ```
   - 動畫播放時輸出移動速度，便於診斷

3. **fighter.gd - PHYSICS_FPS 成正修正** (Line 5)
   - 改為 120（從錯誤的 60）

4. **新增診斷工具**
   - `GameSpeed_Debugger.gd` - 監視遊戲速度
   - `TimingDiagnosticTool.gd` - 詳細的時間診斷
   - Movement.gd 中添加遊戲速度監視日誌

---

## 🔍 診斷遊戲加速問題的方法

### 方法 1：檢查物理幀速率
```
觀察控制台輸出：
[GAME SPEED] @X.XXX秒 | Δt=0.008333(120.0 FPS) | Expected: 1/120
```
- **正常**：Δt ≈ 0.008333（1/120 秒）
- **加速**：Δt < 0.008333
- **減速**：Δt > 0.008333

### 方法 2：檢查動畫播放速度
觀察日誌中的：
```
[SPECIAL MOVE PARAMETERS] 'powerkk'
  進度: X/56 幀
  速度: 160.7 px/秒
```
- 檢查進度是否以預期速率遞減（每幀-1 或 -2 幀）

### 方法 3：驗證 powerkk 移動距離
運行 powerkk，觀察是否確實移動了 ~150 像素
```
計算：160.7 px/秒 × 0.933秒 ≈ 150 像素
```

---

## 🐛 powerkk 移動距離未實現的原因

根據代碼分析，powerkk 使用了 **三相加速曲線**：

```gdscript
power kk: duration=56 frm, move_distance=150 px, acceleration_curve="three_phase"
```

**三相系統構成**：
1. **靜止階段** (0-25%)：固定 25% 持續時間，速度 = 0
2. **加速階段** (25%-45%)：20% 持續時間，速度從 0 加速到最大
   3. **減速階段** (45%-100%)：55% 持續時間，速度從最大減速到 0

**可能的問題**：
- 三相運動系統可能還未正確實現
- 初始速度設為 0，由 AttackMovementHandler 控制實際速度
- 需要檢查 AttackMovementHandler 是否存在及運作

---

## ✅ 驗證修復的檢查清單

在遊戲中執行以下測試：

### 1️⃣ 測試 Fireball（應該會移動）
- [ ] Fireball 速度正常（應在 ~0.7 秒內飛過屏幕）
- [ ] 日誌顯示：`[MOVE DEBUG] 移動距離: 600.0 px, 時長: 42 frm ...`

### 2️⃣ 測試 powerkk（應該會前衝）
- [ ] powerkk 執行時角色應移動 ~150 像素
- [ ] 日誌顯示：`[MOVE DEBUG] 移動距離: 150.0 px, 時長: 56 frm (0.933 s), 速度: 160.7 px/s`
- [ ] 三相曲線應正確應用（開始靜止→加速→減速）

### 3️⃣ 檢查遊戲速度
- [ ] 攻擊動畫時長符合預期（例如 st_mp 應為 ~0.5 秒）
- [ ] 受擊持續時間正常（24 邏輯幀 hitstun ≈ 0.4 秒）
- [ ] 沒有動畫明顯加速或減速的感覺

### 4️⃣ 觀察控制台日誌
- [ ] 每 3 秒看到 `[TIMING DIAGNOSTIC]` 報告
- [ ] 物理 FPS ≈ 120.0（誤差 <5%）
- [ ] 邏輯幀計數合理（大約物理幀的 1/2）

---

## 🚀 後續動作

如果上述檢查發現問題，按優先級：

### Priority 1：確認物理幀速率
```gdscript
// 在 world.gd _process 中添加
print("Engine.physics_ticks_per_second: %d" % Engine.physics_ticks_per_second)
```

### Priority 2：確認 powerkk 的三相曲線實現
搜索 `three_phase` 或 `三相` 的實現位置，確認是否正確

### Priority 3：確認 AttackMovementHandler 的速度應用
檢查是否存在 AttackMovementHandler 並正確應用了 base_speed

---

## 📊 關鍵數值參考

| 項目 | 預期值 | 備註 |
|------|--------|------|
| 物理幀率 | 120 FPS | Engine.physics_ticks_per_second |
| 邏輯幀率 | 60 FPS | LOGIC_FPS 常數 |
| 幀轉換比 | 2:1 | 每個邏輯幀 = 2 物理幀 |
| powerkk 時長 | 56 幀 (0.933s) | 邏輯幀 @ 60 FPS |
| powerkk 距離 | 150 像素 | 完整執行時 |
| powerkk 速度 | 160.7 px/s | 平均速度 |
| Fireball 時長 | 42 幀 (0.700s) | 邏輯幀 @ 60 FPS |
| 標準 Hitstun | 24 幀邏輯 = 48 幀物理 | st_mp 等量 |

---

**生成時間**：2026-02-05  
**診斷工具狀態**：✅ 已部署  
**修復狀態**：⚠️ 待播放測試驗證
