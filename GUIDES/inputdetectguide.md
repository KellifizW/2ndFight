# 格鬥遊戲：同時按鈕組合輸入檢測（摔投系統）

## 概述

本教程教你如何在格鬥遊戲中實現 **同時按下兩個按鈕** 的檢測機制，以此執行摔投等特殊動作。使用 **位運算（Bitwise Operations）** 確保同時按下時才觸發，避免單按鈕誤觸。

---

## 第一部分：核心原理

### 1.1 位運算基礎

格鬥遊戲中，每個按鈕用一個 **比特位（bit）** 表示：

```
按鈕定義：
A = 0001 (1 << 0 = 十進制 1)
B = 0010 (1 << 1 = 十進制 2)
C = 0100 (1 << 2 = 十進制 4)
D = 1000 (1 << 3 = 十進制 8)
```

### 1.2 位運算操作

```
按位或（OR）|  ：組合多個按鈕
按位與（AND）& ：檢查特定按鈕
```

**例子：同時按 A+B**
```
A:      0001
B:  OR  0010
------- ----
結果:   0011  (十進制 = 3)
```

**檢查是否按下 A**
```
輸入:    0011
A:   &  0001
------- ----
結果:   0001  (非零 = 已按下)
```

---

## 第二部分：實現步驟

### 步驟 1：定義按鈕常數

在 `Global.cs` 中：

```csharp
public const int INPUT_FACE_A = 1 << 4;  // 位置 4
public const int INPUT_FACE_B = 1 << 5;  // 位置 5
public const int INPUT_FACE_C = 1 << 6;  // 位置 6
public const int INPUT_FACE_D = 1 << 7;  // 位置 7

// 或使用枚舉
[Flags]
public enum ButtonInputs : ushort
{
    FACE_A = 1 << 0,
    FACE_B = 1 << 1,
    FACE_C = 1 << 2,
    FACE_D = 1 << 3,
}
```

### 步驟 2：收集玩家輸入

在 `GameManager.cs` 的 `ReadInputs()` 方法中：

```csharp
public byte[] ReadInputs(int id, int inputSize)
{
    byte[] input = new byte[inputSize];
    string prefix = (id == 0) ? "k1" : "k2";

    // 分別收集每個按鈕
    if (Input.IsActionPressed(prefix + "_face_a"))
        input[0] |= Global.INPUT_FACE_A;

    if (Input.IsActionPressed(prefix + "_face_b"))
        input[0] |= Global.INPUT_FACE_B;

    if (Input.IsActionPressed(prefix + "_face_c"))
        input[0] |= Global.INPUT_FACE_C;

    if (Input.IsActionPressed(prefix + "_face_d"))
        input[0] |= Global.INPUT_FACE_D;

    return input;
}
```

**關鍵操作：`|=` 按位或賦值**
- 如果按下 A+B，最終 `input[0] = 0x30`（假設各按鈕位置）
- 如果只按下 A，`input[0] = 0x10`

### 步驟 3：建立輸入檢查器

在 `InputManager.cs` 中實現 `CheckButtonInputs()`：

