# 圖標版輸入歷史 - 快速測試指南

## 最快設置方法（5 分鐘）

### 步驟 1: 驗證圖標資源 ✅

確認以下檔案存在：
- `assets/ui/cmdbttn/arrow.png` - 向右箭頭
- `assets/ui/cmdbttn/circle.png` - 圓圈圖標（無方向輸入）⭐ 新增
- `assets/ui/cmdbttn/punch.png` - 拳頭圖標（黃色）
- `assets/ui/cmdbttn/kick.png` - 腳圖標（黃色）

> **重要**：punch.png 和 kick.png 應該是黃色的（不需要 modulate）。系統會自動調整為藍色（輕）和紅色（重）。

### 步驟 2: 在 Godot 中創建場景

1. **打開 Godot 編輯器**

2. **創建新場景**
   - 點擊 Scene → New Scene
   - 選擇 `Other Node` → 搜尋 `VBoxContainer`
   - 點擊 Create

3. **附加腳本**
   - 選中 VBoxContainer 節點
   - 右側 Inspector → Script → 點擊 📄 圖標
   - 選擇 `Load` → 找到 `ui/InputHistoryDisplayIcon.gd`
   - 點擊 Open

4. **設置參數**（在 Inspector 中）
   ```
   ✅ Max History Elements: 10
   ✅ Show Frame Count: true
   ✅ Track Player: "Player A"
   ```

5. **保存場景**
   - 按 `Ctrl+S`
   - 保存路徑: `ui/InputHistoryDisplayIcon.tscn`
   - 節點名稱: `InputHistoryDisplayIcon`

### 步驟 3: 添加到 world.tscn

1. **打開 world.tscn**
   - 在 FileSystem 中雙擊 `world.tscn`

2. **找到 UI 節點**
   - 在場景樹中找到 `UI` 節點

3. **實例化圖標版輸入歷史**
   - 右鍵 `UI` → Instantiate Child Scene
   - 選擇 `ui/InputHistoryDisplayIcon.tscn`
   - 重命名為 `P1InputHistoryIcon`

4. **設置位置**（在 Inspector 中）
   ```
   Layout → Position:
     X: 20
     Y: 80
   
   Layout → Size:
     X: 240
     Y: 350
   ```

5. **確認追蹤玩家**
   ```
   Script Variables → Track Player: "Player A"
   ```

6. **（可選）為玩家 2 重複步驟 3-5**
   - 節點名: `P2InputHistoryIcon`
   - Position: X=1440, Y=80
   - Track Player: "Player B"

7. **保存場景** (`Ctrl+S`)

### 步驟 4: 測試

1. **運行遊戲** (F5)

2. **測試輸入**
   - 按方向鍵：應該看到箭頭旋轉
   - 按攻擊鍵：
     - LP (J/Numpad4) → 藍色拳頭
     - MP (K/Numpad5) → 黃色拳頭
     - HP (L/Numpad6) → 紅色拳頭
     - LK (U/Numpad7) → 藍色腳
     - MK (I/Numpad8) → 黃色腳
     - HK (O/Numpad9) → 紅色腳

3. **測試多按鈕**
   - 同時按 J+U (LP+LK) → 應顯示兩個藍色圖標（拳+腳）

## 預期效果示意圖

```
╔════════════════════════════════════╗
║  輸入歷史（圖標版）                  ║
╠════════════════════════════════════╣
║  3   →   🟡👊                      ║  ← 幀數在最前 ⭐
║  5   ↓   🔵👊 🔵👢                ║  ← 下 + 輕拳+輕腳（投技）
║  2   ↘   🔴👊                      ║  ← 斜下前 + 重拳（波動拳起手）
║  1   ○   🟡👊 🟡👢                ║  ← 無方向 + 中拳+中腳
║  99  ←   🔴👢                      ║  ← 最多 99 幀 ⭐
╚════════════════════════════════════╝
```

**新特性** ⭐：
- 幀數在最前面，更易讀
- 最多顯示 99 幀（不顯示 100+）
- 只顯示數字，不顯示 "f" 後綴
- **方向顯示實際按鍵**：按右鍵永遠顯示 →，按左鍵永遠顯示 ←（不隨角色面向反轉）

## 方向顯示邏輯說明 ⭐

**重要變更**：輸入歷史現在顯示**實際按鍵方向**，不再根據角色面向反轉！

### 示例對比：

