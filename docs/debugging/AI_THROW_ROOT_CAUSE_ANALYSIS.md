# AI 投擲問題初步診斷

## 已調查的系統

✅ **決策層 (AIDecisionLayers.gd)**
- throw 決策在近距離 (< 100px) 時確實被評估
- 優先級範圍: 66±2 for neutral, 78±1 for blocking
- 條件: distance < 100 AND not is_attacking AND not is_hit AND not is_knockfly

✅ **AI 行為層 (ai_behavior.gd)**  
- "_action_to_input("throw")" 確實存在
- throw_pressed 被正確設置為 true
- _commit_action() 轉換邏輯看起來正確

✅ **執行層 (AttackExecutor.gd)**
- throw_pressed 檢查存在於 try_execute_ground_attack()
- 條件: throw_pressed AND not is_crouching
- 應該中斷普通攻擊並執行 throw_enter

---

## 最可能的根本原因 (優先級)

### #1 優先級衝突 🎯 (最可能 = 70%)

**症狀特徵**:
- AI 偶爾投擲，但通常執行普通攻擊
- 調試日誌會顯示投擲被評估但未被選中

**原因分析**:
```
throw 優先級:        66.0 ± (-2.0 to 2.0)   = 64-68 範圍
st_mp 優先級:        67.0 ± (-2.0 to 3.0)   = 65-70 範圍
st_mk 優先級:        67.0 ± (-2.0 to 3.0)   = 65-70 範圍

範圍重疊度: 完全重疊
決策結果: 隨機 (50% throw, 50% normals)
```

**證據來源**:
- 代碼行: `AIDecisionLayers.gd` line 708 for throw_dec.priority
- 代碼行: `AIDecisionLayers.gd` line 715-727 for st_mp/st_mk priority

**修復建議** (按優先級):
```gdscript
// 選項 A: 增加 throw 優先級 (推薦)
throw_dec.priority = 70.0 if opponent.is_blocking else 68.0

// 選項 B: 減少普通攻擊的上限
mp.priority = PRIORITY_NORMAL_MID + randf_range(-2.0, 1.0)  // Max = 68

// 選項 C: 增加特定距離下的 throw 優先級
if distance < 80:  // Very close
    throw_dec.priority = 72.0
```

---

### #2 決策冷卻阻止 ⏳ (機率 = 50%)

**症狀特徵**:
- 除了第一次靠近外，投擲永遠不發生
- 調試日誌顯示決策層未被重新評估

**原因分析**:
```
ai_behavior.get_ai_input() 中的冷卻邏輯:

if decision_cooldown > 0:
    decision_cooldown -= delta
    return committed_input  // 重用舊動作！

決策冷卻持續時間: 0.0833 秒 (DECISION_INTERVAL = 5 幀 @ 60 FPS)

如果上一個決策是「走向前方」(walk_forward):
- 動作持續: 0.3-0.6 秒
- 冷卻持續: 0.083 秒
- 總持續時間: 0.383-0.683 秒

在這段時間內，AI 會重複「walk」輸入，無法評估 throw
```

**證據來源**:
- 代碼行: `ai_behavior.gd` line 325-331
- 動作持續映射: `ai_behavior.gd` line 461-483

**檢查方式**:
監看日誌中 "DECISION INTERVAL" 或 "Committed:" 的頻率:
```
// 正常應該每 0.083 秒（5 幀）出現一次新決策
[AI] Committed: walk_forward (0.50s remaining)
[AI] Committed: walk_forward (0.42s remaining)
[AI] Committed: walk_forward (0.34s remaining)
// ... 無法切換到 throw
```

**修復建議**:
```gdscript
// 在 AIDecisionLayers._evaluate_tactical_layer() 末尾
// 當偵測到 throw 機會時，強制中斷承諾
if throw_dec.priority > 70 and ai.commitment_timer > 0:
    ai.commitment_timer = 0  // 立即重新評估

// 或簡單地降低走路的承諾時間
"walk_forward": {"min": 0.15, "max": 0.25}  // 更頻繁的決策更新
```

