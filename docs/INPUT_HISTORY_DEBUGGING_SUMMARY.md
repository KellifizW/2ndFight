# 輸入歷史異常清除 - 調試工具總結

## 📋 已實施的調試措施

### 🔧 1. 輸入歷史顯示腳本增強

#### InputHistoryDisplayIcon.gd
- ✅ `startup_logs` 改為 `true` 啟用啟動日誌
- ✅ 新增 `debug_history_updates` 開關用於詳細日誌
- ✅ `clear()` 方法現在打印完整的堆棧跟蹤
- ✅ `update_history_display()` 每30幀打印一次狀態
- ✅ `_process()` 監控 `input_durations` 陣列的變化

#### InputHistoryDisplay.gd
- ✅ 新增 `debug_mode` 開關
- ✅ `clear()` 方法也添加堆棧跟蹤輸出

### 🔍 2. 核心系統調試

#### InputManager.gd (scripts/input/)
- ✅ `insert_to_history()` 添加日誌追蹤輸入狀態變更
- ✅ 記錄輸入索引的變化

#### ThrowHandler.gd (scripts/combat/handlers/)
- ✅ `lock_opponent_state()` 添加詳細日誌
- ✅ 清除輸入緩衝時打印警告
- ✅ 檢查是否存在 InputHistoryDisplayIcon 節點

### 🎯 3. 新增診斷工具

#### InputHistoryDebugger.gd (scripts/debug/)
- 自動監控輸入歷史顯示狀態
- 每30幀檢查一次（可配置）
- 偵測異常情況：
  - 顯示元素為0但輸入歷史有數據
  - `input_durations` 陣列為空
  - 追蹤無效的引用

#### 自動集成到 world.gd
- 在 `_ready()` 中自動創建 InputHistoryDebugger 實例
- 無需手動配置

## 🚀 如何使用

### 第1步：運行遊戲
遊戲會自動初始化所有調試工具，無需手動設置。

### 第2步：打開控制台
- 在 Godot 編輯器中按 F5 或點擊"播放"按鈕
- 查看 "Output" 標籤中的控制台輸出

### 第3步：執行摔投
1. 啟動遊戲
2. 按下 LP + LK（摔投）
3. 觀察控制台輸出

## 📊 關鍵調試信息解讀

### 如果看到以下訊息，表示 clear() 被調用：
```
[☠️ CLEAR() CALLED - BUG FOUND! ☠️]
=== 調用堆棧跟蹤 ===
at: InputHistoryDisplayIcon.gd:287 in clear()
at: [某個地點]  ← 這就是問題所在！
```

**含義**：有某處代碼仍在調用 `clear()` 方法。

**對策**：
1. 記下堆棧中的文件位置
2. 去該文件檢查是否有 `input_display.clear()` 或 `display.clear()` 的調用
3. 移除或註釋該調用

### 如果看到以下訊息，表示 input_durations 被清除：
```
[InputHistoryDebugger] Status Check @ Frame 1200
[P1] Display Elements: 0/15 visible
     InputManager history: 8/240 non-zero
     input_durations set: 0 entries
     🔴 [PROBLEM] No visible elements but input history has data!
        → input_durations array likely cleared or not populated
```

**含義**：輸入歷史仍在消息隊列中，但 `input_durations` 陣列已被清除，導致顯示邏輯無法找到要顯示的數據。

**對策**：
1. 搜索 `input_durations.clear()` 或 `input_durations.resize(0)`
2. 檢查是否有地方在重置此陣列

### 正常情況下應該看到：
```
[InputHistoryDebugger] Status Check @ Frame 1200
[P1] Display Elements: 5/15 visible
     InputManager history: 8/240 non-zero
     input_durations set: 5 entries
     Tracking: P1
```

## 📝 調試輸出日誌樣例

### 正常的輸入變更日誌：
```
[InputHistoryDisplayIcon] Input changed | last_idx=5 -> current=6 | last_duration=0.5s (30 frames)
[InputManager:player_a] Input CHANGED | raw_input=0 | idx_change: 5 -> 6
```

### 摔投執行時的日誌：
```
[🔴 ThrowHandler] Clearing opponent's input_buffer at frame 450 | opponent: P2
[ThrowHandler] Input buffer cleared. Calling input display clear() if it exists...
[⚠️ ThrowHandler] Found InputHistoryDisplayIcon - NOT calling clear() to preserve history
```

### 定期狀態檢查：
```
[InputHistoryDisplayIcon] Update | current_idx=10 | non_zero_inputs=12/240 | displayed=5
[InputHistoryDisplayIcon DEBUG] input_durations status: 5/240 entries set (total frames: 150)
```

## 🔎 故障排查清單

- [ ] 啟動遊戲後，世界節點的 "output" 標籤顯示 InputHistoryDebugger 已初始化
- [ ] 正常操作時，InputHistoryDebugger 每30幀輸出一次狀態（正常情況）
- [ ] 執行摔投時：
  - [ ] 是否看到 `[ThrowHandler] Clearing opponent's input_buffer`
  - [ ] 是否看到 `[CLEAR() CALLED]` 消息（應該看不到）
  - [ ] InputHistoryDebugger 的顯示元素計數是否保持不變
- [ ] 摔投後，輸入歷史是否完全消失（應該保留）

## 🎛️ 控制調試級別

在 Inspector 中調整以下設置：

**InputHistoryDisplayIcon.tscn:**
- `Debug History Updates` = true/false （啟用/禁用詳細日誌）
- `Startup Logs` = true/false

**InputHistoryDebugger:**
- `Enabled` = true/false （啟用/禁用狀態檢查）
- `Check Interval Frames` = 30 （調整檢查頻率）

**world.gd:**
- `Startup Logs` = true （啟用世界啟動日誌）

## 🔧 下一步

收集以上日誌信息後，可以：
1. 確認是否有 `clear()` 被調用
2. 確認 `input_durations` 是否被清除
3. 追蹤具體是哪個位置導致問題
4. 定位並修復根本原因

所有調試信息將幫助確定問題的確切位置！
