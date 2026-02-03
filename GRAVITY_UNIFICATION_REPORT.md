## 🎯 重力系統統一修復完整報告

### 問題診斷

根據日誌分析，同樣設置 `3000000.0` 的重力值，但攻擊者（DP 使用者）和被擊者（Knockfly）的實際重力表現不同：

```
[JUMP_TRIGGERED] player_a: dp | velocity.y=-1700000
[KNOCKFLY VERTICAL SPEED] DEN 被擊飛 → 垂直速度 = -1700000
```

兩者初始垂直速度相同，但重力應用邏輯卻不同：
- **攻擊者**: GravityHandler + MoveSet._apply_gravity() (雙重應用)
- **被擊者**: KnockflyHandler 應用 knockfly_gravity (單一應用)

### 根本原因

#### ❌ 修復前的問題

1. **重力應用點不統一**
   - GravityHandler: `fixed_velocity.y += int(gravity * delta)`
   - KnockflyHandler: `fixed_velocity.y += int(knockfly_gravity * delta)`
   - MoveSet._apply_gravity(): `fixed_velocity.y += int(gravity * delta)` (舊邏輯)

2. **執行順序混亂**
   ```
   Movement._physics_process()
     ├─ _handle_knockfly_layground()  (KnockflyHandler)
     ├─ _handle_gravity()             (GravityHandler)
     └─ MoveSet._process_special()    (MoveSet._apply_gravity 舊邏輯)
   ```

3. **重力值來源混淆**
   - 被擊者: knockfly_gravity (來自 Fighter.gd 設定)
   - 攻擊者: move.gravity (來自 MoveSet 定義) 或 world.GRAVITY

### ✅ 修復方案

#### Step 1: 統一重力計算邏輯

在 **GravityHandler.gd** 中實現統一的重力應用函數 `apply_gravity_unified()`：

```gdscript
func apply_gravity_unified(delta: float, move_set: Node = null) -> void:
    # 根據狀態決定使用哪種重力
    
    # Case 1: 被擊飛狀態 → 使用 knockfly_gravity
    if movement_node.is_knockfly:
        gravity_to_apply = int(movement_node.knockfly_gravity)
        gravity_source = "knockfly"
    
    # Case 2: 特殊招式期間 → 使用 move.gravity
    elif move_set.is_spmove and move.gravity > 0:
        gravity_to_apply = int(move.gravity)
        gravity_source = "spmove"
    
    # Case 3: 普通跳躍 → 使用 world.GRAVITY
    else:
        gravity_to_apply = int(world.GRAVITY)
        gravity_source = "world"
    
    # 統一應用重力
    movement_node.fixed_velocity.y += int(float(gravity_to_apply) * delta)
```

#### Step 2: 移除重力的重複應用

- **KnockflyHandler**: 移除 `fixed_velocity.y += int(knockfly_gravity * delta)` 的直接應用
  - 只負責時間計時和狀態轉換
  - 重力由 GravityHandler 統一管理

- **MoveSet._apply_gravity()**: 禁用舊邏輯
  - 評論掉 `_apply_gravity()` 的調用
  - 所有重力計算都由 GravityHandler 負責

#### Step 3: 確保執行順序正確

在 **Movement._physics_process()** 中的執行順序：

```gdscript
func _physics_process(delta: float) -> void:
    # ... 其他邏輯 ...
    
    _handle_knockfly_layground(delta, floor_y)  # 更新狀態和計時
    _handle_gravity(delta, move_set)            # 統一應用重力
    
    # 應用速度到位置
    fixed_position += Vector2i(roundi(fixed_velocity.x * delta), roundi(fixed_velocity.y * delta))
```

### 📊 修復對比

| 項目 | 修復前 | 修復後 |
|------|--------|--------|
| **重力應用點** | 3個地方 (GravityHandler, KnockflyHandler, MoveSet) | 1個地方 (GravityHandler) |
| **被擊飛重力** | `knockfly_gravity` (直接應用) | `knockfly_gravity` (統一應用) |
| **DP重力** | `move.gravity` + `world.GRAVITY` (混合) | `move.gravity` (統一應用) |
| **普通跳躍重力** | `world.GRAVITY` (GravityHandler) | `world.GRAVITY` (統一應用) |
| **邏輯複雜度** | 🔴 高 (多個地方控制) | 🟢 低 (集中管理) |
| **維護難度** | 🔴 高 (修改需要改多個地方) | 🟢 低 (只改 GravityHandler) |