**玩家 1（面向右）：**
- 按 `D` (move_right) → 顯示 → (前進)
- 按 `A` (move_left) → 顯示 ← (後退)

**玩家 2（面向左）：**
- 按 `→` (move_right) → 顯示 → (後退)
- 按 `←` (move_left) → 顯示 ← (前進)

**優點**：
- ✅ 兩個玩家按相同鍵顯示相同方向
- ✅ 更直觀，容易理解實際按了什麼鍵
- ✅ 適合教學和訓練模式
- ✅ 招式檢測仍使用相對方向（自動轉換）

### 招式檢測說明：

雖然輸入歷史顯示絕對方向，但招式檢測會自動轉換為相對方向：

**玩家 1（面向右）波動拳：**
- 實際按鍵：S → S+D → D+K
- 顯示：↓ → ↘ → → 🟡👊
- 檢測：下 → 下前 → 前+拳 ✅

**玩家 2（面向左）波動拳：**
- 實際按鍵：↓ → ↓+← → ←+Numpad5
- 顯示：↓ → ↙ → ← 🟡👊
- 檢測：下 → 下前 → 前+拳 ✅（自動轉換）

兩個玩家都能用各自的方向鍵出波動拳！

## 常見問題快速修復

### ❌ 圖標不顯示
**檢查**：Console 是否有錯誤？
```
[InputHistoryDisplayIcon] 錯誤：無法加載圖標資源
```

**解決**：
1. 檢查圖標路徑是否正確
2. 在 FileSystem 中確認檔案存在
3. 嘗試重新導入圖標（右鍵 → Reimport）

### ❌ 所有圖標都是白色
**原因**：圖標本身就是白色，modulate 無效果

**解決**：
- 方案 A：在 Photoshop/GIMP 中將圖標改為灰色（RGB: 200, 200, 200）
- 方案 B：調整 modulate 顏色為更飽和的顏色

### ❌ 箭頭旋轉後位置錯位
**原因**：舊版本未設置旋轉中心點

**已修復**：✅ 現在使用 `pivot_offset = Vector2(16, 16)` 讓箭頭圍繞中心旋轉，所有方向都對齊在同一行。

### ❌ 圓圈圖標不顯示
**檢查**：確認 `assets/ui/cmdbttn/circle.png` 存在

**解決**：
1. 檢查圖標路徑是否正確
2. 如果沒有 circle.png，可以自己創建一個 32x32 的圓圈圖標
3. Console 會顯示加載狀態：`arrow: true, circle: true, punch: true, kick: true`

### ❌ 按鈕圖標太小看不清
**解決**：
在 `InputHistoryDisplayIcon.gd` 第 110 行，增加圖標大小：
```gdscript
icon.custom_minimum_size = Vector2(36, 36)  # 從 28 改為 36
```

### ❌ 多個按鈕重疊
**解決**：
在第 39 行增加間距：
```gdscript
button_container.add_theme_constant_override("separation", 8)  # 從 4 改為 8
```

## 下一步優化

測試成功後，可以考慮：

1. **添加半透明背景**
   - 在場景中添加 Panel 節點作為背景
   - 設置 Self Modulate: (0, 0, 0, 0.7)

2. **調整顏色**
   - 編輯 `COLOR_LIGHT`, `COLOR_MEDIUM`, `COLOR_HEAVY` 常數
   - 選擇更符合遊戲風格的配色

3. **添加標題**
   - 在 VBoxContainer 上方添加 Label 節點
   - Text: "INPUT HISTORY"

4. **隱藏文字版**
   - 在 world.tscn 中隱藏或刪除舊的 `P1InputHistory` (文字版)

## 效能注意事項

- 圖標版比文字版稍慢（需要渲染多個 TextureRect）
- 建議每個玩家最多顯示 10 個歷史輸入
- 如果出現卡頓，減少 `max_history_elements` 到 8 或 6

## 完成檢查清單

- [ ] 圖標資源已確認存在
- [ ] InputHistoryDisplayIcon.tscn 已創建
- [ ] 已添加到 world.tscn 並設置位置
- [ ] Track Player 已正確設置
- [ ] 運行遊戲，能看到彩色圖標
- [ ] 方向箭頭旋轉正確
- [ ] 按鈕顏色正確（藍/黃/紅）
- [ ] 多按鈕同時顯示正常

---

**祝測試順利！** 🎮
如果遇到問題，請查看詳細的 [ICON_HISTORY_SETUP.md](ICON_HISTORY_SETUP.md)。
