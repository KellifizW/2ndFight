# Hit Stop 延遲實現 - 功能文檔

## 概述（2026-09 更新：解耦式 Hitstop）

現行架構由 World 下的 `HitStopController` 全權負責定格，**不再修改 `Engine.time_scale`**：

- Hit stop 期間（`hitstop_frames` 個物理幀，預設 8 幀 ≈ 66ms）：
  - 雙方角色的 AnimationTree **節點被停止處理**
    （`AnimationTree.process_mode = PROCESS_MODE_DISABLED`）——
    角色動畫由 AnimationTree 驅動 AnimationPlayer 播放，此時 AnimationPlayer 自身的
    `speed_scale` 不會生效（Godot 官方文件明載）；讓 mixer 收不到 internal process
    通知才是真正的定格開關，而且 `active` / `callback_mode_process` / 狀態機節點身分 /
    travel 目標 / 條件參數全部原封不動。
    `AnimationPlayer` / `AnimatedSprite2D` 的 `speed_scale = 0` 仍一併設下，
    覆蓋繞過 AnimationTree 的直接播放（如 landing）。
  - `Fighter` / `Player` 的 `_physics_process` 早退，hitstun / blockstun / knockback
    等幀數計數全部凍結。
  - 背景、粒子特效、VFX、UI 維持正常時間運行。
- 凍結開始當下，`HitStopController._apply_frozen_poses()` 會對**受擊方**的
  AnimationTree `advance(0)`（delta=0 沖洗）：把 `take_hit()` 已排定的 travel 立即
  套用 —— **受擊者在 hitstop 期間就停在受擊／格擋動畫第 0 格**；hitstop 結束後才從
  凍結點繼續播放。攻擊方不沖洗，它本來就停在打中瞬間那一格。

### ⚠️ 為什麼定格不能用 `callback_mode_process = MANUAL`

（2026-09 修正：`hitstop_frames = 60` 時「攻擊者打中瞬間動畫被重置成 idle、解凍後
重播打擊動畫」的根因。）

Godot 引擎行為，與遊戲邏輯無關：

1. `AnimationMixer::set_callback_mode_process()` 內部是
   `set_active(false)` → 換模式 → `set_active(true)`。
2. `AnimationTree::_set_active()` 會把 mixer 的私有旗標 `started` 設成 `true`。
3. 下一次處理（就是定格時的 `advance(0)`）時，`AnimationTree::_blend_pre_process()`
   以 `seeked = true, time = 0, is_external_seeking = false` 進入狀態機。
4. `AnimationNodeStateMachinePlayback::_process()` 的
   「Check seek to 0 (means reset) by parent AnimationNode」分支因此成立 → `_start()`
   → **整台狀態機重啟回 Start 節點**（外加 `reset_request = true`）。

受擊方剛好有 `take_hit()` 排好的 travel，重啟後立刻被帶到受擊動畫，所以完全看不出
異常；攻擊方沒有待處理的 travel，重啟後就掉回 Start → idle。解凍時還原
`callback_mode_process` 會再觸發一次同樣的重啟，此時 `is_attacking` 仍為 true，
動畫層便再 travel 一次攻擊動畫 —— 於是「解凍後打擊動畫又播一次（甚至多次）」。
`hitstop_frames` 越大，這個錯誤姿勢停留得越久，所以在 60 幀時特別明顯。

改用 `process_mode` 定格完全不碰 `active`，兩個症狀的根都被拔掉；順帶也不再每次
hitstop 都因為 `set_active(false)` 而 `_clear_caches()` 重建整份 track cache。

回歸測試：`tests/frame_tests/cases/test_39_attacker_pose_frozen_on_hit.gd`
（以及 `test_37_hitstop_decoupled.gd` / `test_38_long_hitstop_single_attack.gd`）。
- Hit stop 結束：`hitstop_finished` → `SlowMoController` 廣播 `hit_slowmo_finished`
  → `Fighter._on_hit_slowmo_finished()` 啟動被延遲的 hitstun/knockback/blockstun。

> 以下為舊版（全域 time_scale 時代）的實現記錄，`pending_hit_params` /
> `waiting_for_hit_stop_end` 的延遲啟動機制沿用至今。

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