### 🔍 驗證方法

#### 1. 啟用調試日誌

在 GravityHandler.gd 中改為 `if true:`：

```gdscript
if true:  # 改為 true 啟用日誌
    print("[GRAVITY_UNIFIED] ...")
```

執行 DP，輸出應該看到：
```
[GRAVITY_UNIFIED] DAV | source=spmove gravity=3000000 delta=0.0167 old_vy=-1700000 new_vy=-1649900
[GRAVITY_UNIFIED] DEN | source=knockfly gravity=3000000 delta=0.0167 old_vy=-1700000 new_vy=-1649900
```

**重點**: 兩者應該有相同的 gravity 值和相同的計算過程

#### 2. 檢查視覺效果

- DP 攻擊者應該上升然後以相同的重力下落
- 被擊者應該以相同的重力下落

兩者的軌跡應該在物理上一致

### 📝 修改檔案清單

| 檔案 | 修改內容 |
|------|---------|
| GravityHandler.gd | ✅ 新增 `apply_gravity_unified()` 函數，統一所有重力邏輯 |
| KnockflyHandler.gd | ✅ 移除直接重力應用，改由 GravityHandler 管理 |
| MoveSet.gd | ✅ 禁用 `_apply_gravity()` 的調用（評論掉） |
| GravitySystem.gd | ℹ️ 已刪除（邏輯內聯到 GravityHandler） |

### 🎯 修復前後的關鍵差異

#### 修復前：重力應用流程

```
Move._physics_process()
  ├─ KnockflyHandler.handle_knockfly_layground()
  │  └─ fixed_velocity.y += int(knockfly_gravity * delta)     ❌ 應用1次
  ├─ GravityHandler.handle_gravity()
  │  └─ fixed_velocity.y += int(gravity * delta)              ❌ 應用1次（但邏輯不同）
  └─ MoveSet._process_special()
     └─ fixed_velocity.y += int(move.gravity * delta)         ❌ 應用1次（舊邏輯）
```

**問題**: 同一幀中可能應用多次重力，或使用不同的重力值

#### 修復後：重力應用流程

```
Movement._physics_process()
  ├─ KnockflyHandler.handle_knockfly_layground()
  │  └─ 只更新 knockfly_timer 和狀態（不應用重力）
  ├─ GravityHandler.handle_gravity()
  │  └─ apply_gravity_unified(delta, move_set)
  │     ├─ 檢查 is_knockfly → 使用 knockfly_gravity     ✓
  │     ├─ 檢查 is_spmove   → 使用 move.gravity          ✓
  │     └─ 檢查 is_jumping  → 使用 world.GRAVITY         ✓
  │     └─ fixed_velocity.y += int(gravity * delta)       ✅ 應用1次（統一邏輯）
  └─ (MoveSet 不再應用重力)
```

**優勢**: 
- 統一的計算邏輯
- 單一應用點
- 易於維護和調試

### 📌 技術細節（基於 Sakuga-Engine 架構）

#### 固定點數學保證

```gdscript
# 統一的固定點計算
movement_node.fixed_velocity.y += int(float(gravity_to_apply) * delta)

# 確保所有地方都使用相同的公式
# gravity_to_apply: int (固定點值，如 3000000)
# delta: float (時間差，如 0.0167)
# 結果: int (累積到速度中)
```

#### Sakuga-Engine 參考

在附件的 Sakuga-Engine 中，重力應用如下：

```csharp
public void AddGravity(int gravity)
{
    FixedVelocity.Y -= gravity / Global.TicksPerSecond;
}
```

2ndFight 的實現略有不同（使用 `+=` 和 `delta`），但原理相同：
- **統一的應用點**: 單一函數
- **統一的計算邏輯**: 相同的公式
- **狀態驅動**: 根據當前狀態決定使用的重力值

### ✨ 修復完成

所有修改已完成，遊戲現在使用統一的重力系統：

✅ GravityHandler.gd - 統一重力應用
✅ KnockflyHandler.gd - 移除重複應用
✅ MoveSet.gd - 禁用舊邏輯
✅ 無編譯錯誤

遊戲應該現在在攻擊者和被擊者之間使用完全相同的重力計算！

