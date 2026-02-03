# DP 完成後鎖定狀態 - 除錯指南

## 問題描述
角色在完成 DP 招式後，會被暫時鎖定一段時間，才能回到正常狀態。

## 除錯流程

### 1. 監控以下關鍵狀態變數

在遊戲運行時，查看輸出日誌中的以下信息：

#### **ANIM_FINISHED 日誌** (Player.gd)
```
[ANIM_FINISHED] Animation 'dp' finished | Seat: player_a
  [STATE] is_special_moving=true, is_facing_locked=true, is_landing=false, landing_lock_timer=0.000, move_set.is_spmove=true
```
- **is_special_moving**: 應該被重置為 false
- **is_facing_locked**: 應該被重置為 false
- **move_set.is_spmove**: 應該變為 false

#### **SPECIAL_RESET 日誌** (Player.gd)
```
[SPECIAL_RESET] Resetting special move 'dp' | Seat: player_a
  [BEFORE] is_special_moving=true, is_facing_locked=true, is_landing=false, landing_lock_timer=0.000
  [UPDATE] Updating animation state with input_dir=0, crouch=false
  [AFTER] is_special_moving=false, is_facing_locked=false, is_landing=false, landing_lock_timer=0.000
```
- 檢查 BEFORE 和 AFTER 的狀態差異

#### **MOVESET.STOP 日誌** (MoveSet.gd)
```
[MOVESET.STOP] Stopping special move 'dp' | Seat: player_a
  [BEFORE] is_spmove=true, is_special_moving=true, parent.is_special_moving=true, parent.is_facing_locked=true
  [STOP] animation_player.stop() called
  [LOCK] Reset parent.is_facing_locked to false
  [MOVING] Reset parent.is_special_moving to false
  [AFTER] is_spmove=false, is_special_moving=false, parent.is_special_moving=false, parent.is_facing_locked=false
```

#### **ANIM_UPDATE 日誌** (AnimationManager.gd)
```
[ANIM_UPDATE] Seat: player_a, curr_state='Walk', target_state='Walk', is_special_moving=true, is_facing_locked=false, on_floor=true
  [TRAVEL] Moving from 'dp' to 'Walk'
```

### 2. 可能的鎖定原因

| 狀態變數 | 原因 | 檢查位置 |
|---------|------|--------|
| `is_special_moving=true` | 未被重置為 false | `reset_special_state()` 或 `MoveSet.stop_special_move()` |
| `is_facing_locked=true` | 未被重置為 false | `reset_special_state()` 或 `MoveSet.stop_special_move()` |
| `landing_lock_timer>0` | 著地鎖定未清除 | `LandingHandler.handle_landing()` |
| `is_landing=true` | 仍在著地狀態 | `_reset_landing_anim()` |
| `move_set.is_spmove=true` | 特殊招式未停止 | `MoveSet.stop_special_move()` |

### 3. 完整除錯檢查清單

執行 DP 並完成著地，檢查以下順序：

1. **DP 動畫完成**
   - 查看 `[ANIM_FINISHED]` 日誌
   - 確認 animation_name == "dp"

2. **特殊招式重置**
   - 查看 `[SPECIAL_RESET]` 日誌
   - 確認 AFTER 所有狀態都被正確重置

3. **MoveSet 停止**
   - 查看 `[MOVESET.STOP]` 日誌
   - 確認 is_spmove=false, is_special_moving=false, is_facing_locked=false

4. **動畫狀態更新**
   - 查看 `[ANIM_UPDATE]` 日誌
   - 確認 target_state 從 "dp" 變為 "Walk"（或其他正常狀態）

### 4. 常見問題排查

**問題**: 角色卡在 "dp" 動畫狀態
- **原因**: `move_set.is_spmove` 仍為 true
- **解決**: 檢查 `MoveSet.stop_special_move()` 是否被呼叫

**問題**: 角色不能移動（面向被鎖定）
- **原因**: `is_facing_locked=true`
- **解決**: 檢查 `reset_special_state()` 中是否清除此標誌

**問題**: 角色進入了 landing 動畫
- **原因**: `is_landing=true` 或 `landing_lock_timer>0`
- **解決**: 檢查 `LandingHandler` 是否正確跳過 DP 的 landing 邏輯

### 5. 核心代碼流程

```
DP 動畫完成
  ↓
_on_animation_player_finished("dp")
  ↓
reset_special_state()
  ├─ move_set.stop_special_move()
  │   ├─ is_spmove = false
  │   ├─ is_special_moving = false
  │   └─ is_facing_locked = false
  ├─ force_update_facing_direction()
  └─ _update_animation_state(0, crouch_input)
       ↓
       [ANIM_UPDATE] 應該返回 "Walk" 或其他正常狀態
```

### 6. 禁用除錯日誌

修正問題後，刪除或註解以下日誌行：

- Player.gd: `reset_special_state()` 中的 print 語句
- MoveSet.gd: `stop_special_move()` 中的 print 語句
- AnimationManager.gd: `update_animation_state()` 中的 print 語句
- Player.gd: `_compute_target_state()` 中的 print 語句

## 相關文件

- [Player.gd](Player.gd) - reset_special_state()
- [MoveSet.gd](MoveSet.gd) - stop_special_move()
- [AnimationManager.gd](AnimationManager.gd) - update_animation_state()
- [LandingHandler.gd](LandingHandler.gd) - handle_landing()
