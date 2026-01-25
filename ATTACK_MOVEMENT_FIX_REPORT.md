# 攻擊移動系統修復報告

## 問題診斷

### 原因
**AttackMovementHandler 沒有檢查 `enabled` 屬性**，導致即使 movement 資源的 `distance` 很小（10 像素）也會嘗試執行，但效果不明顯。

## 修復內容

### 1. **AttackMovementHandler.gd** 增強
- ✅ 添加 `enabled` 屬性檢查
- ✅ 添加 distance/duration 參數驗證
- ✅ 增強調試輸出，顯示完整的移動參數

### 2. **攻擊移動資源優化**
更新 Player 2 (DEN) 的攻擊移動距離，使其更明顯且符合格鬥遊戲標準：

| 攻擊 | 原距離 | 新距離 | 持續時間 | 曲線類型 |
|------|--------|--------|----------|----------|
| st_hp | 140px | 140px ✅ | 0.5s | BURST |
| st_mk | 10px | **150px** | 0.3s | BURST |
| st_hk | 70px | **180px** | 0.35s | BURST |
| cr_hk | 300px | 300px ✅ | 0.4s | EASE_OUT |

### 3. **曲線類型說明**
- **BURST (5)**: 瞬間爆發後減速（適合重拳型攻擊）
- **EASE_OUT (4)**: 開始快速然後減速（適合滑鏟型攻擊）

## 測試指引

### 準備工作
1. 啟動 Godot 引擎
2. 運行遊戲場景

### 測試步驟
1. **選擇 Player 2 (DEN)** - 因為只有 DEN 配置了攻擊移動
2. 執行以下攻擊並觀察角色移動：
   - **st_hp** (站立重拳): 應向前移動約 140 像素
   - **st_mk** (站立中踢): 應向前移動約 150 像素
   - **st_hk** (站立重踢): 應向前移動約 180 像素
   - **cr_hk** (蹲下重踢): 應向前移動約 300 像素（最明顯）

### 控制台輸出檢查
正常情況應該看到：
```
[AttackMovementHandler] ✓ 啟動 st_mk 移動：distance=150.0, duration=0.30, curve=5, enabled=true
[AttackMovementHandler] time=0.00, speed_mult=1.23, velocity=615000
[AttackMovementHandler] time=0.17, speed_mult=0.87, velocity=429000
[AttackMovementHandler] ✓ 移動完成
```

異常情況：
```
[AttackMovementHandler] st_mk 沒有設定 movement 屬性
// 或
[AttackMovementHandler] st_mk 的 movement 未啟用 (enabled=false)
// 或
[AttackMovementHandler] st_mk 的 movement 參數無效 (distance=0.0, duration=0.0)
```

## 技術細節

### 移動計算公式
```gdscript
base_speed = distance / duration
current_speed = base_speed * speed_multiplier * move_direction
fixed_velocity.x = int(current_speed * SIMULATION_SCALE)
```

### 範例計算 (st_mk)
- distance = 150.0 像素
- duration = 0.3 秒
- SIMULATION_SCALE = 1000
- base_speed = 150 / 0.3 = 500 像素/秒
- 在 BURST 曲線峰值 (speed_multiplier ≈ 1.5):
  - current_speed = 500 * 1.5 = 750 像素/秒
  - fixed_velocity.x = 750 * 1000 = 750,000

## 注意事項

### Player 1 (DAV) 沒有攻擊移動
目前 `p1_attack_data.tres` 的所有攻擊都沒有設置 movement 資源。如需為 DAV 添加攻擊移動：

1. 在 Godot Inspector 中打開 `data/p1_attack_data.tres`
2. 找到想要添加移動的攻擊（例如 st_mk_movement）
3. 創建新的 AttackMovement 資源或引用現有資源
4. 設置參數：
   - enabled = true
   - distance = 100-300（根據攻擊類型）
   - duration = 0.2-0.5
   - curve_type = BURST 或 EASE_OUT

### 調試技巧
如果移動仍然不可見：
1. 檢查控制台是否有 Handler 初始化訊息
2. 確認 `attack_data` 資源正確載入
3. 檢查 `world` 節點是否在 "world" group 中
4. 驗證 SIMULATION_SCALE = 1000

## 修改的檔案

### 核心修復
- ✅ `scripts/combat/handlers/AttackMovementHandler.gd` - 添加驗證邏輯

### 資源優化
- ✅ `data/den_st_mk_movement.tres` - 10px → 150px
- ✅ `data/den_st_hk_movement.tres` - 70px → 180px
- ⚠️ `data/den_st_hp_movement.tres` - 已是 140px（無需修改）
- ⚠️ `data/den_cr_hk_movement.tres` - 已是 300px（無需修改）

## 後續優化建議

### Phase 3 繼續時可考慮
1. **為 Player 1 (DAV) 添加攻擊移動**
2. **創建統一的移動預設值**（例如：輕攻擊 100px，中攻擊 150px，重攻擊 200px）
3. **添加移動動畫事件同步**（在動畫特定幀觸發移動，而非攻擊開始時）
4. **支援多段移動**（例如：先向前衝刺，再後退）

---

**修復完成時間**: 2026-01-25  
**測試狀態**: ✅ 編譯通過，等待運行時測試
