# 🧪 Knockback 同步 - 測試檢查表

## 🎬 測試場景

在遊戲中執行以下操作，並檢查控制台日誌輸出。

---

## ✅ 測試 1: 基本 Knockback 同步

### 場景
1. 進入遊戲，Player A 在正常位置
2. Player B 使用 **st_mp (站立中拳)** 攻擊 Player A
3. 觀察 Player A 的被擊反應和日誌

### 預期結果
```
[KNOCKBACK SETUP] DAV
  - Knockback Duration: 0.55s (66 frames)
  - knockback_frames: 66, knockback_delay_frames: 0

[KNOCKBACK PROGRESS] - 0.0% complete, remaining: 66 frames, velocity: XXXX
[KNOCKBACK PROGRESS] - 9.1% complete, remaining: 60 frames, velocity: XXXX
[KNOCKBACK PROGRESS] - 18.2% complete, remaining: 54 frames, velocity: XXXX
...
[KNOCKBACK PROGRESS] - 100.0% complete, remaining: 0 frames, velocity: 0

[KNOCKBACK END] DAV
  - Expected Duration: 0.55s (66 frames @120 FPS)
  - Actual Duration: 0.55s (或 0.54s-0.56s，允許 ±0.01s 誤差)
  - Sync Status: ✅ 同步
```

### 檢查項目
- [ ] knockback_frames 從 66 遞減到 0 ✅
- [ ] Expected Duration 顯示 0.55s @120 FPS ✅
- [ ] Actual Duration ≈ Expected Duration (誤差 < 0.05s) ✅
- [ ] Sync Status 顯示 ✅ 同步 ✅
- [ ] 角色在被擊期間完整執行移動，不會突然停止 ✅

---

## ✅ 測試 2: 不同攻擊強度

### 測試 2a: 弱攻擊 (st_lp)
```
// 預期: 更短的 knockback 時間
[KNOCKBACK SETUP] 
  - Knockback Duration: 0.3x s (xx frames)
  - Sync Status: ✅ 同步
```
- [ ] knockback 時間與 hitstun 同步 ✅

### 測試 2b: 強攻擊 (st_hp)
```
// 預期: 更長的 knockback 時間
[KNOCKBACK SETUP]
  - Knockback Duration: 0.7x s (xx frames)
  - Sync Status: ✅ 同步
```
- [ ] knockback 時間與 hitstun 同步 ✅

---

## ✅ 測試 3: 連續攻擊

### 場景
1. Player B 連續進行 2-3 次攻擊
2. 每次攻擊期間觀察 knockback 行為

### 預期結果
```
[KNOCKBACK SETUP] DAV (First hit)
  - Expected Duration: 0.55s (66 frames @120 FPS)

[KNOCKBACK END] DAV
  - Sync Status: ✅ 同步

[KNOCKBACK SETUP] DAV (Second hit, 在前一個 knockback 結束後觸發)
  - Expected Duration: 0.55s (66 frames @120 FPS)

[KNOCKBACK END] DAV
  - Sync Status: ✅ 同步
```

- [ ] 第一次 knockback 完整執行 ✅
- [ ] 第二次攻擊觸發時，第一次 knockback 已完成 ✅
- [ ] 沒有 knockback 時間重疊或中斷 ✅

---

## ✅ 測試 4: 空中受擊

### 場景
1. Player A 處於空中
2. Player B 進行空中攻擊
3. 觀察 knockback 行為

### 預期結果
```
[KNOCKBACK SETUP] DAV
  - Knockback Duration: X.xxs (XX frames @120 FPS)
  - Sync Status: ✅ 同步
```

- [ ] 空中 knockback 也能完整執行 ✅
- [ ] 不會提前終止 ✅

---

## ✅ 測試 5: Hitstun vs Knockback 獨立性

### 場景
1. 使用 InputBufferDebug 觀察輸入狀態
2. 被擊期間嘗試輸入 (應該被鎖定)
3. 被擊結束時檢查是否能立即操作

### 預期結果
- [ ] 被擊期間輸入被鎖定 (由 hitstun_frames 控制) ✅
- [ ] knockback 移動與 hitstun 同時進行 ✅
- [ ] Hitstun 結束 = 輸入解禁 (不受 knockback 影響) ✅

---

## 🔧 除錯技巧

### 檢查 FPS 值
```gdscript
// 在控制台輸入以查看當前 FPS
print("PHYSICS_FPS: ", Engine.physics_ticks_per_second)
// 預期輸出: 120
```

