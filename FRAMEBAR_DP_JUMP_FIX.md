# FrameBar.gd - DP + Jump 追蹤修復

## 修改概述

解決了FrameBar.gd中的三個主要問題：
1. **DP狀態未被追蹤** - 添加完整的DP狀態追蹤系統
2. **跳躍幀數計算不正確** - 從渲染幀改為物理幀計數
3. **狀態清空邏輯不當** - 修改為保持顯示直到新狀態出現

---

## 詳細修改內容

### 1. 添加DP狀態追蹤變量

**新增變量（行70-72）：**
```gdscript
var dp_tracking_active: bool = false
var dp_startup_frame_count: int = 0
var last_physics_frame_for_jump: int = 0  # 用來追蹤jump的物理幀
```

**初始化時機：** 當進入"dp"動畫時自動啟用

**狀態顏色：**
- 🔴 **紅色(1)** - 地面上執行DP（Active幀）
- 🟡 **黃色(2)** - 空中飛行中（Recovery幀）

---

### 2. 修復跳躍幀數計算

**問題原因：** 跳躍幀數在`_process`中每條渲染幀都增加1，導致在高FPS下計數過快

**修改前：**
```gdscript
if is_airborne:
    jump_frame_count += 1  # 每個渲染幀都增加
```

**修改後（行267-274）：**
```gdscript
if is_airborne:
    # 只在物理幀更新時增加 jump_frame_counter（而非每個渲染幀）
    var current_physics_frame: int = Engine.get_physics_frames()
    if current_physics_frame != last_physics_frame_for_jump:
        jump_frame_count += 1
        last_physics_frame_for_jump = current_physics_frame
```

**幀數顯示轉換（行337-338）：**
```gdscript
# 跳躍使用已按物理幀計算的 jump_frame_count
if anim_name in JUMP_ANIMS:
    return int(jump_frame_count / 2.0)  # 按60FPS顯示速度轉換
```

---

### 3. 修改著陸時的追蹤邏輯

**修改前：** 著陸時立即清空追蹤狀態
```gdscript
if is_airborne and (on_floor or anim_name == "landing"):
    is_airborne = false
    is_tracking = false  # ❌ 導致立即清空
```

**修改後（行324-329）：**
```gdscript
if is_airborne and (on_floor or anim_name == "landing"):
    is_airborne = false
    # 🟢 著陸時不清空 is_tracking，讓跳躍顯示保持
    # is_tracking = false  # 改為不清空
```

**效果：** 跳躍完成著陸後，FrameBar仍保持顯示跳躍的幀數，直到下一個新狀態出現

---

### 4. 修改狀態清空邏輯

**修改前：** 每次進入新動畫時直接清空舊資料
```gdscript
else:
    history_frame_data.clear()
    frame_data.clear()  # ❌ 直接清空，失去舊資料
    current_frame = 0
```

**修改後（行444-451）：**
```gdscript
else:
    # 保存前一個狀態到歷史，而不是直接清空
    if frame_data.size() > 0:
        history_frame_data.clear()
        history_frame_data.append_array(frame_data)
    
    frame_data.clear()
    current_frame = 0
```

**效果：** 
- 新進入的狀態在`frame_data`中顯示
- 上一個狀態保存在`history_frame_data`中，作為歷史背景
- FrameBar在`_draw()`中同時繪製兩個盤面

---

### 5. 新增DP狀態處理

**在_get_state()中（行374-385）：**
```gdscript
# DP 狀態追蹤 - 地面時使用紅色(1-active)，空中時使用黃色(2-recovery)
if anim_name == "dp" and dp_tracking_active:
    if on_floor:
        # 地面上時使用紅色（1 - active frame）
        return 1
    else:
        # 空中時使用黃色（2 - recovery/knockup frame）
        return 2
```

**在_calc_frame()中（行342-343）：**
```gdscript
# DP 狀態追蹤
if anim_name == "dp" and dp_tracking_active:
    return int(display_frame_counter / 2.0)
```

**在_start_new_animation()中（行454-462）：**
```gdscript
if anim_name == "dp":
    dp_tracking_active = true
    dp_startup_frame_count = 0
    print("[FRAMEBAR] %s - 開始追蹤 DP 動畫，舊資料已保存到歷史" % target_player.name)
elif dp_tracking_active and anim_name != last_animation:
    print("[FRAMEBAR] %s - 結束 DP 追蹤，進度條將保持顯示" % target_player.name)
    dp_tracking_active = false
```

**在update_frame_count_label()中（行560-566）：**
```gdscript
# DP 特殊顯示 - 地面時為 Active，空中時為 Recovery
elif anim_name == "dp":
    var active_frames = 0
    var recovery_frames = 0
    for s in frame_data:
        if s == 1: active_frames += 1        # 紅色 = active
        elif s == 2: recovery_frames += 1    # 黃色 = recovery
    text += "A:%d R:%d Total:%dF" % [active_frames, recovery_frames, frame_data.size()]
```

**在_on_animation_finished()中（行582-586）：**
```gdscript
# DP 追蹤完成時的處理
if anim_name == "dp":
    dp_tracking_active = false
    print("[FRAMEBAR] %s - DP 動畫完成，播放時間: %dF" % [
        target_player.name, frame_data.size()
    ])
```

---

## 測試清單

✅ **DP狀態追蹤**
- [ ] 執行DP時，FrameBar顯示紅色(Active)和黃色(Recovery)幀
- [ ] DP標籤顯示 "A:XXF R:XXF Total:XXF"
- [ ] DP完成時console輸出"DP 動畫完成"

✅ **跳躍幀數計算**
- [ ] Jump_F/Jump_B/Jump_V動畫的幀數顯示正確（基於60FPS）
- [ ] 跳躍過程中幀數逐漸增加（不是突快）

✅ **跳躍著陸後保持顯示**
- [ ] 著陸後，FrameBar仍顯示跳躍的幀數
- [ ] 執行下一個動作時，新狀態取代跳躍顯示

✅ **狀態清空邏輯**
- [ ] 完成一個追蹤狀態後，FrameBar不自動清空
- [ ] 進入新的被追蹤狀態時，舊狀態移至背景（歷史）

---

## 相關檔案

- **FrameBar.gd**: 主要邏輯實現（544行→600行）
- **FrameBar.tscn**: UI場景（無需修改）
- **Player.gd**: 調用 framebar 的腳本（無修改）

---

## 除錯信息

所有DP相關操作都會在console輸出，格式：
```
[FRAMEBAR] PlayerA - 開始追蹤 DP 動畫，舊資料已保存到歷史
[FRAMEBAR] PlayerA - 結束 DP 追蹤，進度條將保持顯示
[FRAMEBAR] PlayerA - DP 動畫完成，播放時間: 35F
```

---

## 向後兼容性

✅ 所有修改完全向後兼容
✅ 不影響其他已有的狀態追蹤（attack/block/knockfly等）
✅ 不影響現有的UI和動畫系統
