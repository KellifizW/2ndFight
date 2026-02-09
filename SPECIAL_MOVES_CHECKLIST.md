# 特殊招式数据驱动化 - 检查清单

## 📋 当前状态（已完成）

### ✅ 1. 数据层（SpecialMoveData）
- [x] SpecialMoveData.gd 定义完整（move_id, character_requirement, damage, knockback, hitstun 等）
- [x] 所有特殊招式已有 .tres 资源文件
  - dav_powerkk.tres
  - dav_super.tres
  - dav_dp.tres
  - dav_fireball.tres
  - den_spnk.tres
  - den_hdk.tres
  - den_fireball.tres

### ✅ 2. 加载层（MoveSet.gd 升级）
- [x] 新增 `@export var special_moves_data: Array[SpecialMoveData]` (L15)
- [x] 保留旧版本后备兼容 `LEGACY_SPECIAL_MOVE_RESOURCES` (L18-25)
- [x] 更新 `_initialize_move_library()` 支持导出数组 (L93-128)
- [x] 自动后备加载机制（检测到 export 为空时）

### ✅ 3. 执行层（Player.gd）
- [x] 通过 MoveSet 节点访问招式数据
- [x] move_library 正确映射 move_id → SpecialMoveData

---

## 🎯 使用方式

### 方式 A：自动兼容模式（推荐 - 现在可用）
✅ **无需任何配置**，游戏立即可用
- 系统自动加载 LEGACY_SPECIAL_MOVE_RESOURCES 中的资源
- 所有特殊招式正常工作
- 与之前完全相同的体验

```
启动游戏 → [MoveSet] 自动加载旧版本资源 → ✅ 游戏正常运行
```

### 方式 B：Inspector 直观管理（升级 - 推荐中期迁移）
1. 打开 player1.tscn / player2.tscn
2. 选择 MoveSet 节点
3. 在 Inspector 中找到"Special Moves Data"
4. 手动拖拽 7 个 .tres 资源进去
5. 保存场景

```
Inspector 中拖拽资源 → special_moves_data 数组填充 → MoveSet 读取 export 数组 → ✅ 优先级高于后备
```

---

## 📊 关键改动说明

| 文件 | 改动 | 目的 |
|------|------|------|
| MoveSet.gd | 新增 @export special_moves_data | 在 Inspector 中直观管理 |
| MoveSet.gd | 更新 _initialize_move_library() | 优先读取 export，后备加载旧资源 |
| MoveSet.gd | 保留 LEGACY_SPECIAL_MOVE_RESOURCES | 向后兼容 |
| SPECIAL_MOVES_DATA_DRIVEN_GUIDE.md | 新增 | 详细使用指南 |
| InitializeSpecialMovesResources.gd | 新增（可选） | 自动初始化工具 |

---

## ✨ 与 AttackData/ThrowData 的对比

### ✅ 现在已统一

| 系统 | 位置 | Export 变量 | 资源类型 | 在 Inspector 可见 |
|------|------|-----------|---------|-----------------|
| 普通攻击 | Player.gd | @export var attack_data | AttackData | ✅ 是 |
| 摔投 | Player.gd | @export var throw_data | ThrowData | ✅ 是 |
| 特殊招式 | MoveSet.gd | @export var special_moves_data | SpecialMoveData[] | ✅ 是（升级后） |

---

## 🧪 验证步骤

### 测试 1：自动兼容性
```
1. 启动游戏
2. 打开 Editor Console（View → Output）
3. 查找输出信息：
   ✅ "[MoveSet] Library initialized with X move types"
   ✅ 如果显示自动加载信息，说明后备机制工作正常
```

### 测试 2：招式执行
```
1. 游戏中选择 DAV 角色
2. 尝试执行：
   - Fireball（波動拳）- 下 → 下前 → 前 + P
   - DP（昇龍拳）- 前 → 下 → 下前 + P
   - Power KK（百貌崩）- 下 + KK
3. 所有招式应正常执行 ✅
```

### 测试 3：数据验证
```gdscript
# 在 MoveSet 的任何函数中验证
print(move_library.keys())
# 应输出：[fireball, dp, powerkk, super, spnk, hdk] 等
```

---

## 🚀 后续优化方向（可选）

### 短期（推荐）
- [ ] 在 player.gd 中也导出 special_moves_data（保持对称性）
- [ ] 为每个场景（player1.tscn / player2.tscn）独立配置资源数组

### 中期
- [ ] 为不同角色创建单独的资源集合（dav_special_moves.tres, den_special_moves.tres）
- [ ] 支持热加载特殊招式资源（方便动态调整难度）

### 长期
- [ ] 创建 SpecialMoveSet 资源类（整合所有特殊招式），类似 AttackData 的设计
  ```gdscript
  class SpecialMoveSet extends Resource:
      @export var powerkk: SpecialMoveData
      @export var super: SpecialMoveData
      @export var dp: SpecialMoveData
      @export var fireball: SpecialMoveData
      # ... 等等
  ```
  这样 Player.gd 就可以：`@export var special_moves: SpecialMoveSet`

---

## 💡 常见问题

**Q: 为什么还保留旧版本的硬编码路径？**  
A: 向后兼容。如果某个旧项目没有更新到新版本，游戏仍会自动工作。

**Q: 修改招式参数时，是否需要重启游戏？**  
A: 
- 如果在 Inspector 中修改 .tres 资源：需要重启（Godot 限制）
- 如果在代码中动态修改：实时生效

**Q: 我可以为 Player A 和 Player B 配置不同的招式吗？**  
A: 可以！因为现在是 @export，每个 player1.tscn 和 player2.tscn 可以有不同的数组。

**Q: 新系统会影响游戏性能吗？**  
A: 否。加载时间略有增加（可忽略），运行时零开销。

---

## 📌 重要提示

✨ **现在无需任何操作，游戏已经完全可用！**

系统会自动：
1. 检测 special_moves_data 是否有内容
2. 如果为空，自动加载旧版本资源
3. 正常运行所有特殊招式

您可以选择立即升级或稍后再升级到 Inspector 管理模式。

---

**相关文件**：
- [SPECIAL_MOVES_DATA_DRIVEN_GUIDE.md](SPECIAL_MOVES_DATA_DRIVEN_GUIDE.md) - 详细指南
- [MoveSet.gd](MoveSet.gd) - 实现代码
- [data/SpecialMoveData.gd](data/SpecialMoveData.gd) - 数据定义
- [data/specials/](data/specials/) - 招式资源（.tres 文件）
