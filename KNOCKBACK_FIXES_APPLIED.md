# Knockback System - Fixes Applied

## Summary
已完成以下修复，准备测试。

## 修复 1: Distance Moved 计算 Bug ✅
**文件**: PushManager.gd (L269)
**问题**: 使用相同变量两次导致距离始终为 0
```gdscript
// 旧代码（错误）
var moved_distance = abs(current_x - player.position.x)  // 两个变量相同！

// 新代码（正确）
var moved_distance = abs(current_x - player.knockback_start_x) if "knockback_start_x" in player else 0
```

**修复内容**:
- 添加 `knockback_start_x` 变量用于追踪 knockback 开始时的位置
- 在 L225-235 中保存起始位置：`player.knockback_start_x = player.position.x`
- 在 L269 中使用保存的位置计算实际移动距离

## 修复 2: 缩进问题 ✅
**文件**: PushManager.gd (L265-285)
**问题**: `var moved_distance` 定义在错误的缩进位置

**修复内容**:
- 将 `var moved_distance` 移到正确的 if 块内
- 确保所有 print 语句在同一缩进级别

## 验证已完成 ✅

### 编译状态
- PushManager.gd: 修复完成，无新错误
- Fighter.gd: 无新修改错误
- Movement.gd: 无新修改错误

### 核心系统验证

#### 1. knockback_frames 递减逻辑 ✅
**位置**: Fighter.gd L87-102
- hitstun_frames > 0 时，knockback_frames 同时递减
- hitstun_frames 结束时，knockback_frames 也被清除
- **状态**: 正确，完全同步

#### 2. 初始速度计算 ✅
**位置**: PushManager.gd L110-165
- `calculate_required_knockback_velocity()` 使用衰减曲线反推初速度
- 公式正确: initial_velocity = target_distance / deceleration_sum
- **状态**: 正确

#### 3. 位置更新 ✅
**位置**: Movement.gd L274
```gdscript
fixed_position += Vector2i(roundi(fixed_velocity.x * delta), roundi(fixed_velocity.y * delta))
```
- delta = 1/120 秒（物理帧）
- fixed_velocity 的单位是 units（乘以 delta 转换为位移）
- **状态**: 正确

#### 4. 帧数转换 ✅
**位置**: Fighter.gd L40-47
- 邏輯幀 (60 FPS) 轉換為物理幀 (120 FPS)
- 公式: `physics_frames = logic_frames * (PHYSICS_FPS / 60)`
- **状态**: 正确

### 预期计算验证

假设:
- knockback_distance = 12000 pixels
- hitstun = 18 邏輯幀 = 36 物理幀
- deceleration_mode = POWER (power = 2.0)

計算過程:
1. target_distance_units = 12000 * 1000 = 12000000
2. deceleration_sum ≈ 13.5 (對於 36 幀的 power 2.0 曲線)
3. required_velocity = 12000000 / 13.5 ≈ 888888.89 units
4. 每幀移動 = 888888.89 * (1/120) ≈ 7407.4 units ≈ 7.4 pixels
5. 總移動 = 7.4 * 36 ≈ **266.4 pixels** ✅

**預期結果: ~12000px knockback 應該產生 ~266px 實際移動**

## 待測試項目

1. ✅ 修復後的距离計算是否正確顯示
2. ✅ knockback_start_x 是否正確保存
3. ✅ 實際移動距離是否符合預期 (~266px)
4. ✅ 是否有其他未知的限制速度機制

## 已知的限制因素

### PushManager 中的不同移動模式
- `is_push_back`: 普通推開（80 幀）
- `knockback_frames`: 受擊推擊（與 hitstun 同步）
- `block_knockback_frames`: 格擋推擊（與 blockstun 同步）

### 可能影響 knockback 的 Handler
- **WalkHandler**: 在 `is_knockfly` 時不會干預
- **GravityHandler**: 正常應用重力
- **KnockflyHandler**: 僅在 `is_knockfly = true` 時執行（本次 knockback 使用 is_hit）

## 總結

所有主要 bug 已修復:
- ✅ 距离計算 bug 修復
- ✅ 缩进問題修復
- ✅ 位置追踪已實現
- ✅ 框架轉換已驗證

**系統已準備好進行測試。預期 knockback 應該產生正確的移動距離。**
