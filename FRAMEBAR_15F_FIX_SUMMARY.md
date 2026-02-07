# FrameBar 15F Bug 修復報告

## 問題總結
- **現象**：DEN 角色的 `st_lp` 攻擊在未擊中時顯示 14F（正常），但擊中對手後變成 15F（異常）
- **根本原因**：動畫完成信號與 `attack_duration_timer` 遞減的時機不同步，導致 `display_frame_counter` 超計數

## 修復方案（已實施）

### 1. Player.gd 修復（主要修復）

**位置**：`player.gd` line 460-490 `_on_animation_player_finished()`

**修改內容**：
```gdscript
# 🟢 【FIX】攻擊動畫完成時，立即停止計時器以防止額外幀計數
if (anim_name in GROUND_ATTACK_ANIMS or anim_name in AIR_ATTACK_ANIMS) and is_attacking and attack_duration_timer > 0:
    print("[ATTACK ANIM FINISH] Stopping attack_duration_timer early | remaining: %d frames → 0" % attack_duration_timer)
    attack_duration_timer = 0  # 🟢 立即停止，防止 display_frame_counter 超過
```

**原理**：
- 當 attack 動畫完成時（Godot 的 `animation_finished` 信號觸發），立即將 `attack_duration_timer` 設為 0
- 這會在下一幀停止 FrameBar 的 `timer_driven` 計數
- 防止動畫完成後還繼續增加 display_frame_counter

### 2. FrameBar.gd 防護措施（次要防護）

**位置**：`FrameBar.gd` line 286-299

**修改內容**：
```gdscript
# 🟢 【防護】如果是攻擊動畫，確保不超過 attack_duration_timer
if anim_name in ATTACK_ANIMS and "attack_duration_timer" in target_player:
    var max_frames = target_player.attack_duration_timer
    if display_frame_counter > max_frames:
        display_frame_counter = max_frames  # 🟢 限制上限，防止超計數
```

**原理**：
- 雙重防護，即使 `attack_duration_timer` 沒有及時停止，也能限制 `display_frame_counter` 不超過預期值
- 防止任何潛在的超計數情況

## 預期結果

### 修復前
```
未擊中時：st_lp 顯示 14F ✓
擊中時：st_lp 顯示 15F ✗
```

### 修復後
```
未擊中時：st_lp 顯示 14F ✓
擊中時：st_lp 顯示 14F ✓
```

## 驗證方法

1. **啟動遊戲**，使用 DEN 角色
2. **執行 st_lp 攻擊**（不擊中對手）
   - 觀察 FrameBar 顯示 14F
   - 檢查日誌：`[ATTACK ANIM FINISH] Stopping attack_duration_timer early`
3. **執行 st_lp 攻擊並擊中對手**
   - 觀察 FrameBar 仍顯示 14F（不再變成 15F）
   - 檢查日誌：`[ATTACK ANIM FINISH]` 和 `[FRAMEBAR OVERFLOW CHECK]`（如果有的話）

## 調試日誌

修復後會產生以下日誌：

```
[ATTACK ANIM FINISH] Stopping attack_duration_timer early | remaining: X frames → 0
[FRAMEBAR COUNTER] ...display_frame_counter: 28 (attack anim)
[ATTACK ANIM FINISH] Ground attack reset
```

## 相關資訊

| 項目 | 值 |
|------|-----|
| st_lp 動畫長度 | 0.23333333 秒 |
| @60FPS 邏輯幀 | 14 frames |
| @120FPS 物理幀 | 28 frames |
| 修復檔案 | Player.gd, FrameBar.gd |
| 影響範圍 | 所有攻擊動畫（地面和空中）|

## 後續優化建議

如果後續還有類似問題，可考慮以下優化：
1. **使用動畫位置而非計時器**：讓 FrameBar 直接讀取 `animation_player.get_current_animation_position()`
2. **統一時間單位**：確保動畫、計時器和幀計數都基於相同的參考點
3. **添加幀同步機制**：在每次重要狀態變化時同步各系統的幀計數
