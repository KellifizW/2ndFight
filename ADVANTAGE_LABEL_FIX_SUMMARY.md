# AdvantageLabel 修復總結

## 修復內容

### 問題 1: "未完動畫已經'預判'到有利幀"
**原因**: 使用靜態的 `attack_duration_frames`（完整動畫時長）預先計算優勢
**解決**: 改為實時使用 `attack_duration_timer`（每幀遞減）

### 問題 2: Advantage 顯示為 +5 而非 +4
**說明**: 由於新系統實時追蹤，console 會輸出詳細計算數據，便於驗證是否確實應該是 +4

---

## 修改清單

### world.gd

#### 1. `_calculate_hit_advantage()` 函數（第 315-355 行）
**改動**: 攻擊者恢復時間計算

```gdscript
# 舊邏輯（預判式）
attacker_recover_frame = attack_start_frame + attack_duration_frames

# 新邏輯（實時追蹤）
if is_still_attacking and timer_remaining > 0:
    attacker_recover_frame = current_frame + timer_remaining  # 每幀更新
else:
    attacker_recover_frame = frame_counter.get_current_frame()  # 攻擊結束確認
```

**優勢**:
- ✅ 實時更新，不再"預判"
- ✅ 基於當前 `attack_duration_timer` 值

#### 2. `_on_hit_detected()` 函數（第 704-730 行）
**改動**: 簡化被擊者資訊記錄，移除不必要的 attack_duration_frames 預先計算

**舊邏輯**:
```gdscript
# 在 hit 時預先計算攻擊時長
attack_duration_frames = int(round(anim_length * frame_counter.PHYSICS_FPS))
```

**新邏輯**:
```gdscript
# 移除預先計算，改由 _calculate_hit_advantage() 直接使用 timer
print("[HIT DETECTION] ...")  # 只記錄被擊幀號和 hitstun 幀數
```

---

## 驗證方式

### Console 輸出檢查
執行 st_lp 攻擊後，查看 Godot console 是否輸出：

```
[HIT DETECTION] 被擊者 Player_B 進入 28 物理幀 hitstun (14.0 邏輯幀)
[HIT DETECTION] 被擊幀數: XXX 物理幀 (YYY 邏輯幀) | 攻擊者將在 _calculate_hit_advantage() 中實時評估恢復時間

[ADVANTAGE CALC] Attacker 恢復時間計算（實時追蹤）：
[ADVANTAGE CALC]   - 當前物理幀: NNN
[ADVANTAGE CALC]   - attack_duration_timer: ZZZ 物理幀 (仍在進行)
[ADVANTAGE CALC]   - 預期恢復幀: NNN + ZZZ

[ADVANTAGE CALC] 最終優勢計算結果：
[ADVANTAGE CALC]   - Attacker 恢復幀: AAA 物理幀
[ADVANTAGE CALC]   - Target 恢復幀: BBB 物理幀
[ADVANTAGE CALC]   - 邏輯幀差異: (BBB - AAA) / 2.0
```

### 實時更新驗證
- **修復前**: Advantage 在動畫進行中保持靜態值
- **修復後**: Advantage 在動畫進行中會隨 timer 遞減而計算變化，直到動畫結束

---

## 後續測試（用戶需執行）

1. 錄製 DEN st_lp 的 Advantage 數值變化過程
2. 確認是否是實時更新（而非靜態）
3. 確認最終數值是 +4 還是 +5
4. 提供 console 輸出中的具體數值用於驗證計算邏輯

---

## 相關文檔
- [ADVANTAGE_LABEL_FIX.md](./ADVANTAGE_LABEL_FIX.md) - 詳細技術分析
- [world.gd](./world.gd) - 實現代碼

**修復日期**: 2026-02-08
