# Hit Stop 延遲實現 - 功能文檔

> ## ⚡ 2026-08 更新：hitstop 計時重寫 + 編輯器可調參數
>
> **症狀**：打中對手後遊戲時間完全沒有凍結（hitstop 根本不出現）。
>
> **原因**：舊實現用 `Tween` + `set_ignore_time_scale()` 計時 hitstop。
> 這條路徑有兩個致命弱點：
> 1. `set_ignore_time_scale()` 是較新的引擎 API，且不同 Godot 版本對
>    「tween 是否真的用真實時間推進」行為不一致 —— tween 提前完成時
>    `time_scale` 會被瞬間還原，凍結短到肉眼看不見；
> 2. KO 慢動作（`enter/exit_slowmo_animation`）與回合重置會 `kill()` 同一個
>    tween，`_on_hit_slowmo_finished` 永遠不會被呼叫 → `is_hit_slowmo` 卡死
>    為 `true`，之後**所有** `request_hit_freeze()` 都被開頭的防重入判斷擋掉，
>    hitstop 從此永遠不再出現。
>
> **修復**：
> - hitstop 改用 **wall clock（`Time.get_ticks_msec()`）+ `_process` 輪詢**計時。
>   `_process` 每個渲染幀都會執行、完全不受 `Engine.time_scale` 影響，
>   凍結保證會生效、也保證會結束，`is_hit_slowmo` 不可能卡死。
> - 回合重置改呼叫 `SlowMoController.cancel_hit_freeze()`，完整還原
>   動畫速度 / FrameCounter / 等待中的 hitstun，不再直接改旗標。
> - `MoveSet.freeze_game()`（超必殺凍結）同步改用真實時間 SceneTreeTimer，
>   並把危險的 `Engine.time_scale = 0.0` 改為 0.02。
>
> **編輯器可調參數**（world.tscn → `SlowMoController` 節點 Inspector）：
>
> | 參數 | 預設 | 說明 |
> |------|------|------|
> | `enable_hitstop` | `true` | hitstop 總開關 |
> | `hitstop_frames` | `8` | hitstop 時長（60fps 邏輯幀；8 幀 ≈ 0.133s） |
> | `hit_slowmo_time_scale` | `0.02` | 凍結期間的 `Engine.time_scale`（越小越凍） |
> | `sync_animation_speed` | `true` | 凍結期間同步玩家動畫速度 |
> | `slowmo_time_scale` | `0.2` | KO 慢動作時間縮放 |
> | `slowmo_enter_time` / `slowmo_exit_time` | `0.4` | KO 慢動作過渡時間（秒） |
>
> 程式端也可對單次命中覆蓋時長：`request_hit_freeze(custom_frames)`。
> 迴歸測試：`tests/frame_tests/cases/test_37_hitstop_time_freeze.gd`。

## 概述
現在 **knockback、hitstun、blockstun 都會在 hit stop 效果完成後才真正開始計時**。

這確保了更精確的遊戲感受：
- Hit stop 期間（time_scale 變低）：角色被擊中但不開始 hitstun 計數
- Hit stop 結束（time_scale 恢復到 1.0）：**立即**開始 hitstun/knockback/blockstun 計數

## 實現原理

### 1. SlowMoController 的改動
**文件**: [slow_mo_controller.gd](slow_mo_controller.gd)

新增信號：
```gdscript
signal hit_slowmo_finished  # Hit stop 完成時觸發
```

當 hit stop 完成時發送信號：
```gdscript
func _on_hit_slowmo_finished():
    is_hit_slowmo = false
    Engine.time_scale = normal_time_scale
    emit_signal("time_scale_changed", normal_time_scale)
    # 🟢 發送信號通知所有 Fighter，hit stop 已完成
    emit_signal("hit_slowmo_finished")
```

### 2. Fighter 的改動
**文件**: [fighter.gd](fighter.gd)

#### 新增變數（第 29-30 行）
```gdscript
var pending_hit_params: Dictionary = {}      # 存儲 take_hit 的所有參數
var waiting_for_hit_stop_end: bool = false   # 標記是否在等待 hit stop 完成
```

#### _ready() 連接信號（第 40-43 行）
```gdscript
if world and world.has_node("SlowMoController"):
    var slowmo_controller = world.get_node("SlowMoController")
    slowmo_controller.hit_slowmo_finished.connect(_on_hit_slowmo_finished)
```

#### take_hit() 中的邏輯修改（第 261-282 行）
檢查是否有 hit stop 正在進行：

```gdscript
# 🟢 檢查是否有 hit stop 正在進行
var slowmo_controller = world.get_node_or_null("SlowMoController") if world else null
if slowmo_controller and slowmo_controller.is_hit_slowmo:
    # Hit stop 正在進行 → 延遲設置 hitstun/knockback/blockstun
    waiting_for_hit_stop_end = true
    pending_hit_params = {
        "hit_frames": hit_frames,
        "blockstun": 0,
        "skip_push": skip_push,
        "knockback_delay_frames": sec_to_frames(knockback_delay_duration),
        "hit_push_initial_velocity": knockback_velocity
    }
else:
    # Hit stop 未進行或已完成 → 立即設置 hitstun/knockback/blockstun
    hitstun_frames = hit_frames
    initial_hitstun = hitstun_duration
```

