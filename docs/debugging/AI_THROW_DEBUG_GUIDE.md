# AI 投擲系統調試指南

## 問題陳述

CPU AI 從未執行投擲招式，即使對手距離 < 100 且條件滿足。

## 診斷流程

本指南提供逐步追蹤投擲執行流程的完整日誌點。

### 流程概觀

```
AI 決策層評估
    ↓
AIDecisionLayers.get_best_decision() 選擇投擲
    ↓
AI 行為轉換為輸入
    ↓
ai_behavior._action_to_input("throw") → throw_pressed = true
    ↓
Player.get_input() 返回輸入字典
    ↓
AttackExecutor.try_execute_ground_attack() 檢查 throw_pressed
    ↓
ThrowHandler 執行投擲
```

## 調試檢查點

### 1️⃣ 決策層檢查 - 投擲是否被評估？

**文件**: `ai/AIDecisionLayers.gd` (line ~675)

**輸出信息**:
```
[TACTICAL THROW CHECK] Frame=XXXX Seat=player_a | distance=50.5 targetDist=100 | conditions: is_attacking=false is_hit=false is_knockfly=false | ELIGIBLE=true

[TACTICAL THROW ADDED] Frame=XXXX Seat=player_a | priority=66.5 reason='Close range: throw (both characters)'
```

**檢查點**：
- [ ] 距離 <= 100 像素？
- [ ] AI 未在進行攻擊？ (is_attacking=false)
- [ ] AI 未被擊中？ (is_hit=false)
- [ ] AI 未在擊飛？ (is_knockfly=false)
- [ ] ELIGIBLE=true？

**如果失敗原因**:
- 距離太遠 → AI 未靠近對手
- is_attacking=true → AI 前一攻擊未完成
- is_hit=true 或 is_knockfly=true → AI 被打中

---

### 2️⃣ 決策選擇檢查 - 投擲是否被選中為最佳動作？

**文件**: `ai/AIDecisionLayers.gd` (line ~178)

**輸出信息**:
```
[DECISION LAYER FINAL] Frame=XXXX Seat=player_a | Selected: 'throw' (66.5) | reason: 'Close range: throw (both characters)'

// OR if throw not selected:
[THROW NOT SELECTED] Frame=XXXX | throw_priority=66.5 < selected_priority=67.3 | reason: 'Close range: st_mp'
```

**檢查點**：
- [ ] 投擲是否被選中？ (Selected: 'throw'?)
- [ ] 優先級是多少？ (should be ~66-78)
- [ ] 是否有其他動作優先級更高？

**如果失敗原因**:
- 優先級太低 → 被普通攻擊打敗
  - throw: 66±2
  - st_mp: 67±2.5
  - st_mk: 67±2.5
  - 差異不夠大，隨機波動會影響選擇

---

### 3️⃣ 行為轉換檢查 - 投擲是否被轉換為正確的輸入？

**文件**: `ai/ai_behavior.gd` (line ~495)

**輸出信息**:
```
[AI._action_to_input] Frame=XXXX Seat=player_a | Setting throw_pressed=true

[AI._commit_action] Frame=XXXX Seat=player_a | action='throw' duration=0.70s | throw_pressed in result=true
```

**檢查點**：
- [ ] 是否呼叫了 _action_to_input("throw")？
- [ ] throw_pressed 是否設置為 true？
- [ ] throw_pressed 是否在返回的字典中？

**如果失敗原因**:
- 未呼叫 → "throw" 從未作為動作被承諾

---

### 4️⃣ AttackExecutor 檢查 - 投擲輸入是否被工作者識別？

**文件**: `scripts/combat/handlers/AttackExecutor.gd` (line ~54)

**輸出信息**:
```
[ATTACK_EXECUTOR] Frame=XXXX Seat=player_a is_ai=true | throw_pressed=true, is_crouching=false, is_attacking=false | attack_type=none

[EXECUTE THROW] Frame=XXXX Seat=player_a | ✅ Executing 'throw_enter' (was attacking: none)
```

**檢查點**：
- [ ] throw_pressed=true？
- [ ] is_crouching=false？ (蹲下時無法投擲)
- [ ] is_attacking=false？ (無法中斷某些動作)
- [ ] 是否印出 "EXECUTE THROW"？

**如果失敗原因**：
- throw_pressed=false → 投擲輸入未通過 get_input()
- is_crouching=true → AI 正在蹲下，無法投擲
- is_attacking=true → AI 正在執行其他攻擊

---

### 5️⃣ ThrowHandler 檢查 - 投擲碰撞是否被檢測？

**文件**: `scripts/combat/handlers/ThrowHandler.gd` (line ~510+)

**輸出信息**:
```
[ThrowHandler] STARTUP phase | throw_enter animation
[ThrowHandler] Found X overlapping areas
[ThrowHandler] Valid throw target found: Player_B
[ThrowHandler] Position locked | attacker: Vector2i | opponent: Vector2i | offset: Vector2i
```

