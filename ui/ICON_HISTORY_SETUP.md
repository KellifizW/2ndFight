# InputHistoryDisplayIcon 圖標版使用指南

## 功能說明

使用圖標資源替代文字的輸入歷史顯示：
- **arrow.png**: 方向箭頭（旋轉實現8個方向）
- **circle.png**: 圓圈（表示無方向輸入/NEUTRAL）⭐
- **punch.png**: 拳圖標（藍/黃/紅代表輕/中/重）
- **kick.png**: 腳圖標（藍/黃/紅代表輕/中/重）

**方向顯示邏輯** ⭐ 重要：
- 顯示**實際按鍵方向**，不根據角色面向反轉
- 按 `move_right` → 箭頭指向右 (→)
- 按 `move_left` → 箭頭指向左 (←)
- 玩家 1 面向右，按左鍵 → 顯示 ← (後退)
- 玩家 2 面向左，按右鍵 → 顯示 → (後退)
- **一致性**：兩個玩家按相同按鍵顯示相同方向

**招式檢測邏輯** ⭐ 重要：
- 內部使用**相對方向**進行招式檢測
- 面向右的角色：波動拳 = 下→下右→右+拳
- 面向左的角色：波動拳 = 下→下左→左+拳（自動轉換）
- **分離設計**：顯示用絕對方向，檢測用相對方向

## 視覺效果

```
3   [→圖標]  [🟡👊]         # 向前 + MP (黃色拳)
5   [↓圖標]  [🔵👊][🔵👢]   # 下 + LP+LK (藍色拳+腳，投技)
2   [↘圖標]  [🔴👊]         # 下前 + HP (紅色拳)
1   [○圖標]  [🟡👊][🟡👢]   # 無方向 + MP+MK (圓圈圖標) ⭐ 新功能
8   [↑圖標]  [🔵👢]         # 向上 + LK (跳躍輕腳)
99  [→圖標]  [🟡👊]         # 最多顯示 99 幀 ⭐
```

**顯示格式優化** ⭐：
- 幀數在最前面，一眼就能看到輸入持續時間
- 最多顯示 99 幀，不會有三位數的幀數
- 只顯示數字，不顯示 "f"，更簡潔明瞭

## 顏色映射

| 顏色 | 按鈕 | 用途 | RGB 值（用戶測試） |
|------|------|------|--------------------|
| 🔵 藍色 | LP, LK | 輕攻擊 (Light) | RGB(30, 100, 255) I:3.0 |
| 🟡 黃色 | MP, MK | 中攻擊 (Medium) | 不 modulate（圖標本身黃色） |
| 🔴 紅色 | HP, HK | 重攻擊 (Heavy) | RGB(255, 80, 160) I:1.0 |

## 方向旋轉角度

| 方向 | 旋轉角度 | InputManager 編碼 |
|------|----------|-------------------|
| → (FORWARD) | 0° | 3 |
| ↘ (DOWN_FORWARD) | 45° | 2 |
| ↓ (DOWN) | 90° | 1 |
| ↙ (DOWN_BACK) | 135° | 4 |
| ← (BACK) | 180° | 5 |
| ↖ (UP_BACK) | -135° | 8 |
| ↑ (UP) | -90° | 6 |
| ↗ (UP_FORWARD) | -45° | 7 |
| ○ (NEUTRAL) | 隱藏 | 0 |

## 使用步驟

### 方案一：替換現有的 InputHistoryDisplay

如果你想直接替換文字版本：

1. **備份原始腳本**（可選）
   ```
   重命名 InputHistoryDisplay.gd → InputHistoryDisplay_text.gd
   ```

2. **使用圖標版本**
   ```
   重命名 InputHistoryDisplayIcon.gd → InputHistoryDisplay.gd
   ```

3. **重新啟動 Godot**
   - 關閉編輯器
   - 重新打開項目
   - 場景中的 InputHistoryDisplay 會自動使用新腳本

### 方案二：創建新的圖標版場景（推薦）

保留文字版本，創建獨立的圖標版本：

1. **在 Godot 編輯器中創建新場景**
   - 右鍵 `ui/` 資料夾 → New Scene
   - 根節點選擇 `VBoxContainer`
   - 命名為 `InputHistoryDisplayIcon`

2. **附加腳本**
   - 選中 VBoxContainer 根節點
   - 在 Inspector 中 Attach Script
   - 選擇 `ui/InputHistoryDisplayIcon.gd`

3. **設置屬性**（在 Inspector 中）
   ```
   Max History Elements: 10
   Show Frame Count: true
   Track Player: "Player A"  (或 "Player B")
   ```

4. **保存場景**
   - 保存為 `ui/InputHistoryDisplayIcon.tscn`

5. **添加到 world.tscn**
   - 打開 `world.tscn`
   - 找到 `UI` 節點
   - 刪除或隱藏舊的 `P1InputHistory`/`P2InputHistory`
   - 實例化 `InputHistoryDisplayIcon.tscn` 兩次：
     - 節點名: `P1InputHistory` → Track Player: "Player A"
     - 節點名: `P2InputHistory` → Track Player: "Player B"

6. **調整位置**
   ```
   P1InputHistory (左側):
   - Position: X=20, Y=80
   - Size: X=240, Y=350
   
   P2InputHistory (右側):
   - Position: X=1440, Y=80
   - Size: X=240, Y=350
   ```

## 自定義顏色

如果你想調整顏色，編輯 `InputHistoryDisplayIcon.gd` 中的常數：