#### 新增回調方法（第 388-400 行）
```gdscript
func _on_hit_slowmo_finished() -> void:
    if waiting_for_hit_stop_end and pending_hit_params.size() > 0:
        print("[HIT STOP END] %s - 啟動被延遲的 hitstun/knockback/blockstun" % name)
        _apply_pending_hit_effect()
        waiting_for_hit_stop_end = false
        pending_hit_params.clear()
```

#### 新增應用延遲效果的方法（第 402-427 行）
```gdscript
func _apply_pending_hit_effect() -> void:
    var hit_frames = pending_hit_params.get("hit_frames", 0)
    var blockstun = pending_hit_params.get("blockstun", 0)
    var skip_push = pending_hit_params.get("skip_push", false)
    
    # 啟動 hitstun
    hitstun_frames = hit_frames
    if blockstun > 0:
        blockstun_frames = blockstun
        initial_blockstun_frames = blockstun
    
    # 啟動 knockback（如果不跳過 push）
    if not skip_push:
        var knockback_delay_frames_val = pending_hit_params.get("knockback_delay_frames", 0)
        var hit_frames_val = pending_hit_params.get("hit_frames", 0)
        var hit_push_initial_velocity_val = pending_hit_params.get("hit_push_initial_velocity", 0)
        
        knockback_delay_frames = knockback_delay_frames_val
        
        if knockback_delay_frames <= 0:
            knockback_frames = hit_frames_val
            initial_knockback_frames = hit_frames_val
            hit_push_velocity = hit_push_initial_velocity_val
        else:
            knockback_frames = 0
            initial_knockback_frames = hit_frames_val
            hit_push_velocity = 0.0
```

## 執行流程

### 無 Hit Stop 的情況（快速）
```
take_hit() 呼叫
  ↓
檢查：slowmo_controller.is_hit_slowmo = false
  ↓
立即設置：hitstun_frames = hit_frames
  ↓
立即設置：knockback_frames, initial_knockback_frames
  ↓
開始計時
```

### 有 Hit Stop 的情況（延遲）
```
take_hit() 呼叫
  ↓
檢查：slowmo_controller.is_hit_slowmo = true
  ↓
儲存所有參數到 pending_hit_params
  ↓
設置：waiting_for_hit_stop_end = true
  ↓
等待...
  ↓
SlowMoController._on_hit_slowmo_finished() 觸發
  ↓
發送信號：hit_slowmo_finished
  ↓
Fighter._on_hit_slowmo_finished() 被調用
  ↓
執行：_apply_pending_hit_effect()
  ↓
開始計時（在 hit stop 完全結束後）
```

## 日誌示例

### 無 Hit Stop
```
[FIXED-FRAME HITSTUN START] Player_A 進入 hit，66 幀 (0.550秒)
[KNOCKBACK SETUP] Player_A
  - 立即啟動 knockback_frames: 66
```

### 有 Hit Stop（延遲）
```
[HITSTUN DELAYED] Player_B - Hit stop 進行中，延遲設置 hitstun/knockback/blockstun
[KNOCKBACK SETUP] Player_B
  - ⏳ 等待 hit stop 結束...
...（Hit stop 進行中）...
[HIT STOP END] Player_B - 啟動被延遲的 hitstun/knockback/blockstun
[HIT EFFECT APPLIED] Player_B - hitstun: 66 frames, blockstun: 0 frames, knockback: 66 frames
```

## 優勢

✅ **精確的遊戲感受**: Hitstun/knockback 不會被 hit stop 延遲時間"偷走"  
✅ **視覺一致**: 角色停止移動→hit stop 結束→開始被推動（更直覺）  
✅ **幀計數精確**: 所有效果都在正常時間縮放下計時  
✅ **向後相容**: 沒有 hit stop 時行為完全相同  

## 故障排查

| 問題 | 原因 | 解決方案 |
|-----|------|--------|
| Hitstun 未開始 | `waiting_for_hit_stop_end` 未清除 | 檢查 `_on_hit_slowmo_finished()` 是否被調用 |
| Knockback 未執行 | Hit stop 發生但未結束 | 檢查 SlowMoController 的 `hit_slowmo_time` 設置 |
| 重複計時 | `pending_hit_params` 未清除 | 確保 `_apply_pending_hit_effect()` 被正確調用 |

## 相關代碼位置
- **SlowMoController**: [slow_mo_controller.gd#L7](slow_mo_controller.gd#L7), [slow_mo_controller.gd#L110](slow_mo_controller.gd#L110)
- **Fighter._ready()**: [fighter.gd#L40-L43](fighter.gd#L40-L43)
- **Fighter.take_hit()**: [fighter.gd#L261-L282](fighter.gd#L261-L282)
- **Fighter._on_hit_slowmo_finished()**: [fighter.gd#L388-L400](fighter.gd#L388-L400)
- **Fighter._apply_pending_hit_effect()**: [fighter.gd#L402-L427](fighter.gd#L402-L427)
