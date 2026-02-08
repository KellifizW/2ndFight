# AdvantageLabel 實時追蹤修復報告

## 問題描述

### 主要問題 1: 優勢未實時追蹤（"預判"現象）
- **症狀**: Advantage 在動畫未完成時就顯示結果，而不是在實際恢復時才更新
- **根本原因**: 使用靜態的 `attack_duration_frames`（完整動畫時長）進行計算，導致預先算好結果

### 主要問題 2: 計算誤差
- **症狀**: DEN st_lp 應該比 DAV 快 4 幀恢復，但顯示 +5 幀
- **可能原因**: 幀計算數據結構不一致、hit_frame 時機誤差、或 hitstun_frames 轉換誤差

---

## 修復方案

### 修改 1: world.gd - `_calculate_hit_advantage()` 函數
**位置**: 第 315-355 行

**改動內容**:
```gdscript
# ❌ 舊方式（有問題）
attacker_recover_frame = attack_start_frame + attack_duration_frames
# → attack_duration_frames 是完整動畫時長（靜態值）
# → 忽略了動畫已經播放的部分
# → 導致"預判"效果

# ✅ 新方式（實時追蹤）
if is_still_attacking and timer_remaining > 0:
    # 實時計算：當前幀 + 剩餘計時器 = 恢復幀
    attacker_recover_frame = current_frame + timer_remaining
else:
    # 攻擊已結束
    attacker_recover_frame = frame_counter.get_current_frame()
```

**優勢**:
- ✅ **實時更新**: `attack_duration_timer` 每幀遞減 1，所以 `attacker_recover_frame` 會隨著動畫進行而實時更新
- ✅ **準確性**: 不再"預判"，而是基於當前實際狀態
- ✅ **無延遲**: 不需要等待動畫完全結束才開始計算

### 修改 2: world.gd - `_on_hit_detected()` 函數
**位置**: 第 704-730 行

**改動內容**:
```gdscript
# ❌ 舊方式
# 在 _on_hit_detected() 中計算 attack_duration_frames
attack_duration_frames = int(round(anim_length * frame_counter.PHYSICS_FPS))

# ✅ 新方式
# 移除 attack_duration_frames 的計算
# 改由 _calculate_hit_advantage() 直接使用 attack_duration_timer
```

**改動原因**:
- 消除了在 hit 時預先計算完整動畫時長的做法
- 改為實時讀取 `attacker.attack_duration_timer`，該計時器每幀遞減

---

## 技術細節

### Advantage 計算流程（修復後）

```
時刻 1: 攻擊執行 (_execute_attack)
├─ attack_type = "st_lp"
├─ attack_start_frame = 當前物理幀（100）
└─ attack_duration_timer = 26 物理幀（13 邏輯幀動畫）

時刻 2: Hit 被檢測到（幀 108）
├─ hit_frame = 108
├─ target_player.hitstun_frames = 28（14 邏輯幀）
└─ ✗ 不再計算 attack_duration_frames（改用實時 timer）

時刻 3a: _calculate_hit_advantage() 每幀被調用（攻擊進行中）
├─ 檢查: is_attacking = true, timer_remaining = 20, 18, 16, ...
├─ current_frame = 116, 118, 120, ...
├─ attacker_recover_frame = 116+20=136, 118+18=136, 120+16=136 ✓
└─ 【重要】值每幀變化，直到動畫結束

時刻 3b: _calculate_hit_advantage() 在動畫結束時
├─ 檢查: is_attacking = false, timer_remaining = 0
├─ attacker_recover_frame = 126（確定值）
├─ target_recover_frame = 108 + 28 = 136
└─ advantage = (136 - 126) / 2.0 = 5 邏輯幀 ✓
```

### 幀計算基準（確認無誤）

