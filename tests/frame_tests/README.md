# Frame Tests（Stage 0/1 安全網）

確定性物理幀測試框架。格鬥遊戲的邏輯建立在固定 120 FPS 物理 tick 上，
本框架用「腳本化輸入 → 斷言物理幀狀態/位置/血量」的方式鎖定遊戲行為，
是後續 Stage 1（統一時間域）、Stage 2（狀態機重構）的安全網。

## 執行

```bash
# 需要 Godot 4.7.x CLI（在 PATH 或用 GODOT_BIN 指定）
bash tests/frame_tests/run_frame_tests.sh
# 等同:
godot --headless --path . -s res://tests/frame_tests/run_tests.gd
```

退出碼: `0` = 全部通過，`1` = 有失敗，`2` = 載入/環境錯誤。

## 現有用例

| 用例 | 驗證內容 |
|---|---|
| test_01_world_spawn | 雙玩家生成、血量 100、面向、初始動畫 Walk |
| test_02_walk_movement | 走速 360 px/s（24 物理幀 = 72px）、按住不觸發 dash、放開即停 |
| test_03_jump_and_landing | 跳躍離地、apex、landing 狀態進出、is_jumping 清除 |
| test_04_ground_attack_frames | st_mp 啟動/動畫狀態/48 物理幀內結束、攻擊不誤傷 500px 外的 P2 |
| test_05_hit_damage_hitstun | st_mp 命中: 傷害 6.0、hitstun 48 物理幀、無 knockfly、恢復 |
| test_06_block_no_damage | 後退格擋: blockstun 32 物理幀、不扣血、恢復 |
| test_07_fireball_spawn | fireballM 在動畫 Call Method 時間點生成、spmove 狀態恢復 |
| test_08_frame_counter_determinism | FrameCounter 60 物理幀精確推進、邏輯幀換算 |
| test_09_debug_logger_default_off | Debug logger 預設關閉（Stage 0 新不變式） |
| test_10_hitstun_decrement | hitstop 期間凍結、之後 48 次逐幀遞減至 0 |
| test_11_landing_lock_frames | 無輸入著地狀態精確持續 23 物理幀 |
| test_12_dash_frames | 雙擊前衝精確持續 42 物理幀 |
| test_13_combo_requires_active_stun | 非 hitstun 內的下一次命中不可延續 combo counter |
| test_14_dash_window_expires | double-tap dash window 36 物理幀後必須清除 |
| test_15_vfx_preloader_character_vfx | 遊戲載入時預載/預熱 hit、block、spawnfire、火球 VFX |

## 設計規則（寫新用例時請遵守）

1. **狀態隔離**: 每個用例由 runner 生成全新 world，用例不需要清理。
2. **計時用物理幀**: `await_frames(n)` 等 n 個物理幀（120 FPS）。
   1 邏輯幀（60 FPS 幀數據）= 2 物理幀。不要用真實秒數斷言。
3. **輸入**: `tap(action)` / `hold(action, n)` 餵 `Input.action_*`。
   P2 的 action 帶 `_p2` 後綴（如 `move_right_p2`）。
4. **hitstop 影響**: 命中會觸發 `Engine.time_scale=0.02` 約 0.13 秒真實時間，
   物理幀推進變慢 → 命中相關用例的等待窗口要留足（現行用 300 幀上限）。
5. **lambda 限制**: `wait_until()` 的條件 lambda 只能 capture 局部變數，
   不能直接寫 `p1`（self 成員）。先 `var me = p1` 再傳 lambda。
6. **輸出**: 測試結果直接 `print`（不經過 Debug logger），確保 runner 輸出一定可見。
7. **禁止**: 用例中修改全局設定、載入其他場景、依賴用例執行順序。

## 新增用例步驟

1. 在 `cases/` 建 `test_NN_描述.gd`，明確 `extends "res://tests/frame_tests/frame_test_case.gd"`，實作 `run() -> bool`。
2. 把路徑加進 `run_tests.gd` 的 `CASES` 陣列（維持編號順序）。
3. 跑 `bash tests/frame_tests/run_frame_tests.sh` 確認全綠。

## 已知限制

- 方向指令宏（QCF、DP 等）的輸入模擬尚未納入（test_07 用直接呼叫代替）。
- 空中攻擊、dash、摔投、knockfly 完整流程的 frame 斷言留待後續階段擴充。
- 多段招式（100p）的每段 hitstun 斷言尚未納入。
