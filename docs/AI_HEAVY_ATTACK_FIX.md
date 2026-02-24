# AI Heavy Attack Fix - 重攻击修復報告

## 問題診斷

### 原始問題
用戶報告：AI對戰只使用輕攻擊（lp/lk）和中攻擊（mp/mk），**完全不使用重攻擊**（hp/hk）。

### 根本原因
通過分析 `AIDecisionLayers.gd` 中的 `_evaluate_tactical_layer()` 函數發現：

1. **優先級範圍不平等**：
   - 輕攻擊（lp/lk）：66-71 範圍
   - 中攻擊（mp/mk）：66-70 範圍
   - 重攻擊（hp/hk）：**65-69 範圍** ← 上限更低！

2. **額外的距離限制**：
   - 中距離（100-250）的重攻擊被限制在 `if distance < 200` 條件內
   - 這進一步減少了重攻擊被選擇的機會

3. **數學概率問題**：
   - 當所有決策都在決策池中競爭時，優先級上限較低的選項（69）很難戰勝上限較高的選項（70-71）
   - 即使範圍有重疊，重攻擊的平均優先級也低於輕/中攻擊

## 解決方案

### 修改內容

#### 1. 中距離（100-250）重攻擊
**文件位置**：`ai/AIDecisionLayers.gd` 第 412-438 行

**修改前**：
```gdscript
# Priority 7: Heavy attacks (slower startup, higher damage) - 再次提升優先級
if distance < 200:  # ← 有距離限制
    var st_hp = Decision.new()
    st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-2.0, 2.0)  # 65-69
    # ... (其他重攻擊也是 65-69)
```

**修改後**：
```gdscript
# Priority 7: Heavy attacks (slower startup, higher damage) - 提升至與輕攻擊相同範圍
# ← 移除距離限制
var st_hp = Decision.new()
st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)  # 66-71
# ... (所有重攻擊都是 66-71)
```

#### 2. 近距離（<100）重攻擊
**文件位置**：`ai/AIDecisionLayers.gd` 第 591-618 行

**修改前**：
```gdscript
# Priority 5: Heavy attacks
var st_hp = Decision.new()
st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-2.0, 2.0)  # 65-69
# ... (其他重攻擊也是 65-69)
```

**修改後**：
```gdscript
# Priority 5: Heavy attacks - 提升至與輕攻擊相同範圍
var st_hp = Decision.new()
st_hp.priority = PRIORITY_NORMAL_HIGH + randf_range(-1.0, 4.0)  # 66-71
# ... (所有重攻擊都是 66-71)
```

### 修改摘要

| 攻擊類型 | 修改前範圍 | 修改後範圍 | 額外條件變化 |
|---------|-----------|-----------|-------------|
| st_hp (中距離) | 65-69 | 66-71 | 移除 `if distance < 200` |
| st_hk (中距離) | 65-69 | 66-71 | 移除 `if distance < 200` |
| cr_hp (中距離) | 65-69 | 66-71 | 移除 `if distance < 200` |
| cr_hk (中距離) | 65-69 | 66-71 | 移除 `if distance < 200` |
| st_hp (近距離) | 65-69 | 66-71 | 無 |
| st_hk (近距離) | 65-69 | 66-71 | 無 |
| cr_hp (近距離) | 65-69 | 66-71 | 無 |
| cr_hk (近距離) | 65-69 | 66-71 | 無 |

## 技術細節

### 優先級計算邏輯
```gdscript
# 現在所有攻擊類型都使用相同的優先級範圍：
PRIORITY_NORMAL_HIGH (67) + randf_range(-1.0, 4.0) = 66-71
PRIORITY_NORMAL_MID (67) + randf_range(-1.0, 4.0) = 66-71
PRIORITY_NORMAL_LOW (67) + randf_range(-1.0, 4.0) = 66-71
PRIORITY_CROUCH (67) + randf_range(-1.0, 4.0) = 66-71
```

### 預期效果

1. **完全平等的競爭機會**：所有普通攻擊（輕/中/重）現在有相同的優先級範圍（66-71），確保數學上的公平選擇概率。

2. **移除距離限制**：中距離的重攻擊現在在整個100-250範圍內都可用，而不僅僅是100-200。

3. **多樣化的戰鬥風格**：AI應該會展示更豐富的攻擊模式，包括：
   - 輕攻擊（快速但傷害低）
   - 中攻擊（平衡的速度和傷害）
   - 重攻擊（慢速但傷害高）

## 測試驗證

### 測試步驟
1. 啟動遊戲
2. 選擇AI對戰模式（按C鍵切換P1 AI，按V鍵切換P2 AI）
3. 觀察戰鬥日誌中的 `[EXECUTE_ATTACK]` 行
4. 確認出現以下攻擊：
   - ✅ st_hp, st_hk (站立重拳/重腳)
   - ✅ cr_hp, cr_hk (蹲下重拳/重腳)

### 成功標準
在1分鐘的AI對戰中，應該觀察到：
- 至少 2-3 次重攻擊（hp/hk）
- 輕/中/重攻擊的比例大致平衡（各佔 20-40%）
- 不再出現"只有輕/中攻擊"的單調模式

## 相關文件
- `ai/AIDecisionLayers.gd` - 主要修改文件
- `AI_ATTACK_DIVERSITY_FIX.md` - 之前的輕攻擊修復報告
- `AI_ATTACK_DIVERSITY_QUICK.md` - 快速參考指南

## 修訂歷史
- **2026-02-06**: 初次修復 - 將重攻擊優先級從 65-69 提升至 66-71，移除中距離距離限制
- **2026-02-06**: 第三次調整 - 經過兩次輕攻擊/中攻擊優先級調整後，最終將重攻擊提升至相同範圍
