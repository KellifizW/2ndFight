# AdvantageLabel +5 vs +4 根本原因分析與修復

## 問題分析

### 症狀
用戶實測：DEN st_lp 應該比 DAV 快 **4幀** 恢復，但系統顯示 **+5幀**

### 根本原因（已找到）

系統使用了**「當前幀 + 剩餘timer」** 的計算方式，但在hit stop期間會出現誤差：

**日誌數據：**
```
攻擊開始幀: 221
攻擊時長: 26 物理幀
被擊幀: 228（已進行 7 幀）
當前幀（hit時）: 228
attack_duration_timer（hit時）: 18

系統計算（錯誤）：
- DEN恢復幀 = 228 + 18 = 246
- DAV恢復幀 = 228 + 28 = 256
- 差異 = 10 物理幀 = 5 邏輯幀 ❌

正確計算：
- DEN恢復幀 = 221 + 26 = 247 物理幀
- DAV恢復幀 = 228 + 28 = 256 物理幀
- 差異 = 9 物理幀 = 4.5 邏輯幀 = 4 邏輯幀（向下舍入）✅
```

### 為什麼會誤差？

**Hit stop期間的問題：**
1. FrameCounter 被凍結（不遞增）
2. attack_duration_timer 也被凍結（不遞減）
3. 當advantage在hit stop期間計算時，current_frame = 228，timer = 18
4. 計算出 228 + 18 = 246（**錯誤**）
5. 實際上DEN應該在 221 + 26 = 247 才能恢復

**正確的做法：**
- 攻擊本身的持續時間是**確定的、不變的**
- 不應該用「當前幀 + timer」，而應該用「開始幀 + 完整時長」
- 這樣不受hit stop凍結的影響

---

## 修復方案

### 修改 1: world.gd - `_on_hit_detected()` 函數
**目的**: 記錄攻擊的完整持續時間

```gdscript
# 記錄攻擊開始幀
if "attack_start_frame" in attacker:
    attack_start_frame = attacker.attack_start_frame

# 記錄攻擊完整時長（從動畫讀取）
if anim_player and anim_player.has_animation(attack_type):
    var anim_length = anim_player.get_animation(attack_type).length
    attack_duration_frames = int(round(anim_length * frame_counter.PHYSICS_FPS))
    # 結果: attack_duration_frames = 26 物理幀
```

### 修改 2: world.gd - `_calculate_hit_advantage()` 函數

#### 2a. Attacker恢復幀計算（第 315-339 行）

```gdscript
# ❌ 舊方式（hit stop會出錯）
attacker_recover_frame = current_frame + attack_duration_timer

# ✅ 新方式（準確、不受hit stop影響）
attacker_recover_frame = attack_start_frame + attack_duration_frames
```

#### 2b. 舍入方式修改（第 343-351 行）

```gdscript
# ❌ 舊方式
var logic_advantage_frames = int(round(float(physics_advantage_frames) / 2.0))
# 9 / 2 = 4.5 → round()為 5 ❌

# ✅ 新方式
var logic_advantage_frames = int(float(physics_advantage_frames) / 2.0)
# 9 / 2 = 4.5 → int()為 4 ✅
```

---

## 計算驗證

### 根據用戶提供的日誌

| 項目 | 值 | 說明 |
|------|---|------|
| 攻擊開始幀 | 221 | 來自[EXECUTE_ATTACK] |
| 攻擊時長 | 26 物理幀 | 0.217s × 120 FPS |
| 被擊幀 | 228 | frame_counter.get_current_frame() |
| DEN恢復幀 | 221 + 26 = **247** | 攻擊開始 + 時長 |
| DAV恢復幀 | 228 + 28 = **256** | 被擊 + hitstun |
| **差異** | **9 物理幀** | 256 - 247 |
| **邏輯幀** | **4.5 → 4** | 9 / 2 = 4.5，int()為4 |

### 修復後的console輸出

```
[HIT DETECTION] 攻擊時長: 0.217 秒 = 13 邏輯幀 = 26 物理幀 (st_lp)
[HIT DETECTION] 被擊幀數: 228 物理幀 | 攻擊開始幀: 221 | 攻擊時長: 26 物理幀

[ADVANTAGE CALC] Attacker 恢復時間計算（基於動畫時長）：
[ADVANTAGE CALC]   - 攻擊開始幀: 221 物理幀
[ADVANTAGE CALC]   - 攻擊完整時長: 26 物理幀
[ADVANTAGE CALC]   - 攻擊恢復幀: 247 物理幀 (221 + 26)

[ADVANTAGE CALC] Target 恢復時間計算：
[ADVANTAGE CALC]   - 被擊幀: 228 物理幀
[ADVANTAGE CALC]   - hitstun_frames: 28 物理幀
[ADVANTAGE CALC]   - 目標恢復幀: 256 物理幀

[ADVANTAGE CALC] 最終優勢計算結果：
[ADVANTAGE CALC]   - Attacker恢復幀: 247 物理幀 (123.5 邏輯幀)
[ADVANTAGE CALC]   - Target恢復幀: 256 物理幀 (128.0 邏輯幀)
[ADVANTAGE CALC]   - 物理幀差異: 9 (120 FPS)
[ADVANTAGE CALC]   - 邏輯幀差異: 4 (60 FPS) [9 / 2.0 = 4.50 → 向下舍入為 4]
[ADVANTAGE CALC]   - 秒數優勢: 0.066667 秒 (4 / 60.0)

[HIT ADVANTAGE] ✓ 優勢計算完成 - DEN: +4F ✅
```

---

## 格鬥遊戲設計背景

在格鬥遊戲中，**frame advantage** 是攻擊後能夠採取行動的時間優勢定義。

當advantage = +4F時：
- 攻擊者在第 0 幀可以行動
- 防守者在第 4 幀才能行動
- 攻擊者領先 4 幀

這正是用戶實測的結果。

---

## 涉及文件修改

- `world.gd`:
  - `_on_hit_detected()` - 記錄 attack_start_frame 和 attack_duration_frames
  - `_calculate_hit_advantage()` - 使用「開始幀 + 時長」而非「當前幀 + 剩餘timer」
  - 舍入方式: `round()` → `int()`

---

## 修改日期
- **2026-02-08** - 根本原因分析與修復完成
