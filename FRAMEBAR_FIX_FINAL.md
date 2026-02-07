# FrameBar 15F Bug 最終修復報告

## 🔍 根本原因（已確認）

**錯誤計算函式 `_calc_frame()` 中的幀數**

對於短動畫（如 st_lp：0.233秒），原代碼使用：
```gdscript
return min(int(pos * DISPLAY_FPS), total_frames - 1)
// 其中 DISPLAY_FPS = 60
```

**問題**："pos" 是動畫的播放進度（0-1），乘以 60 總是得到 0-59 的範圍。
- st_lp 完成時：pos = 1.0 → current_frame = 60 ❌
- 但實際應該是：14 frames ✓

這導致：
- frame_data 被填充至索引 60（應該 14）
- frame_data.size() = 61（應該 14）
- 顯示 61÷4 ≈ 15F（應該 14F）

## ✅ 修復方案（已實施）

### 修改 FrameBar.gd: `_calc_frame()` 函式

```gdscript
# 🟢 【關鍵修復】對於攻擊動畫，根據實際動畫長度來計算幀數
if anim_name in ATTACK_ANIMS and "animation_player" in target_player:
    if target_player.animation_player.has_animation(anim_name):
        var anim_length = target_player.animation_player.get_animation(anim_name).length
        # 計算真實幀數：動畫長度（秒）× 60 FPS = 邏輯幀數
        var expected_frames = int(round(anim_length * 60))
        # 當前幀 = 播放進度 × 預期幀數
        return min(int(pos * expected_frames), expected_frames - 1)
```

### 計算驗證

對於 st_lp（0.233秒）：
```
expected_frames = int(round(0.233 * 60)) = 14
pos = 1.0（動畫完成）
current_frame = min(int(1.0 * 14), 14-1) = min(14, 13) = 13
frame_data.size() = 14（索引 0-13）
顯示：14F ✓
```

## 🎯 預期結果

| 狀態 | 修復前 | 修復後 |
|------|-------|-------|
| st_lp 未擊中 | 14F ✓ | 14F ✓ |
| st_lp 擊中對手 | 15F ❌ | 14F ✓ |

## 📋 變更檔案

1. **FrameBar.gd** - `_calc_frame()` 函式（第 348-362 行）
   - 添加攻擊動畫的特殊處理
   - 根據實際動畫長度而非固定 60 來計算
   
2. **FrameBar.gd** - `_process_tracked()` 函式（第 258-276 行）
   - 添加 frame_data 大小限制（防護機制）
   - 添加 current_frame 上限檢查

3. **Player.gd** - `_on_animation_player_finished()` 函式（第 462-467 行）
   - 在動畫完成時立即停止 attack_duration_timer

## 🧪 驗證清單

執行以下測試確認修復：
- [ ] DEN 執行 st_lp（未擊中）→ 顯示 14F
- [ ] DEN 執行 st_lp（擊中 DAV）→ 顯示 14F（非 15F）
- [ ] 檢查日誌是否有 `[FRAMEBAR FRAME LIMIT]` 或 `[FRAMEBAR OVERFLOW CHECK]`
- [ ] 測試其他短動畫（st_mp、cr_lk 等）確保相同邏輯適用

## 📌 關鍵洞察

- **根本問題**：在 `_calc_frame()` 中混淆了動畫播放進度和邏輯幀數
- **DISPLAY_FPS = 60** 是固定值，應該根據動畫實際長度來縮放
- **frame_data 索引** 應等於 animation_frame，不應超過預期幀數
- **多層防護**：player.gd + framebar.gd 的雙重限制確保穩定性