```csharp
public bool CheckButtonInputs(int index, Global.ButtonInputs buttonNumber, Global.ButtonMode buttonMode)
{
    // 步驟 A：檢查各按鈕的當前狀態
    bool action_ba = IsBeingPressed(index, Global.INPUT_FACE_A);
    bool action_bb = IsBeingPressed(index, Global.INPUT_FACE_B);
    bool action_bc = IsBeingPressed(index, Global.INPUT_FACE_C);
    bool action_bd = IsBeingPressed(index, Global.INPUT_FACE_D);

    // 步驟 B：根據 buttonMode 設定期望狀態
    switch (buttonMode)
    {
        case Global.ButtonMode.PRESS:      // 剛按下
            action_ba = WasPressed(index, Global.INPUT_FACE_A);
            action_bb = WasPressed(index, Global.INPUT_FACE_B);
            action_bc = WasPressed(index, Global.INPUT_FACE_C);
            action_bd = WasPressed(index, Global.INPUT_FACE_D);
            break;
            
        case Global.ButtonMode.HOLD:       // 正在按著
            action_ba = IsBeingPressed(index, Global.INPUT_FACE_A);
            action_bb = IsBeingPressed(index, Global.INPUT_FACE_B);
            action_bc = IsBeingPressed(index, Global.INPUT_FACE_C);
            action_bd = IsBeingPressed(index, Global.INPUT_FACE_D);
            break;
            
        case Global.ButtonMode.RELEASE:    // 剛放開
            action_ba = WasReleased(index, Global.INPUT_FACE_A);
            action_bb = WasReleased(index, Global.INPUT_FACE_B);
            action_bc = WasReleased(index, Global.INPUT_FACE_C);
            action_bd = WasReleased(index, Global.INPUT_FACE_D);
            break;
    }

    // 步驟 C：提取期望的按鈕組合
    bool canA = (buttonNumber & Global.ButtonInputs.FACE_A) > 0;
    bool canB = (buttonNumber & Global.ButtonInputs.FACE_B) > 0;
    bool canC = (buttonNumber & Global.ButtonInputs.FACE_C) > 0;
    bool canD = (buttonNumber & Global.ButtonInputs.FACE_D) > 0;

    // 步驟 D：比對（XOR 邏輯）
    // 若 canA = true，則 action_ba 必須 true
    // 若 canA = false，則 action_ba 必須 false
    return (canA == action_ba) && (canB == action_bb) && 
           (canC == action_bc) && (canD == action_bd);
}
```

**邏輯解釋：**
- `canA == action_ba` 等同於 `!(canA ^ action_ba)`（邏輯相等）
- 兩者相等時返回 `true`，不相等時返回 `false`

### 步驟 4：定義輸入資源文件

在 Godot 中建立 `23_Input_AB.tres`（A+B 摔投）：

```gdresource
[gd_resource type="Resource" script_class="MotionInputs" format=3]

[sub_resource type="Resource" id="Resource_tyq07"]
script = ExtResource("InputSequence")
Buttons = 3  # FACE_A(1) | FACE_B(2) = 3

[sub_resource type="Resource" id="Resource_26osb"]
script = ExtResource("InputOption")
Inputs = Array[Object]([SubResource("Resource_tyq07")])

[resource]
script = ExtResource("MotionInputs")
ValidInputs = Array[Object]([SubResource("Resource_26osb")])
InputBuffer = 2
```

**按鈕值對應表：**
```
Buttons 值  | 意義
------------|--------
1           | FACE_A
2           | FACE_B
3           | FACE_A + FACE_B (摔投)
4           | FACE_C
5           | FACE_A + FACE_C
6           | FACE_B + FACE_C
7           | FACE_A + FACE_B + FACE_C
8           | FACE_D
...
```

### 步驟 5：建立摔投動作

在 `28_Kaede_AB.tres` 中定義摔投：

```gdresource
[gd_resource type="Resource" script_class="MoveSettings" format=3]

[ext_resource type="Resource" path="res://Fighters/Shared/Inputs/23_Input_AB.tres" id="1_up8bs"]

[resource]
script = ExtResource("MoveSettings")
MoveName = "Throw"
MoveState = 58  # 摔投狀態機編號
Inputs = ExtResource("1_up8bs")  # A+B 輸入
Priority = 6    # 優先級（數字越小越優先）
UseOnGround = true
```

### 步驟 6：狀態轉換檢查

在 `SakugaActor.cs` 的 `StateTransitions()` 中：

