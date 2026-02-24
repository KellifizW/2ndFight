# ThrowHandler 摔投 Pivot 位置调整指南

## 📍 什么是 Pivot 位置？

**Pivot（枢轴）位置**决定了在摔投过程中，**被摔者相对于攻击者的位置**。

```
攻击者 (DEN)                    被摔者 (DAV)
    ●──────────────────────────→●
    |                              |
    |    pivot_offset_x           |
    |    pivot_offset_y           |
    └──────────────────────────────┘
```

## 🎮 如何编辑 Pivot 位置

### 方法 1：修改 ThrowData 资源文件（推荐）

每个角色的摔投数据存储在独立的 `.tres` 资源文件中：

**文件位置**：
- Dennis (DEN): `data/dennis_throw_data.tres`
- Dave (DAV): `data/dave_throw_data.tres`

**编辑步骤**：

1. **在 Godot 中打开资源文件**
   - FileSystem 面板中找到 `data/dennis_throw_data.tres`
   - 双击打开 Inspector

2. **找到 Pivot Position Offset 设置**：
   ```
   Position Settings ▼
     ├─ Pivot Offset X: 50.0    ← 水平距离（像素）
     └─ Pivot Offset Y: -30.0   ← 垂直距离（像素，负值=向上）
   ```

3. **调整数值**：
   - **Pivot Offset X**：被摔者距离攻击者的**水平距离**
     - 正值 = 被摔者在前方（面向方向）
     - 负值 = 被摔者在背后
     - 建议范围：30.0 ~ 80.0 像素
   
   - **Pivot Offset Y**：被摔者距离攻击者的**垂直距离**
     - 负值 = 被摔者在上方（通常用于举起动作）
     - 正值 = 被摔者在下方
     - 建议范围：-50.0 ~ 20.0 像素

4. **保存并测试**：
   - Ctrl+S 保存资源
   - 运行游戏测试摔投动画

### 方法 2：在代码中动态修改（高级用法）