---

### #3 蹲下狀態阻止 🚫 (機率 = 30%)

**症狀特徵**:
- 投擲偶爾執行，但在特定位置失敗
- 調試日誌顯示 `[ATTACK_EXECUTOR] ... is_crouching=true`

**原因分析**:
```
投擲要求: throw_pressed AND not is_crouching

AI _action_to_input("throw") 沒有設置 crouch_pressed:
但 neutral_input() 可能設置默認 crouch_pressed = true?

檢查: ai_behavior.gd 行 585-592 (_neutral_input)
```

**修復建議**:
```gdscript
func _action_to_input(action: String) -> Dictionary:
	var input = _neutral_input()
	
	// 添加這一行到 "throw": 情況
	"throw":
		input.throw_pressed = true
		input.crouch_pressed = false  // 【新增】確保不蹲下
```

---

### #4 距離檢查失敗 📏 (機率 = 20%)

**症狀特徵**:
- throw 決策從未出現在日誌中
- 調試日誌沒有 "[TACTICAL THROW CHECK]" 行

**原因分析**:
```
throw 決策需要: distance < 100

如果 AI 停留在 100-150 範圍內，將被視為「中距離」
中距離決策層優先執行走路攻擊，不評估 throw
```

**修復建議**:
```gdscript
// 在決策層擴大距離範圍
if distance < 120:  // 增加 20 像素
    // throw 邏輯
```

---

## 調試計畫

執行以下步驟以確認根本原因：

### 階段 1: 確認 throw 被評估 (5 分鐘)

```
1. 啟動遊戲
2. 按 C 啟用 AI
3. 靠近對手 (距離 < 100)
4. 檢查控制台是否有 "[TACTICAL THROW CHECK] ... ELIGIBLE=true"
5. 檢查是否有 "[TACTICAL THROW ADDED]"

結果:
✓ 兩個都出現 → 移至階段 2
✗ 都沒出現 → 可能是距離或狀態問題 (#4 or #3)
```

### 階段 2: 確認 throw 是否被選中 (5 分鐘)

```
1. 監看 "[DECISION LAYER FINAL]" 行
2. 檢查它是否說 "Selected: 'throw'"

結果:
✓ 是 → 移至階段 3
✗ 不是 → 優先級問題確認 (#1) → 應用修復
```

### 階段 3: 確認 throw_pressed 是否發送 (5 分鐘)

```
1. 監看 "[AI._action_to_input]" 行
2. 檢查是否有 "Setting throw_pressed=true"

結果:
✓ 是 → 移至階段 4
✗ 不是 → 決策冷卻問題 (#2) → 應用修復
```

### 階段 4: 確認 AttackExecutor 是否執行 (5 分鐘)

```
1. 監看 "[EXECUTE THROW]" 行
2. 檢查是否執行了投擲

結果:
✓ 是 → 投擲應該工作 (檢查 ThrowHandler)
✗ 不是 → 蹲下/攻擊狀態問題 (#3) → 應用修復
```

---

## 推薦立即修復

基於代碼分析，首先嘗試這個修復：

**文件**: `ai/AIDecisionLayers.gd` (近距離分支，line ~708)

```gdscript
// 當前代碼 (優先級太相似):
throw_dec.priority = 66.0 + randf_range(-2.0, 2.0)

// 修復為:
throw_dec.priority = 70.0 + randf_range(-1.0, 1.0)  // 範圍: 69-71
```

這會確保投擲（69-71）始終優先於普通攻擊（65-70），同時保留對手格擋時更高的優先級（78±1）。

---

## 提交後測試

修復後，運行此測試檢查清單：

- [ ] AI 靠近時開始投擲
- [ ] 投擲在 10 秒內至少執行 2-3 次
- [ ] 投擲有時被格擋、有時成功
- [ ] 日誌顯示 "[EXECUTE THROW]" 且成功率 > 50%