```csharp
public void StateTransitions()
{
    if (Animator.GetCurrentState().stateTransitions.Length <= 0) return;

    // 逐一檢查狀態轉換（按優先級排序）
    for (int i = 0; i < Animator.GetCurrentState().stateTransitions.Length; i++)
    {
        if (Animator.GetCurrentState().stateTransitions[i].StateIndex < 0) continue;
        
        // 檢查輸入是否符合
        bool validInput = Inputs.CheckMotionInputs(
            Animator.GetCurrentState().stateTransitions[i].Inputs
        );

        // 所有條件都滿足時執行轉換
        if (validInput && otherConditions)
        {
            Animator.PlayState(nextState);
            return;  // 重要：執行後立即返回，確保優先級
        }
    }
}
```

---

## 第三部分：完整流程圖

```
玩家同時按 A+B
         ↓
    讀取輸入
    input |= INPUT_FACE_A    (0x10)
    input |= INPUT_FACE_B    (0x20)
    結果: input = 0x30 (3)
         ↓
    遊戲Tick：ParseInputs(0x30)
         ↓
    InputManager.CheckMotionInputs()
         ↓
    檢查狀態轉換（按優先級）
    ├─ 第 1 個：A+B (Buttons=3) ← 首先匹配！
    │   isActive = (3 & 1) == 1 && (3 & 2) == 2
    │   結果 = true
    │   執行摔投動作，返回
    │
    └─ 第 2+ 個：未執行
         ↓
    播放摔投狀態機
```

---

## 第四部分：代碼示例

### 完整檢查函數

```csharp
// 簡化版：快速檢查
public bool IsComboPressed(ushort input, int buttons)
{
    // 提取期望的按鈕
    for (int i = 0; i < 4; i++)
    {
        int buttonBit = (1 << i);
        bool shouldPress = (buttons & buttonBit) != 0;
        bool isPressed = (input & buttonBit) != 0;
        
        // 不符合則返回 false
        if (shouldPress != isPressed) 
            return false;
    }
    return true;
}

// 使用
if (IsComboPressed(currentInput, 3))  // 3 = A+B
{
    ExecuteThrow();
}
```

### 用於 AI 的輸入生成

```csharp
private ushort GenerateInput(AIInput input)
{
    int result = 0;

    // Face button inputs
    if ((input.Buttons & Global.ButtonInputs.FACE_A) > 0)
        result |= Global.INPUT_FACE_A;
    if ((input.Buttons & Global.ButtonInputs.FACE_B) > 0)
        result |= Global.INPUT_FACE_B;

    return (ushort)result;
}
```

---

## 第五部分：常見問題

### Q1：為什麼要用位運算而不是布林陣列？

```csharp
// ❌ 低效方式
bool[] buttons = new bool[4];
buttons[0] = isA;
buttons[1] = isB;

// ✅ 高效方式（位運算）
int buttons = 0;
if (isA) buttons |= INPUT_FACE_A;
if (isB) buttons |= INPUT_FACE_B;

// 優點：單一整數 vs 陣列，性能快 10+ 倍
```

### Q2：如何檢測「先按 A 再按 B」的順序？

```csharp
// 使用輸入紀錄的歷史
public bool CheckOrderedInput(int indexA, int indexB)
{
    // 確保 A 的歷史記錄在 B 之前
    return (InputHistory[indexA].duration > InputHistory[indexB].duration) &&
           WasPressed(indexB, INPUT_FACE_B);
}
```

### Q3：同時按 A+B+C 三個按鈕？

```csharp
// Buttons = 7 (1|2|4 = 0111)
[sub_resource type="Resource"]
Buttons = 7  # A + B + C
```

### Q4：如何避免 A 單獨執行而誤觸摔投？

**關鍵是優先級和狀態轉換順序：**
1. 狀態機中，A+B 的轉換條件應在 A 之前檢查
2. 只要 A+B 輸入檢查成功，立即返回（不檢查後續的 A）

```csharp
// 正確的優先級順序
StateTransitions[0]: A+B (Buttons=3)  ← 先檢查
StateTransitions[1]: A   (Buttons=1)
StateTransitions[2]: B   (Buttons=2)
```

---

## 第六部分：調試技巧

### 1. 列印當前輸入值

