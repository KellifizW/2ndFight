# 🔴 輸入歷史異常清除 - 快速診斷卡

## 📌 問題概述
- **症狀**：按摔投(LP+LK)時，輸入歷史顯示被異常清空
- **原因**：待診斷（調試工具已部署）

## ⚡ 快速診斷步驟

### 1️⃣ 啟動遊戲並打開控制台
```
F5 或點擊播放 → 查看 "Output" 標籤
```

### 2️⃣ 觀察啟動訊息（應該看到）
```
[WORLD] ✓ InputHistoryDebugger 已初始化 - 監控輸入歷史顯示狀態
```
✅ 看到 = 調試工具已啟動，準備診斷
❌ 看不到 = world.gd 可能沒有正確加載

### 3️⃣ 執行摔投並收集日誌
1. 正常遊玩一段時間
2. 按 LP + LK 執行摔投
3. **關鍵**：記下摔投前後的輸入歷史顯示是否消失

### 4️⃣ 檢查控制台輸出

#### 🚨 紅旗信號 (代表問題存在)
```
[☠️ CLEAR() CALLED - BUG FOUND! ☠️]
=== 調用堆棧跟蹤 ===
```
❌ 這表示有代碼在調用 `clear()`

```
🔴 [PROBLEM] No visible elements but input history has data!
   → input_durations array likely cleared or not populated
```
❌ 這表示 `input_durations` 陣列被清除了

#### ✅ 綠旗信號 (表示正常)
```
[InputHistoryDisplayIcon] Input changed | last_idx=X -> current=Y
[InputHistoryDisplayIcon] Update | current_idx=X | non_zero_inputs=Y
```

## 🎯 根據不同結果採取行動

### 情況 A：看到 clear() 被調用的堆棧跟蹤
```
→ 移除或註釋調用 clear() 的代碼
→ 搜索: input_display.clear() 或 display.clear()
```

### 情況 B：input_durations 陣列為空
```
→ 檢查 _process() 是否被執行
→ 檢查 input_start_times 陣列的狀態
→ 搜索: input_durations.clear() 或 input_durations.resize(0)
```

### 情況 C：沒看到任何異常信息
```
→ 確認輸入歷史顯示在遊戲中確實消失了（不是幻覺）
→ 檢查 update_history_display() 的邏輯
→ 考慮是否是 Engine.time_scale 或其他系統干擾
```

## 📁 相關文件位置
| 文件 | 用途 | 位置 |
|------|------|------|
| InputHistoryDisplayIcon.gd | 圖標版顯示腳本 (已增強日誌) | scripts/ui/ |
| InputHistoryDisplay.gd | 文字版顯示腳本 (已增強日誌) | scripts/ui/ |
| InputHistoryDebugger.gd | 自動診斷工具 | scripts/debug/ |
| InputManager.gd | 輸入追蹤 (已增強日誌) | scripts/input/ |
| ThrowHandler.gd | 摔投執行 (已增強日誌) | scripts/combat/handlers/ |
| world.gd | 自動集成調試器 | scripts/core/ |

## 🔥 高優先級檢查

在控制台中搜索以下關鍵詞（按優先級）：

1. **[☠️ CLEAR() CALLED**
   - 頻率：應該不出現
   - 若出現：找到問題！

2. **[PROBLEM] No visible elements**
   - 頻率：應該不出現
   - 若出現：input_durations 被清除

3. **[ThrowHandler] Clearing opponent's input_buffer**
   - 頻率：每次摔投時出現一次
   - 正常現象

4. **[InputHistoryDebugger] Status Check**
   - 頻率：每30幀出現一次
   - 如果未出現：調試工具未啟動

## 💾 保存日誌方便分析

### Windows (PowerShell)
```powershell
# 運行遊戲並重定向輸出到文件
$process = Start-Process "godot.exe" -PassThru
# 等待遊戲運行和記錄...
# 輸出應該會顯示在 Godot 編輯器的 Output 標籤中
```

### 在 Godot 編輯器中
1. 右鍵點擊 Output 內容
2. 全選 (Ctrl+A)
3. 複製並貼到記事本

## 🎬 測試場景

推薦的完整測試流程：
```
1. 啟動遊戲 → 觀察初始化日誌
2. 正常進行 10-15 秒 → 觀察定期狀態檢查
3. 執行摔投 → 觀察是否有異常信息
4. 等待 30-60 秒 → 再檢查一次狀態
5. 重複摔投 2-3 次 → 確認問題是否穩定重現
```

## 📞 如果仍無法確定問題

收集以下信息提供給開發者：
1. 完整的控制台輸出日誌（特別是摔投前後）
2. 是否始終在摔投時發生，還是偶發
3. 是否兩個玩家都會發生
4. 說明在遊戲中視覺上看到輸入歷史消失的確切時間點

---
**下一步**：執行上述診斷步驟，查看控制台輸出，根據結果確定問題根源！
