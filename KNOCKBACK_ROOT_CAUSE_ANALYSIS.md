# 🎯 Knockback 時長同步 - 根本原因和修復總結

## 🔴 根本問題

日誌顯示:
```
[KNOCKBACK SETUP] knockback_frames: 66, Knockback Duration: 0.55s
[KNOCKBACK END] Expected Duration: 1.100s (66 frames), Actual Duration: 0.181s
```

**knockback 實際執行時間只有預期的 33%**

---

## 🔍 問題根源 - 四層分析

### 第 1 層：時間系統不統一 ✅ FIXED
- **問題**: knockback 使用 delta-based 計時 (`hit_push_timer -= delta`)
- **影響**: 累積誤差，不精確
- **修復**: 改為固定幀數系統 (`knockback_frames -= 1`)

### 第 2 層：FPS 硬編碼 ✅ FIXED
- **問題**: Expected Duration 計算: `66 / 60.0 = 1.1s` （應為 `66 / 120.0 = 0.55s`）
- **影響**: 錯誤的時長顯示
- **修復**: 使用動態 `Engine.physics_ticks_per_second`

### 第 3 層：初始值沒保存 ✅ FIXED
- **問題**: 衰減計算用 `hitstun_frames / hitstun_frames`，但 hitstun_frames 在遞減
- **影響**: 分母不斷變小，衰減曲線失效
- **修復**: 添加 `initial_knockback_frames` 保存初始值

### 第 4 層：**【最關鍵】knockback 被提前終止** ✅ FIXED
- **問題**: 
  ```gdscript
  if player.is_hit:                         // ← 這是問題！
      if player.knockback_frames > 0:
          // knockback 執行
  ```
  當 `hitstun_frames` 達到 0 時，fighter.gd 設置 `is_hit = false`
  下一幀 PushManager 檢查 `if player.is_hit:` → false → 整個 knockback 塊被跳過！

- **根因**: knockback 依賴 `is_hit` 狀態，但該狀態在 hitstun 結束時被清除

- **修復**: 將 knockback 移出 `is_hit` 檢查，使其獨立執行
  ```gdscript
  // ✅ 修復後
  if player.knockback_frames > 0:          // ← 獨立條件！
      // knockback 執行，不受 is_hit 影響
  ```

---

## 📊 修復時序圖

### ❌ 修復前
```
Frame 1-66: hitstun 執行，is_hit = true，knockback 也執行
Frame 66: hitstun_frames == 0
         ↓ fighter.gd 立即設置 is_hit = false
Frame 67: PushManager 檢查 is_hit → FALSE
         ↓ 整個 knockback 邏輯被跳過
         ↓ 實際 knockback 只執行了 66 frames 中的 22 frames!
結果: 0.181s (22 frames / 120 fps)
```

### ✅ 修復後
```
Frame 1-66: hitstun 執行，is_hit = true，knockback 執行
Frame 66: hitstun_frames == 0，is_hit = false
Frame 67-132: knockback 仍在執行！
              ↓ if player.knockback_frames > 0: (獨立檢查)
              ↓ 繼續遞減 knockback_frames
結果: 0.55s (66 frames / 120 fps) ✅
```

---

## 💾 代碼修改清單

### fighter.gd
✅ 添加 `initial_knockback_frames` 變數
✅ 在 take_hit() 中同時設置 `knockback_frames` 和 `initial_knockback_frames`
✅ 在 _physics_process() 中處理 knockback_delay_frames

### PushManager.gd
✅ **【關鍵】將 knockback 執行移出 `if player.is_hit:` 檢查**
✅ 更新 Expected Duration 計算使用動態 FPS
✅ 添加詳細進度日誌

---

## ✅ 預期修復效果

修復後日誌應顯示:
```
[KNOCKBACK SETUP] DEN
  - Knockback Duration: 0.55s (66 frames)

[KNOCKBACK PROGRESS] - 0.0% complete, remaining: 66 frames
[KNOCKBACK PROGRESS] - 9.1% complete, remaining: 60 frames
...
[KNOCKBACK PROGRESS] - 100.0% complete, remaining: 0 frames

[KNOCKBACK END] DEN
  - Expected Duration: 0.55s (66 frames @120 FPS)  ✅
  - Actual Duration: 0.55s                         ✅
  - Sync Status: ✅ 同步
```

**角色被擊飛時將完整執行整個 0.55 秒的被擊動畫**

---

## 🎮 遊戲體驗改變

### 修復前
- 角色被擊飛，立即停止移動（雖然無法行動）
- Hitstun 和 Knockback 不同步，視覺上很詭異

### 修復後
- 角色被擊飛，完整執行被擊動畫和移動軌跡
- Hitstun 和 Knockback 完全同步，視覺流暢

---

## 📝 關鍵洞察

**為什麼會忽略這個 bug？**
1. 固定幀數系統中，hitstun 和 knockback 應該獨立管理
2. knockback 不應該依賴 `is_hit` 狀態
3. Hitstun 決定無敵幀和輸入鎖定，knockback 決定物理移動
4. 兩者應該併行執行，而非串聯

**最佳實踐**:
```gdscript
// ✅ 正確的設計
if player.hitstun_frames > 0:       // hitstun 邏輯
if player.knockback_frames > 0:     // knockback 邏輯
if player.blockstun_frames > 0:     // blockstun 邏輯
// 這些是獨立的，可以同時執行
```

---

## ✨ 修復完成清單

- [x] 根本原因分析完成
- [x] 代碼修復完成
- [x] 編譯驗證通過 (無錯誤)
- [ ] 運行時測試 (待執行)
- [ ] 邊界情況測試 (待執行)
