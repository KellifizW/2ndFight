# 幀計數器實現報告

## 變更摘要

### ✅ 已完成

#### 1. **FrameCounter.gd 創建**
- 位置：`c:\Users\t-way\Documents\2ndFight\2ndfight\2ndFight\FrameCounter.gd`
- 功能：
  - `global_frame: int` - 累計幀數計數器
  - `is_paused: bool` - 暫停狀態（支持 slow-mo）
  - 核心方法：
    - `get_current_frame() -> int` - 取得當前幀數
    - `frames_to_seconds(frames: int) -> float` - 幀數轉秒
    - `seconds_to_frames(seconds: float) -> int` - 秒轉幀數
    - `pause()`/`resume()` - 暫停/恢復計數
    - `reset()` - 重置計數器
    - `has_elapsed_frames()` - 檢查是否超過指定幀數
    - `get_remaining_frames()` - 取得剩餘幀數

#### 2. **world.gd 修改**
- **變數替換：**
  - `attacker_recover_time: float` → `attacker_recover_frame: int` ✅
  - `target_recover_time: float` → `target_recover_frame: int` ✅
  - `block_attack_recover_time: float` → `block_attack_recover_frame: int` ✅
  - `block_defend_recover_time: float` → `block_defend_recover_frame: int` ✅
  - 新增：`frame_counter: FrameCounter = null` ✅

- **_ready() 修改：**
  - 新增幀計數器初始化（行 107-110）
  - `frame_counter = FrameCounter.new()` 並加入場景樹 ✅

- **_calculate_hit_advantage() 修改：**
  - 替換 `Time.get_unix_time_from_system()` 為 `frame_counter.get_current_frame()` ✅
  - 改用整數減法計算優勢 ✅
  - 改進日誌輸出格式 ✅

- **_calculate_block_advantage() 修改：**
  - 同上，替換為幀數計算 ✅
  - 新增防守優勢計算的日誌 ✅

- **reset_players() 修改：**
  - 新增優勢計算變數重置（行 616-620）
  - 新增幀計數器重置：`frame_counter.reset()` ✅

- **_on_hit_detected() 修改：**
  - 所有時間戳變數改為 `-1` 初始化 ✅

#### 3. **slow_mo_controller.gd 修改**
- **request_hit_freeze() 修改：**
  - 新增幀計數器暫停（行 57-59）：
    ```gdscript
    var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
    if frame_counter:
        frame_counter.pause()
    ```

- **_on_hit_slowmo_finished() 修改：**
  - 新增幀計數器恢復（行 131-134）：
    ```gdscript
    var frame_counter = get_tree().root.get_node_or_null("World/FrameCounter")
    if frame_counter:
        frame_counter.resume()
    ```

### 📊 編譯檢查結果

✅ **world.gd** - 無編譯錯誤
✅ **slow_mo_controller.gd** - 無編譯錯誤  
✅ **FrameCounter.gd** - 無編譯錯誤

### 🔄 運作流程

#### 優勢計算（之前 ❌ 浮點誤差）
```
Old: Time.get_unix_time_from_system() → 1706881234.12345
     Time.get_unix_time_from_system() → 1706881234.13567
     差異 = 0.01222 秒 × 60 = 0.7332 → 舍入為 1 幀 ❌ 誤差
```

#### 優勢計算（現在 ✅ 完全精確）
```
New: frame_counter.get_current_frame() = 42
     frame_counter.get_current_frame() = 55
     差異 = 55 - 42 = 13 幀 ✅ 完全精確
     秒數 = 13 / 60.0 = 0.21667 秒 ✅
```

#### Slow-Mo 暫停機制
```
1. 擊中發生 → slowmo_controller.request_hit_freeze()
2. 幀計數器暫停 → frame_counter.pause()
3. Engine.time_scale 設為 0.02
4. Hit stop 完成 → _on_hit_slowmo_finished()
5. 幀計數器恢復 → frame_counter.resume()
6. Engine.time_scale 恢復為 1.0
```

### 🎯 預期改善

| 指標 | 之前 | 現在 |
|------|------|------|
| 優勢計算穩定性 | 浮動 ±5ms | 精確 1 幀 |
| 優勢幀數範圍 | 0.068~0.088 秒 | 確定值（如 4F = 0.06667秒） |
| 計算精度 | 舍入誤差 ±1 幀 | 無誤差（整數減法） |
| Slow-Mo 同步 | 無幀計數器同步 | 完全同步暫停/恢復 |

### ✅ 驗證檢查清單

- [x] FrameCounter.gd 編譯通過
- [x] world.gd 編譯通過
- [x] slow_mo_controller.gd 編譯通過
- [x] 無遺漏的舊變數引用
- [x] 優勢計算邏輯完整（hit 和 block）
- [x] Reset 函數更新正確
- [x] 日誌輸出清晰
- [x] Slow-Mo 與幀計數器整合

### 📝 建議下一步

1. **測試遊戲流程：**
   - 在 World 場景執行遊戲
   - 觀察優勢標籤的數值穩定性
   - 驗證優勢幀數是否一致

2. **測試 Slow-Mo：**
   - 進行攻擊擊中對手（觀察 hit stop 效果）
   - 檢查幀計數器日誌是否顯示 ⏸ 和 ▶

3. **驗證其他系統相容性：**
   - 檢查 hitstun_frames 系統是否正常運作
   - 檢查 AnimationPlayer 時序是否正確

### 🔗 相關檔案修改

| 檔案 | 修改行數 | 類型 |
|------|---------|------|
| `FrameCounter.gd` | 60 | 新建 |
| `world.gd` | 15 行（變數） + 30 行（邏輯） | 修改 |
| `slow_mo_controller.gd` | 6 行（暫停） + 4 行（恢復） | 修改 |

---

**實現日期：** 2026-02-02  
**狀態：** ✅ 完成，準備測試  
**下一步：** 運行遊戲驗證功能
