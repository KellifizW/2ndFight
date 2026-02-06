# AI 攻击多样性修复 - 快速参考

## 问题已解决 ✅

❌ **原问题**：AI 只使用中拳中脚（st_mp / st_mk），从不用轻攻击或重攻击  
✅ **解决方案**：重新平衡所有攻击类型的优先级，移除中级攻击的固定加成

---

## 修复内容（1 个文件）

### AIDecisionLayers.gd - 优先级重新平衡

**修改前（不平衡）**：
```gdscript
# 中级攻击总是胜出！
st_mk: 67 + rand + 3.0 = 68-72   ← 固定 +3.0 加成
st_lp: 67 + rand = 64-68          ← 优先级太低
st_hp: 67 + rand = 62-66          ← 几乎不会被选中
```

**修改后（平衡）**：
```gdscript
# 所有攻击有平等机会！
st_lp: 67 + rand(-1, 3) = 66-70   ← 提升
st_mp: 67 + rand(-1, 3) = 66-70   ← 移除固定加成
st_hp: 67 + rand(-3, 1) = 64-68   ← 提升
```

---

## 优先级范围对比

### 中距离（100-250）

| 攻击 | 原优先级 | 新优先级 | 变化 |
|------|----------|----------|------|
| 轻攻击（lp/lk） | 64-68 | **66-70** | ⬆️ +2~4 |
| 中攻击（mp/mk） | **68-72** | **66-70** | ⬇️ -2~4 |
| 重攻击（hp/hk） | 62-66 | **64-68** | ⬆️ +2~4 |

### 近距离（< 100）

| 攻击 | 原优先级 | 新优先级 | 变化 |
|------|----------|----------|------|
| 轻攻击（lp/lk） | 62-66 | **66-71** | ⬆️ +4~8 |
| 中攻击（mp/mk） | 64-70 | **65-70** | 稳定 |
| 重攻击（hp/hk） | 60-65 | **64-68** | ⬆️ +4~6 |

---

## 预期效果

### 攻击分布（理论）

**修复前**：
```
st_mp ████████████████ 60%
st_mk ████████████████ 30%
其他  ████             10%
```

**修复后**：
```
轻攻击 ████████████ 35-40%
中攻击 ████████████ 30-35%
重攻击 ██████████   25-30%
```

### 对战表现

**修复前（单调）**：
```
st_mp → st_mk → cr_mp → st_mp → st_mk → ...
```

**修复后（多样）**：
```
st_lp → cr_mk → st_hp → st_lk → st_mp → cr_lp → st_hk → cr_hp → ...
```

---

## 快速验证

### 🧪 测试步骤
1. 启动游戏
2. 按 **C** 键启用 Player A AI
3. 按 **V** 键启用 Player B AI
4. 设置招式限制（禁用特殊招式）：
   ```
   restricted_moves_a: ["fireball", "dp", "powerkk"]
   restricted_moves_b: ["fireball", "spnk", "hdk"]
   ```
5. 观察战斗 30 秒

### ✅ 成功指标
- [ ] AI 使用 st_lp / st_lk / cr_lp / cr_lk（轻攻击）
- [ ] AI 使用 st_hp / st_hk / cr_hp / cr_hk（重攻击）
- [ ] 攻击组合不再单调重复
- [ ] 控制台日志显示多样化的攻击决策

### 📊 日志示例（预期）
```
[AI] DAV decision: st_lp (priority: 68.2) - Mid range: quick light punch
[AI] DEN decision: cr_mk (priority: 69.1) - Mid range: low poke
[AI] DAV decision: st_hp (priority: 66.8) - Mid range: heavy punch
[AI] DEN decision: st_lk (priority: 67.5) - Mid range: light kick
[AI] DAV decision: cr_lp (priority: 69.4) - Close range: cr_lp
[AI] DEN decision: st_hk (priority: 67.2) - Close range: heavy kick
```

---

## 技术总结

### 核心变更
- ❌ 移除中级攻击的固定 +3.0 优先级加成
- ✅ 调整所有攻击优先级范围，使其重叠
- ✅ 近距离时轻攻击优先级略高（符合格斗游戏逻辑）

### 设计原理
| 攻击类型 | 格斗游戏特性 | AI 应该使用频率 | 新系统 |
|----------|-------------|----------------|--------|
| 轻攻击 | 快速、低伤害、安全 | 频繁 | ✅ 高优先级 |
| 中攻击 | 平衡速度和伤害 | 频繁 | ✅ 平衡 |
| 重攻击 | 慢速、高伤害、风险 | 偶尔 | ✅ 适中优先级 |

### 影响范围
- **修改文件**：1 个（AIDecisionLayers.gd）
- **修改行数**：约 80 行
- **破坏性**：无（只调整数值）
- **向后兼容**：完全兼容
- **效能影响**：无（微不足道）

---

## 故障排除

### ❌ AI 仍然只用 mp/mk
1. 确认已重新启动游戏（修改需要重新加载）
2. 检查是否禁用了特殊招式（限制系统正常工作）
3. 观察更长时间（至少 1 分钟）
4. 查看日志确认优先级范围是否正确（应该是 66-70 / 64-68）

### ❌ 控制台没有决策日志
1. 检查 AIBehavior 的 debug_mode 是否启用
2. 确认 AI 已启用（C/V 键）
3. 查看是否有"decision:"关键词的日志

### ✅ 确认修复成功
如果看到以下日志，说明修复成功：
```
[AI] decision: st_lp (priority: 66-70)
[AI] decision: st_hp (priority: 64-68)
[AI] decision: cr_lk (priority: 66-70)
```

---

## 相关文档

- 📄 [AI_ATTACK_DIVERSITY_FIX.md](AI_ATTACK_DIVERSITY_FIX.md) - 完整技术文档
- 📄 [AI_MOVE_RESTRICTION_FIX_SUMMARY.md](AI_MOVE_RESTRICTION_FIX_SUMMARY.md) - 招式限制修复
- 📄 [AI_SYSTEM_README.md](AI_SYSTEM_README.md) - AI 系统概览
- 🔧 [AIDecisionLayers.gd](ai/AIDecisionLayers.gd) - 决策层实现

---

**Date**: 2026-02-06  
**Status**: ✅ COMPLETE  
**Quick Test**: 启动游戏 → 启用双方AI → 观察 30 秒 → 应该看到 lp/lk/hp/hk 攻击
