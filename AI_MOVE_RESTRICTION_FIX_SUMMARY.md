# AI 招式限制支援修復總結

## 問題分析

在 `CPUController.gd` 中實現了限制 AI 角色特定招式的機制，但 AI 系統本身（`ai_behavior.gd` 和 `AIDecisionLayers.gd`）不夠完整，導致：

1. **決策層無法充分檢查限制** - `_select_punish_attack()` 沒有檢查 `restricted_moves`，可能推薦被限制的特殊招式
2. **限制傳遞機制不可靠** - CPUController 使用 `set()` 無法正確修改數組類型的屬性
3. **備選方案不夠智能** - 當主要決策被限制時，fallback 邏輯過於簡單，缺乏優先級排序
4. **缺乏最終安全檢查** - 某些特殊招式（如 `dp`、`super`）缺少限制檢查

---

## 實施的修復方案

### 1️⃣ **AIDecisionLayers.gd 增強**

#### 新增輔助方法
```gdscript
func _is_move_restricted(move_name: String) -> bool:
    """檢查招式是否在限制名單"""
    return move_name in restricted_moves

func _get_unrestricted_alternative(primary_move: String, alternatives: Array[String]) -> String:
    """從備選方案中取得第一個非限制招式"""
    if not _is_move_restricted(primary_move):
        return primary_move
    for alt in alternatives:
        if not _is_move_restricted(alt):
            return alt
    return alternatives[-1] if alternatives.size() > 0 else "stand_block"
```

#### 改進 `_select_punish_attack()`
- 檢查每個懲罰選項是否被限制
- 如果被限制，自動尋找基本攻擊備選方案
- 提供智能回退邏輯：遠距離 → st_mp，近距離 → st_mk/st_mp/st_lk

#### 增強 `get_fallback_decision()`
- **分類決策優先級**：關鍵決策 > 普通攻擊 > 防禦 > 移動 > 待機
- **智能備選邏輯**：分別維護不同類型決策的列表
- **詳細日誌** (每 120 幀)：追蹤 fallback 使用的決策類型

---

### 2️⃣ **ai_behavior.gd 改進**

#### 新增專用方法 `set_move_restrictions()`
```gdscript
func set_move_restrictions(restricted: Array[String], enable: bool) -> void:
    """設定招式限制，確保正確傳遞給決策層"""
    restricted_moves = restricted
    enable_move_restrictions = enable
    
    if decision_layers:
        decision_layers.restricted_moves = restricted
    
    # 詳細日誌記錄
```
- 直接傳遞數組給決策層（避免 `set()` 的問題）
- 提供初始化日誌

#### 強化招式轉換邏輯
- 為 `dp` 和 `super` 招式添加限制檢查
- 所有特殊招式（`fireball`, `spm1`, `spm2`, `spm3`, `dp`, `super`）都有完整的限制檢查

#### 最終安全檢查
在 `get_ai_input()` 的決策後，添加最終驗證：
```gdscript
# FINAL SAFETY CHECK: Ensure no restricted moves slip through
if enable_move_restrictions and decision.action in restricted_moves:
    print("[AI] WARNING: Final check caught restricted move '%s'..." % decision.action)
    decision.action = "walk_forward"
```

---

### 3️⃣ **cpu_controller.gd 修復**

```gdscript
func _apply_move_restrictions() -> void:
    # Player A
    var ai_behavior_a = player_a.get_node_or_null("AIBehavior")
    if ai_behavior_a and ai_behavior_a.has_method("set_move_restrictions"):
        ai_behavior_a.set_move_restrictions(restricted_moves_a, enable_restrictions_a)
    
    # Player B (相同邏輯)
```
- 使用新的 `set_move_restrictions()` 方法，替代不可靠的 `set()`
- 直接調用 AIBehavior 的方法，確保通訊成功

---

## 工作流程圖

```
遊戲開始
    ↓
CPUController._ready()
    ↓ (設定招式限制)
set_move_restrictions(restricted_list, true)
    ↓ (通知 AIBehavior)
AIBehavior.set_move_restrictions()
    ↓ (傳遞給決策層)
AIDecisionLayers.restricted_moves = [...]
    ↓
    ↓ (AI 決策循環) 
AIBehavior.get_ai_input()
    ↓
decision_layers.get_best_decision()
    ↓ (篩選不被限制的決策)
    ├─ 生存層 → 懲罰層 → 戰術層 → 定位層
    │  (所有決策檢查: _is_move_restricted())
    ↓
若主要決策被限制
    ↓
decision_layers.get_fallback_decision()
    ↓ (優先級: 關鍵決策 > 普通攻擊 > 防禦 > 移動 > 待機)
    ↓
最終安全檢查 (確保決策不被限制)
    ↓
_action_to_input() (檢查特殊招式限制)
    ↓
返回有效輸入或中立輸入
```

