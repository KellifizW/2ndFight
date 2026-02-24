# 🔧 多段Hit碰撞问题诊断与修复

## 问题症状
- 不设置multihit时，攻击能正常打到对手
- 设置multihit=true之后，攻击无法打到对手

## 根本原因分析

### 问题1：hit_phases可能未被正确加载
在HitResponseHandler中，当检测到`is_multi_hit=true`时：
```gdscript
if active_move and active_move.is_multi_hit and active_move.hit_phases.size() > 0:
    phase_data = _get_multi_hit_phase(active_move, target, elapsed_frames)
    if phase_data == null:
        return  # ❌ 直接返回，跳过碰撞处理！
```

如果`hit_phases`为空或`phase_data`为null，就会**直接return**，导致整个碰撞检测被跳过。

### 问题2：DAVMoveSet中100p没有fallback
```gdscript
_md = _load_smd(smd_100p, "res://data/specials/dav_100p.tres")
if _md: move_library[_md.name] = _md
# ❌ 没有else！如果加载失败，100p就不会被添加到move_library
```

## 修复方案

### ✅ 修改1：HitResponseHandler - 改进多段hit逻辑
**位置**：[HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd#L60-L90)

```gdscript
if active_move and active_move.is_multi_hit:
    if active_move.hit_phases.size() == 0:
        # Fallback：如果hit_phases为空，当作非多段招式处理
        active_move.is_multi_hit = false
        print("[HitResponseHandler] ⚠️  hit_phases 為空，自動降級為非多段模式")
    else:
        # 继续多段hit逻辑，但不再直接return null
```

**改进**：
- 如果`hit_phases`为空，自动fallback到非多段模式，**继续执行碰撞检测**
- 当未到达hit_phase时间点时，使用基础参数而不是返回null
- 添加详细日志追踪碰撞状态

### ✅ 修改2：MoveSet._smd_to_move_data() - 添加多段加载诊断
**位置**：[MoveSet.gd](MoveSet.gd#L171-L215)

```gdscript
# 🔴 读取 hit_phases（多段招式）
var hit_phases = res.get("hit_phases") if "hit_phases" in res else []
var is_multi_hit = res.get("is_multi_hit") if "is_multi_hit" in res else false
if is_multi_hit and hit_phases.size() > 0:
    print("[_smd_to_move_data] ✓ Multi-hit detected for '%s': %d phases loaded" % [mid, hit_phases.size()])
elif is_multi_hit and hit_phases.size() == 0:
    print("[_smd_to_move_data] ⚠️  Multi-hit flagged for '%s' but hit_phases is empty!" % mid)
```

**改进**：
- 清楚显示是否成功加载了hit_phases
- 诊断多段招式配置问题

### ✅ 修改3：DAVMoveSet - 添加100p fallback和诊断
**位置**：[DAVMoveSet.gd](DAVMoveSet.gd#L84-L95)

```gdscript
if _md:
    print("[DAVMoveSet] 100p loaded: is_multi_hit=%s, hit_phases.size()=%d" % [_md.is_multi_hit, _md.hit_phases.size()])
    move_library[_md.name] = _md
else:
    # 添加fallback，确保100p始终存在
    move_library["100p"] = MoveData.new(
        "100p", "DAV", 3.0, 120.0, 60.0, ..., false, []
    )
```

**改进**：
- 100p现在有fallback，不会因为资源加载失败而消失
- 详细打印hit_phases的内容，便于诊断

## 数据流验证

现在的数据流应该是：

```
1. HitResponseHandler 检测到碰撞
   ├─ is_spmove=true ✓
   └─ active_move=100p ✓

2. 检查 is_multi_hit
   ├─ false → 继续正常碰撞处理
   └─ true → 检查 hit_phases
      ├─ size > 0 → 获取 phase_data
      │  ├─ phase_data != null → 应用hit参数
      │  └─ phase_data == null → 使用基础参数（继续处理！）
      └─ size == 0 → Fallback to 非多段模式（继续处理！）

3. 应用碰撞伤害、硬直等效果 ✓
```

关键改进：**即使是多段招式，现在也不会因为hit_phases无效而跳过碰撞处理**

## 测试步骤

运行游戏后，查看日志输出：

```
[_smd_to_move_data] ✓ Multi-hit detected for '100p': 3 phases loaded
[DAVMoveSet] 100p loaded: is_multi_hit=true, hit_phases.size()=3
  [Phase0] frame=8, damage=5.0, hitstun=18, knockback=50.0
  [Phase1] frame=16, damage=5.0, hitstun=18, knockback=50.0
  [Phase2] frame=24, damage=6.0, hitstun=30, knockback=120.0
```

如果看到这些，说明hit_phases已正确加载。然后执行100p时，应该看到：

```
[HitResponseHandler] 碰撞检测：move=100p, is_spmove=true, is_multi_hit=true, hit_phases.size()=3
[HitResponseHandler] ℹ️  100p 多段招式但未达hit時間點 (elapsed=X)
[HitResponseHandler] XXX 擊中 OOO
  - hitstun: YY frames
  - damage: ZZ
```

如果仍然看不到最后的碰撞日志，说明问题在其他地方（hitbox不存在、方向错误等）。

---

修复完成：2026-02-24
关键改进：从**碰撞失败（return）**改为**碰撞成功（fallback）**
