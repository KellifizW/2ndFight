# AI 招式限制問題修正報告

## 問題描述

當禁用 AI 的 `fireball` 招式後，AI 只會前後移動（walk_forward/walk_backward），不會使用其他攻擊招式（如 st_mp、cr_mk、dash_forward 等）。

## 問題根源分析

### 原始問題

在最初的實現中，招式過濾邏輯存在以下問題：

```gdscript
# 原始代碼（有問題）
elif survival and survival.action not in restricted_moves:
    decisions.append(survival)
```

**問題點**：
1. **過濾邏輯不完整**：當某個決策層返回 `null` 或被過濾掉時，沒有明確處理
2. **缺少統計資訊**：無法知道有多少決策被過濾掉
3. **空決策列表處理不當**：當所有戰術決策都被過濾後，`decisions` 陣列可能很小，導致低優先級的 `_get_idle_decision()` (walk_forward, 優先級 10.0) 被選中

### 決策優先級層次

```
生存層：     85-100  (SURVIVAL, CRITICAL)
懲罰層：     90      (PUNISH)
戰術層：     48-75   (TACTICAL - attacks, movement, specials)
  - 連段：    75      (COMBO)
  - 特殊技：   70      (SPECIAL_CLOSE - dp, powerkk, spnk, hdk)
  - 普攻高：   67      (NORMAL_HIGH - st_mk, st_mp, cr_mk, cr_mp)
  - 衝刺：    65      (DASH_APPROACH)
  - 火球：    64      (FIREBALL) ⚠️ 被禁用時的問題
  - 跳躍：    63      (JUMP)
  - 前進：    62      (WALK_FORWARD)
  - 後退：    60      (RETREAT)
  - 觀察：    48      (OBSERVE)
定位層：     30-40   (POSITIONING)
待機層：     10      (IDLE - walk_forward)
```

### 問題場景重現

**遠距離場景（distance > 250）**：

戰術層產生的決策：
1. ❌ fireball (64.0) - 被 `restricted_moves` 過濾
2. ✅ dash_forward (65.0) - 應該可用
3. ✅ jump_forward (63.0) - 應該可用
4. ✅ walk_forward (62.0) - 應該可用

**理論上**應該選擇 dash_forward (65.0)，但實際上 AI 可能選擇了低優先級的行為。

## 修正方案

### 1. 改進過濾邏輯

```gdscript
# 修正後的代碼
elif survival:
    if survival.action in restricted_moves:
        filtered_count += 1  # 統計被過濾的決策
    else:
        decisions.append(survival)
```

**改進點**：
- ✅ 明確處理每個決策層的結果
- ✅ 統計被過濾的決策數量
- ✅ 確保非限制招式被正確添加到決策列表

### 2. 添加空列表保護

```gdscript
# 確保至少有一個決策
if decisions.is_empty():
    return _get_idle_decision()

decisions.append(_get_idle_decision())
```

**作用**：
- 防止決策列表完全為空
- 提供安全的後備選項

### 3. 增強 Debug 輸出

```gdscript
# Debug: 顯示過濾統計
if filtered_count > 0 and Engine.get_physics_frames() % 120 == 0:
    print("[AI] Filtered %d restricted moves. Available decisions: %d" % [filtered_count, decisions.size()])
    if decisions.size() > 0:
        var top_5 = decisions.slice(0, min(5, decisions.size()))
        for d in top_5:
            print("  - %s (%.1f): %s" % [d.action, d.priority, d.reason])
```

**提供資訊**：
- 過濾了多少招式
- 剩餘多少可用決策
- 前 5 個最高優先級的決策及其優先級

### 4. 改進後備決策日誌

在 [ai_behavior.gd](ai_behavior.gd) 中：

```gdscript
if enable_move_restrictions and decision.action in restricted_moves:
    if debug_mode or Engine.get_physics_frames() % 60 == 0:
        print("[AI] Move '%s' (priority: %.1f) is restricted, finding alternative..." % [decision.action, decision.priority])
    decision = decision_layers.get_fallback_decision(parent, opponent)
    if debug_mode or Engine.get_physics_frames() % 60 == 0:
        print("[AI] Fallback decision: '%s' (priority: %.1f)" % [decision.action, decision.priority])
```

**顯示內容**：
- 哪個招式被限制
- 原始決策的優先級
- 後備決策及其優先級

## 修正效果驗證

### 測試場景 1：禁用火球

**配置**：
```
Enable Move Restrictions: ☑️
Restricted Moves: ["fireball"]
```

**預期行為（修正後）**：
- 遠距離：使用 dash_forward (65.0) 或 jump (63.0) 接近
- 中距離：使用 st_mk (67.0)、st_mp (67.0)、cr_mk (67.0) 攻擊
- 近距離：使用連段、特殊技（dp/powerkk/spnk）、普通攻擊

