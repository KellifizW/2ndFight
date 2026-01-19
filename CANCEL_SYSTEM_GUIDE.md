# 取消攻擊系統使用指南（純 Call Method Track）

## 📋 系統概述

這個系統使用 **Option 1 (純動畫軌道驅動)**：

- **所有設定都在動畫軌道中完成**
- **不需要修改 .tres 檔案**
- **直觀、簡單、視覺化**

---

## 🎯 已完成的程式碼修改

### Player.gd 新增功能
- `allowed_cancel_targets`：儲存當前允許的取消目標
- `_open_cancel_window(duration, allowed_moves)`：開啟取消窗口（由動畫軌道調用，**接受參數**）
- `_close_cancel_window()`：關閉取消窗口（由動畫軌道調用）
- 自動檢查輸入的招式是否在允許列表中

**方法簽名**：
```gdscript
func _open_cancel_window(duration: float, allowed_moves: Array = []) -> void
```

**參數說明**：
- `duration`：取消窗口持續時間（秒），例如 0.3
- `allowed_moves`：允許取消成的招式陣列，例如 ["powerkk", "fireball"]

---

## ✅ 下一步：在 Godot 編輯器中添加動畫軌道

### **步驟 1：開啟動畫編輯器**
1. 打開 Godot 專案
2. 開啟場景：`player1.tscn` 或 `characters/WOO.tscn`
3. 選擇根節點（Player）
4. 切換到底部的 **Animation 面板**

### **步驟 2：編輯 st_mp 動畫**
1. 在動畫列表中選擇 `st_mp`
2. 你會看到現有的軌道（Sprite frames, Hitbox, 等等）

### **步驟 3：新增 Call Method Track**
1. 點擊 **Add Track** 按鈕（軌道列表上方）
2. 選擇 **Call Method Track**
3. 選擇目標節點：`.` （當前的 Player 節點）
4. 新軌道會出現在列表底部

### **步驟 4：插入方法調用關鍵影格（重要！）**

#### **開啟取消窗口**：
1. 將時間軸移動到 **0.2 秒**（或你希望允許取消的時間點）
2. 點擊新增的 Call Method Track 上的 **Insert Key** 按鈕
3. 在彈出的視窗中：
   - **Method**: 選擇或輸入 `_open_cancel_window`
   - **Arguments**: **只需要一個參數**
     - **Arg 0** (Array): `["powerkk", "fireball"]` ← 允許的招式清單
       - Type: 選擇 `Array`
       - Size: `2`
       - Element 0 (String): `powerkk`
       - Element 1 (String): `fireball`
4. 點擊 **OK**

**⚠️ 重點**：不需要 duration 參數！取消窗口的結束時間由 `_close_cancel_window` 控制。

#### **關閉取消窗口（必須）**：
1. 將時間軸移動到 **0.5 秒**（取消窗口結束時間）
2. 插入關鍵影格
3. Method: `_close_cancel_window`
4. Arguments: 留空（此方法無參數）

### **視覺化範例**：
```
st_mp 動畫 (0.6 秒總長度):
├─ Track 0-4: Sprite、Hitbox、Hurtbox (現有)
├─ Track 5: Call Method Track (新增)
│   ├─ [0.2s] → _open_cancel_window(["powerkk", "fireball"])  # 開啟
│   └─ [0.5s] → _close_cancel_window()                        # 關閉
```

**取消窗口持續時間 = 0.5s - 0.2s = 0.3 秒**（由動畫軌道位置決定）

---

## 🎮 測試流程

### 1. **測試 st_mp → powerkk 取消**
1. 啟動遊戲
2. 使用 DAV 角色
3. 按 `st_mp` 攻擊
4. **在擊中對手後 0.2-0.5 秒內**，輸入 powerkk 指令（下、下前、前 + 拳）
5. 應該會看到：
   - st_mp 動畫被中斷
   - 立即執行 powerkk

### 2. **檢查控制台輸出**
成功的取消會顯示：
```
[Cancel] st_mp 開啟取消窗口: 0.30s, 允許目標: ["powerkk", "fireball"]
[Cancel] 取消 st_mp → powerkk
[Cancel] 取消窗口關閉
```

### 3. **測試限制**
嘗試在 st_mp 後使用 DP（昇龍拳）：
- ❌ **應該無法取消**（因為 DP 不在 st_mp_cancel_targets 中）
- st_mp 動畫會正常播放完畢

---

## 🔧 為其他招開啟動畫**
開啟 `player1.tscn`，選擇 `cr_mk` 動畫

#### 2. **添加 Call Method Track**
1. Add Track → Call Method Track → 選擇 `.` (Player 節點)
2. 在 **0.25 秒** 插入關鍵影格：
   - Method: `_open_cancel_window`
   - **Arg 0**: `0.2` ← 取消窗口持續 0.2 秒
   - **Arg 1**: `["dp", "fireball"]` ← 可以取消成 DP 或波動拳
3. （可選）在 **0.45 秒** 插入：
   - Method: `_close_cancel_window`

