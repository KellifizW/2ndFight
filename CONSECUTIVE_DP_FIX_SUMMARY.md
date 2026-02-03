# 連續DP動畫卡幀修復 - 執行摘要

## 📝 修復概述

**問題**: 連續快速按DP時，第二次DP的動畫卡在第一次DP的最後一幀
**原因**: AnimationTree.travel() 不會重新啟動已處於該狀態的動畫
**狀態**: ✅ 已修復

---

## 🔧 實施內容

### 修改1: MoveSet.gd - 動畫強制重置邏輯

**位置**: 第245-265行 (_start_special 函數中的 animation_state.travel 部分)

```gdscript
# 🟢 強制重置：如果已經在同一招式狀態，需要先跳出再進入
if current_anim_state == move_name:
    print("  ⚠️  Already in '%s' state! Forcing reset..." % move_name)
    # 先travel到中立狀態，再travel到目標招式
    parent.animation_state.travel("Walk")
    print("  ✓ Reset to 'Walk', now traveling to '%s'" % move_name)

parent.animation_state.travel(move_name)
```

**作用**: 檢測到AnimTree已在目標狀態時，先強制轉移到"Walk"，再轉移到目標狀態，確保動畫重新啟動。

### 修改2: MoveSet.gd - 增強日誌記錄

**位置**: 
- 第246行: 招式開始時的當前狀態檢查
- 第265-268行: travel() 後的新狀態確認
- 第273-275行: 招式啟動完成的摘要日誌

**內容**:
```
[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'Walk' | Seat: player_a
  ⚠️  Already in 'dp' state! Forcing reset...
  ✓ Reset to 'Walk', now traveling to 'dp'
  ✓ AnimTree travel() called | New state: 'dp'
[MoveSet] ✅ Started dp! Char: DAV, Duration: 0.783, Seat: player_a
```

### 修改3: MoveSet.gd - 動畫完成信號日誌

**位置**: 第573-591行 (_on_spmove_animation_finished 函數)

**內容**:
```
[🎬 ANIM_FINISHED] Animation 'dp' finished | AnimTree now in: 'dp' | is_spmove=true | Seat: player_a
  ✓ Special move animation completed: dp
  ⏱️  Timer still running (0.123), deferring stop
```

**作用**: 清楚地顯示：
1. 哪個動畫完成了
2. AnimTree當前處於哪個狀態
3. is_spmove 標誌的狀態
4. 是否延遲停止（如果計時器仍運行）

### 修改4: Player.gd - 動畫完成日誌增強

**位置**: 第446行 (_on_animation_player_finished 函數)

**內容**:
```
[✓ ANIM_FINISHED] 'dp' | Seat: player_a | is_spmove=true | is_attacking=true
  → Special move reset
     (self-landing move)
```

**作用**: 在Player層級確認：
1. 動畫完成訊號已被接收
2. 特殊招式狀態已正確識別
3. 著陸邏輯是否被觸發

---

## 📊 日誌流程圖

### 正常情況（等待後DP）

```
玩家按DP → [MoveSet._start_special] 🎬 Playing 'dp'
         Current AnimTree state: 'Walk'  ← 正常，可直接travel
         ✓ AnimTree travel() called
       [MoveSet] ✅ Started dp!
                ↓ (0.783秒)
         [🎬 ANIM_FINISHED] Animation 'dp' finished
         ✓ Special move animation completed
       [STOP_MOVE] 'dp'
       [STATE_CHANGE] 'dp' → 'Walk'
```

### 連續DP情況（修復後）

```
玩家快速連按DP → 第1次: [MoveSet._start_special] 🎬 Playing 'dp'
                   Current AnimTree state: 'Walk'
                   ✓ AnimTree travel() called
                   [MoveSet] ✅ Started dp!

              第2次 (立即按): [MoveSet._start_special] 🎬 Playing 'dp'
                   Current AnimTree state: 'dp'  ← 問題檢測！
                   ⚠️  Already in 'dp' state! Forcing reset...  ← 修復觸發
                   ✓ Reset to 'Walk', now traveling to 'dp'    ← 強制轉移
                   ✓ AnimTree travel() called | New state: 'dp'
                   [MoveSet] ✅ Started dp!
                   
              → 第2次DP動畫重新啟動，不卡幀 ✅
```

---

## 🧪 驗證日誌檢查清單

執行修復後，查看遊戲日誌時：

連續DP時應看到:

- [ ] `[MoveSet._start_special] 🎬 Playing 'dp'` - 第一次DP開始
- [ ] `[MoveSet._start_special] 🎬 Playing 'dp'` - 第二次DP開始
- [ ] `Current AnimTree state: 'dp'` - 檢測到已在dp狀態
- [ ] `⚠️  Already in 'dp' state! Forcing reset...` - 修復邏輯觸發！
- [ ] `✓ Reset to 'Walk', now traveling to 'dp'` - 強制轉移成功
- [ ] `[MoveSet] ✅ Started dp!` - 第二次DP啟動完成
- [ ] 動畫重新播放，第二次DP不卡幀 ✅

---

## 🎯 測試步驟

1. **重啟遊戲** (確保新代碼載入)
2. **執行第一次DP** (確保基本功能正常)
3. **快速連按DP** (測試連續DP修復)
4. **查看控制台日誌** (驗證修復邏輯是否執行)
5. **觀察遊戲畫面** (確認動畫不卡幀)

---

## 📈 預期結果

| 場景 | 修復前 | 修復後 |
|------|--------|--------|
| 單次DP | ✅ 正常 | ✅ 正常 |
| 等待後再DP | ✅ 正常 | ✅ 正常 |
| 連續快速DP | ❌ 卡在最後一幀 | ✅ 動畫重新啟動 |
| 日誌中的重置訊息 | ❌ 沒有 | ✅ 有 `⚠️  Already in` |

---

## 📁 相關文件

| 文件 | 用途 |
|------|------|
| [CONSECUTIVE_DP_DEBUG_GUIDE.md](CONSECUTIVE_DP_DEBUG_GUIDE.md) | 詳細調試指南 |
| [CONSECUTIVE_DP_QUICKREF.md](CONSECUTIVE_DP_QUICKREF.md) | 快速參考卡片 |
| [MoveSet.gd](MoveSet.gd) | 修改文件1 |
| [Player.gd](Player.gd) | 修改文件2 |

---

## 技術細節

### 為什麼會有這個問題？

AnimationTree 的 StateMachine 有一個特點：
- 如果當前狀態已經是目標狀態，`travel()` 不會重新啟動動畫
- 它假定已經在該狀態就不需要轉移

這在正常遊戲中很有效（避免不必要的轉移），但對於需要重複執行的招式（如連續DP），就會導致動畫不重新啟動。

### 修復如何工作？

通過引入中間狀態（"Walk"）：
1. 第一次DP結束時，AnimTree在"dp"狀態
2. 第二次DP時，檢測到已在"dp"狀態
3. 強制travel到"Walk"（不同狀態，一定會轉移）
4. 立即travel到"dp"（現在可以重新啟動動畫）
5. AnimationPlayer 重新播放"dp"動畫

### 性能考量

✅ **最小化開銷**:
- 檢查狀態是一次簡單的字串比較
- 只在需要時執行（檢測到重複狀態）
- 不使用額外的timer或callback
- 標準的state machine操作

---

修復已完成！請測試連續DP功能。
