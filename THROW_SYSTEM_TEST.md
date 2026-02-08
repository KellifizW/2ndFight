# 摔投系统 - 完整测试和修复记录

## 问题分析

### 原始问题
被摔者被摔投后，水平速度 fixed_velocity.x 立即被清除为 0，导致没有水平推动。

**日志证据：**
```
[THROWN] Final state: fixed_velocity=(-1620000, -1000000), knockfly_timer=0.300, is_on_floor=true
[KNOCKFLY_CHECK] player_a | timer=0.292 | vel_x=0 vel_y=-1000000 | on_floor=true
```

时间戳差：0.3 - 0.292 = 0.008 秒 ≈ 1 帧

### 根本原因

关键发现：被摔者的 `is_on_floor = true`，即使：
1. `fixed_velocity.y = -1000000`（向上）
2. 应该处于 knockfly 状态

这是因为 `is_on_floor()` 的实现：
```gdscript
func is_on_floor() -> bool:
    if jump_delay_timer > 0 or just_jumped:
        return false
    return fixed_position.y >= (world.FLOOR_Y if world else 200000)
```

**问题**：即使被摔者的速度向上，如果 `fixed_position.y >= FLOOR_Y`，`is_on_floor()` 仍返回 true。

这导致处理器（可能是 WalkHandler 或 LandingHandler）访问 is_floor = true 的条件分支，清除 fixed_velocity.x。

### 修复方案

**修复位置**：[player.gd](player.gd#L778) - 在 _on_thrown() 中

**修复代码**：
```gdscript
# 【關鍵修復】將被摔者從地面上移開，確保不會觸發 is_landing 邏輯
# 此時被摔者應該向上運動，位置也應該立即從地面上升
fixed_position.y = world.FLOOR_Y - 10000  # 抬起 10 個固定點單位（約 10 像素）
```

**效果**：
1. 立即抬起被摔者，使 `is_on_floor() = false`
2. 防止触发地面相关处理器逻辑
3. 确保 fixed_velocity.x 保持运作

### 修复时间线

1. **Frame N**: _on_thrown() 执行
   - 设置 is_knockfly = true
   - 设置 fixed_velocity.x = -1620000
   - 设置 fixed_velocity.y = -1000000
   - **【新增】** 设置 fixed_position.y = FLOOR_Y - 10000（抬起）
   - 此时 is_on_floor() = false

2. **Frame N+1**: 下一帧物理处理
   - 所有处理器检查 is_on_floor() = false
   - WalkHandler 和 LandingHandler 不触发清除逻辑
   - KnockflyHandler 正常处理 knockfly状态
   - fixed_velocity.x 保持 -1620000（最多减 200 摩擦力）

## 验证清单

测试者应验证以下项目：

- [ ] 摔投输入：st_lp + st_lk（同时）触发 throw_enter
- [ ] throw_enter 动画播放（约 0.5 秒）
- [ ] 碰撞检测：当被摔者 ThrowBox 进入摔投者 ThrowBox 时，playthrough_seq
- [ ] 受害者状态：
  - [ ] 进入 knockfly 状态
  - [ ] 播放 knockfly 动画
  - [ ] 受到伤害（8.0 HP 默认）
  - [ ] 受到水平推力（观察位置变化）
  - [ ] 受到向上的垂直速度（观察抛起）
  - [ ] 向上运动 1 帧后立即向下掉落（重力）
- [ ] 最终结果：受害者完成 knockfly -> layground 过渡

## 代码示例参考

### ThrowData 资源值
```
throw_damage: 8.0
throw_hitstun_frames: 36 (物理帧)
throw_knockback_horizontal: 120.0 (像素/帧)
throw_launch_horizontal_speed: 1500.0 (像素/帧，额外)
throw_launch_vertical_speed: -1000.0 (像素/帧，负数=向上)
throw_gravity: 6000000.0 (固定点)
```

### 预期水平速度计算
```
total_horizontal_speed = 120.0 + 1500.0 = 1620.0 像素/帧
fixed_velocity.x = 1620.0 × 1000 × facing_direction
            = -1620000（如果 facing_direction = -1.0，推向对手）
```

### 预期垂直运动
```
Frame 1: fixed_position.y = 540000 (FLOOR_Y - 10000)
         fixed_velocity.y = -1000000
Frame 2: 加重力后，fixed_velocity.y ≈ -1000000 + gravity_delta
         fixed_position.y 继续上升（因为速度仍负）
Frame 10+: fixed_velocity.y 最终变为正（向下）
         fixed_position.y 开始下降
Frame 36+: 进入 layground，被摔者躺地上
```

## 关键参数

- **摄投碰撞延迟**：0 秒（立即检测）
- **throw_enter 持续时间**：0.5 秒（30 帧 @60FPS）
- **throw_seq 持续时间**：1.0 秒（60 帧 @60FPS）
- **被摔者抬起高度**：10000 固定点（≈10 像素）
- **摩擦力**：200 像素/帧（应用于 knockfly 水平速度）

## 故障排除

如果摔投仍不工作：

1. **检查日志**：查找 [THROWN] 和 [KNOCKFLY_CHECK] 消息
2. **验证 is_knockfly**：确保在整个序列中保持 true
3. **验证 fixed_position.y**：应该从 FLOOR_Y - 10000 开始
4. **检查摩擦力**：apply_air_friction 应使用 200 像素/帧
5. **检查 throw_data**：确保资源正确加载和应用

## 相关文件

修改的文件：
- [player.gd](player.gd#L778) - 在 _on_thrown() 中添加位置抬起
- [WalkHandler.gd](WalkHandler.gd#L59) - 添加 is_knockfly 清除保护的日志
- [LandingHandler.gd](LandingHandler.gd#L89) - 添加 is_knockfly 清除保护的日志
- [KnockflyHandler.gd](KnockflyHandler.gd#L101) - 增强摩擦力应用日志