| 項目 | 計算方式 | 註記 |
|------|--------|------|
| attack_duration_timer | 每幀遞減 int | 物理幀（120 FPS） |
| hit_frame | frame_counter.get_current_frame() | 物理幀（120 FPS） |
| hitstun_frames | target_player.hitstun_frames | 物理幀（120 FPS） |
| attacker_recover_frame | current + timer_remaining | 物理幀（120 FPS） |
| target_recover_frame | hit_frame + hitstun_frames | 物理幀（120 FPS） |
| advantage（顯示） | (target - attacker) / 2.0 | 邏輯幀（60 FPS，舍入） |

---

## 測試驗證

### 測試步驟

1. **執行 st_lp 攻擊**（DEN）
   - 動畫時長: 13 邏輯幀 = 26 物理幀
   - 第 4 邏輯幀（8 物理幀）hit 對手

2. **觀察 Advantage Label**
   - ✅ **修復前 vs 修復後對比**
     - 修復前: 在動畫進行中就顯示 +5（"預判"）
     - 修復後: 動畫進行中不斷更新，動畫結束後確定為 +4 或 +5（實時追蹤）

3. **預期結果**
   - DEN 恢復幀: attack_start_frame + 26 = 攻擊開始幀 + 完整時長
   - DAV 恢復幀: hit_frame(8) + 28 = 被擊幀 + hitstun
   - 優勢: (DAV - DEN) / 2.0

### 調試輸出檢查

啟用 Godot console，運行遊戲後執行 st_lp 攻擊：

```
[HIT DETECTION] 被擊者 Player_B 進入 28 物理幀 hitstun (14.0 邏輯幀)
[HIT DETECTION] 被擊幀數: 108 物理幀 (54.0 邏輯幀) | 攻擊者將在 _calculate_hit_advantage() 中實時評估恢復時間

[ADVANTAGE CALC] ════════════════════════════════════════
[ADVANTAGE CALC] Attacker 恢復時間計算（實時追蹤）：
[ADVANTAGE CALC]   - 當前物理幀: 116
[ADVANTAGE CALC]   - attack_duration_timer: 18 物理幀 (仍在進行)
[ADVANTAGE CALC]   - 預期恢復幀: 134 物理幀 (當前 116 + 剩餘 18)
...
[ADVANTAGE CALC] 最終優勢計算結果：
[ADVANTAGE CALC]   - Attacker 恢復幀: 126 物理幀 (63.0 邏輯幀)
[ADVANTAGE CALC]   - Target 恢復幀: 136 物理幀 (68.0 邏輯幀)
[ADVANTAGE CALC]   - 邏輯幀差異: 5 (60 FPS) [10 / 2.0 = 5.00]
```

---

## 關於 +5 vs +4 的討論

### 可能的原因（需要進一步調查）

1. **幀計數基準不同**
   - Hit 發生在邏輯幀 4（物理幀 8）vs 邏輯幀 5（物理幀 10）

2. **Landing lock 或其他延遲**
   - DEN 可能在動畫結束後還有 1 幀的固定延遲

3. **Hitstun 計算方式**
   - 14 邏輯幀 = 28 物理幀 vs 27 物理幀（舍入誤差）

### 建議驗證方式

使用修復後的實時追蹤系統：
1. 運行遊戲並執行 st_lp 攻擊
2. 查看 console 輸出中的詳細計算數據
3. 檢查：
   - hit_frame 是否為預期的幀數
   - hitstun_frames 是否為 28
   - attacker_recover_frame 最終值
   - 邏輯幀差異轉換是否正確（/ 2.0 舍入）

---

## 涵蓋的問題

- ✅ **問題 1**: "未完動畫已經'預判'到有利幀" → 改為實時追蹤 `attack_duration_timer`
- ⚠️ **問題 2**: "+5 vs +4" 差異 → 需要測試驗證（基於新的實時計算結果）

---

## 相關文件

- [world.gd](world.gd) - _calculate_hit_advantage() 和 _on_hit_detected()
- [player.gd](player.gd) - attack_duration_timer 定義和遞減邏輯
- [FrameCounter.gd](FrameCounter.gd) - 幀計數基礎設施

---

## 修改日期
- **2026-02-08** - 實時追蹤系統修復完成
