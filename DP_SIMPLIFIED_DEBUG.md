# 🔍 簡化版 DP 日誌分析

## 快速檢查清單

執行 DP 後，查看輸出窗口的以下日誌順序：

### ✅ **正常流程（應該看到）**

```
[MoveSet._start_special] Starting move: dp (player: DAV)
[MoveSet._start_special] Animation 'dp' found, length: 0.783 seconds
[MoveSet._start_special] Playing via AnimationTree.travel(): dp
[MoveSet] Started dp! Character: DAV, Duration: 0.783

[播放中... 持續進行 _physics_process ...]

✓ [ANIM_FINISHED] 'dp' | Seat: player_a          ← 關鍵！必須看到此行
  → Special move reset
     (self-landing move)

[STATE_CHANGE] player_a: 'dp' → 'Walk' (spmove=false)

[RESET_SPECIAL] Move 'dp' | Seat: player_a
[STOP_MOVE] 'dp' | Seat: player_a

[STATE_CHANGE] player_a: 'Walk' → 'Walk' (spmove=false)
```

## 🔴 **異常情況（目前看到）**

根據你提供的日誌：

```
✗ 完全沒有 [✓ ANIM_FINISHED] 的日誌！
  這表示 animation_player.animation_finished 信號未被觸發

⚠️ 取而代之的是：
  - 持續輸出數百行 [ANIM_UPDATE] 和 [COMPUTE]
  - 直到 ~0.783 秒後才呼叫 [STOP_MOVE]
  - 這說明某個地方在強制停止動畫，而不是讓動畫自然完成
```

## 🎯 **問題診斷**

| 症狀 | 原因 | 檢查 |
|------|------|------|
| ✗ 沒有 `[✓ ANIM_FINISHED]` | `animation_finished` 信號未觸發 | 檢查 AnimationPlayer 連接 |
| ✓ 有 `[STOP_MOVE]` | 某個超時機制強制停止了 | 檢查 MoveSet.process_move() |
| ✓ 多次 `[STATE_CHANGE]` dp→Walk | 動畫狀態在改變但 is_spmove 未清除 | 已在 _on_animation_player_finished 中修正 |

## 🔧 **下一步**

重新運行遊戲，查看現在是否出現 `[✓ ANIM_FINISHED]` 日誌。

### 如果仍未出現：

可能是 AnimationPlayer 的 `animation_finished` 信號連接問題。檢查：
1. [Player.gd](Player.gd#L160) 是否正確連接了信號？
2. AnimationPlayer 是否真的在播放 DP 動畫？

### 如果已出現：

那麼問題已解決，DP 應該能正常完成了。

## 📝 **日誌簡化說明**

刪除了冗長的 BEFORE/AFTER 和 DURING 日誌，改為：
- `[✓ ANIM_FINISHED]` - 動畫完成信號
- `[RESET_SPECIAL]` - 特殊狀態重置
- `[STOP_MOVE]` - 招式停止
- `[STATE_CHANGE]` - 動畫狀態轉換（僅輸出有變化時）

這樣輸出更清晰，容易追蹤問題。