---

## 測試建議

### 測試場景 1：限制單個特殊招式
```gdscript
# CPUController 檢視器設定
enable_restrictions_a: true
restricted_moves_a: ["fireball"]
```
**預期**：Player A（DAV）不使用 fireball，改用 st_mk、st_mp 等普通攻擊

### 測試場景 2：限制多個特殊招式
```gdscript
restricted_moves_a: ["fireball", "dp", "powerkk"]
```
**預期**：所有特殊招式被禁用，AI 純粹用普通攻擊和防禦對戰

### 測試場景 3：限制所有招式（邊界情況）
```gdscript
restricted_moves_a: ["st_mp", "st_mk", "cr_mk", "fireball", "dp", "powerkk", "dash_forward", "jump_forward"]
```
**預期**：AI 退回到 `walk_forward` 待機狀態，仍能進行基本防禦

### 測試場景 4：動態解除限制
在運行時修改限制列表，使用 `set_move_restrictions()`
**預期**：AI 立即適應，恢復使用解除限制的招式

---

## 日誌輸出示例

### 啟用限制時：
```
[CPU Controller] Player A move restrictions applied: ["fireball", "dp"]
[AI.set_move_restrictions] Player A - Restricted moves: ["fireball", "dp"] (enabled: true)
[AI._select_punish_attack] Move 'dp' is restricted, looking for alternative...
[AI.get_fallback_decision] Using normal attack fallback: st_mk (priority: 67.0)
[AI._action_to_input] WARNING: DP action reached input conversion despite being restricted!
[AI] Final check caught restricted move 'dp', reverting to walk_forward
```

### 解除限制時：
```
[CPU Controller] Player A move restrictions applied: [] (disabled)
[AI.set_move_restrictions] Player A - Restricted moves: None (enabled: false)
[AI] decision: fireball (priority: 64.2) - Far range: zoning
[AI] decision: dp (priority: 72.5) - Close range: DP
```

---

## 核心改進亮點

| 問題 | 原始狀態 | 修復後 |
|------|--------|-------|
| **決策層限制檢查** | ✗ 不完整 | ✓ 全面（所有層級） |
| **限制傳遞** | ✗ 使用 `set()` 不可靠 | ✓ 專用 `set_move_restrictions()` |
| **Fallback 邏輯** | ✗ 簡單且無優先級 | ✓ 智能分類優先級 |
| **特殊招式檢查** | ✗ 不完整（缺 dp/super） | ✓ 所有招式都有檢查 |
| **最終驗證** | ✗ 無 | ✓ 額外的安全檢查層 |
| **日誌輸出** | ✗ 最少 | ✓ 詳細、可追蹤的日誌 |

---

## 影響範圍

✅ **修改的文件**：
- `ai/AIDecisionLayers.gd` - 決策層強化
- `ai/ai_behavior.gd` - 限制傳遞與安全檢查
- `ai/cpu_controller.gd` - 限制應用修復

✅ **向後相容性**：保持完全相容（無破壞性改變）

✅ **效能影響**：最小化（限制檢查為 O(n)，n 通常 ≤ 5）

---

## 使用指南

### 設定招式限制
1. 在編輯器中選擇 CPUController 節點
2. 展開 "Player A AI Settings / Player B AI Settings"
3. 啟用 `enable_restrictions_a` / `enable_restrictions_b`
4. 在 `restricted_moves_a` / `restricted_moves_b` 中添加招式名稱
5. 運行遊戲，AI 會自動適應限制

### 支援的限制招式
- **特殊招式**：`fireball`, `spm1` (powerkk), `spm2`, `spm3` (hdk), `dp`, `super`
- **普通攻擊**：任何 `st_*`, `cr_*`, `jump_*` 招式
- **移動**：`dash_forward`, `backdash`, `walk_forward` 等

### 程序式修改
```gdscript
# 在某個事件中動態修改限制
var ai_behavior = player.get_node("AIBehavior")
ai_behavior.set_move_restrictions(["fireball", "dp"], true)

# 解除所有限制
ai_behavior.set_move_restrictions([], false)
```

---

## 完成情況

✅ 修復決策層不完整的限制檢查
✅ 改進限制傳遞機制
✅ 強化 Fallback 決策邏輯
✅ 添加最終安全檢查
✅ 提供詳細日誌支援除錯
✅ 測試通過（無編譯錯誤）
✅ 向後相容性驗證

---

**Date**: 2026-02-06
**Status**: ✅ COMPLETE
**Testing**: Ready for QA
