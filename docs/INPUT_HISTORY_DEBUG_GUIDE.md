# 輸入歷史顯示異常清除 - 診斷指南

## 🔍 問題症狀
- 按摔投時，輸入歷史顯示會被清空
- 其他場景可能也會異常清除

## 📋 已添加的調試工具

### 1. InputHistoryDisplayIcon.gd 內的調試日誌
- **clear() 方法**：現在會打印完整的堆棧跟蹤，顯示誰在調用此方法
- **update_history_display()**：每30幀打印一次狀態
- **_process()**：監控 input_durations 陣列的變化

### 2. InputManager.gd 內的調試日誌
- **insert_to_history()**：追蹤輸入狀態變更

### 3. ThrowHandler.gd 內的調試日誌
- **lock_opponent_state()**：當清除對手輸入緩衝時打印日誌

### 4. InputHistoryDebugger.gd（新工具）
自動監控輸入歷史顯示的完整狀態

## 🚀 使用步驟

### 步驟 1：添加 InputHistoryDebugger 到場景
1. 在 world.tscn 中任選一個位置（如 World 節點下）
2. 添加新 Node 或編輯 world.gd 的 _ready()
3. 創建 InputHistoryDebugger 實例：

```gdscript
# 在 world.gd 中
func _ready():
    var debugger = preload("res://scripts/debug/InputHistoryDebugger.gd").new()
    add_child(debugger)
```

或者直接將 InputHistoryDebugger.gd 綁定到 world 場景的任何節點

### 步驟 2：運行遊戲並執行摔投
1. 啟動遊戲
2. 執行摔投操作（按 LP+LK）
3. 觀察控制台輸出

## 📊 預期輸出分析

### 正常情況（輸入歷史保留）
```
[InputHistoryDebugger] Status Check @ Frame 1200
[P1] Display Elements: 5/15 visible
     InputManager history: 8/240 non-zero
     input_durations set: 5 entries
     Tracking: P1
```

### 異常情況（輸入歷史被清除）
```
[InputHistoryDebugger] Status Check @ Frame 1200
[P1] Display Elements: 0/15 visible        ← 🔴 沒有可見項
     InputManager history: 8/240 non-zero  
     input_durations set: 0 entries         ← 🔴 input_durations 被清除!
     Tracking: P1
     🔴 [PROBLEM] No visible elements but input history has data!
            → input_durations array likely cleared or not populated
```

## 🔎 問題定位流程

### 如果看到 clear() 被調用的堆棧：
```
[☠️ CLEAR() CALLED - BUG FOUND! ☠️]
=== 調用堆棧跟蹤 ===
at: InputHistoryDisplayIcon.gd:287 in clear()
at: [你的代碼位置]  ← 這裡會顯示誰在調用 clear()
```

→ 這意味著有某個腳本在呼叫 clear()，即使我們禁用了它。
→ 檢查該位置的調用代碼並移除或修改。

### 如果 input_durations 陣列為空但輸入歷史仍有數據：
```
🔴 [PROBLEM] No visible elements but input history has data!
       → input_durations array likely cleared or not populated
```

→ 問題是 input_durations 沒有被正確填充
→ 檢查 _process() 或 update_history_display() 的邏輯
→ 查看是否有地方在修改 input_durations

## 📝 快速檢查清單

- [ ] 運行遊戲，在控制台查看是否有 `clear()` 被調用的消息
- [ ] 執行摔投並觀察輸入歷史是否消失
- [ ] 檢查 InputHistoryDebugger 的輸出
- [ ] 查看 input_durations 是否被清除

## 🔧 常見問題

### Q: 為什麼 input_durations 陣列為 0？
A: 可能是：
1. 從未執行過 _process() → 檢查 InputHistoryDisplayIcon 是否在場景中
2. InputManager 沒有記錄輸入 → 檢查 InputManager._physics_process()
3. 數組被某處清除 → 搜索 `input_durations.clear()` 或 `resize(0)`

### Q: 摔投時為什麼輸入歷史消失？
A: 很可能是：
1. ThrowHandler 調用了某個清除方法
2. input_durations 在摔投時被重置
3. update_history_display() 的可見性邏輯有問題

## 📞 收集信息
當報告問題時，請提供：
1. 控制台中 `clear()` 的完整堆棧跟蹤（如果出現）
2. InputHistoryDebugger 的狀態輸出（摔投前後）
3. 是否看到 `input_durations` 為空的警告
