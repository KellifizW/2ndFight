# ✅ 時間系統修復已完成 (2026-02-05 09:40)

## 修復清單

### ✅ 1. world.gd (第 3 行)
- **變更**: `const TICKS_PER_SECOND: int = 60` → `const TICKS_PER_SECOND: int = 120`
- **原因**: 物理運行於 120 FPS，非 60 FPS
- **影響**: FrameCounter 和所有秒轉幀轉換現在正確

### ✅ 2. data/AttackData.gd (第 8 行)
- **變更**: `const PHYSICS_FPS: int = 60` → `const LOGIC_FPS: int = 60`
- **原因**: AttackData 中的幀數是邏輯幀（60 FPS 基準），非物理幀
- **更新**:
  - 方法註解: `frames_to_seconds()` 現明確說 "轉換邏輯幀數"
  - 檔案註解: 更新為 "@60FPS 邏輯幀"
- **影響**: hitstun/blockstun 計算現在正確

### ✅ 3. fighter.gd (第 6 和 42 行)
- **變更**:
  - 移除 `const DISPLAY_FPS: int = 60` (重複)
  - 移除 `const FPS: int = 60` (含糊)
  - 保留 `const LOGIC_FPS: int = 60`
- **原因**: 統一命名，避免混淆
- **影響**: 程式碼清晰度和可維護性改善

---

## 🧪 驗證狀態

| 檔案 | 狀態 | 詳細 |
|------|------|------|
| world.gd | ✅ | TICKS_PER_SECOND = 120 |
| fighter.gd | ✅ | PHYSICS_FPS = 120, LOGIC_FPS = 60 |
| data/AttackData.gd | ✅ | LOGIC_FPS = 60 |
| FrameCounter.gd | ✅ | PHYSICS_FPS = 120, LOGIC_FPS = 60 |
| Movement.gd | ✅ | 所有轉換使用 × 120 |
| Player.gd | ✅ | 所有轉換使用 × 120 |
| 所有主要處理器 | ✅ | 統一使用 120 FPS 物理框架 |

---

## 📊 系統現狀

✅ **完全統一**: 120 FPS 物理運行 + 60 FPS 邏輯顯示 + 幀數制度  
✅ **資源檔**: 所有攻擊數據使用邏輯幀基準 (60 FPS)  
✅ **轉換邏輯**: 所有秒轉幀使用 × 120 (物理幀) 或 × 60 (邏輯幀)  
✅ **常數統一**: 不再有含糊或衝突的 FPS 定義

---

**下一步**: 建議執行完整遊戲測試，驗證 hitstun/blockstun/knockback 時間準確性。