**檢查點**：
- [ ] throw_enter 動畫是否啟動？
- [ ] 是否檢測到重疊區域（ThrowBox）？
- [ ] 是否找到有效的投擲目標？

**如果失敗原因**：
- 距離太遠 → 投擲框不重疊
- ThrowBox 禁用 → 碰撞檢測被跳過

---

## 問題分類

### 情況 A: 決策層問題 ❌

**症狀**：
```
[TACTICAL THROW CHECK] ... ELIGIBLE=true
[TACTICAL THROW ADDED] ... (投擲被添加到決策)
但沒有 [DECISION LAYER FINAL] 或投擲未被選中
```

**根本原因**：
1. 投擲優先級太低（66）vs 普通攻擊（67）
2. 隨機波動導致普通攻擊獲勝

**修復**：
- 增加投擲基礎優先級：`throw_dec.priority = 70.0` (instead of 66.0)
- 或減少普通攻擊優先級：`mp.priority = PRIORITY_NORMAL_MID + 0.0` (instead of +3.0)

---

### 情況 B: 輸入獲取問題 ❌

**症狀**：
```
[DECISION LAYER FINAL] ... Selected: 'throw'
但沒有 [AI._action_to_input] 或沒有 [ATTACK_EXECUTOR]
```

**根本原因**：
1. get_ai_input() 未返回 throw_pressed
2. 決策層承諾失敗
3. 決策冷卻時間 (decision_cooldown) 仍活躍

**修復**：
- 檢查 decision_cooldown 的計時邏輯
- 確保 _commit_action() 確實被呼叫

---

### 情況 C: 執行障礙問題 ❌

**症狀**：
```
[ATTACK_EXECUTOR] ... throw_pressed=true
但沒有 [EXECUTE THROW] 或有 [THROW BLOCKED]
```

**根本原因**：
1. is_crouching=true → AI 正在蹲下
2. is_attacking=true → AI 仍在前一個攻擊中
3. throw_enter/throw_seq 已經在運行

**修復**：
- AI 不應蹲下（檢查 _neutral_input() 設置）
- 攻擊應在 0.3s 內完成（檢查 ACTION_DURATIONS["throw"] = {"min": 0.7, "max": 0.7}）

---

### 情況 D: 碰撞檢測問題 ❌

**症狀**：
```
[EXECUTE THROW] ... (投擲啟動)
但沒有 [ThrowHandler] STARTUP 或沒有 "Valid throw target found"
```

**根本原因**：
1. ThrowBox 禁用
2. 對手距離超出投擲框範圍
3. 對手在無敵狀態

**修復**：
- 檢查場景中是否存在 ThrowBox
- 檢查 ThrowHit/ThrowHurt 碰撞體設置

---

## 快速測試步驟

### 步驟 1：啟用 AI 並強制靠近

1. 啟動遊戲
2. 按 **C** 鍵啟用 Player A AI
3. 按 **A+D** 快速靠近 Player B（距離 < 100）

### 步驟 2：監看控制台輸出

打開 **Output** 面板（Godot → Output），監看以下日誌：

```
[TACTICAL THROW CHECK] ...       # 檢查點 1️⃣
[TACTICAL THROW ADDED] ...       # 檢查點 1️⃣
[DECISION LAYER FINAL] ...       # 檢查點 2️⃣
[AI._action_to_input] ...        # 檢查點 3️⃣
[ATTACK_EXECUTOR] ...            # 檢查點 4️⃣
[EXECUTE THROW] ...              # 檢查點 4️⃣
[ThrowHandler] ...               # 檢查點 5️⃣
```

### 步驟 3：識別卡在哪裡

- 卡在檢查點 1️⃣？ → 距離/狀態問題
- 卡在檢查點 2️⃣？ → 優先級問題
- 卡在檢查點 3️⃣？ → 決策冷卻/承諾問題
- 卡在檢查點 4️⃣？ → 蹲下/攻擊狀態問題
- 卡在檢查點 5️⃣？ → 碰撞檢測問題

---

## 記錄範本

使用此範本記錄您的調試過程：

```
【投擲調試日誌】
日期: ____
字符: DAV vs DEN
條件: ________

✓ [TACTICAL THROW CHECK] ....     ELIGIBLE=____
✓ [TACTICAL THROW ADDED] ....     priority=____
✓ [DECISION LAYER FINAL] ....     selected=____ priority=____
✓ [AI._action_to_input] ....      throw_pressed=____
✓ [ATTACK_EXECUTOR] ....          throw_pressed=____ condition=____
✓ [EXECUTE THROW] .....           output: YES/NO
✓ [ThrowHandler] STARTUP ...      output: YES/NO

卡在檢查點: ____
推測原因: ____
```

---

## 相關文檔

- [ThrowHandler 系統](../systems/ThrowHandler_Implementation_Summary.md)
- [AI 決策層](../ai/AIDecisionLayers.md)
- [輸入緩衝系統](../guides/INPUT_BUFFER_IMPLEMENTATION.md)

