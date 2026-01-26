# InputHistoryDisplay 使用指南

> **注意**：此為舊版文字版本的文檔，已被 InputHistoryDisplayIcon（圖標版）取代。
> 建議使用圖標版：參見 [ICON_HISTORY_SETUP.md](ICON_HISTORY_SETUP.md) 和 [ICON_QUICK_START.md](ICON_QUICK_START.md)

## 功能說明（已棄用）
`InputHistoryDisplay.gd` 是文字版輸入歷史顯示組件（已被圖標版取代）。

**請使用新的圖標版本：**
- 📄 [InputHistoryDisplayIcon.gd](InputHistoryDisplayIcon.gd) - 圖標版主腳本
- 📖 [ICON_QUICK_START.md](ICON_QUICK_START.md) - 5分鐘快速設置
- 📖 [ICON_HISTORY_SETUP.md](ICON_HISTORY_SETUP.md) - 詳細使用指南

---

## 舊版使用步驟（已棄用）

### 1. 創建 UI 場景

在 Godot 編輯器中：

1. **創建新場景**
   - 右鍵 `ui/` 資料夾 → New Scene
   - 根節點選擇 `VBoxContainer`
   - 命名為 `InputHistoryDisplay`

2. **添加腳本**
   - 選中 VBoxContainer 根節點
   - 在 Inspector 中 Attach Script
   - 選擇已存在的 `ui/InputHistoryDisplay.gd`

3. **設置屬性**（在 Inspector 中）
   ```
   Max History Elements: 10 (顯示最近 10 個輸入)
   Show Frame Count: true (顯示幀數)
   ```

4. **保存場景**
   - 保存為 `ui/InputHistoryDisplay.tscn`

### 2. 添加到 World 場景

打開 `world.tscn`:

1. **實例化 InputHistoryDisplay**
   - 在場景樹中找到 `UI` 節點
   - 右鍵 → Instantiate Child Scene
   - 選擇 `ui/InputHistoryDisplay.tscn`
   - 命名為 `P1InputHistory` (玩家 1) 或 `P2InputHistory` (玩家 2)

2. **設置位置和追蹤玩家**（在 Inspector 中）
   
   **玩家 1 輸入歷史（左側）：**
   ```
   Node Name: P1InputHistory
   Position: X=50, Y=100
   Size: X=200, Y=300
   Track Player: "Player A"  ← 重要！在 Inspector 中選擇
   Max History Elements: 10
   Show Frame Count: true
   ```
   
   **玩家 2 輸入歷史（右側）：**
   ```
   Node Name: P2InputHistory
   Position: X=1430, Y=100
   Size: X=200, Y=300
   Track Player: "Player B"  ← 重要！在 Inspector 中選擇
   Max History Elements: 10
   Show Frame Count: true
   ```

3. **完成！**
   - 不需要在 world.gd 中添加任何代碼
   - 系統會自動在運行時連接到對應的玩家
   - 如果看不到輸入顯示，檢查 Console 是否有錯誤訊息

### 3. 樣式優化（可選）

如果你想要更好的視覺效果，可以添加背景和邊框：

1. **添加 Panel 背景**
   - 選中 `InputHistoryDisplay` 節點
   - 右鍵 → Add Child Node → `Panel`
   - 將 Panel 移到最上方（拖動到 VBoxContainer 之前）
   - 設置 Panel 屬性：
     ```
     Self Modulate: (0, 0, 0, 0.7) # 半透明黑色
     ```

2. **添加標題**
   - 在 VBoxContainer 內添加 `Label` 子節點
   - 命名為 "TitleLabel"
   - Text: "INPUT HISTORY"
   - Horizontal Alignment: Center

### 4. 測試

運行遊戲後，你應該能看到：
- 最新輸入在頂部
- 每個輸入顯示：方向符號（↓↘→等）+ 按鈕名稱（LP/MP/HP等）+ 持續幀數（例如 "15f"）
- 舊輸入會自動向下滾動

## 顯示格式說明

```
幀  方向  按鈕      
----  ----  --------  
3     →     MP        # 向前按住 MP，持續 3 幀
12    ↓     -         # 蹲下，持續 12 幀
2     ↘     LP        # 斜下前+LP，持續 2 幀
5     ○     LP+LK     # 同時按 LP 和 LK，持續 5 幀 ⭐ 新功能
1     ←     HP+HK     # 同時按 HP 和 HK
99    →     MP        # 最多顯示 99 幀 ⭐ 新功能
```