```csharp
Debug.Log($"Current Input: {currentInput:X} (Binary: {Convert.ToString(currentInput, 2)})");
// 輸出示例: Current Input: 30 (Binary: 110000)
```

### 2. 驗證按鈕值

```csharp
public void DebugInputCheck(int input, int expectedButtons)
{
    bool matches = IsComboPressed(input, expectedButtons);
    Debug.Log($"Input: {Convert.ToString(input, 2)}, Expected: {Convert.ToString(expectedButtons, 2)}, Match: {matches}");
}
```

### 3. 檢查輸入紀錄

```csharp
public void PrintInputHistory()
{
    for (int i = 0; i < InputHistory.Length; i++)
    {
        Debug.Log($"Frame {i}: {Convert.ToString(InputHistory[i].rawInput, 2)}");
    }
}
```

---

## 第七部分：優化建議

### 1. 輸入緩衝（Input Buffer）

允許玩家提前 2-6 幀輸入，增加可操作性：

```csharp
[Export] public int InputBuffer = 2;  // 在資源中定義

// 檢查時
bool validBuffer = (CurrentTime - LastInputTime) <= InputBuffer;
```

### 2. 輸入去抖（Anti-Spam）

防止誤觸導致的連續觸發：

```csharp
public void ParseInputs(ushort rawInputs)
{
    // 檢查輸入是否改變
    if (rawInputs == LastInput) return;
    
    Inputs.InsertToHistory(rawInputs);
    LastInput = rawInputs;
}
```

### 3. 側面翻轉處理

搖桿方向需根據角色方向翻轉：

```csharp
int left = side ? Global.INPUT_LEFT : Global.INPUT_RIGHT;
int right = side ? Global.INPUT_RIGHT : Global.INPUT_LEFT;

if (Input.IsActionPressed("left"))
    result |= left;  // 自動翻轉
```

---

## 第八部分：完整實作檢查清單

- [ ] **Global.cs** 中定義按鈕常數
- [ ] **GameManager.cs** 實現輸入讀取（|= 組合）
- [ ] **InputManager.cs** 實現 `CheckButtonInputs()`
- [ ] 建立輸入資源文件（`.tres`）
- [ ] 建立動作資源文件（`.tres`）
- [ ] 配置狀態轉換優先級順序
- [ ] 測試單按鈕（A、B）與組合（A+B）
- [ ] 驗證優先級（確保不誤觸）
- [ ] 添加輸入緩衝
- [ ] 從Godot編輯器驗證輸入檢查器

---

## 第九部分：測試案例

```gherkin
功能：摔投輸入檢測

場景：玩家同時按 A+B
  當 玩家在相鄰距離內
  且 當前狀態允許摔投
  且 同時按下 A 和 B
  那麼 應該執行摔投動作
  且   不執行 A 單獨攻擊
  且   不執行 B 單獨攻擊

場景：玩家僅按 A
  當 玩家按下 A
  那麼 應該執行 A 攻擊
  且   不執行摔投

場景：玩家僅按 B
  當 玩家按下 B
  那麼 應該執行 B 攻擊
  且   不執行摔投
```

---

## 參考資源

| 檔案 | 用途 |
|------|------|
| `Global.cs` | 按鈕常數定義 |
| `GameManager.cs` | 輸入讀取 |
| `InputManager.cs` | 輸入檢查邏輯 |
| `SakugaActor.cs` | 狀態轉換 |
| `23_Input_AB.tres` | A+B 輸入定義 |
| `28_Kaede_AB.tres` | 摔投動作定義 |

---

## 結論

使用 **位運算** 和 **優先級系統** 的組合，可以優雅地實現複雜的同時按鈕檢測，同時保持高效能和易維護性。關鍵是：

1. ✅ 用位運算 `|=` 組合輸入
2. ✅ 用位與檢查 `&` 驗證
3. ✅ 用優先級順序優先檢查組合輸入
4. ✅ 用狀態轉換提前返回確保優先級

祝你的格鬥遊戲開發順利！🎮