如果需要根据条件动态调整，可在 [ThrowHandler.gd](../ThrowHandler.gd#L125-L145) 的 `lock_opponent()` 函数中修改：

```gdscript
func lock_opponent(opponent: Node, throw_data_resource: ThrowData) -> void:
    grabbed_opponent = opponent
    throw_data = throw_data_resource
    
    # 🎯 动态调整 pivot 位置（示例）
    # 根据对手状态、距离、特殊条件等调整
    
    # 示例 1：根据对手体型调整
    if "character_size" in opponent and opponent.character_size == "large":
        throw_pivot_offset.x = throw_data.pivot_offset_x * 1.2  # 大体型角色稍远一些
    else:
        throw_pivot_offset.x = throw_data.pivot_offset_x
    
    # 示例 2：根据摔投类型调整
    if throw_data.resource_name == "super_throw":
        throw_pivot_offset.y = throw_data.pivot_offset_y - 20  # 超必杀举得更高
    else:
        throw_pivot_offset.y = throw_data.pivot_offset_y
    
    # ... 其余代码保持不变
```

## 📐 Pivot 位置与动画配合

### 重要原则：**Pivot 位置应与动画视觉效果匹配**

**示例场景**：Dennis 的摔投动画举起 Dave

1. **动画设计**：
   - Dennis 在 AnimatedSprite2D 中播放"举起"动作
   - 视觉上双手位置在 (50, -30) 像素位置

2. **Pivot 设置**：
   ```
   Pivot Offset X: 50.0   ← 匹配动画中双手的水平位置
   Pivot Offset Y: -30.0  ← 匹配动画中双手的垂直位置
   ```

3. **效果**：
   - Dave 的 root 位置被锁定在 Dennis 的 (50, -30) 位置
   - Dave 的精灵显示在"被举起"的位置
   - 视觉上看起来 Dennis 确实"抓住"了 Dave

### 调整技巧：

**如果被摔者显示位置不对**：
1. 暂停游戏在摔投帧
2. 观察被摔者应该在哪里
3. 测量偏差（水平/垂直像素）
4. 调整 Pivot Offset X/Y 相应数值
5. 重新测试

## 🔧 常见应用场景

### 场景 1：过肩摔（Over-the-Shoulder Throw）
```
Pivot Offset X: 40.0   # 靠近攻击者
Pivot Offset Y: -40.0  # 高举过头
```

### 场景 2：扫堂腿（Leg Sweep）
```
Pivot Offset X: 60.0   # 稍远（腿部延伸）
Pivot Offset Y: 30.0   # 接近地面（正值）
```

### 场景 3：背摔（Backdrop）
```
Pivot Offset X: -20.0  # 负值 = 背后
Pivot Offset Y: -10.0  # 稍微抬起
```

### 场景 4：抱摔（Bear Hug）
```
Pivot Offset X: 30.0   # 非常近（紧贴）
Pivot Offset Y: -20.0  # 略微举起
```

## ⚙️ 技术细节

### Fixed-Point 坐标系统

ThrowHandler 内部使用 **fixed-point 坐标系**（1 像素 = 1000 单位）：

```gdscript
// update_opponent_position() 中的核心逻辑：
var facing = player_node.facing_direction  // 1.0 或 -1.0
var target_position = player_node.fixed_position + Vector2i(
    int(throw_pivot_offset.x * facing),  // 自动镜像（面向左时反转）
    throw_pivot_offset.y
)
grabbed_opponent.fixed_position = target_position
```

**自动镜像机制**：
- 面向右 (facing = 1.0): `pivot_offset_x = +50` → 对手在右前方
- 面向左 (facing = -1.0): `pivot_offset_x = +50 × (-1) = -50` → 对手在左前方（自动镜像）

### 位置锁定频率

- **更新频率**：每个物理帧（120 FPS）
- **锁定时机**：从 `HOLD` 阶段开始，直到 `release_opponent()` 调用
- **优先级**：ThrowHandler 的位置设置会**覆盖**所有其他系统（Movement、PushManager 等）

## 🎨 视觉调试技巧

### 使用 Debug 模式实时查看位置

在 [ThrowHandler.gd](../ThrowHandler.gd) 中启用 debug：

```gdscript
@export var debug_enabled: bool = true  # 在 Inspector 中勾选
```

启用后，控制台每 30 帧输出：
```
[ThrowHandler] Position locked | attacker: (635000, 550000) | opponent: (585000, 520000) | offset: (50000, -30000)
```

**读取方式**：
- `attacker`: 攻击者的 fixed_position（单位）
- `opponent`: 被摔者的 fixed_position（单位）
- `offset`: 实际应用的 pivot 偏移（单位，已乘以 1000）

**转换为像素**：除以 1000
```
offset: (50000, -30000) → (50, -30) 像素
```

## 📋 快速参考

| 参数 | 位置 | 类型 | 默认值 | 用途 |
|------|------|------|--------|------|
| `pivot_offset_x` | ThrowData 资源 | float | 50.0 | 水平距离（像素） |
| `pivot_offset_y` | ThrowData 资源 | float | -30.0 | 垂直距离（像素） |
| `throw_pivot_offset` | ThrowHandler.gd | Vector2i | (50000, -30000) | 内部存储（fixed-point） |
| `facing_direction` | Player/Movement | float | ±1.0 | 自动镜像计算 |

## ✅ 最佳实践

1. **先设计动画，再调整 Pivot**
   - 动画优先：在 AnimationPlayer 中完成攻击者的摔投动作
   - 然后调整 Pivot 使被摔者"贴合"攻击者的动作

2. **使用小步调整**
   - 每次修改 ±5 像素
   - 测试后再继续调整
   - 避免大幅度跳变

3. **考虑对称性**
   - 如果摔投动画是对称的（左右镜像），Pivot X 只需设置一次
   - facing_direction 会自动处理镜像

4. **保持合理范围**
   - Pivot Offset X: 20 ~ 100 像素（太远会显得脱节）
   - Pivot Offset Y: -60 ~ 40 像素（太高/太低会显得不自然）

5. **为不同角色创建独立 ThrowData**
   - 每个角色都应有自己的 `*_throw_data.tres` 文件
   - 这样可以针对不同体型/动画风格调整

---

## 🔗 相关文档

- [ThrowHandler 动画事件设置](ThrowHandler_Animation_Events_Setup.md)
- [ThrowData 资源完整字段说明](../data/ThrowData.gd)
- [摔投系统架构总览](../AI_SYSTEM_README.md#throw-system)

---

**最后更新**: 2026-02-09
**适用版本**: Godot 4.x | 120 FPS Physics System