```gdscript
# 在第 18-20 行
# 根據用戶測試的值調整
const COLOR_LIGHT = Color(30.0/255.0 * 3.0, 100.0/255.0 * 3.0, 1.0 * 3.0)    # 藍色 - RGB(30,100,255) I:3.0
const COLOR_MEDIUM = Color(1.0, 1.0, 1.0)                                      # 黃色 - 不 modulate
const COLOR_HEAVY = Color(1.0, 80.0/255.0, 160.0/255.0)                        # 紅色 - RGB(255,80,160)
```

**顏色調整建議**：
- 更亮的藍色：`Color(0.3 * 4.0, 0.7 * 4.0, 1.0 * 4.0)` （增加強度乘數）
- 更深的紅色：`Color(1.0, 60.0/255.0, 120.0/255.0)`
- 如果 punch.png/kick.png 是白色而非黃色，可以改回 `Color(1.0, 1.0, 0.4)` 來上黃色

## 自定義圖標大小

編輯 `InputHistoryElement._init()` 中的大小：

```gdscript
# 方向圖標大小（第 33 行）
direction_icon.custom_minimum_size = Vector2(32, 32)  # 改為 40x40 或更大

# 按鈕圖標大小（第 110 行）
icon.custom_minimum_size = Vector2(28, 28)  # 改為 32x32 或更大

# 按鈕間距（第 39 行）
button_container.add_theme_constant_override("separation", 4)  # 改為 6 或 8
```

## 添加背景和邊框

為了讓圖標更突出，可以添加半透明背景：

1. **在場景中添加 Panel**
   - 選中 `InputHistoryDisplayIcon` (VBoxContainer)
   - 右鍵 → Add Child Node → `Panel`
   - 將 Panel 拖到 VBoxContainer 之上（作為父節點）

2. **設置 Panel 屬性**
   ```
   Self Modulate: (0, 0, 0, 0.7)  # 半透明黑色
   ```

3. **調整 VBoxContainer 為 Panel 的子節點**
   - 確保 VBoxContainer 是 Panel 的子節點
   - 設置 VBoxContainer 的 Anchors: Full Rect

## 測試效果

運行遊戲後，你應該看到：
- ✅ 彩色方向箭頭（隨輸入方向旋轉）
- ✅ 彩色按鈕圖標（藍/黃/紅代表輕/中/重）
- ✅ 多按鈕同時顯示（例如投技時顯示兩個圖標）
- ✅ 幀數顯示在右側

## 故障排除

### 問題：圖標不顯示或顯示白色方塊
**原因**：圖標路徑錯誤或資源未正確加載

**解決**：
1. 確認圖標路徑正確：
   ```gdscript
   const ARROW_PATH = "res://assets/ui/cmdbttn/arrow.png"
   const PUNCH_PATH = "res://assets/ui/cmdbttn/punch.png"
   const KICK_PATH = "res://assets/ui/cmdbttn/kick.png"
   ```

2. 在 Godot 編輯器中檢查圖標是否存在於 `assets/ui/cmdbttn/` 資料夾

3. 檢查 Console 是否有錯誤訊息：
   ```
   [InputHistoryDisplayIcon] 錯誤：無法加載圖標資源
   ```

### 問題：方向箭頭旋轉不正確
**原因**：arrow.png 的初始方向不是向右

**解決**：
- 如果 arrow.png 初始是向上，在 `_set_direction()` 函數中所有角度減 90°
- 如果 arrow.png 初始是向下，在 `_set_direction()` 函數中所有角度加 90°

### 問題：顏色看起來不明顯
**原因**：原始圖標本身有顏色，modulate 是乘法混合

**解決**：
1. 確保 punch.png 和 kick.png 是**純白色或淺灰色**圖標
2. 如果圖標是黃色，modulate 效果會被原色影響
3. 在 Photoshop/GIMP 中將圖標轉為灰度或白色

### 問題：同時按下多個按鈕時圖標重疊
**解決**：增加按鈕間距
```gdscript
button_container.add_theme_constant_override("separation", 8)  # 從 4 改為 8
```

## 進階功能

### 添加特殊招式高亮

當檢測到特殊招式（如波動拳）時，可以添加發光效果：

```gdscript
# 在 _set_buttons() 函數中添加
func _set_buttons_with_highlight(buttons: int, is_special_move: bool):
	# ... 原有代碼 ...
	
	if is_special_move:
		# 添加發光效果
		for icon in button_container.get_children():
			var glow = icon.duplicate()
			glow.modulate = Color(1, 1, 1, 0.5)
			glow.scale = Vector2(1.2, 1.2)
			button_container.add_child(glow)
```

### 顯示 Charge 狀態

顯示蓄力進度條（用於蓄力技）：

```gdscript
# 添加到 InputHistoryElement
var charge_bar: ProgressBar

func _init(...):
	# ... 原有代碼 ...
	charge_bar = ProgressBar.new()
	charge_bar.custom_minimum_size = Vector2(100, 8)
	container.add_child(charge_bar)

func set_charge(h_charge: int, v_charge: int):
	if abs(h_charge) > 30 or abs(v_charge) > 30:
		charge_bar.visible = true
		charge_bar.value = max(abs(h_charge), abs(v_charge))
	else:
		charge_bar.visible = false
```

## 對比：文字版 vs 圖標版

| 特性 | 文字版 | 圖標版 |
|------|--------|--------|
| 易讀性 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 視覺效果 | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| 性能 | 略快 | 略慢（需加載圖標）|
| 空間佔用 | 較小 | 較大 |
| 多語言支持 | 需翻譯 | 無需翻譯 |
| 開發難度 | 簡單 | 中等 |

**建議**：圖標版更適合最終發布版本，文字版適合開發調試。