### 查看所有 knockback 相關日誌
在 VS Code 中搜索: `\[KNOCKBACK`
應該看到:
- `[KNOCKBACK SETUP]`
- `[KNOCKBACK PROGRESS]`
- `[KNOCKBACK END]`
- `[KNOCKBACK DELAY END]` (如果有延遲)

### 驗證 initial_knockback_frames 保存
添加臨時日誌:
```gdscript
// 在 PushManager.gd 中
print("[DEBUG] initial_knockback_frames: %d, knockback_frames: %d" % [player.initial_knockback_frames, player.knockback_frames])
// 應該看到 initial 值保持不變，knockback 逐幀遞減
```

---

## 📊 預期日誌範例

### ✅ 正確的同步狀態
```
[KNOCKBACK SETUP] DAV
  - Push Distance: 3.0 pixels
  - Initial Velocity: 3000.0 units
  - Delay Duration: 0.00s (0 frames)
  - Knockback Duration: 0.55s (66 frames)
  - Total Duration: 0.55s
  - knockback_frames: 66, knockback_delay_frames: 0

[KNOCKBACK PROGRESS] DAV - 0.0% complete, remaining: 66 frames, velocity: 2970 (initial: 66, hitstun: 66)
[KNOCKBACK PROGRESS] DAV - 9.1% complete, remaining: 60 frames, velocity: 2445 (initial: 66, hitstun: 66)
[KNOCKBACK PROGRESS] DAV - 18.2% complete, remaining: 54 frames, velocity: 1920 (initial: 66, hitstun: 66)
[KNOCKBACK PROGRESS] DAV - 27.3% complete, remaining: 48 frames, velocity: 1395 (initial: 66, hitstun: 66)
[KNOCKBACK PROGRESS] DAV - 36.4% complete, remaining: 42 frames, velocity: 870 (initial: 66, hitstun: 66)
[KNOCKBACK PROGRESS] DAV - 45.5% complete, remaining: 36 frames, velocity: 345 (initial: 66, hitstun: 66)
[KNOCKBACK PROGRESS] DAV - 54.5% complete, remaining: 30 frames, velocity: -180 (initial: 66, hitstun: 66)
...
[KNOCKBACK PROGRESS] DAV - 100.0% complete, remaining: 0 frames, velocity: 0 (initial: 66, hitstun: 66)

[KNOCKBACK END] DAV
  - Expected Duration: 0.55s (66 frames @120 FPS)
  - Actual Duration: 0.550s
  - Sync Status: ✅ 同步
```

### ❌ 異常情況 (應該不會再出現)
```
[KNOCKBACK END] DAV
  - Expected Duration: 1.100s (66 frames @60 FPS)     ❌ 硬編碼 FPS!
  - Actual Duration: 0.181s                           ❌ 提前終止!
  - Sync Status: ❌ 不同步                             ❌
```

---

## 🎯 測試優先級

| 優先級 | 測試項 | 重要性 |
|------|-------|------|
| 🔴 高 | 基本 Knockback 同步 | 核心修復驗證 |
| 🔴 高 | Expected ≈ Actual Duration | 時長精度 |
| 🟡 中 | 連續攻擊 | 邊界條件 |
| 🟡 中 | 空中受擊 | 特殊情況 |
| 🟢 低 | 弱/強攻擊差異 | 參數變化 |

---

## ✨ 修復成功的標誌

✅ **所有以下條件同時滿足**:
1. 日誌中 Expected Duration 使用正確的 FPS (120)
2. Actual Duration ≈ Expected Duration (誤差 < 0.05s)
3. knockback_frames 從初始值逐幀遞減到 0
4. Sync Status 顯示 ✅ 同步
5. 角色被擊飛時能完整執行整個被擊動畫，不會突然停止

---

## 📝 測試結果記錄

### 測試日期: _______________
### 測試人員: _______________

| 測試 | 結果 | 備註 |
|-----|------|------|
| 基本同步 | ✅ / ❌ | |
| FPS 計算 | ✅ / ❌ | |
| 時長精度 | ✅ / ❌ | |
| 連續攻擊 | ✅ / ❌ | |
| 空中受擊 | ✅ / ❌ | |

### 總體評估
- [ ] 修復成功 ✅
- [ ] 需要進一步調整 🔧
- [ ] 發現新問題 ⚠️

### 備註
_________________________________
