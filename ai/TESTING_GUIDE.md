# AI 招式限制測試指南

## 快速測試步驟

### 1. 啟用 Debug 模式

在 Godot 編輯器中：
1. 選擇 Player 場景中的 **AIBehavior** 節點
2. 在 Inspector 勾選 ☑️ **Debug Mode**
3. 勾選 ☑️ **Enable Move Restrictions**

### 2. 測試案例

#### 測試 A：禁用火球（預期：使用接近戰）

**配置**：
```
Enable Move Restrictions: ☑️
Debug Mode: ☑️
Restricted Moves: ["fireball"]
```

**預期結果**：
- ✅ AI 會使用 dash_forward 接近
- ✅ 中距離會使用 st_mk、st_mp 攻擊
- ✅ 近距離會使用連段和特殊技
- ✅ Console 顯示：`Filtered 1 restricted moves`

**驗證方法**：
```
1. 啟動遊戲
2. 按 V 鍵啟用 Player B AI
3. 保持遠距離（> 250 像素）
4. 觀察 Console 輸出
```

**預期 Console 輸出**：
```
[AI] Filtered 1 restricted moves. Available decisions: 8
  - dash_forward (65.0): Far range: aggressive approach
  - jump_forward (63.5): Far range: jump approach
  - walk_forward (62.0): Far range: steady approach
[AI] player_b decision: dash_forward (priority: 65.0) - Far range: aggressive approach
```

---

#### 測試 B：禁用所有特殊技（預期：只用普攻）

**配置**：
```
Enable Move Restrictions: ☑️
Debug Mode: ☑️
Restricted Moves: ["fireball", "dp", "powerkk", "spnk", "hdk", "super"]
```

**預期結果**：
- ✅ AI 只使用普通攻擊（st_mp, cr_mk 等）
- ✅ 使用移動（dash, walk, jump）
- ❌ 不會使用任何特殊技
- ✅ Console 顯示：`Filtered X restricted moves` (X >= 1)

**預期 Console 輸出**：
```
[AI] Filtered 6 restricted moves. Available decisions: 12
  - st_mk (68.5): Mid range: poke
  - st_mp (66.2): Mid range: quick poke
  - cr_mk (65.8): Mid range: low poke
[AI] player_b decision: st_mk (priority: 68.5) - Mid range: poke
```

---

#### 測試 C：禁用普攻（預期：使用特殊技和移動）

**配置**：
```
Enable Move Restrictions: ☑️
Debug Mode: ☑️
Restricted Moves: ["st_mp", "st_mk", "cr_mp", "cr_mk"]
```

**預期結果**：
- ✅ AI 會使用特殊技（fireball, dp, powerkk, spnk, hdk）
- ✅ 使用移動招式接近
- ❌ 不使用被禁用的普攻
- ✅ Console 顯示普攻被過濾

---

#### 測試 D：禁用移動（預期：原地攻擊）

**配置**：
```
Enable Move Restrictions: ☑️
Debug Mode: ☑️
Restricted Moves: ["dash_forward", "backdash", "walk_forward", "walk_backward"]
```

**預期結果**：
- ✅ AI 使用跳躍移動
- ✅ 使用攻擊招式
- ❌ 不會前後走動或衝刺
- ⚠️ 可能較被動（因為缺少地面移動）

---

## 故障診斷

### 問題 1：AI 仍然只會移動

**可能原因**：
1. 過濾邏輯仍有問題
2. 決策優先級配置錯誤
3. 戰術層沒有產生攻擊決策

**診斷步驟**：
```
1. 確認 Debug Mode 已啟用
2. 查看 Console 輸出的 "Available decisions" 數量
3. 檢查最高優先級的決策是什麼
```

**Console 輸出範例（問題情況）**：
```
[AI] Filtered 1 restricted moves. Available decisions: 2  ⚠️ 太少！
  - walk_forward (62.0): Far range: steady approach
  - walk_forward (10.0): Default behavior
```

**解決方案**：
- 檢查是否意外禁用了太多招式
- 確認 `restricted_moves` 陣列只包含想禁用的招式

---

### 問題 2：沒有 Console 輸出

