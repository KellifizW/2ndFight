# 特殊招式数据驱动化升级指南

## 📋 现状总结

你的特殊招式系统已经是 **100% 数据驱动**的！现在升级后，可以像管理 `AttackData` 和 `ThrowData` 一样在 Inspector 中直观管理 `.tres` 资源。

---

## ✨ 新功能

### Before（旧方式）
```gdscript
// MoveSet.gd 中硬编码
const SPECIAL_MOVE_RESOURCES: Array[String] = [
    "res://data/specials/dav_powerkk.tres",
    "res://data/specials/dav_super.tres",
    // ... 无法在 Inspector 中修改
]
```

### After（新方式）
```gdscript
// MoveSet.gd 中导出为 @export
@export var special_moves_data: Array[SpecialMoveData] = []
// ✅ 可在 Inspector 中直观添加/移除/编辑所有资源
```

---

## 🚀 使用步骤

### 方式 1：自动初始化（推荐）

1. **启动游戏**（运行 world.tscn）
2. **打开 Editor Console**（View → Output）
3. 观察输出，应该看到：
   ```
   [MoveSet] 检测到 special_moves_data 为空，自动加载旧版本资源...
   [MoveSet] Library initialized with 5 move types: [fireball, dp, powerkk, super, spnk, hdk]
   ```
   ✅ 系统会自动后备加载所有旧版本资源，游戏正常运行

### 方式 2：手动在 Inspector 中配置（永久方案）

1. **打开 player1.tscn** 或 **player2.tscn**
2. **选择 MoveSet 节点**（在 Player 下）
3. 在 Inspector 右侧找到 **Special Moves Data** 数组
4. 点击"Array[SpecialMoveData]"展开
5. **设置数组大小**为 7（或你有多少个招式）
6. **逐一拖拽资源**：
   - `res://data/specials/dav_powerkk.tres` → 第0个
   - `res://data/specials/dav_super.tres` → 第1个
   - `res://data/specials/dav_dp.tres` → 第2个
   - （以此类推...）
7. **保存场景**（Ctrl+S）

**提示**：Inspector 支持直接拖拽 `.tres` 文件进去！

---

## 🎯 设计对比

### AttackData（现有）
```gdscript
// player.gd
@export var attack_data: AttackData  // ← 在 Inspector 中直观加载

// 使用
ATTACK_TABLE = {
    "st_mp": attack_data.st_mp,
}
```

### ThrowData（现有）
```gdscript
// player.gd
@export var throw_data: ThrowData  // ← 在 Inspector 中直观加载
```

### SpecialMoveData（升级后 = 同样流程）
```gdscript
// MoveSet.gd（作为 MoveSet 的子组件）
@export var special_moves_data: Array[SpecialMoveData] = []  // ✨ 新增

// 使用
move_library["fireball"] = []
move_library["fireball"].append(special_moves_data[i])
```

---

## 📊 特殊招式结构

每个 `SpecialMoveData` 资源包含：

```gdscript
class SpecialMoveData extends Resource:
    @export var move_id: String = ""                    # "fireball", "dp", "powerkk"
    @export var character_requirement: String = "*"    # "DAV", "DEN", "*"（通用）
    
    # 战斗数据
    @export var damage: float = 0.0                     # 伤害值
    @export var knockback: float = 0.0                  # 推力
    @export var hitstun_frames: int = 18                # 硬直帧数 @60FPS
    @export var blockstun_frames: int = 10              # 防御硬直 @60FPS
    
    # 时序数据
    @export var duration_frames: int = 0                # 招式总长度
    @export var move_distance: float = 0.0              # 位移距离
    
    # 特殊参数
    @export var is_projectile: bool = false             # 是否为远距离招
    @export var projectile_speed: float = 0.0           # 弹体速度
    # ... 还有更多参数
```

**修改方式**：
1. **在 Inspector 中**：找到对应的 `.tres` 文件，直接编辑每个参数
2. **在代码中**：
   ```gdscript
   var move = get_move_data_for_character("fireball", "DAV")
   move.damage = 15.0  // 修改伤害
   ```

---

## ✅ 优势对比

| 特性 | 旧方式（硬编码） | 新方式（Export） |
|------|-----------------|-----------------|
| 在 Inspector 看到资源 | ❌ 无法直观管理 | ✅ 完全可见 |
| 添加新招式 | ❌ 需修改代码 | ✅ 直接拖拽资源 |
| 修改参数 | ❌ 需要两步（修改 .tres + 代码） | ✅ 只需修改 .tres |
| 场景隔离 | ❌ 全局常量 | ✅ 每个 MoveSet 实例独立 |
| 与 AttackData 一致 | ❌ 不同的模式 | ✅ 统一的数据驱动设计 |

---

## 🔄 后备兼容性

新系统包含自动后备机制：

```gdscript
if resources_to_load.is_empty():
    // 如果 special_moves_data 为空，自动加载旧版本硬编码资源
    for path in LEGACY_SPECIAL_MOVE_RESOURCES:
        var resource = load(path)
        if resource != null:
            resources_to_load.append(resource)
```

✅ **这意味着**：
- 游戏会立即可用（向后兼容）
- 你可以逐步迁移（不强制一次性修改）
- 旧存档和项目不会破损

---

## 🧪 验证方法

1. **启动游戏**
2. **打开 Editor Console**（View → Output）
3. **看输出**：
   ```
   [MoveSet] Library initialized with 5 move types: [fireball, dp, powerkk, super, spnk, hdk]
   ```
   ✅ 说明所有招式已正确加载

4. **测试招式执行**：在游戏中尝试执行特殊招式（如 Fireball, DP）
5. **命令行检查**：
   ```gdscript
   print(move_set.move_library.keys())  // 应看到 [fireball, dp, ...]
   ```

---

## 💡 下一步建议

### 立即可行
- ✅ 游戏已经兼容，无需修改
- ✅ 所有招式仍然正常工作

### 可选优化
1. **在 player.gd 中也导出 `special_moves_data`**：
   ```gdscript
   // player.gd
   @export var special_moves_data: Array[SpecialMoveData] = []
   
   // 在 _ready() 中传递给 MoveSet
   if move_set:
       move_set.special_moves_data = special_moves_data
       move_set._initialize_move_library()
   ```
   这样 Player 和 MoveSet 的界面就完全一致了

2. **为每个角色配置单独的招式集**：
   - p1_attack_data.tres （player1 的普通攻击）
   - p2_attack_data.tres （player2 的普通攻击）
   - p1_special_moves.tres （player1 的特殊招式）
   - p2_special_moves.tres （player2 的特殊招式）

---

## 📚 参考资源

- [AttackData 设计](data/AttackData.gd) - 参考此模式
- [ThrowData 设计](data/ThrowData.gd) - 参考此模式
- [SpecialMoveData 完整定义](data/SpecialMoveData.gd)
- [MoveSet 实现](MoveSet.gd#L14) - 查看 special_moves_data export
- [特殊招式资源示例](data/specials/) - 查看所有 .tres 文件

---

## 🎉 总结

✨ **你的特殊招式系统现在完全数据驱动且直观可管理！**

- ✅ 已实现数据驱动架构
- ✅ 现在支持在 Inspector 中直观编辑
- ✅ 完全向后兼容（自动后备加载）
- ✅ 设计模式与 AttackData/ThrowData 一致
