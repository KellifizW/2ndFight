# 🔴 空中 Pushbox 失效 - 快速診斷卡

## ⚡ 30秒快速啟用調試

1. **World 場景** → 選擇 **PushManager**
2. **Inspector** → **Debug Settings** 
3. ✅ **Debug Air Pushbox**

按 **F5** 執行遊戲

## 📊 預期輸出

### ✅ 推送正常（地面或空中）
```
[AIR_Y_OVERLAP_OK] overlap_y=150000 → will apply push | final_x: Player_A->XXX, Player_B->YYY
```
角色X位置改變 = 推送成功！

### ❌ 推送失敗（空中卡住）
```
[AIR_CRITICAL_BUG] Y軸檢查失敗！overlap_y=0 ≤ 0 → 推送被跳過！
[AIR_PUSHBOX_FAILURE_DETAIL]
  Y軸深度計算: depth.y=0 (失敗！應 > 0)
```
這就是問題所在！

## 🎯 根本原因

根據調試日誌，檢查以下內容：

| 日誌提示 | 可能原因 | 檢查項 |
|---------|--------|------|
| `overlap_y=0` | Y軸邊界計算誤差 | Player.colbox_half_height 值 |
| `dist_y > sum_half_y` | 碰撞箱太小 | Y 高度是否在跳躍時改變 |
| 沒有任何日誌 | skip_pushbox 被激活 | 檢查 Fighter.gd `skip_pushbox` 標誌 |
| `x_valid=false` | X軸距離太遠 | 推動倍數設定 |

## 📋 調試檢查清單

- [ ] 兩個角色都跳起來（都在空中）
- [ ] 讓他們相靠近（應該推開但沒推開）
- [ ] **Output 終端**看到 `[AIR_` 開頭的日誌了嗎？
  - ❌ 沒看到 → 檢查 `debug_air_pushbox` 為 true
  - 看到 `[AIR_CRITICAL_BUG]` → Y軸計算問題
  - 看到 `[AIR_NO_OVERLAP_DETECTED]` → 距離太遠或碰撞箱太小

## 🔧 臨時修復方案

如果確認是 `overlap_y=0` 導致的，可在 [PushManager.gd](../scripts/core/PushManager.gd) L494 試試：

```gdscript
# 舊（嚴格要求）
if overlap_fixed_y > 0:

# 新（容許舍入誤差）
if overlap_fixed_y > -1000:  # 容許 ±1 像素以內的誤差
```

## 📞 提交診斷

如果問題仍未解決，請提交：
1. **完整日誌** (複製 `[AIR_CRITICAL_BUG]` 開始的所有行)
2. **複現步驟** (哪些輸入導致失效)
3. **角色設定** (colbox_half_height 的值)

---

**詳細指南**: [AIR_PUSHBOX_DEBUG_GUIDE.md](AIR_PUSHBOX_DEBUG_GUIDE.md)  
**最後更新**: 2026-02-26