#### 3. **完成！**
現在 cr_mk 可以在 0.25-0.45 秒之間取消成 DP 或波動拳了。

### **常見設定範例**

#### **st_mk（DAV 角色）**：
```gdscript
[0.2s] → _open_cancel_window(0.3, ["powerkk", "dp", "fireball"])
```

#### **cr_mp（輕攻擊，只能取消成波動拳）**：
```gdscript
[0.15s] → _open_cancel_window(0.15, ["fireball"])
```

#### **st_mk（DEN 角色）**：
```gdscript
[0.25s] → _open_cancel_window(0.25, ["spnk", "hdk", "fireball"])
```)`
- `[0.45s]` → `_close_cancel_window()`

#### 3. **完成！**
現在 cr_mk 可以在 0.25-0.45 秒之間取消成 DP 了。

---

## 📊 角色專用設定範例

### **DAV 角色**：
```
st_mp → ["powerkk", "fireball"]  # 可以取消成兩種特殊招
cr_mk → ["dp", "fireball"]       # 下段踢可以取消成昇龍拳
```

### **DEN 角色**：
```
st_mk → ["spnk", "hdk", "fireball"]  # 可以取消成三種招式
cr_mp → ["fireball"]                 # 只能取消成波動拳
```

---

## ⚠️ 注意事項

### **動畫軌道時機點建議**：
- **開啟取消窗口**：在 Hitbox 激活後 1-2 幀（約 0.016-0.033 秒）
- **關閉取消窗口**：在動畫結束前 0.1 秒，或下一個動作開始時
❌ 問題 1：加了 Call Method Track 但無法取消**

**原因**：Call Method 沒有傳入參數！

**解決方法**：
1. 在動畫編輯器中，選中你的 `_open_cancel_window` 關鍵影格
2. 檢查右側 Inspector 面板的 **Arguments** 區域
3. 必須有兩個參數：
   - **Arg 0** (float): 例如 `0.3`
   - **Arg 1** (Array): 例如 `["powerkk", "fireball"]`
4. 如果是空的，點擊 **Arguments** 右側的 `+` 按鈕添加參數

**檢查方法**：
- 啟動遊戲後，控制台應該顯示：
  ```
  [Cancel] st_mp 開啟取消窗口: 0.30s, 允許目標: ["powerkk", "fireball"]
  ```
- 如果顯示 `0.00s, 允許目標: []`，表示參數沒有傳入

### **❌ 問題 2：控制台沒有任何 [Cancel] 訊息**
- Call Method Track 可能沒有正確指向 Player 節點
- 檢查軌道的目標路徑是否為 `.` (當前節點)
- 方法名稱拼寫是否正確：`_open_cancel_window`（以底線開頭）

### **❌ 問題 3：可以取消成不該允許的招式**
- 檢查 Call Method 中 **Arg 1** 的陣列內容
- 確認招式名稱拼寫正確（例如 `"powerkk"` 不是 `"power_kk"`）

### **❌ 問題 4：陣列參數格式錯誤**
在 Godot 編輯器中輸入陣列參數時：
- ✅ 正確：`["powerkk", "fireball"]`
- ❌ 錯誤：`"powerkk", "fireball"` (沒有方括號)
- ❌ 錯誤：`[powerkk, fireball]` (沒有引號)ndow()  # 第二次取消窗口（不同時機）
└─ [0.5s] → _close_cancel_window()
```

---

## 🐛 故障排除

### **問題 1：無法取消**
- 檢查控制台是否有 `[Cancel] 開啟取消窗口` 訊息
- 確認動畫軌道的時間點設定正確
- 確認 `allowed_cancel_targets` 包含你想使用的招式

### **問題 2：可以取消成不該允許的招式**
- 檢查 AttackData.tres 中的 `cancel_targets` 陣列
- 確認沒有多餘的招式名稱

### **問題 3：動畫軌道方法找不到**
- 確保方法名稱是 `_open_cancel_window`（以底線開頭）
- 檢查 Player.gd 中是否正確定義了這些方法

---

## 🎓 進階：自訂取消邏輯

### **只在擊中時允許取消（Hit Confirm Cancel）**
修改 `_on_hit_detected()`：
```gdscript
func _on_hit_detected(_target: String, _stun: float, is_blocked: bool, _was_in_stun: bool) -> void:
    # 只在成功擊中（非格擋）時開啟取消窗口
    if not is_blocked:
        _open_cancel_window()
```

然後在動畫中**移除** Call Method Track，改由擊中事件觸發。

---

## 📝 總結

✅ **已完成**：
- AttackData 擴展（取消窗口時長、允許目標）
- Player.gd 取消系統邏輯
- 通用的 `_open_cancel_window()` 和 `_close_cancel_window()` 方法

❌ **需要手動操作**：
- 在 Godot 編輯器中為每個攻擊動畫添加 Call Method Track
- 調整 .tres 檔案中的 cancel_targets 以平衡遊戲

💡 **優勢**：
- 不需要改程式碼就能調整取消規則
- 視覺化編輯取消時機點
- 支援每個角色、每個招式的獨立設定
