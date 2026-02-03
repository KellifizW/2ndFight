# 連續DP動畫卡幀 - 快速修復參考

## 🔧 修復內容

### 問題
連續快速按DP時，第二次DP的動畫卡在第一次DP的最後一幀。

### 根本原因
AnimationTree.travel() 不會重新啟動已經處於該狀態的動畫。

### 解決方案
在 `_start_special()` 中添加**強制重置邏輯**：
- 檢測當前AnimTree狀態
- 如果已在目標狀態，先travel到"Walk"（中間狀態）
- 然後travel到目標狀態（"dp"）
- 這樣確保動畫被重新啟動

---

## 📊 新增日誌位置

| 位置 | 日誌前綴 | 用途 |
|------|--------|------|
| **MoveSet._start_special** | `[MoveSet._start_special] 🎬` | 檢測動畫重複狀態 |
| **MoveSet._on_spmove_animation_finished** | `[🎬 ANIM_FINISHED]` | 追踪動畫完成 |
| **Player._on_animation_player_finished** | `[✓ ANIM_FINISHED]` | 確認Player層級完成 |

---

## 🧪 關鍵日誌模式

### ✅ 正常（連續DP後應看到）

```
[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'dp' | Seat: player_a
  ⚠️  Already in 'dp' state! Forcing reset...
  ✓ Reset to 'Walk', now traveling to 'dp'
  ✓ AnimTree travel() called | New state: 'dp'
[MoveSet] ✅ Started dp! ...
```

### ❌ 異常（未看到強制重置）

```
[MoveSet._start_special] 🎬 Playing 'dp' | Current AnimTree state: 'dp' | Seat: player_a
[MoveSet] ✅ Started dp! ...
  (沒有"Already in"或"Reset to"的日誌)
```

---

## 📋 測試檢查清單

- [ ] 第一次DP: 動畫正常播放並著地
- [ ] 等待後DP: 動畫正常（對照組）
- [ ] 連續DP (快速): 第二次DP動畫重新啟動，不卡幀
- [ ] 查看日誌: 連續DP時是否有 `⚠️  Already in 'dp' state!`
- [ ] 查看日誌: 每次DP都有 `[🎬 ANIM_FINISHED]`
- [ ] 測試其他招式: 確保powerkk/hdk/fireball也正常

---

## 修改文件清單

| 文件 | 修改內容 |
|------|---------|
| **MoveSet.gd** | 添加動畫強制重置邏輯 + 詳細日誌 |
| **Player.gd** | 增強_on_animation_player_finished日誌 |

---

## 性能影響

✅ **極小**: 修復邏輯只在檢測到重複狀態時執行
✅ **無額外開銷**: 不使用timer或callback，直接state檢查

---

如有問題，參考 [CONSECUTIVE_DP_DEBUG_GUIDE.md](CONSECUTIVE_DP_DEBUG_GUIDE.md) 的詳細說明。
