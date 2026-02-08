# 摔投输入容许机制实现指南

## 目录
1. [系统概述](#系统概述)
2. [容许机制三层架构](#容许机制三层架构)
3. [核心实现代码](#核心实现代码)
4. [完整流程示例](#完整流程示例)
5. [调试与优化](#调试与优化)

---

## 系统概述

### 问题背景

格斗游戏中，玩家需要 **同时按下 A+B 键** 来执行摔投。但现实中：
- 人类反应速度有限（~100-200ms）
- 不同控制器反应时间不同
- 网络延迟（在线对战）
- 帧率波动

**纯精准检测会导致**：
- ❌ 摔投识别率极低
- ❌ 玩家体验差
- ❌ 不公平（某些人更容易成功）

**解决方案：容许机制**
- ✅ 允许玩家不完全精准同时按下
- ✅ 在一定范围（8帧 ≈ 133ms）内识别
- ✅ 保持输入的确定性（支持Rollback）

---

## 容许机制三层架构

```
┌─────────────────────────────────────────────────────────┐
│              摔投输入识别（A+B同时按）                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 第1层：位掩码同时性检测                            │  │
│  │ ✓ 检查 rawInput 的位是否同时包含 A 和 B           │  │
│  │ ✓ 不需要像素级精准                                │  │
│  │ ✓ 允许顺序错开（A先或B先）                        │  │
│  └──────────────────────────────────────────────────┘  │
│                         ↓                               │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 第2层：输入缓冲窗口                                │  │
│  │ ✓ 允许提前8帧按下                                 │  │
│  │ ✓ duration <= InputBuffer 的输入被接受             │  │
│  │ ✓ 延后超过8帧就会失败                             │  │
│  └──────────────────────────────────────────────────┘  │
│                         ↓                               │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 第3层：按钮隔离和状态验证                          │  │
│  │ ✓ 检查没有同时按C/D等其他按钮                     │  │
│  │ ✓ 确保处于可执行摔投的状态                        │  │
│  │ ✓ 确认对手在摔投范围内                            │  │
│  └──────────────────────────────────────────────────┘  │
│                         ↓                               │
│                  ✅ 摔投执行成功                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 核心实现代码

### 第1层：位掩码同时性检测

#### 按钮定义（Global.cs）

```csharp
namespace SakugaEngine
{
    public static class Global
    {
        // 按钮的位掩码定义
        public const int INPUT_FACE_A = 1 << 4;  // 0b00010000
        public const int INPUT_FACE_B = 1 << 5;  // 0b00100000
        public const int INPUT_FACE_C = 1 << 6;  // 0b01000000
        public const int INPUT_FACE_D = 1 << 7;  // 0b10000000
        
        // 摔投按钮组合
        public const int INPUT_THROW = INPUT_FACE_A | INPUT_FACE_B;  // 0b00110000
        
        // 位标志枚举
        [Flags]
        public enum ButtonInputs : ushort
        {
            FACE_A = 1 << 0,  // 0b0001
            FACE_B = 1 << 1,  // 0b0010
            FACE_C = 1 << 2,  // 0b0100
            FACE_D = 1 << 3,  // 0b1000
        }
    }
}
```

#### 输入注册结构（InputManager.cs）

```csharp
public class InputManager
{
    // 输入历史常量
    public const int InputHistorySize = 16;  // 16帧循环缓冲
    
    // 输入记录结构
    public struct InputRegistry
    {
        public ushort rawInput;      // 该帧按下的所有按钮位掩码
        public ushort duration;      // 该输入持续的帧数
        public short hCharge;        // 水平蓄力值
        public short vCharge;        // 竖直蓄力值
        public ushort bCharge;       // 按钮蓄力值
    }
    
    // 输入历史数组
    public InputRegistry[] InputHistory = new InputRegistry[InputHistorySize];
    public int CurrentHistory = 0;  // 当前索引
    
    /// <summary>
    /// 每帧调用：记录输入到历史
    /// </summary>
    public void InsertToHistory(ushort input)
    {
        // 检查输入是否改变
        if (InputHistory[CurrentHistory].rawInput != input)
        {
            // 移进行到下一个历史索引
            CurrentHistory++;
            if (CurrentHistory >= InputHistorySize) 
                CurrentHistory = 0;  // 循环
            
            // 初始化新输入
            InputHistory[CurrentHistory].rawInput = input;
            InputHistory[CurrentHistory].duration = 0;  // 从0开始
            
            // 复制前一帧的蓄力值
            int previousInput = CurrentHistory - 1;
            if (previousInput < 0) previousInput += InputHistorySize;
            
            InputHistory[CurrentHistory].hCharge = InputHistory[previousInput].hCharge;
            InputHistory[CurrentHistory].vCharge = InputHistory[previousInput].vCharge;
            InputHistory[CurrentHistory].bCharge = InputHistory[previousInput].bCharge;
        }
        
        // 当前输入持续时间+1
        InputHistory[CurrentHistory].duration++;
        ChargeBuffer();  // 更新蓄力值
    }
}
```

#### 位掩码检查函数（InputManager.cs）

```csharp
public class InputManager
{
    /// <summary>
    /// 检查指定帧的按钮是否被按下
    /// </summary>
    public bool IsBeingPressed(int index, int input)
    {
        // 使用位AND：如果input的位在rawInput中被设置，结果不为0
        return (InputHistory[index].rawInput & input) != 0;
    }
    
    /// <summary>
    /// 检查该帧是否是按钮刚被按下的第一帧
    /// </summary>
    public bool WasPressed(int index, int input)
    {
        int previousInput = index - 1;
        if (previousInput < 0) previousInput += InputHistorySize;
        
        // 条件：
        // 1. 当前帧：按钮已按下
        // 2. 前一帧：按钮未按下
        // 3. duration == 1：只在第一帧响应
        return (InputHistory[index].rawInput & input) != 0 &&
               (InputHistory[previousInput].rawInput & input) == 0 &&
               InputHistory[index].duration == 1;
    }
    
    /// <summary>
    /// 检查按钮是否仍被按住
    /// </summary>
    public bool WasBeingPressed(int index, int input)
    {
        int previousInput = index - 1;
        if (previousInput < 0) previousInput += InputHistorySize;
        
        return (InputHistory[index].rawInput & input) == 0 &&
               (InputHistory[previousInput].rawInput & input) != 0;
    }
}
```

**示例：A+B 同时性检测**

```csharp
// 在Frame 20时检查A+B是否同时按下
int frameIndex = 20;

bool hasA = InputManager.IsBeingPressed(frameIndex, Global.INPUT_FACE_A);
bool hasB = InputManager.IsBeingPressed(frameIndex, Global.INPUT_FACE_B);
bool hasC = !InputManager.IsBeingPressed(frameIndex, Global.INPUT_FACE_C);
bool hasD = !InputManager.IsBeingPressed(frameIndex, Global.INPUT_FACE_D);

// A+B同时，且没有C、D
if (hasA && hasB && hasC && hasD)
{
    Debug.Log("✅ 检测到摔投输入！");
}
```

---

### 第2层：输入缓冲窗口

#### 摔投输入定义（MotionInputs.cs）

```csharp
[GlobalClass]
public partial class MotionInputs : Resource
{
    /// <summary>
    /// 有效的输入序列数组
    /// 例如：[↓, A+B] 表示"下+A+B"的摔投
    /// </summary>
    [Export] public InputOption[] ValidInputs;
    
    /// <summary>
    /// 方向是否使用绝对方向（不受角色朝向影响）
    /// </summary>
    [Export] public bool AbsoluteDirection;
    
    /// <summary>
    /// 🔑 输入缓冲窗口（帧数）
    /// 允许输入在过去 N 帧内被识别
    /// 默认值：8帧 ≈ 133ms @60fps
    /// </summary>
    [Export] public int InputBuffer = 8;
    
    /// <summary>
    /// 方向蓄力限制（0表示无限制）
    /// </summary>
    [Export] public int DirectionalChargeLimit = 0;
    
    /// <summary>
    /// 按钮蓄力限制（0表示无限制）
    /// </summary>
    [Export] public int ButtonChargeLimit = 0;
}
```

#### 缓冲检查逻辑（InputManager.cs）

```csharp
public class InputManager
{
    /// <summary>
    /// 检查输入是否在缓冲窗口内
    /// </summary>
    private bool IsWithinInputBuffer(int historyIndex, int inputBuffer)
    {
        // 如果inputBuffer为0，表示无缓冲限制
        if (inputBuffer == 0)
            return true;
        
        // duration <= inputBuffer：输入持续时间在缓冲范围内
        return InputHistory[historyIndex].duration <= inputBuffer;
    }
    
    /// <summary>
    /// 检查整个输入序列是否有效
    /// </summary>
    public bool CheckMotionInputs(MotionInputs motion)
    {
        if (motion == null) return false;
        
        bool inputFound = false;
        
        // 遍历所有有效的输入选项
        for (int i = 0; i < motion.ValidInputs.Length; i++)
        {
            // 定义输入序列的起始位置
            int startingInput = (CurrentHistory - motion.ValidInputs[i].Inputs.Length) + 1;
            if (startingInput < 0) 
                startingInput += InputHistorySize;
            
            inputFound = true;
            
            // 检查序列中的每个输入
            for (int j = 0; j < motion.ValidInputs[i].Inputs.Length; j++)
            {
                int historyIndex = (startingInput + j) % InputHistorySize;
                
                // 🔑 检查这个输入是否在缓冲窗口内
                bool validBuffer = IsWithinInputBuffer(
                    historyIndex, 
                    motion.InputBuffer
                );
                
                if (!validBuffer)
                {
                    inputFound = false;
                    break;
                }
                
                // 检查方向和按钮
                var directionals = motion.ValidInputs[i].Inputs[j].DirectionalInputs;
                var buttons = motion.ValidInputs[i].Inputs[j].ButtonInputs;
                
                bool validInput = false;
                
                if (directionals > 0 && buttons == 0)
                {
                    // 只有方向
                    validInput = CheckDirectionalInputs(historyIndex, directionals, ...);
                }
                else if (directionals == 0 && buttons > 0)
                {
                    // 只有按钮（如A+B摔投）
                    validInput = CheckButtonInputs(historyIndex, buttons, ...);
                }
                else if (directionals > 0 && buttons > 0)
                {
                    // 同时有方向和按钮（如↓+A+B）
                    validInput = CheckDirectionalInputs(...) 
                                 && CheckButtonInputs(...);
                }
                
                if (!validInput)
                {
                    inputFound = false;
                    break;
                }
            }
            
            if (inputFound) break;  // 找到有效序列，退出
        }
        
        return inputFound;
    }
}
```

**缓冲窗口的时间表示**

```
输入时间轴：
────────────────────────────────────────────→ 时间

Frame 20: 玩家按下 A+B
└─ duration = 1, 2, 3, 4, 5, 6, 7, 8, 9, ...

Frame 28: 游戏检查摔投输入
└─ 检查 Frame 20-28 的历史
└─ Frame 20 的 duration = 8，刚好在缓冲范围内
✅ 识别成功！

Frame 29: 游戏再次检查摔投输入
└─ 检查 Frame 21-29 的历史
└─ Frame 20 已经超出窗口
└─ 如果没有新输入，检查失败

输入缓冲窗口 = 8帧 @ 60fps ≈ 133ms
```

---

### 第3层：按钮隔离和状态验证

#### 按钮检查（InputManager.cs）

```csharp
public class InputManager
{
    /// <summary>
    /// 检查指定按钮组合是否满足
    /// </summary>
    public bool CheckButtonInputs(
        int index, 
        Global.ButtonInputs buttonNumber, 
        Global.ButtonMode buttonMode)
    {
        // 根据按钮模式（按下、按住、释放等）检查
        bool action_ba = false, action_bb = false, action_bc = false, action_bd = false;
        
        switch (buttonMode)
        {
            case Global.ButtonMode.PRESS:
                // 检查该帧是否刚按下
                action_ba = WasPressed(index, Global.INPUT_FACE_A);
                action_bb = WasPressed(index, Global.INPUT_FACE_B);
                action_bc = WasPressed(index, Global.INPUT_FACE_C);
                action_bd = WasPressed(index, Global.INPUT_FACE_D);
                break;
                
            case Global.ButtonMode.HOLD:
                // 检查该帧是否被按住
                action_ba = IsBeingPressed(index, Global.INPUT_FACE_A);
                action_bb = IsBeingPressed(index, Global.INPUT_FACE_B);
                action_bc = IsBeingPressed(index, Global.INPUT_FACE_C);
                action_bd = IsBeingPressed(index, Global.INPUT_FACE_D);
                break;
                
            case Global.ButtonMode.RELEASE:
                // 检查该帧是否刚释放
                action_ba = WasReleased(index, Global.INPUT_FACE_A);
                action_bb = WasReleased(index, Global.INPUT_FACE_B);
                action_bc = WasReleased(index, Global.INPUT_FACE_C);
                action_bd = WasReleased(index, Global.INPUT_FACE_D);
                break;
            // ... 其他模式
        }
        
        // 🔑 按钮隔离：只允许指定的按钮被按下
        bool canA = (buttonNumber & Global.ButtonInputs.FACE_A) > 0;
        bool canB = (buttonNumber & Global.ButtonInputs.FACE_B) > 0;
        bool canC = (buttonNumber & Global.ButtonInputs.FACE_C) > 0;
        bool canD = (buttonNumber & Global.ButtonInputs.FACE_D) > 0;
        
        // 逻辑：
        // - 如果指令要求按A，则action_ba必须为true
        // - 如果指令不要求A，则action_ba必须为false
        return (buttonNumber == 0 && !action_ba && !action_bb && !action_bc && !action_bd) ||
               (!canA || canA == action_ba) && 
               (!canB || canB == action_bb) &&
               (!canC || canC == action_bc) && 
               (!canD || canD == action_bd);
    }
}
```

**示例：A+B摔投的按钮检查**

```csharp
// 定义A+B摔投指令
var throwMotion = new MotionInputs
{
    ValidInputs = new InputOption[]
    {
        new InputOption
        {
            // 只有按钮，没有方向要求
            Inputs = new InputSequence[]
            {
                new InputSequence
                {
                    DirectionalInputs = 0,  // 没有方向要求
                    ButtonInputs = Global.ButtonInputs.FACE_A | Global.ButtonInputs.FACE_B
                }
            }
        }
    },
    InputBuffer = 8  // 8帧缓冲
};

// 在Frame 20检查
int frameIndex = 20;
bool isThrowInput = CheckButtonInputs(
    frameIndex,
    Global.ButtonInputs.FACE_A | Global.ButtonInputs.FACE_B,
    Global.ButtonMode.HOLD
);

// 这会检查：
// ✓ Frame 20是否同时按着A+B
// ✓ Frame 20是否没有按C或D
```

#### 状态验证（SakugaFighter.cs）

```csharp
public class SakugaFighter : SakugaActor
{
    /// <summary>
    /// 执行摔投
    /// </summary>
    public void ThrowDamage(SakugaActor target, HitboxElement box, Vector2I contact)
    {
        // 第3层检查：状态和范围验证
        
        // 检查1：对手是否存在
        if (target == null)
        {
            Debug.Log("❌ 摔投失败：对手不存在");
            return;
        }
        
        // 检查2：对手是否可被摔投
        if (!target.CanBeThrown())
        {
            Debug.Log("❌ 摔投失败：对手无法被摔投（无敌帧、已被摔投等）");
            return;
        }
        
        // 检查3：对手是否在摔投范围内（物理碰撞检测）
        // PhysicsWorld.cs 已经在执行碰撞检测前完成了范围检查
        
        // 检查4：确认当前状态允许执行摔投
        var currentState = animator.GetCurrentState();
        if (!currentState.CanExecuteThrow || currentState.Type != StateType.COMBAT)
        {
            Debug.Log("❌ 摔投失败：当前状态不允许摔投");
            return;
        }
        
        // ✅ 所有检查通过，执行摔投
        Debug.Log("✅ 摔投执行成功！");
        
        // 应用摔投伤害
        target.hitstun_type = box.ThrowHitReaction;
        target.hit_stun.start((short)box.ThrowHitstopAfterHit);
        
        // 设置对手为"被摔投"状态
        target.is_grabbed = true;
        target.grabber = this;
        
        // 播放被摔投动画...
        // 应用击退...
    }
}
```

---

## 完整流程示例

### 场景：玩家执行A+B摔投

```
游戏状态时间轴
═══════════════════════════════════════════════════════════

Frame 18: 对手在摔投范围内，角色处于可出招状态
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Frame 19: 玩家快速按下A，然后立即按下B
  │
  ├─ 输入事件：按下 INPUT_FACE_A (0b00010000)
  │  └─ InputManager.InsertToHistory(0b00010000)
  │     └─ InputHistory[CurrentHistory].rawInput = 0b00010000
  │     └─ InputHistory[CurrentHistory].duration = 1
  │
  └─ 输入事件：同时按住A，新增B (0b00110000)
     └─ InputManager.InsertToHistory(0b00110000)
        └─ CurrentHistory++
        └─ InputHistory[CurrentHistory].rawInput = 0b00110000
        └─ InputHistory[CurrentHistory].duration = 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Frame 20-26: 玩家继续按住A+B
  │
  └─ 每帧调用 InputManager.InsertToHistory(0b00110000)
     └─ InputHistory[CurrentHistory].rawInput 保持 = 0b00110000
     └─ InputHistory[CurrentHistory].duration++ (2, 3, 4, 5...)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Frame 27: 玩家释放A+B
  │
  └─ InputManager.InsertToHistory(0b00000000)  // 都释放了
     └─ CurrentHistory++ (新索引)
     └─ InputHistory[CurrentHistory].rawInput = 0b00000000
     └─ InputHistory[CurrentHistory].duration = 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Frame 28: 摔投判定启动，游戏检查输入
  │
  ├─ 第1层：位掩码检查
  │  │
  │  ├─ 查询历史：找A+B同时出现的帧
  │  │  └─ Frame 19: rawInput = 0b00010000 (只有A) ❌
  │  │  └─ Frame 20: rawInput = 0b00110000 (A+B) ✅
  │  │  └─ Frame 21: rawInput = 0b00110000 (A+B) ✅
  │  │  ... (继续向前搜索)
  │  │
  │  └─ 条件：(rawInput & 0b00110000) == 0b00110000 ✅
  │
  ├─ 第2层：缓冲窗口检查
  │  │
  │  └─ 检查找到的A+B帧是否在缓冲范围内
  │     Frame 20的duration = 28 - 20 = 8
  │     InputBuffer = 8
  │     8 <= 8 ✅ （刚好在范围边界）
  │
  ├─ 第3层：按钮隔离检查
  │  │
  │  └─ Frame 20是否只有A+B，没有C或D？
  │     (rawInput & INPUT_FACE_C) == 0 ✅
  │     (rawInput & INPUT_FACE_D) == 0 ✅
  │
  └─ 最终结果：✅ 摔投输入判定成功！

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Frame 29: 执行摔投伤害
  │
  └─ SakugaFighter.ThrowDamage()
     │
     ├─ 验证检查：
     │  ├─ 对手存在？✅
     │  ├─ 对手可被摔投？✅
     │  ├─ 在摔投范围内？✅
     │  └─ 状态允许？✅
     │
     └─ 执行摔投效果：
        ├─ 应用硬直
        ├─ 设置击退速度
        ├─ 标记为"被抓住"状态
        └─ 网络同步（Rollback）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ 摔投成功！（即使玩家没有超精准同时按）
```

### 失败案例对比

#### 案例1：超过缓冲窗口

```
Frame 19: 按下A+B
Frame 20-26: 继续按住
Frame 27: 释放

Frame 28: 摔投判定 → duration = 8 ✅ 成功
Frame 29: 第二次检查 → duration = 9 ❌ 失败（超过8帧）
Frame 35: 已经超出16帧历史 → 数据丢失 ❌ 彻底失败
```

#### 案例2：同时按了C键

```
Frame 19: 按下A+B
Frame 20: 不小心加按了C → rawInput = 0b01110000
          ├─ Frame 20有A ✓
          ├─ Frame 20有B ✓
          ├─ Frame 20有C ✗ (不允许!)
          └─ 按钮隔离检查失败 ❌

Result: 不会被识别为摔投，可能触发其他指令
```

#### 案例3：超精准但在错误状态

```
Frame 19: 按下A+B（完全同时）✓
Frame 20-28: 缓冲检查通过 ✓
Frame 28: 输入检查全通过 ✓

但是：
- 对手无敌帧中 ❌
- 或当前处于跳跃状态（不允许摔投） ❌
- 对手已经在被摔投 ❌

Result: 虽然输入识别成功，但摔投执行失败
```

---

## 调试与优化

### 调试日志添加

```csharp
// InputManager.cs 中添加调试
public bool CheckMotionInputs(MotionInputs motion)
{
    // 调试模式
    #if DEBUG_INPUT
    Debug.Log($"=== 检查摔投输入 ===");
    Debug.Log($"当前帧: {CurrentHistory}");
    Debug.Log($"缓冲窗口: {motion.InputBuffer}");
    #endif
    
    for (int i = 0; i < motion.ValidInputs.Length; i++)
    {
        int startingInput = (CurrentHistory - motion.ValidInputs[i].Inputs.Length) + 1;
        if (startingInput < 0) startingInput += InputHistorySize;
        
        #if DEBUG_INPUT
        Debug.Log($"\n--- 检查序列 {i} ---");
        Debug.Log($"起始位置: {startingInput}");
        #endif
        
        for (int j = 0; j < motion.ValidInputs[i].Inputs.Length; j++)
        {
            int historyIndex = (startingInput + j) % InputHistorySize;
            
            #if DEBUG_INPUT
            Debug.Log($"Frame {historyIndex}: " +
                     $"input=0b{InputHistory[historyIndex].rawInput:B8}, " +
                     $"duration={InputHistory[historyIndex].duration}");
            #endif
            
            // ... 检查逻辑 ...
        }
    }
}

// ThrowDamage 中添加调试
public void ThrowDamage(SakugaActor target, HitboxElement box, Vector2I contact)
{
    #if DEBUG_THROW
    Debug.Log($"=== 摔投检查 ===");
    Debug.Log($"执行者: {Name}");
    Debug.Log($"目标: {target?.Name ?? "NULL"}");
    Debug.Log($"目标状态: {target?.CurrentState?.Name}");
    Debug.Log($"可摔投: {target?.CanBeThrown()}");
    Debug.Log($"距离: {Vector2I.Distance(Position, target?.Position ?? Vector2I.Zero)}");
    #endif
    
    // ... 检查逻辑 ...
}
```

### 性能优化

#### 1. 减少重复计算

```csharp
// ❌ 低效：每次都重新计算
public void Update()
{
    if (CheckMotionInputs(throwMotion)) { /* ... */ }
}

// ✅ 高效：缓存结果
private bool _cachedThrowInput = false;
private int _cachedThrowFrame = -1;

public void Update()
{
    if (animator.frame != _cachedThrowFrame)
    {
        _cachedThrowInput = CheckMotionInputs(throwMotion);
        _cachedThrowFrame = animator.frame;
    }
    
    if (_cachedThrowInput) { /* ... */ }
}
```

#### 2. 减少数组访问

```csharp
// ❌ 低效：多人次访问数组
bool check1 = IsBeingPressed(index, INPUT_A);
bool check2 = IsBeingPressed(index, INPUT_B);
bool check3 = !IsBeingPressed(index, INPUT_C);

// ✅ 高效：一次缓存
ushort rawInput = InputHistory[index].rawInput;
bool check1 = (rawInput & INPUT_A) != 0;
bool check2 = (rawInput & INPUT_B) != 0;
bool check3 = (rawInput & INPUT_C) == 0;
```

### 参数调整建议

```csharp
// 标准配置（默认）
public int InputBuffer = 8;  // 8帧 ≈ 133ms

// 对于新手友好的游戏
public int InputBuffer = 10;  // 10帧 ≈ 167ms

// 对于竞技游戏
public int InputBuffer = 6;   // 6帧 ≈ 100ms

// 对于仓促摔投（Kara Cancel Window）
public int KaraCancelWindow = 3;  // 3帧 ≈ 50ms
```

---

## 参考资源

### 相关文件位置

| 文件 | 用途 |
|------|------|
| `Scripts/SakugaEngine/Global.cs` | 按钮和输入常量定义 |
| `Scripts/SakugaEngine/Components/InputManager.cs` | 输入历史和检查逻辑 |
| `Scripts/SakugaEngine/Resources/MotionInputs.cs` | 输入定义和缓冲参数 |
| `Scripts/SakugaEngine/Components/SakugaFighter.cs` | 摔投执行和伤害处理 |
| `Scripts/SakugaEngine/Collision/PhysicsWorld.cs` | 摔投碰撞检测 |

### 相关教学文档

- [ThrowSystem_GDScript_Tutorial.md](ThrowSystem_GDScript_Tutorial.md) - 摔投系统教学
- [Sakuga Engine Architecture](./README.md) - 引擎架构文档

---

## 总结

### 三层容许机制的关键要点

| 层级 | 技术 | 作用 | 容许度 |
|------|------|------|--------|
| **L1** | 位掩码 AND | 检查A、B同时性 | 相对宽松 |
| **L2** | 输入缓冲 | 允许提前按下 | **8帧** (~133ms) |
| **L3** | 状态验证 | 确保有效执行 | 严格 |

### 实现的好处

✅ **玩家体验更好** - 不必超精准同时按  
✅ **确定性强** - 支持Rollback Netcode  
✅ **易于维护** - 参数化设计（可调整缓冲值）  
✅ **易于扩展** - 可添加更多条件判断  
✅ **公平竞争** - 对所有玩家一致  

---

**文档版本**: 1.0  
**更新日期**: 2026-02-09  
**作者**: Sakuga Engine Community