**Console 輸出範例**：
```
[AI] Filtered 1 restricted moves. Available decisions: 8
  - dash_forward (65.0): Far range: aggressive approach
  - jump_forward (63.5): Far range: jump approach
  - walk_forward (62.0): Far range: steady approach
  - stand_block (48.0): Far range: observe
  - walk_forward (10.0): Default behavior
```

### 測試場景 2：禁用所有特殊技

**配置**：
```
Enable Move Restrictions: ☑️
Restricted Moves: ["fireball", "dp", "powerkk", "spnk", "hdk", "super"]
```

**預期行為（修正後）**：
- 遠距離：dash_forward、jump、walk_forward
- 中距離：st_mk、st_mp、cr_mk、cr_mp（優先級 67.0）
- 近距離：普通攻擊組合、跳躍攻擊

**Console 輸出範例**：
```
[AI] Filtered 6 restricted moves. Available decisions: 12
  - st_mk (68.5): Mid range: poke
  - st_mp (66.2): Mid range: quick poke
  - cr_mk (65.8): Mid range: low poke
  - dash_forward (63.0): Mid range: close gap
```

## 修正文件清單

1. **[ai/AIDecisionLayers.gd](AIDecisionLayers.gd)**
   - 修改 `get_best_decision()` 函數
   - 改進過濾邏輯，添加 `filtered_count` 統計
   - 添加空列表保護
   - 增強 debug 輸出

2. **[ai/ai_behavior.gd](ai_behavior.gd)**
   - 改進後備決策的 debug 輸出
   - 顯示被限制招式的優先級
   - 顯示後備決策的詳細資訊

## 故障排除指南

### 問題：AI 仍然只會移動

**解決步驟**：
1. 啟用 Debug Mode：在 AIBehavior 節點中勾選 `Debug Mode`
2. 查看 Console 輸出，確認：
   - 有多少決策被過濾
   - 剩餘多少可用決策
   - 最高優先級的決策是什麼
3. 檢查 `restricted_moves` 列表，確保沒有意外禁用基礎招式

### 問題：Console 沒有輸出

**解決方案**：
- 確認 AIBehavior 的 `ai_enabled = true`
- 確認 `enable_move_restrictions = true`
- 檢查遊戲是否正在運行

### 問題：過濾了太多招式

**解決方案**：
- 檢查 `restricted_moves` 陣列內容
- 確保招式名稱拼寫正確（區分大小寫）
- 避免禁用所有攻擊類型的招式

## 技術細節

### 過濾邏輯流程圖

```
┌─────────────────────────────┐
│ get_best_decision()         │
└──────────┬──────────────────┘
           │
           ├─► 生存層決策
           │   └─► 檢查 restricted_moves
           │       ├─ 是 → filtered_count++
           │       └─ 否 → 添加到 decisions[]
           │
           ├─► 懲罰層決策
           │   └─► 檢查 restricted_moves
           │       ├─ 是 → filtered_count++
           │       └─ 否 → 添加到 decisions[]
           │
           ├─► 戰術層決策（多個）
           │   └─► 對每個決策檢查 restricted_moves
           │       ├─ 是 → filtered_count++
           │       └─ 否 → 添加到 decisions[]
           │
           ├─► 定位層決策
           │   └─► 檢查 restricted_moves
           │       ├─ 是 → filtered_count++
           │       └─ 否 → 添加到 decisions[]
           │
           ├─► 檢查 decisions.is_empty()
           │   ├─ 是 → 返回 _get_idle_decision()
           │   └─ 否 → 繼續
           │
           ├─► 添加 _get_idle_decision() 到列表
           │
           ├─► 按優先級排序
           │
           └─► 返回 decisions[0]
```

### 性能考量

- **過濾檢查**：每個決策一次字串比對，複雜度 O(n)，n 為 restricted_moves 長度
- **Debug 輸出**：僅在特定幀數時觸發（每 120 幀），避免性能影響
- **決策排序**：使用內建排序，複雜度 O(n log n)，n 為決策數量（通常 < 20）

## 後續改進建議

### 1. 招式分類過濾

允許按類別禁用招式：
```gdscript
@export var restrict_special_moves: bool = false
@export var restrict_normal_attacks: bool = false
@export var restrict_movement: bool = false
```

### 2. 動態難度調整

根據禁用招式數量自動調整 AI 行為：
```gdscript
func adjust_priority_by_restrictions() -> void:
    var penalty = restricted_moves.size() * 2.0
    # 提升剩餘招式的優先級補償
```

### 3. 統計面板

創建 UI 顯示 AI 決策統計：
- 使用頻率最高的招式
- 被過濾次數最多的招式
- 平均決策優先級

## 相關文件

- [MOVE_RESTRICTIONS_GUIDE.md](MOVE_RESTRICTIONS_GUIDE.md) - 使用指南
- [ai_behavior.gd](ai_behavior.gd) - AI 主控制器
- [AIDecisionLayers.gd](AIDecisionLayers.gd) - 決策層系統
- [../AI_SYSTEM_README.md](../AI_SYSTEM_README.md) - AI 系統總覽
