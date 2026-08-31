# Hit Stop 延遲實現 - 功能文檔

## 概述
現在 **knockback、hitstun、blockstun 都會在 hit stop 效果完成後才真正開始計時**。

這確保了更精確的遊戲感受：
- Hit stop 期間：角色被擊中但不開始 hitstun 計數
- Hit stop 結束：**立即**開始 hitstun/knockback/blockstun 計數

## 2026-08 重構：解耦式 HitStop（HitStopManager）

> **重要**：舊實作用 `Engine.time_scale = 0.02` 做**全域**凍結，會連背景特效、
> 火花粒子、UI 計時器、音效一起凍住（畫面死寂感、打擊感喪失）。
> 現改採業界標準（SF6 / GGST / Tekken 8）的**角色層凍結**：

**檔案**: [HitStopManager.gd](../../scripts/core/HitStopManager.gd)（節點 `World/SlowMoController/HitStopManager`）

| 凍結（只影響角色） | 不凍結（正常速度） |
|---|---|
| 角色動畫：`AnimationPlayer` / `AnimationTree` 的 `speed_scale = 0` | VFX 粒子 / 打擊火花（VFXImpact、VFXSmoke、場景粒子） |
| 角色物理：`Movement` / `Player` / `Fireball` 依 `SlowMoController.is_hit_slowmo` 早退（位置 0 位移、Hitbox/Hurtbox 不動） | 音效 |
| Sprite 像素級微震抖（jitter）：每物理幀對 `AnimatedSprite2D.position` 疊加隨機偏移（**不碰 CharacterBody 物理座標**） | UI（計時器、血條、連段數、FrameBar）與鏡頭 |

**@export 參數**（在編輯器選取 `World → SlowMoController → HitStopManager` 調整）：
- 時長（邏輯幀 @60FPS）：`light_hit_frames`(6) / `medium_hit_frames`(8) / `heavy_hit_frames`(10) / `block_hit_frames`(4) / `special_hit_frames`(10)
- Jitter：`jitter_enabled` / `jitter_amplitude`(2.0 px) / `jitter_vertical_ratio`(0.4) / `jitter_end_ratio`(0.2，振幅線性衰減終點)
- 主開關在 `SlowMoController.enable_hitstop`

**流程**：`HitResponseHandler` / `fireball.gd` 命中 → `SlowMoController.request_hit_freeze(attack_type, is_blocked)`
→ 設 `is_hit_slowmo = true` + 暫停 FrameCounter → `HitStopManager.request_hitstop()`（動畫凍結 + jitter 開始 + 物理幀倒數）
→ 倒數歸零 → 還原動畫速度與 sprite 偏移 → 發 `hitstop_ended`
→ `SlowMoController._on_hitstop_ended()`：恢復 FrameCounter、發 `hit_slowmo_finished`（見下方延遲機制）。

`SlowMoController` 保留的全域 `time_scale` 用途：**只**用於手動/KO 慢動作（`slowmo_time_scale = 0.2` 的戲劇效果），與 hitstop 無關。

## 舊版（pre-2026-08）SlowMoController 改動（歷史記錄）

### 1. SlowMoController 的改動
**文件**: [slow_mo_controller.gd](slow_mo_controller.gd)

新增信號：
```gdscript
signal hit_slowmo_finished  # Hit stop 完成時觸發
```

（舊版用 Tween 在真實時間 `hit_slowmo_time` 後把 `Engine.time_scale` 拉回 1.0；
現由 HitStopManager 的物理幀倒數取代，`_on_hitstop_ended()` 為對應回調。）

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
| Hitstun 未開始 | `waiting_for_hit_stop_end` 未清除 | 檢查 `SlowMoController._on_hitstop_ended()` 是否被調用 |
| Knockback 未執行 | Hit Stop 發生但未結束 | 檢查 `HitStopManager` 的時長參數（`*_hit_frames`）與 `SlowMoController.enable_hitstop` |
| 重複計時 | `pending_hit_params` 未清除 | 確保 `_apply_pending_hit_effect()` 被正確調用 |
| 角色沒有定格 | `is_hit_slowmo` 未設為 true | 確認命中路徑有呼叫 `request_hit_freeze()`（HitResponseHandler / fireball.gd） |
| 特效跟著一起凍 | 誤用全域凍結 | 檢查有無程式碼對 hitstop 使用 `Engine.time_scale` / `get_tree().paused`（只允許手動/KO 慢動作用） |

## 相關代碼位置
- **SlowMoController**: [slow_mo_controller.gd#L7](slow_mo_controller.gd#L7), [slow_mo_controller.gd#L110](slow_mo_controller.gd#L110)
- **Fighter._ready()**: [fighter.gd#L40-L43](fighter.gd#L40-L43)
- **Fighter.take_hit()**: [fighter.gd#L261-L282](fighter.gd#L261-L282)
- **Fighter._on_hit_slowmo_finished()**: [fighter.gd#L388-L400](fighter.gd#L388-L400)
- **Fighter._apply_pending_hit_effect()**: [fighter.gd#L402-L427](fighter.gd#L402-L427)
