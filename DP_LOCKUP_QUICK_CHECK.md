# DP 鎖定問題 - 快速日誌檢查

## 運行遊戲並執行 DP，查看以下日誌輸出

### 預期的正常流程日誌

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DP 著地時
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[ANIM_UPDATE] Seat: player_a, curr_state='dp', target_state='dp', ...
  [TRAVEL] Moving from 'dp' to 'dp'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DP 動畫完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[ANIM_FINISHED] Animation 'dp' finished | Seat: player_a
  [STATE] is_special_moving=true, is_facing_locked=true, is_landing=false, landing_lock_timer=0.000, move_set.is_spmove=true
  [HANDLER] Special move animation finished
  [SPECIAL] This is a self-landing move (dp/hdk/powerkk)
  
[MOVESET.STOP] Stopping special move 'dp' | Seat: player_a
  [BEFORE] is_spmove=true, is_special_moving=true, parent.is_special_moving=true, parent.is_facing_locked=true
  [STOP] animation_player.stop() called
  [LOCK] Reset parent.is_facing_locked to false
  [MOVING] Reset parent.is_special_moving to false
  [AFTER] is_spmove=false, is_special_moving=false, parent.is_special_moving=false, parent.is_facing_locked=false

[SPECIAL_RESET] Resetting special move 'dp' | Seat: player_a
  [BEFORE] is_special_moving=true, is_facing_locked=true, is_landing=false, landing_lock_timer=0.000
  [DURING] Calling force_update_facing_direction()
  [UPDATE] Updating animation state with input_dir=0, crouch=false
  [ANIM_UPDATE] Seat: player_a, curr_state='dp', target_state='Walk', is_special_moving=false, is_facing_locked=false, on_floor=true
    [TRAVEL] Moving from 'dp' to 'Walk'
  [AFTER] is_special_moving=false, is_facing_locked=false, is_landing=false, landing_lock_timer=0.000
```

## 問題診斷

### 症狀 1: 角色卡在 DP 動畫狀態

**日誌特徵**：
```
[ANIM_UPDATE] curr_state='dp', target_state='Walk', ...
  [TRAVEL] Moving from 'dp' to 'Walk'
[ANIM_UPDATE] curr_state='dp', target_state='Walk', ...  ← 持續不斷重複
  [TRAVEL] Moving from 'dp' to 'Walk'
```

**原因**：
- `move_set.is_spmove` 未被清除（仍為 true）
- 檢查 `[MOVESET.STOP]` 的 AFTER 是否 `is_spmove=false`

**修正**：
- 檢查 `MoveSet.stop_special_move()` 的執行流程

---

### 症狀 2: 角色無法轉向（面向鎖定）

**日誌特徵**：
```
[SPECIAL_RESET] Resetting special move 'dp' | Seat: player_a
  [BEFORE] is_special_moving=true, is_facing_locked=true, ...
  [AFTER] is_special_moving=false, is_facing_locked=true  ← 仍鎖定！
```

**原因**：
- `is_facing_locked` 未被清除
- 檢查 `reset_special_state()` 是否呼叫 `force_update_facing_direction()`

**修正**：
```gdscript
is_facing_locked = false  # 添加此行
force_update_facing_direction()
```

---

### 症狀 3: 角色進入著地動畫

**日誌特徵**：
```
[ANIM_UPDATE] target_state='landing', ...  ← 不應該進入 landing
  [TRAVEL] Moving from 'dp' to 'landing'
```

**原因**：
- `is_landing=true` 或 `landing_lock_timer>0`
- 檢查 `LandingHandler` 未正確跳過 DP

**修正**：
- 確認 `LandingHandler.handle_landing()` 中的 DP 檢查邏輯

---

### 症狀 4: 特殊招式狀態未清除

**日誌特徵**：
```
[MOVESET.STOP] Stopping special move 'dp' | Seat: player_a
  [BEFORE] is_spmove=true, is_special_moving=true, parent.is_special_moving=true, ...
  [STOP] animation_player.stop() called
  [AFTER] is_spmove=true, is_special_moving=true, parent.is_special_moving=true  ← 未清除！
```

**原因**：
- `stop_special_move()` 中的清除邏輯未執行
- 檢查是否有早期 return 或異常

**修正**：
- 確認 `move_set.is_spmove = false` 被執行

---

## 快速查找技巧

按 Ctrl+Shift+M 打開「問題」面板，搜索：
- `DP_LOCKUP_DEBUG_GUIDE.md` 查看完整指南
- `[ANIM_FINISHED]` 找動畫完成日誌
- `[SPECIAL_RESET]` 找狀態重置日誌
- `[MOVESET.STOP]` 找招式停止日誌
- `[ANIM_UPDATE]` 找動畫狀態更新日誌

## 關鍵代碼位置

| 功能 | 文件 | 行數 |
|------|------|------|
| 動畫完成處理 | [Player.gd](Player.gd#L454) | 454 |
| 特殊狀態重置 | [Player.gd](Player.gd#L115) | 115 |
| 招式停止 | [MoveSet.gd](MoveSet.gd#L312) | 312 |
| 著地處理 | [LandingHandler.gd](LandingHandler.gd) | 全文 |
| 動畫狀態更新 | [AnimationManager.gd](AnimationManager.gd#L77) | 77 |
| 目標狀態計算 | [Player.gd](Player.gd#L390) | 390 |
