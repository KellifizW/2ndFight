# DP跳的高度问题 - 完整分析与修复

## 📍 DP高度设定位置

**文件**: [MoveSet.gd](MoveSet.gd#L148)  
**行号**: 第148-150行

```gdscript
move_library["dp"] = MoveData.new(
    "dp", "DAV", 5.0, 320.0, 47.0, 200.0, 4.0, -2000.0, false, false, 6200000.0, "special", true, "none", 0.0, 0.0, 0.0,
    6200000.0, -2700.0, 20.0, 39, 23  # 🟢 knockfly_gravity: 100→20
)
```

### DP参数解读

| 参数位置 | 参数名 | 当前值 | 含义 | 单位 |
|---------|--------|--------|------|------|
| 参数8 | `jump_speed` | **-2000.0** | 跳跃初始速度 | 像素/帧（未缩放） |
| 参数11 | `gravity` | **6200000.0** | 移动期间的重力 | 已缩放单位 |
| 参数17 | `knockfly_gravity` | **6200000.0** | 被击后的重力 | 已缩放单位 |
| 参数18 | `knockfly_vertical_speed` | **-2700.0** | 被击后的垂直速度 | 像素/帧（未缩放） |

---

## ❌ 根本问题：重力过大导致快速下降

### 物理模拟流程

1. **跳起触发** (`_process_jump()` 第4帧)：
   ```
   velocity.y = jump_speed * SIMULATION_SCALE
             = -2000 * 1000
             = -2,000,000  ✅ 正确
   ```

2. **重力应用** (每帧)：
   ```
   velocity.y += gravity * delta
            += 6200000.0 * (1/60)
            += 103,333.33 per frame  ⚠️ 过大！
   ```

3. **速度变化**：
   - 第1帧: `velocity.y = -2,000,000 + 103,333 = -1,896,667`
   - 第5帧: `velocity.y = -2,000,000 + 516,667 = -1,483,333` (速度减半)
   - 第10帧: `velocity.y = -2,000,000 + 1,033,333 = -966,667`
   - **第20帧**: `velocity.y = -2,000,000 + 2,066,666 ≈ 66,666` (开始下降)
   - **第20-31帧**: 角色上升约150像素，然后快速下降

### 日志验证问题

从你的日志：
```
[JUMP] y=550000, jump_timer=0.000
  → JUMP TRIGGERED! velocity.y=-2000000

[JUMP] y=534193  (上升16807单位 ≈ 17像素)
[JUMP] y=519249  (再上升14944单位 ≈ 15像素)
[JUMP] y=505166  (再上升14083单位 ≈ 14像素)
...
[JUMP] y=397248  (最高点)
[JUMP] y=550000  (落地)
```

**最高高度差**: `550000 - 397248 = 152,752` 单位 ≈ **153像素**  
**预期高度** (用正确的重力): ~400-500像素  
**实际上升时间**: 约18-19帧（整个0.9秒动画的20%）

---

## 🔍 根本原因：gravity数值设计错误

### 问题源头

`gravity: 6200000.0` 被设计成：
- **假设**: 这是已经乘以 `SIMULATION_SCALE (1000)` 的值
- **实际**: 这个值是**标准world.GRAVITY**的等价值
- **而world.GRAVITY = 6,200,000** (在world.gd第8行)

所以：
```
MoveSet DP gravity = 6200000.0
World standard gravity = 6200000.0

结果：DP跳跃受到与普通跳跃相同的重力
问题：但DP的jump_speed (-2000) 远小于normal jump_speed
导致：height = velocity²/gravity，DP跳跃高度不足
```

### 对比分析

从Movement.gd或JumpHandler.gd查看普通跳跃的jump_speed值：

**假设**普通跳跃参数（典型fighting game）：
- Normal jump_speed: -8000 ~ -12000 (像素/帧)
- 重力: world.GRAVITY = 6200000.0

**DP参数**：
- DP jump_speed: **-2000** (只有普通跳跃的1/4 ~ 1/6)
- DP gravity: **6200000.0** (相同重力)

**物理结果**：
```
最大高度 = velocity² / (2 * gravity)

Normal jump: (-10000)² / (2 * 6200000) ≈ 8000 pixels
DP jump:    (-2000)²  / (2 * 6200000) ≈ 320 pixels
```

但由于每帧重力应用和速度减速，实际结果更低。

---

## ✅ 修复方案

### **推荐方案：增加DP的jump_speed**

DP应该是一个**上升式的升龍拳**，不是小跳。建议的参数：

| 参数 | 原值 | 建议值 | 理由 |
|------|------|--------|------|
| `jump_speed` | **-2000** | **-8000 至 -10000** | 增加4-5倍，达到合理的升龍拳高度 |
| `gravity` | 6200000.0 | 6200000.0 | 保持不变，使用标准物理 |

### 实施代码修改

在MoveSet.gd第148-150行修改：

```gdscript
move_library["dp"] = MoveData.new(
    "dp", "DAV", 5.0, 320.0, 47.0, 200.0, 4.0, -8000.0, false, false, 6200000.0, "special", true, "none", 0.0, 0.0, 0.0,
    6200000.0, -2700.0, 20.0, 39, 23
    #                  ^^^^ 从 -2000.0 改为 -8000.0
)
```

### 修改后的物理行为

```
新跳速: -8000.0
缩放后: -8,000,000

第1帧: velocity = -8,000,000 + 103,333 = -7,896,667
第10帧: velocity = -8,000,000 + 1,033,333 = -6,966,667
第20帧: velocity = -8,000,000 + 2,066,667 = -5,933,333
第30帧: velocity = -8,000,000 + 3,100,000 = -4,900,000
第40帧: velocity = -8,000,000 + 4,133,333 = -3,866,667
```

预期结果：
- **上升时间**: ~35-40帧 (~0.6秒)
- **最大高度**: ~600-800像素
- **整个DP动画** (0.783秒 = 47帧) **中包含完整跳跃 + 落地**

---

## 📊 日志分析补充

你提供的日志中，关键观察：

1. **重复的 [STATE_CHANGE] Start → Walk**  
   ```
   [STATE_CHANGE] player_a: 'Start' → 'Walk' (spmove=false)
   [STATE_CHANGE] player_a: 'Start' → 'Walk' (spmove=false)
   [STATE_CHANGE] player_a: 'Start' → 'Walk' (spmove=false)
   ```
   → 这是正常的，说明角色处于闲置状态，反复尝试更新动画状态但保持相同

2. **DP执行日志**  
   ```
   [MoveSet._start_special] Starting move: dp (player: DAV)
   [MoveSet._start_special] Animation 'dp' found, length: 0.783 seconds
   [PROCESS_MOVE] DP move processing
     [DP_JUMP] Calling _process_jump, jump_delay=4.000
   [JUMP] Seat: player_a, jump_timer=0.058, is_jumping=false, y=550000, floor=550000
   ...
   [STOP_MOVE] 'dp' | Seat: player_a
   ```
   → DP完整执行，0.783秒后停止 ✅

3. **跳跃触发时刻**  
   ```
   jump_timer=-0.008 时触发 (应该在 <=0 时)
   velocity.y=-2000000 (正确应用了SIMULATION_SCALE)
   ```
   → 跳跃机制本身正确，只是jump_speed值太小 ⚠️

4. **物理套用**  
   ✅ 已套用world.GRAVITY  
   ✅ 已套用SIMULATION_SCALE到jump_speed  
   ❌ jump_speed值太小（-2000 不足以进行升龍拳）

---

## 总结

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| **DP跳得很低** | `jump_speed = -2000` 过小，重力正常但速度不足 | 增加jump_speed到 -8000 ~ -10000 |
| **高度套用了物理** | ✅ 重力应用正确（SIMULATION_SCALE已乘） | ✅ 已套用world.GRAVITY和SIMULATION_SCALE |
| **速度套用了自定义物理** | ✅ 每帧应用gravity * delta | ✅ 符合fixed-point物理 |

**下一步**: 修改jump_speed参数，重新测试DP的跳起高度。
