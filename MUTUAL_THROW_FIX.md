# 互相摔投冲突修复说明

## 🎮 问题定义

**之前的表现**：
- 角色 A 执行 throw_enter
- 角色 B 执行 throw_enter
- 两个 ThrowBox 互相碰撞
- 双方 **都成功进入 throw_seq**，互相锁定并绑在一起
- 由于 PushManager 也被禁用了，导致**疯狂后移**的怪现象

## ✅ 修复方案

### 核心逻辑变化

当双方同时执行摔投时（互相检测到 throw_enter）：

1. **不进入 throw_seq**
   - 攻击者保持 throw_enter 动画
   - 被摔者也保持 throw_enter 动画（不进入 is_being_thrown 状态）

2. **互相向后推开**
   - 调用 `ThrowHandler.handle_mutual_throw_collision()`
   - 施加反向速度（300 像素/秒）
   - 双方相反方向退后

3. **动画完成后自动重置**
   - throw_enter 动画完成
   - 自动调用 `reset_attack_state()`
   - 回到中立状态

## 🔧 技术细节

### 修改文件

#### 1. **ThrowHandler.gd** （新增函数）
```gdscript
func handle_mutual_throw_collision(opponent: Node) -> void:
    """处理双方同时执行摔投的冲突"""
    # 推开速度：300 像素/秒（固定点单位）
    var knockback_velocity = int(300.0 * world_node.SIMULATION_SCALE)
    
    # 攻击者向后推开（与朝向相反）
    player_node.fixed_velocity.x = -knockback_velocity * int(player_facing)
    
    # 对手向后推开（与朝向相反）
    opponent.fixed_velocity.x = -knockback_velocity * int(opponent_facing)
```

#### 2. **Player.gd** - `_check_throw_hit()` 函数
**添加了互相冲突检测**：
```gdscript
# 检查对手是否也在执行摔投
var opponent_in_throw = "attack_type" in opponent and opponent.attack_type in ["throw_enter", "throw_seq"]

if opponent_in_throw:
    # 互相摔投冲突：双方都向后推开
    throw_handler.handle_mutual_throw_collision(opponent)
    throw_hit_detected = true  # 标记已检查
    return  # 不进入 throw_seq
```

#### 3. **Player.gd** - `_on_animation_player_finished()` 函数
**改进了状态检查**：
```gdscript
if anim_name == "throw_enter":
    # 只在真正进入 throw_seq 时，跳过重置
    if throw_hit_detected and attack_type == "throw_seq":
        # 成功摔投，进入 throw_seq
        return
    else:
        # 互相冲突 或 没有命中，重置
        reset_attack_state()
```

#### 4. **Movement.gd** - `_physics_process()` 函数
**修改了 throw lock 机制**：
```gdscript
# 【修改】只在 throw_seq 时锁定，throw_enter 允许移动
if "attack_type" in self and self.attack_type == "throw_seq":
    is_throw_locked = true

# throw_enter 时不锁定，允许互相冲突时的速度应用
```

## 🎬 执行流程图

```
时间轴：Frame 0━━━━━━━━━━━━━━━━━━━━━━┓
                                    ┃
Player A: [throw_enter 动画播放 ~30 帧]┃
          ↓ (frame 5)                 ┃
          ThrowBox collision detected ┃
          ↓                           ┃
          检查 B 的状态               ┃
          → B.attack_type == "throw_enter"  ← 互相冲突！
          ↓                           ┃
          施加速度: vel_x = -300,000  ┃
          keep throw_enter 动画播放   ┃
                                    ┃
Player B: [throw_enter 动画播放 ~30 帧]┃
          ↓ (frame 3)                 ┃
          ThrowBox collision detected ┃
          ↓                           ┃
          检查 A 的状态               ┃
          → A.attack_type == "throw_enter"  ← 互相冲突！
          ↓                           ┃
          施加速度: vel_x = +300,000  ┃
          keep throw_enter 动画播放   ┃
                                    ┃
时间轴：Frame 30━━━━━━━━━━━━━━━━━━━━━━┛
                    ↓
          throw_enter 动画完成
          ↓
          双方都调用 reset_attack_state()
          ↓
          回到中立状态（Walk/Idle）
          
【视觉效果】：双方互相推开，各向后退，然后恢复正常
```

## 🧪 测试清单

### 测试场景 1：简单互相摔投

1. **Player A**：走近 Player B，输入 st_lp + st_lk（摔投）
2. **Player B**：同时输入 st_lp + st_lk（摔投）
3. **预期结果**：
   - ✅ 双方都进入 throw_enter 动画
   - ✅ 双方互相向后推开（~1-2 米）
   - ✅ 双方各自完成 throw_enter 动画
   - ✅ 双方回到中立状态（不互相绑定）

### 测试场景 2：一方正常摔投，另一方逃脱

1. **Player A**：执行摔投，成功击中 Player B
2. **预期结果**：
   - ✅ A 进入 throw_seq
   - ✅ B 进入 is_being_thrown 状态（被举起）
   - ✅ B 可以按键逃脱（mash buttons）
   - ✅ 正常的摔投→逃脱流程

### 测试场景 3：快速连续摔投

1. **Player A**：执行摔投，throw_enter 完成
2. **立即输入**：再次摔投（st_lp + st_lk）
3. **预期结果**：
   - ✅ 第一次 throw_enter 正常完成并重置
   - ✅ 第二次 throw_enter 立即启动
   - ✅ throw_hit_detected 在新摔投时被重新初始化

## 📊 性能影响

- **CPU**：无额外开销（只是多一个 if 检查）
- **内存**：无增加（没有新的数据结构）
- **网络**：对于联网对战，互相冲突信息通过输入重放自动同步

## 🔗 相关系统

- **PushManager**：在摔投期间被禁用（包括 throw_enter），互相冲突时由 ThrowHandler 直接施加速度
- **Movement.gd**：throw_enter 允许速度应用，throw_seq 锁定位置
- **AnimationPlayer**：throw_enter 动画完成时触发 `_on_animation_player_finished()`

---

**修复日期**：2026-02-09
**测试状态**：待验证 ✓