**多按鈕同時顯示**：系統現在支援同時按下多個按鈕的顯示！
- 例如：`LP+LK` 表示同時按下 LP 和 LK（投技）
- 例如：`MP+MK` 表示同時按下 MP 和 MK
- 最多可顯示 6 個按鈕組合（如 `LP+MP+HP+LK+MK+HK`）

**幀數顯示優化** ⭐ 新功能：
- 幀數顯示在最前面，編排更緊淊
- 最多顯示 99 幀，避免長時間持續輸入的數字過大
- 只顯示數字，不顯示 "f" 後綴，更簡潔

方向符號對應：
- `○` = 中立 (NEUTRAL)
- `↓` = 下 (DOWN)
- `↘` = 下前 (DOWN_FORWARD)
- `→` = 前 (FORWARD)
- `↙` = 下後 (DOWN_BACK)
- `←` = 後 (BACK)
- `↑` = 上 (UP) ⭐ 新功能
- `↗` = 上前 (UP_FORWARD) ⭐ 新功能
- `↖` = 上後 (UP_BACK) ⭐ 新功能

按鈕對應：
- `LP` = 輕拳 (Light Punch)
- `MP` = 中拳 (Medium Punch)
- `HP` = 重拳 (Heavy Punch)
- `LK` = 輕腳 (Light Kick)
- `MK` = 中腳 (Medium Kick)
- `HK` = 重腳 (Heavy Kick)

## 進階設置

### 自定義顯示數量

在 Inspector 中修改 `Max History Elements` 來改變顯示的輸入數量（預設 10）。

### 隱藏幀數

如果不想顯示幀數，將 `Show Frame Count` 設為 `false`。

### 動態切換追蹤玩家

在運行時切換追蹤的玩家：

\`\`\`gdscript
# 在任何腳本中
var input_display = $UI/P1InputHistory
input_display.set_player(new_player)
\`\`\`

### 清空顯示

\`\`\`gdscript
var input_display = $UI/P1InputHistory
input_display.clear()  # 清空所有輸入歷史顯示
\`\`\`

## 故障排除

### 問題：顯示空白或沒有符號
**可能原因和解決方法**：

1. **未設置 Track Player**
   - 檢查 Inspector 中的 `Track Player` 是否設為 "Player A" 或 "Player B"
   - 確保節點名稱正確（P1InputHistory 追蹤 Player A，P2InputHistory 追蹤 Player B）

2. **InputManager 未正確初始化**
   - 檢查 Console 是否有 "[InputHistoryDisplay] 成功連接" 的訊息
   - 如果看到 "找不到 InputManager"，檢查玩家場景是否有 InputManager 子節點

3. **字體太小看不見**
   - 已更新代碼增加字體大小到 16
   - 如果還是看不到，嘗試添加白色背景 Panel

4. **玩家還未生成**
   - 確保在選角畫面選擇了角色後再進入遊戲
   - 或在 world.tscn 的 Inspector 中手動指派角色資源

### 問題：輸入不更新
**解決**：檢查 InputManager 的 `insert_to_history()` 是否在 `update_input()` 中被調用。

### 問題：方向/按鈕顯示錯誤
**解決**：檢查 `raw_input` 的編碼格式是否正確（高 8 位=方向，低 8 位=按鈕）。

### 調試步驟

1. **檢查連接狀態**
   - 運行遊戲後查看 Console
   - 應該看到：`[InputHistoryDisplay] 成功連接到 PlayerA 的 InputManager`

2. **測試輸入**
   - 按方向鍵或攻擊按鈕
   - 輸入歷史應該立即顯示

3. **檢查 InputManager**
   ```gdscript
   # 在 Player 場景中確認有 InputManager 節點
   # 並且在 player.gd 的 _physics_process 中調用：
   if has_node("InputManager"):
       $InputManager.update_input()
   ```

## 未來擴展

可以添加的功能：
- [ ] 彩色按鈕圖示（用 Sprite2D 替代 Label）
- [ ] 特殊招式檢測標記（在檢測到波動拳時高亮顯示）
- [ ] 輸入準確度評分（顯示指令執行的精確度）
- [ ] 錄製/回放功能
