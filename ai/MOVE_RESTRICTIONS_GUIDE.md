# AI 招式限制系統使用指南

## 概述

這個系統允許您在 Godot Inspector 中直接設定 AI 對手可以使用的招式，用於測試和訓練不同的 AI 行為模式。

## 使用方法

### 在 Godot 編輯器中配置

1. **打開玩家場景**
   - 在 Godot 編輯器中打開 `player1.tscn` 或 `player2.tscn`

2. **選擇 AIBehavior 節點**
   - 在場景樹中找到並選擇 `AIBehavior` 節點

3. **配置招式限制**
   - 在 Inspector 面板中找到 **Move Restrictions** 分類
   - 勾選 ☑️ **Enable Move Restrictions**
   - 在 **Restricted Moves** 陣列中添加要禁用的招式

### 可用招式列表

#### 特殊招式
- `fireball` - 火球（通用招式）
- `dp` - 昇龍拳（DAV 專屬）
- `powerkk` - Power KK（DAV 專屬）
- `spnk` - Special NK（DEN 專屬）
- `hdk` - Heavy DK（DEN 專屬）
- `super` - 超必殺技

#### 普通攻擊
- `st_mp` - 站立中拳
- `st_mk` - 站立中腳
- `cr_mp` - 蹲下中拳
- `cr_mk` - 蹲下中腳

#### 移動招式
- `dash_forward` - 前衝刺
- `backdash` - 後撤步
- `jump_forward` - 前跳
- `jump_backward` - 後跳
- `jump_neutral` - 垂直跳

#### 防禦動作
- `stand_block` - 站立格擋
- `crouch_block` - 蹲下格擋

## 測試情境範例

### 情境 1：測試無火球對戰
```
Enable Move Restrictions: ☑️
Restricted Moves: ["fireball"]
```
**預期行為**：AI 將更多使用接近戰、跳躍攻擊和地面普通攻擊

### 情境 2：測試純基礎攻擊
```
Enable Move Restrictions: ☑️
Restricted Moves: ["fireball", "dp", "powerkk", "spnk", "hdk", "super"]
```
**預期行為**：AI 只使用 st_mp、cr_mk、jump 等基礎招式

### 情境 3：測試無防禦反擊技
```
Enable Move Restrictions: ☑️
Restricted Moves: ["dp", "super"]
```
**預期行為**：AI 在壓力下會更多使用格擋和後撤

### 情境 4：測試地面戰
```
Enable Move Restrictions: ☑️
Restricted Moves: ["jump_forward", "jump_backward", "jump_neutral"]
```
**預期行為**：AI 只在地面移動和攻擊

### 情境 5：測試無位移攻擊
```
Enable Move Restrictions: ☑️
Restricted Moves: ["dash_forward", "backdash"]
```
**預期行為**：AI 使用步行和跳躍進行位置調整

## 系統工作原理

### 決策過濾機制

當 AI 做出決策時，系統會：

1. **正常決策流程**
   - AI 透過分層決策系統選擇最佳動作

2. **招式檢查**
   - 檢查選定的動作是否在 `restricted_moves` 列表中

3. **後備決策**
   - 如果動作被限制，系統自動尋找次優的合法動作
   - 優先級順序：生存 > 懲罰 > 戰術 > 定位 > 待機

4. **安全機制**
   - 如果所有招式都被限制，AI 會使用安全的待機動作（walk_forward）

### Debug 輸出

啟用 `Debug Mode` 後，當 AI 遇到被限制的招式時，會在控制台輸出：
```
[AI] Move 'fireball' is restricted, finding alternative...
[AI] NEW DECISION: 'dash_forward' locked for 0.35s (priority-based)
```

## 技術細節

### 文件修改

1. **ai_behavior.gd**
   - 添加 `enable_move_restrictions` 和 `restricted_moves` 導出變數
   - 在決策執行前檢查招式限制
   - 調用後備決策函數

2. **AIDecisionLayers.gd**
   - 在 `get_best_decision()` 中過濾被限制的招式
   - 添加 `get_fallback_decision()` 函數提供替代選擇
   - 維護 `restricted_moves` 陣列

### 性能影響

- **最小化**：只在決策階段（每 0.15 秒）檢查一次
- **無運行時開銷**：如果 `enable_move_restrictions = false`，系統完全不運行

## 注意事項

1. **關鍵生存決策**
   - 即使被限制，生存層的決策（優先級 >= 95）會被強制轉換為 `stand_block`
   - 這確保 AI 在危險情況下仍有防禦能力

2. **Combo 系統**
   - 連段中的招式不受限制影響
   - 一旦開始連段，會執行完整序列

3. **動作承諾**
   - 已承諾的動作不會被中斷
   - 限制只在新決策時生效

## 擴展建議

### 未來可能的功能

1. **頻率限制**
   ```gdscript
   # 例如：每 10 秒只能使用 1 次火球
   @export var move_cooldowns: Dictionary = {"fireball": 10.0}
   ```

2. **條件限制**
   ```gdscript
   # 例如：只在遠距離禁用火球
   @export var distance_based_restrictions: Dictionary = {}
   ```

3. **動態難度調整**
   ```gdscript
   # 根據玩家表現自動調整限制
   func adjust_restrictions_by_performance() -> void
   ```

## 故障排除

### 問題：AI 不執行任何動作
**解決方案**：檢查是否限制了太多招式，確保至少保留基本移動（walk_forward/backward）

### 問題：AI 忽略限制設定
**解決方案**：確認 `Enable Move Restrictions` 已勾選

### 問題：限制的招式仍然出現
**解決方案**：
1. 檢查招式名稱拼寫是否正確
2. 確認 AIBehavior 節點正確初始化
3. 啟用 Debug Mode 查看決策日誌

## 相關文件

- [ai/README.md](README.md) - AI 系統總覽
- [../AI_SYSTEM_README.md](../AI_SYSTEM_README.md) - 詳細 AI 架構文檔
- [AIDecisionLayers.gd](AIDecisionLayers.gd) - 決策系統實現
- [ai_behavior.gd](ai_behavior.gd) - AI 行為主控制器
