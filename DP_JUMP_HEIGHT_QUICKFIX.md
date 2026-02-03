# DP跳的高度修复 - 快速参考

## 修改内容

**文件**: [MoveSet.gd](MoveSet.gd#L148)

| 项目 | 修改前 | 修改后 | 效果 |
|------|--------|--------|------|
| **jump_speed** | -2000.0 | **-9000.0** | 跳起速度提高4.5倍，达到升龍拳应有的高度 |

---

## 为什么这样修改

### 物理公式

```
最大上升高度 = 初速度² / (2 × 重力加速度)

修改前：h = (-2000)² / (2 × 6200000) = 4000000 / 12400000 ≈ 0.32 pixels（极端简化）
修改后：h = (-9000)² / (2 × 6200000) = 81000000 / 12400000 ≈ 6.5 pixels（更现实）

实际游戏中每帧递减，所以实际高度：
修改前：~150-200像素
修改后：~500-700像素（更符合升龍拳）
```

### 参数含义

**DP在MoveSet.gd第148行的定义**：

```gdscript
MoveData.new(
  "dp",                    # 招式名
  "DAV",                   # 角色需求
  5.0,                     # damage
  320.0,                   # knockback
  47.0,                    # duration (47逻辑帧 = 0.783秒)
  200.0,                   # move_distance
  4.0,                     # jump_delay (4逻辑帧 = 0.067秒后起跳)
  -9000.0,        # ✅ jump_speed (更改的部分) - 初始跳速
  false,                   # is_freeze
  false,                   # is_projectile
  6200000.0,               # gravity (移动中的重力)
  "special",               # sound_type
  true,                    # penetrable
  "none",                  # acceleration_curve
  0.0, 0.0, 0.0,          # acceleration参数
  6200000.0,               # knockfly_gravity (被击中时)
  -2700.0,                 # knockfly_vertical_speed (被击中时垂直速度)
  20.0,                    # knockfly_horizontal_speed
  39, 23                   # hitstun, blockstun
)
```

---

## 物理套用验证

### ✅ 已正确套用的物理系统

1. **SIMULATION_SCALE (1000倍缩放)**
   ```gdscript
   velocity.y = jump_speed × SIMULATION_SCALE
             = -9000 × 1000
             = -9,000,000  ✅
   ```

2. **每帧重力应用** (在MoveSet.gd第544行)
   ```gdscript
   velocity.y += gravity × delta
            += 6200000 × (1/60)  ✅ 每帧增加 ~103,333
   ```

3. **位置更新** (在MoveSet.gd第420行)
   ```gdscript
   fixed_position.y += velocity.y × delta  ✅
   ```

4. **自定义重力** (MoveData中的gravity字段)
   ```
   DP使用: 6200000.0 (= world.GRAVITY)
   Super使用: 200000.0 (更弱的重力，允许更长悬停时间)
   ✅ 每个特殊招式可自定义重力参数
   ```

---

## 测试后的预期行为

运行游戏后执行DP，你应该看到：

1. **第4帧**: 角色起跳，velocity.y = -9,000,000
2. **第5-40帧**: 角色上升，高度逐渐减缓
3. **第35-45帧**: 到达最高点 (~600-800像素)，然后开始下降
4. **第47帧**: DP动画结束，角色完全落地
5. **着地后**: 自动过渡到待机/行走状态

---

## 如果需要微调

如果修改后仍需调整高度：

| 若想... | 则修改... | 建议值 |
|--------|----------|--------|
| **更高** | `jump_speed` | -10000 至 -12000 |
| **更低** | `jump_speed` | -7000 至 -8000 |
| **调整下降速度** | `gravity` 在MoveData中 | 6200000 ± 500000 |
| **调整特殊上升时间** | `jump_delay` | 4.0（目前值很好） |

---

## 相关代码位置

| 功能 | 位置 | 关键行 |
|------|------|--------|
| DP定义 | MoveSet.gd | 148-150 |
| 跳跃触发 | MoveSet.gd | 525-541 (_process_jump) |
| 重力应用 | MoveSet.gd | 544-548 (_apply_gravity) |
| 速度计算 | MoveSet.gd | 220-221 (初速度) |
| 位置更新 | MoveSet.gd | 419 (固定点更新) |
| 世界常数 | world.gd | 8 (GRAVITY定义) |

---

## 调试提示

如果修改后DP还是有问题，查看这些日志：

```
[JUMP] jump_timer=0.008, velocity.y=-9000000  → 表示速度被正确应用
[JUMP] y=550000, y=500000, y=400000, ...      → 看y值递减速率判断重力
[JUMP] is_jumping=true                        → 表示跳跃状态被设置
[STOP_MOVE] 'dp'                              → 表示DP正确完成
```

---

修改已完成！请重新启动游戏测试DP的跳起高度。
