# 連續DP動畫卡幀問題 - 調試指南

## 問題描述

- ✅ **第一次DP**: 動畫正常播放到結束
- ❌ **連續快速DP** (立即按第二次): 第二次DP的動畫卡在第一次DP的最後一幀
- ✅ **等待後再DP**: 分開執行時正常

**根本原因**: AnimationTree 在連續DP時，如果 `animation_state` 已經處於 "dp" 狀態，`travel("dp")` 不會重新啟動動畫。

---

## 修復方案

已在 MoveSet.gd 中添加 **動畫強制重置邏輯**：

```gdscript
# 🟢 強制重置：如果已經在同一招式狀態，需要先跳出再進入
if current_anim_state == move_name:
    print("  ⚠️  Already in '%s' state! Forcing reset..." % move_name)
    # 先travel到中立狀態，再travel到目標招式
    parent.animation_state.travel("Walk")
    print("  ✓ Reset to 'Walk', now traveling to '%s'" % move_name)

parent.animation_state.travel(move_name)
```

**工作流程**:
```
連續DP時的狀態轉換：
第一次DP:  Start → Walk → dp (播放中) → dp (完成)
第二次DP:  dp (卡住) 
           ↓ (新修復)
           dp → Walk (強制中間狀態) → dp (重新啟動)
```

---

## 新增調試日誌

已添加4組新的調試日誌來追踪問題：

### 1. **招式開始時的動畫狀態檢查** (MoveSet._start_special)

```
[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'Walk' | Seat: player_a
  ⚠️  Already in 'dp' state! Forcing reset...
  ✓ Reset to 'Walk', now traveling to 'dp'
  ✓ AnimTree travel() called | New state: 'dp'

[MoveSet] ✅ Started dp! Char: DAV, Duration: 0.783, Seat: player_a
```

**解讀**:
- `Current AnimTree state: 'Walk'` → 正常，可以直接travel到dp
- `Current AnimTree state: 'dp'` → 問題！第二次DP時已經在dp狀態
- `Already in 'dp' state! Forcing reset...` → 修復啟動，強制重置

### 2. **動畫完成信號** (MoveSet._on_spmove_animation_finished)

```
[🎬 ANIM_FINISHED] Animation 'dp' finished | AnimTree now in: 'dp' | is_spmove=true | Seat: player_a
  ✓ Special move animation completed: dp
  ⏱️  Timer still running (0.123), deferring stop

[STOP_MOVE] 'dp' | Seat: player_a
```

**解讀**:
- `AnimTree now in: 'dp'` → AnimTree仍處於dp狀態（正常，會在下一幀轉移出去）
- `Timer still running` → 動畫完成但物理計時器還未結束，延遲stop
- `[STOP_MOVE]` → 當所有計時器完成時，正式停止招式

### 3. **Player層級的動畫完成** (Player._on_animation_player_finished)

```
[✓ ANIM_FINISHED] 'dp' | Seat: player_a | is_spmove=true | is_attacking=true
  → Special move reset
     (self-landing move)
```

**解讀**:
- 確認DP被識別為自帶著地的招式
- 調用特殊招式重置邏輯

### 4. **動畫狀態轉換** (AnimationManager.update_animation_state)

```
[STATE_CHANGE] player_a: 'dp' → 'Walk' (spmove=false)
```

**解讀**:
- DP動畫完成後，AnimationTree轉移到Walk狀態
- `spmove=false` 表示特殊招式標誌已清除

---

## 測試方法

### 測試1: 正常DP（應該成功）

```
步驟:
1. 執行DP
2. 等待DP完全播放並著地 (~1秒)
3. 再執行一次DP

預期日誌序列:
[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'Walk' | Seat: player_a
  ✓ AnimTree travel() called | New state: 'dp'
[MoveSet] ✅ Started dp! ...
[🎬 ANIM_FINISHED] Animation 'dp' finished | AnimTree now in: 'dp'
  ✓ Special move animation completed: dp
[STOP_MOVE] 'dp'
[STATE_CHANGE] player_a: 'dp' → 'Walk'
```

