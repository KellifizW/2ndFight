# FrameBar 15F Bug 分析報告

## 問題描述
使用 DEN 角色的 `st_lp` 攻擊：
- **未擊中時**：顯示 14F（正常）
- **擊中對手後**：顯示 15F（不正常）

## 根本原因

### 1. 動畫長度計算
```
st_lp 動畫長度: 0.23333333 秒（DEN.tscn line 4866）

@60FPS logic frames:  0.23333333 × 60 = 14.0 frames ✓
@120FPS physics frames: 0.23333333 × 120 = 28.0 frames ✓
```

### 2. attack_duration_timer 設置（Player.gd line 626）
```gdscript
attack_duration_timer = int(round(anim_length * 60 * 2))
                      = int(round(0.23333333 * 120))
                      = int(round(28.0))
                      = 28 frames @120FPS ✓
```

### 3. display_frame_counter 的增加過程

**正常情況（未擊中）：**
```
Frame 0:   display_frame_counter = 0（attack開始時重置）
Frame 1-27: display_frame_counter += 1（每個物理幀增加1）
Frame 28:   動畫完成 → animation_finished 信號觸發
           → reset_attack_state() → attack_duration_timer = 0
           → is_attacking = false → FrameBar 不再為 timer_driven
```

**BUT 實際發生的情況：**
```
Frame 0-27:   display_frame_counter = 0 → 28（正确）
Frame 28-29:  display_frame_counter = 28 → 30（額外增加2幀！）
Frame 30:     最終顯示 = round(30/2.0) = 15F ✗
```

### 4. 可能的原因

**問題 A: 動畫完成信號延遲**
- Godot 的 AnimationPlayer.animation_finished 信號可能在動畫實際完成後的 1-2 幀才發送
- 在這 1-2 幀期間，display_frame_counter 仍在增加（因為 is_attacking=true，timer_driven=true）
- 最後動畫長度比預期多 1-2 幀

**問題 B: 浮點精度與舍入偏差**
- 0.23333333 秒可能在實際計數時導致額外的 1-2 幀累積
- 特別是在轉換單位(秒→幀)和舍入時

**問題 C: FrameBar 的 display_frame_counter++ 時機**
- 在 _process_tracked() 中，每個物理幀增加 1（line 290）
- 但這可能與動畫完成信號的時機不同步

## 解決方案

### 方案 1: 動畫完成時立即停止 timer_driven 計數
在 `_on_animation_player_finished()` 或動畫完成回調中：
```gdscript
# 當攻擊動畫完成時，立即凍結 display_frame_counter
if anim_name in ATTACK_ANIMS:
    attack_duration_timer = 0  # 立即停止 timer_driven
    is_attacking = false       # 停止攻擊狀態
```

### 方案 2: 同步 display_frame_counter 與實際動畫長度
在 attack 開始時記錄預期的幀數，動畫完成時驗證：
```gdscript
# 在 _process_tracked() 中
if anim_name in ATTACK_ANIMS and was_active and not is_active:
    # 動畫剛結束，檢查 display_frame_counter 是否超過預期值
    var expected_frames = attack_duration_timer  # @120FPS
    if display_frame_counter > expected_frames:
        display_frame_counter = expected_frames  # 強制同步
```

### 方案 3: 基於動畫時長而非計時器（推薦）
```gdscript
# 在 FrameBar._calc_frame() 中
if anim_name in ATTACK_ANIMS:
    # 直接使用動畫播放位置（animation_player.get_current_animation_position()）
    # 而非 display_frame_counter
    var anim_time = animation_player.current_animation_position
    var anim_length = animation_player.get_animation(anim_name).length
    var frame_60fps = int(anim_time * 60)  # @60FPS 邏輯幀
    return frame_60fps
```

## 建議的修復

**最簡單的修復**：在 attack 動畫完成時立即停止計數
- 修改 `_on_animation_player_finished()` 
- 當 `anim_name in ATTACK_ANIMS` 時，立即設置 `attack_duration_timer = 0`
- 這會停止 FrameBar 的 timer_driven 計數

**最健壯的修復**：使用動畫播放位置而非計時器
- FrameBar 應該使用 `animation_player.get_current_animation_position()` 
- 而非 `display_frame_counter` 計算幀數
- 這樣可以精確同步顯示幀數與實際動畫進度

## 相關代碼位置
- Player.gd line 380-383: attack_duration_timer 遞減邏輯
- Player.gd line 460-492: _on_animation_player_finished() 回調
- FrameBar.gd line 240, 248, 290: display_frame_counter 修改
- FrameBar.gd line 330: _calc_frame() 計算邏輯（int(display_frame_counter / 2.0)）
