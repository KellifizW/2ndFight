# InputHistoryDisplay 快速設置（1 分鐘完成）

## 步驟 1：在 Godot 編輯器中

1. **打開 world.tscn**
2. **找到 UI 節點**（在場景樹中）
3. **右鍵 UI → Instantiate Child Scene**
4. **選擇 `ui/InputHistoryDisplay.tscn`**（建立兩次，一個給 P1，一個給 P2）

## 步驟 2：設置第一個（玩家 1）

選中剛添加的 InputHistoryDisplay 節點：

1. **改名為** `P1InputHistory`
2. **在 Inspector 中設置**：
   ```
   Layout → Position: X=50, Y=100
   Layout → Size: X=200, Y=300
   
   Script Variables:
   └─ Track Player: "Player A"  ← 下拉選單選擇
   └─ Max History Elements: 10
   └─ Show Frame Count: ✓
   ```

## 步驟 3：設置第二個（玩家 2）

重複步驟 2，添加第二個 InputHistoryDisplay：

1. **改名為** `P2InputHistory`
2. **在 Inspector 中設置**：
   ```
   Layout → Position: X=1430, Y=100  ← 右側
   Layout → Size: X=200, Y=300
   
   Script Variables:
   └─ Track Player: "Player B"  ← 下拉選單選擇
   └─ Max History Elements: 10
   └─ Show Frame Count: ✓
   ```

## 步驟 4：保存並測試

1. **保存場景** (Ctrl+S)
2. **運行遊戲** (F5)
3. **按方向鍵或攻擊鍵**
4. **應該看到輸入歷史顯示**：
   ```
   ○  -   5f
   →  MP  3f
   ↓  -   12f
   ```

## 如果看不到輸入歷史

### 檢查清單：

- [ ] 確認 `Track Player` 設置正確（P1InputHistory = "Player A"，P2InputHistory = "Player B"）
- [ ] 檢查 Console 是否有錯誤訊息
- [ ] 確認玩家場景中有 `InputManager` 子節點
- [ ] 嘗試調整位置（可能在螢幕外）

### Console 應該顯示：
```
[InputHistoryDisplay] 成功連接到 PlayerA 的 InputManager
[InputHistoryDisplay] 成功連接到 PlayerB 的 InputManager
```

如果看到這些訊息但還是沒有顯示，檢查：
1. 字體顏色是否與背景衝突（添加 Panel 背景）
2. Size 是否太小（設為至少 200x300）

## 可選：添加背景

讓輸入歷史更易見：

1. **選中 P1InputHistory**
2. **右鍵 → Add Child Node → Panel**
3. **拖動 Panel 到 VBoxContainer 之前**（讓它在最底層）
4. **設置 Panel**：
   ```
   Layout → Anchors Preset: Full Rect
   Theme Overrides → Styles → Panel: [新建 StyleBoxFlat]
     └─ Bg Color: 黑色 (0, 0, 0, 0.8)
     └─ Border Width: 2
     └─ Border Color: 白色
   ```
5. **對 P2InputHistory 重複相同步驟**

完成！現在你有專業的輸入歷史顯示了。