### 測試2: 連續DP（修復前會卡，修復後應正常）

```
步驟:
1. 快速連續執行DP (立即按第二次，不等第一次完成)

預期日誌序列 (修復後):
[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'Walk' | Seat: player_a
[MoveSet] ✅ Started dp! ...

[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'dp' | Seat: player_a
  ⚠️  Already in 'dp' state! Forcing reset...
  ✓ Reset to 'Walk', now traveling to 'dp'  ← 關鍵！強制重置
  ✓ AnimTree travel() called | New state: 'dp'
[MoveSet] ✅ Started dp! ...
```

### 日誌中的關鍵指標

| 日誌 | 含義 | 正常? |
|------|------|------|
| `[MoveSet._start_special] 🎬` | DP招式開始 | ✅ 應該出現 |
| `Current AnimTree state: 'Walk'` | AnimTree已轉出dp狀態 | ✅ 好的（可直接travel） |
| `Current AnimTree state: 'dp'` | AnimTree仍在dp狀態 | ⚠️ 需要強制重置 |
| `⚠️  Already in 'dp' state!` | 檢測到重複狀態 | ✅ 表示修復已啟動 |
| `✓ Reset to 'Walk'` | 強制重置成功 | ✅ 修復工作中 |
| `[🎬 ANIM_FINISHED]` | 動畫完成信號 | ✅ 應該出現 |
| `[STOP_MOVE]` | 招式正式停止 | ✅ 應該出現在ANIM_FINISHED後 |
| `[STATE_CHANGE] 'dp' → 'Walk'` | AnimTree最終轉移 | ✅ 應該出現 |

---

## 如果問題仍未解決

### 情況A: 連續DP仍然卡幀，但沒有看到`⚠️  Already in 'dp' state!`

**可能原因**: AnimTree在DP完成時沒有轉移到其他狀態

**檢查**:
1. 查看是否有 `[STATE_CHANGE] 'dp' → 'Walk'` 日誌
2. 如果沒有，可能是 `_compute_target_state()` 的邏輯問題
3. 查看是否有其他錯誤日誌

### 情況B: 看到強制重置日誌，但動畫仍卡在最後一幀

**可能原因**: 
- AnimationPlayer 的 animation_finished 信號沒有被正確觸發
- 第一次DP的計時器未正確清除

**檢查**:
1. 確認是否有 `[🎬 ANIM_FINISHED] Animation 'dp' finished` 日誌
2. 如果沒有，表示 AnimationPlayer.animation_finished 信號未觸發
3. 檢查 Player.gd 的 animation_tree 連接是否正確

### 情況C: 第一次DP就有問題

**檢查**:
1. DP動畫長度是否設置正確 (應為 0.783秒 = 47幀)
2. AnimationPlayer 中是否真的有 "dp" 動畫
3. 查看 `[MoveSet._start_special] WARNING` 日誌

---

## 代碼位置

| 功能 | 文件 | 行號 |
|------|------|------|
| **動畫強制重置邏輯** | MoveSet.gd | 246-265 |
| **招式開始日誌** | MoveSet.gd | 245, 265-268 |
| **動畫完成處理** | MoveSet.gd | 573-591 |
| **Player層級日誌** | Player.gd | 446-477 |

---

## 預期修復結果

執行修復後：

```
連續DP時:
✅ 第一次DP: 動畫正常播放 → 著地 → 恢復待機
✅ 第二次DP: 動畫重新啟動，不卡在上一次的最後一幀
✅ 第三次DP: 持續正常運作
```

**性能**: 修復邏輯只在需要時執行（檢測到重複狀態時），不影響正常DP的執行效率。

---

修改已完成！請重新啟動遊戲進行測試。
