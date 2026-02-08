# ThrowHandler 動畫事件配置指南

## 概述

ThrowHandler 系統已實現並整合完成。本文檔說明如何在 Godot 編輯器中為每個角色的摔投動畫添加必要的 Call Method 事件。

---

## 系統架構回顧

### 摔投流程

```
1. Player presses st_lp + st_lk (throw input)
   ↓
2. AttackExecutor triggers throw_enter animation
   ↓
3. STARTUP phase: _check_throw_hit() loops (calls throw_handler.check_grab_collision())
   ↓
4. Frame ~5: Collision detected → throw_handler.lock_opponent() called
   ↓
5. GRAB → HOLD phase: opponent position locked (throw_handler.update_opponent_position())
   ↓
6. throw_seq animation starts
   ↓
7. Frame ~1: [ANIMATION EVENT] on_animation_start_hold() (optional)
   ↓
8. Frame ~29: [ANIMATION EVENT] on_animation_release()
   ↓
9. EXECUTE phase: opponent launched with velocity (throw_handler.release_opponent())
   ↓
10. RECOVERY: throw completes, both players return to normal state
```

---

## 需要添加的動畫事件

每個角色需要為 **2 個動畫** 添加事件：

### 1. `throw_enter` 動畫（可選）
- **目的**: 檢查並抓取對手（目前自動由 _check_throw_hit() 處理）
- **事件**: 無（目前實現中通過每幀檢查，不需要事件）

### 2. `throw_seq` 動畫（必需）

#### 事件 A: 開始持有階段（可選，用於除錯）
- **幀數**: Frame 1
- **軌道類型**: Call Method Track
- **目標節點**: Player (self)
- **方法名**: `throw_handler.on_animation_start_hold`
- **參數**: 無

#### 事件 B: 釋放對手（必需）
- **幀數**: Frame 29（或接近動畫結束的幀，根據角色調整）
- **軌道類型**: Call Method Track
- **目標節點**: Player (self)
- **方法名**: `throw_handler.on_animation_release`
- **參數**: 無

---

## 在 Godot 編輯器中添加事件（詳細步驟）

### Step 1: 打開角色場景

1. 在 Godot 編輯器中打開角色場景：
   - `characters/player1.tscn`（Player A）
   - `characters/player2.tscn`（Player B）

2. 選中角色根節點（通常是 `Player` 或 `CharacterBody2D`）

3. 在底部打開 **Animation** 面板

### Step 2: 選擇 throw_seq 動畫

1. 在 Animation 面板的動畫選擇器中選擇 `throw_seq`

2. 確認動畫長度（例如 40 幀 @60FPS）

### Step 3: 添加 Call Method Track（如果沒有）

1. 點擊 **Add Track** 按鈕（在軌道列表上方）

2. 選擇 **Call Method Track**

3. 在彈出的節點選擇器中選擇 **Player 自身**（通常是根節點 `.`）

4. 確認創建軌道

### Step 4: 添加釋放事件（Frame 29）

1. 將時間軸拖動到 **Frame 29**（或接近結束的幀，如 Frame 35/40）
   - **重要**: 釋放幀應該在動畫接近結束時觸發，確保對手已經完成完整的摔投動作

2. 右鍵點擊 Call Method Track → **Insert Key**

3. 在彈出的 **Method Selector** 中：
   - 在 **Method** 欄位輸入：`throw_handler.on_animation_release`
   - 或在列表中找到 `throw_handler` → `on_animation_release`

4. 點擊 **OK** 確認

5. 驗證事件：
   - 時間軸上應該出現一個 **鑽石形標記**
   - 點擊標記，右側 Inspector 應顯示方法名稱

### Step 5: 添加開始持有事件（可選，Frame 1）

1. 將時間軸拖動到 **Frame 1**

2. 在同一個 Call Method Track 上右鍵 → **Insert Key**

3. 方法名：`throw_handler.on_animation_start_hold`

4. 確認

### Step 6: 保存場景

1. 按 **Ctrl+S** 或 File → Save Scene

2. 重複 Step 1-6 為另一個角色（Player B）配置

---

## 配置參數調整（可選）

### 調整釋放時機

如果摔投動畫的節奏與預設不符，可以調整釋放幀：

1. 播放 `throw_seq` 動畫（預覽模式）

2. 觀察何時應該"拋出"對手（視覺上最適合的時機）

3. 記錄該幀數（例如 Frame 25、Frame 32）

4. 移動 `on_animation_release` 事件到該幀

### 調整 ThrowData 參數

在 Inspector 中選擇角色，找到 **Throw Data** 資源：

1. **Pivot Offset X/Y**: 對手在摔投期間的相對位置
   - `pivot_offset_x: 50.0` → 對手在攻擊者右側 50 像素
   - `pivot_offset_y: -30.0` → 對手在攻擊者上方 30 像素

2. **Escape Window End Frame**: 逃脫窗口關閉幀數
   - 預設 `15`（@60FPS）= 0.25 秒

