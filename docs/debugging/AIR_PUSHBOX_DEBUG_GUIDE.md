# 空中 Pushbox 失效調試指南

## 問題描述
角色的 pushbox 在地面時正常運作，但在空中時會間中失效，導致兩個空中角色可以相互穿過。

## 調試方法

### 1️⃣ 啟用空中 Pushbox 調試日誌

**步驟**:
1. 在 Godot 編輯器中選擇 **World 場景** 中的 **PushManager** 節點
2. 在 **Inspector** 面板找到 **Debug Settings** 群組
3. 啟用 **Debug Air Pushbox** 選項（勾選框）

```
PushManager (Inspector)
├─ Debug Settings
│  ├─ Debug Knockback Velocity Calc: ☐
│  ├─ Debug Knockback Execution: ☐
│  ├─ Debug Position Tracking: ☐
│  └─ Debug Air Pushbox: ☑️ ← 啟用此項
```

### 2️⃣ 執行遊戲並重現問題

1. 按 **F5** 啟動遊戲
2. 使兩個角色都跳起來（都在空中）
3. 讓他們相互接近直到相撞
4. **重要**：觀察 **Output 終端**（Godot 下方的輸出面板）

### 3️⃣ 解讀調試日誌

#### 正常情況（推送工作）
```
[AIR_PUSHBOX_CHECK] Player_A vs Player_B | P_state(jump=true knockfly=false) vs O_state(jump=true knockfly=false)
[AIR_BOX_CALC] Player_A: center=(500000,400000) size=(80000,160000) | Player_B: center=(600000,410000) size=(80000,160000)
[AIR_OVERLAP_DETECTED] Player_A vs Player_B | overlap_x=40000 overlap_y=150000 | check: x_valid=true y_valid=true
[AIR_PUSH_VEC_CALC] Player_A->12000 | Player_B->-12000 | unpush_self=false unpush_other=false
[AIR_Y_OVERLAP_OK] overlap_y=150000 → will apply push
```

✅ **結果**: 兩個角色都被推開（X位置改變）

#### 故障情況（推送失敗）
```
[AIR_PUSHBOX_CHECK] Player_A vs Player_B | P_state(jump=true knockfly=false) vs O_state(jump=true knockfly=false)
[AIR_BOX_CALC] Player_A: center=(500000,400000) size=(80000,160000) | Player_B: center=(600000,410000) size=(80000,160000)
[AIR_OVERLAP_DETECTED] Player_A vs Player_B | overlap_x=40000 overlap_y=0 | check: x_valid=true y_valid=false
[AIR_CRITICAL_BUG] Player_A vs Player_B | Y軸檢查失敗！overlap_y=0 ≤ 0 → 推送被跳過！
[AIR_PUSHBOX_FAILURE_DETAIL]
  Player A (Player_A): pos=(500.0,400.0) box_center=(500000,400000) size=(80000,160000)
  Player B (Player_B): pos=(600.0,410.0) box_center=(600000,410000) size=(80000,160000)
  Y軸邊界 A: top=320000 bottom=480000 | B: top=330000 bottom=490000
  Y軸深度計算: depth.y=0 (失敗！應 > 0)
```

❌ **結果**: 推送被完全跳過！角色相互穿過

## 調試日誌欄位說明

### [AIR_PUSHBOX_CHECK]
- **jump**: 是否正在跳躍狀態
- **knockfly**: 是否在受擊漂浮狀態

### [AIR_BOX_CALC]
- **center**: 碰撞箱中心 (fixed-point 單位，1000 = 1像素)
- **size**: 碰撞箱大小 (固定點單位)

### [AIR_OVERLAP_DETECTED]
- **overlap_x**: X軸重疊深度（應 > 0）
- **overlap_y**: Y軸重疊深度（應 > 0）
- **x_valid / y_valid**: 檢查是否符合條件

### [AIR_PUSHBOX_FAILURE_DETAIL]
- **pos**: 全局位置（像素）
- **box_center**: 固定點坐標的碰撞箱中心
- **size**: 碰撞箱尺寸（固定點）
- **Y軸邊界**: 上下邊界的固定點值
- **depth.y**: Y軸計算深度（≤0 = 失敗）

## 根本原因分析

### 可能原因 1️⃣：Y軸邊界計算誤差
```
如果: A_bottom (480000) < B_top (330000)
結果: 沒有Y軸重疊 → overlap_y = 0
```

**檢查項**:
- Player A 和 Player B 的 **colbox_half_height** 是否相同？
- Y 位置差距是否超過碰撞箱高度？

### 可能原因 2️⃣：Pushbox 節點偏移錯誤
```
center = fixed_position + fixed_offset * facing_direction
```

**檢查項**:
- 每個角色的 Pushbox 節點是否正確定位？
- 朝向反轉時偏移是否正確計算？

### 可能原因 3️⃣：碰撞箱尺寸在空中改變
```
size = colbox_half_width * 2, colbox_half_height * 2
```

**檢查項**:
- 着陸時是否誤改了 `colbox_half_height`？
- 跳躍時是否應用了不同的碰撞尺寸？

## 進階調試步驟

### 添加更詳細的位置追蹤

編輯 [PushManager.gd](../../scripts/core/PushManager.gd) 的 `log_air_pushbox_failure` 函數，添加：

```gdscript
# 計算實際Y距離
var distance_y = abs(collider_a.center.y - collider_b.center.y)
var sum_half_heights = (collider_a.size.y + collider_b.size.y) / 2
print("  Y軸距離: %d | 需要重疊: %d | 實際重疊: %d" % [
    distance_y, sum_half_heights, sum_half_heights - distance_y
])
```

### 驗證固定點轉換

在終端檢查絕對數值是否正確：
```
# 範例：位置 500.0 像素
# 固定點 = 500 * 1000 = 500000 ✓
# 碰撞箱高度 160 像素 = 160 * 1000 = 160000 ✓
```

## 常見修復

### 修復 1: Y軸檢查條件放寬（臨時）

如果 `overlap_fixed_y` 由於舍入誤差變成 -1 ~ 1，可在 PushManager 中改為：

```gdscript
# 原始（嚴格）
if overlap_fixed_y > 0:

# 修復（容許小誤差）
if overlap_fixed_y > -SIMULATION_SCALE:  # 容許 -1000 以內的誤差
```

### 修復 2: 確保碰撞箱在空中保持一致

檢查 [Movement.gd](../../Movement.gd) 或 [Fighter.gd](../../Fighter.gd) 的 `colbox_half_width` / `colbox_half_height` 設定，確認在跳躍時不改變。

## 回報問題

如果啟用日誌後仍無法找到原因，請回報：
1. **完整的調試日誌輸出**（[AIR_CRITICAL_BUG] 到 [AIR_PUSHBOX_FAILURE_DETAIL]）
2. **複現步驟**（哪些動作導致失效）
3. **角色配置**（colbox_half_width / colbox_half_height 的值）

---

**最後更新**: 2026-02-26  
**調試開關位置**: PushManager Inspector > Debug Settings > Debug Air Pushbox