**可能原因**：
1. Debug Mode 未啟用
2. AI 未啟用
3. 輸出被其他日誌淹沒

**解決方案**：
```gdscript
# 在 ai_behavior.gd 中強制輸出
if enable_move_restrictions:
    print("[AI TEST] Move restrictions active: %s" % str(restricted_moves))
```

---

### 問題 3：過濾了所有招式

**Console 輸出**：
```
[AI] Filtered 20 restricted moves. Available decisions: 1  ⚠️
  - walk_forward (10.0): Default behavior
```

**原因**：`restricted_moves` 陣列過大

**解決方案**：
- 縮小 `restricted_moves` 範圍
- 確保至少保留基礎攻擊或移動招式

---

## 效能檢查清單

### 修正前後對比

| 指標 | 修正前 | 修正後 |
|------|--------|--------|
| 禁用火球後使用攻擊 | ❌ 否 | ✅ 是 |
| 決策統計輸出 | ❌ 無 | ✅ 有 |
| 空決策列表保護 | ⚠️ 不完整 | ✅ 完整 |
| 後備決策詳細資訊 | ⚠️ 簡單 | ✅ 詳細 |

---

## 進階測試

### 動態切換測試

**測試目的**：驗證運行時修改 `restricted_moves` 是否生效

**步驟**：
1. 遊戲中啟用 AI
2. 觀察 AI 行為（使用所有招式）
3. 在 Inspector 中添加 `["fireball"]` 到 `restricted_moves`
4. 觀察 AI 行為變化

**預期結果**：
- ✅ AI 立即停止使用火球
- ✅ 開始使用其他攻擊招式

---

### 壓力測試

**測試目的**：驗證系統在極端情況下的穩定性

**測試案例 1：禁用所有招式（除了 idle）**
```
Restricted Moves: [所有攻擊和移動招式]
```

**預期結果**：
- ✅ AI 使用 walk_forward (idle 決策)
- ✅ 不會崩潰
- ✅ Console 顯示大量過濾

**測試案例 2：空陣列（無限制）**
```
Restricted Moves: []
Enable Move Restrictions: ☑️
```

**預期結果**：
- ✅ AI 正常使用所有招式
- ✅ Console 不顯示過濾資訊

---

## 性能測量

### 測量指標

1. **決策延遲**：從決策產生到執行的時間
   - 目標：< 16.67ms（1 幀）
   - 實際：< 1ms（因為只在 0.15s 間隔執行）

2. **過濾開銷**：檢查 `restricted_moves` 的成本
   - 複雜度：O(n × m)，n=決策數量，m=限制招式數量
   - 典型值：20 × 6 = 120 次字串比對
   - 影響：可忽略（< 0.1ms）

3. **Debug 輸出頻率**：
   - 每 120 幀一次（2 秒間隔）
   - 不影響遊戲效能

---

## 已知限制

### 1. Combo 系統不受限制

**現況**：一旦開始連段，所有步驟都會執行，即使包含被限制的招式

**原因**：Combo 有獨立的保護機制

**影響**：低（連段通常由普攻組成）

### 2. 生存決策強制轉換

**現況**：優先級 >= 95 的生存決策如果被限制，會強制轉為 `stand_block`

**原因**：確保 AI 在危險情況下有防禦能力

**影響**：無（符合預期）

### 3. 決策統計僅在 Debug 模式顯示

**現況**：需要啟用 Debug Mode 才能看到詳細輸出

**原因**：避免生產環境的日誌污染

**影響**：無（測試時啟用即可）

---

## 回歸測試清單

- [ ] 測試 A：禁用火球
- [ ] 測試 B：禁用所有特殊技
- [ ] 測試 C：禁用普攻
- [ ] 測試 D：禁用移動
- [ ] 動態切換測試
- [ ] 壓力測試（禁用所有招式）
- [ ] 空陣列測試（無限制）
- [ ] 確認 Console 輸出正確
- [ ] 確認 AI 行為符合預期
- [ ] 確認無錯誤訊息

---

## 聯絡與反饋

如果發現新問題，請提供：
1. `restricted_moves` 陣列內容
2. Console 完整輸出
3. AI 實際行為描述
4. 預期行為描述