3. **Escape Mash Threshold**: 逃脫所需按鍵次數
   - 預設 `8`（在 15 幀內按 8 次任意按鍵）

---

## 測試清單

添加事件後，在遊戲中測試：

### 基本測試
- [ ] 按下 J+K（st_lp+st_lk）觸發 `throw_enter` 動畫
- [ ] 靠近對手時成功抓取（進入 `throw_seq`）
- [ ] 對手位置鎖定在攻擊者旁邊（不下降、不移動）
- [ ] `throw_seq` 動畫播放完成後對手被拋出
- [ ] 對手飛出軌跡符合預期（拋物線）
- [ ] 傷害正確應用（檢查 Healthbar）

### 進階測試
- [ ] 逃脫機制：在抓取後快速連按 8 次任意鍵
  - 對手應該在 15 幀內逃脫
  - 雙方進入短暫硬直
  - 對手未受傷害
- [ ] 雙方 facing_direction 正確（朝向對手）
- [ ] 座位系統：Player A 和 Player B 都能執行摔投
- [ ] 釋放時機：對手在正確的幀被拋出（視覺檢查）

### 除錯工具
- [ ] 開啟 ThrowHandler 的 `debug_enabled = true`（預設已開啟）
- [ ] 查看控制台輸出：
  ```
  [ThrowHandler] Throw initiated - entering STARTUP phase
  [ThrowHandler] Valid throw target found: PlayerB
  [ThrowHandler] Opponent locked: PlayerB | pivot_offset: (50000, -30000)
  [ThrowHandler] Position locked | attacker: (100000, 200000) | opponent: (150000, 170000)
  [ThrowHandler] Opponent released | damage: 8.0 | hitstun: 72 physics frames
  ```

---

## 常見問題排查

### 問題 1: 對手沒有被鎖定位置（仍然掉落）

**原因**: `on_animation_release` 事件過早觸發或未觸發

**解決**:
1. 檢查 `throw_seq` 動畫的 Call Method Track 是否存在
2. 確認事件幀數在動畫長度範圍內（例如 Frame 29 < 動畫總長 40）
3. 檢查方法名拼寫：`throw_handler.on_animation_release`

### 問題 2: 對手立即被拋出，沒有持有階段

**原因**: `throw_handler.lock_opponent()` 未被呼叫

**解決**:
1. 確認 `_check_throw_hit()` 正確檢測碰撞
2. 檢查 ThrowBox 是否啟用（`monitoring = true`, `monitorable = true`）
3. 檢查對手的 ThrowBox/ThrowHurt 是否存在

### 問題 3: 控制台出現 "ThrowHandler not found" 錯誤

**原因**: ThrowHandler 未正確初始化

**解決**:
1. 確認 `Player._initialize_handlers()` 包含 ThrowHandler 初始化代碼
2. 檢查 `player.gd` 的 `@onready var throw_handler: ThrowHandler = null` 是否存在
3. 重新編譯場景（關閉並重新打開）

### 問題 4: 逃脫機制不工作

**原因**: 輸入緩衝計數錯誤或窗口已關閉

**解決**:
1. 在抓取後**立即**開始連打（不要等動畫播放）
2. 嘗試增加 `escape_window_end_frame`（例如從 15 改為 20）
3. 降低 `escape_mash_threshold`（例如從 8 改為 6）
4. 檢查控制台是否輸出 `[ThrowHandler] Escape window started`

---

## AnimationPlayer 事件架構圖

```
throw_seq Timeline (40 frames @60FPS)
├─ Frame 0: Animation starts
├─ Frame 1: [EVENT] on_animation_start_hold() (optional)
│            → ThrowHandler enters HOLD phase
│            → Position locking begins
├─ Frame 2-28: HOLD phase active
│              → update_opponent_position() called every frame
│              → Opponent synced to pivot_offset
├─ Frame 29: [EVENT] on_animation_release() ⚠️ CRITICAL
│             → ThrowHandler enters EXECUTE phase
│             → Opponent velocity applied
│             → Damage and hitstun applied
└─ Frame 40: Animation completes
             → ThrowHandler enters RECOVERY phase
             → State reset
```

---

## 多段摔投擴展（未來功能）

如果需要實現多段摔投（例如：抓取 → 膝撞 → 拋出），可以添加多個 `on_animation_release` 事件：

```gdscript
# throw_seq 動畫
Frame 10: [EVENT] throw_handler.on_animation_release()  # 第一段（膝撞）
Frame 29: [EVENT] throw_handler.on_animation_release()  # 第二段（拋出）
```

配合 `ThrowData.is_multi_hit = true` 和 `release_phases` 數組。

---

## 參考

- **ThrowHandler.gd**: 摔投邏輯核心實現
- **ThrowData.gd**: 摔投參數資源定義
- **GUIDES/ThrowSystem_GDScript_Tutorial.md**: Sakuga Engine 架構參考
- **THROW_SYSTEM_TEST.md**: 現有摔投系統測試記錄

---

**更新日期**: 2026-02-08  
**版本**: v1.0 - ThrowHandler Integration
