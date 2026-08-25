# 2ndFight 重構與測試計劃
> 建立: 2026-08-21 | 最後更新: 2026-08-21
> 狀態圖例: ✅ 已完成(已併入 main) | 🔄 進行中 | ⏳ 待開始
> 目前基準: `main` (Godot 4.7.2, physics 120 FPS)
>
> 本文檔是整個重構計劃的單一入口: 診斷依據、各階段目標與方法、
> 測試方法、架構守則、風險清單。每完成一個階段, 更新對應狀態。
---
## 1. 診斷摘要: 為什麼要重構
本專案是 AI 迭代堆疊的產物(單一 squash commit 歷史、每輪修復加補丁而非重構)。
功能完整、遊戲可玩, 但維護成本已超過收益: 加一個招式需要動 8+ 處、
每處都要小心不破壞其他招式的隱性依賴。
### 1.1 對照標準 frame 制式格鬥遊戲架構
| 維度 | 業界標準 | 重構前現狀 | 狀態 |
|---|---|---|---|
| 時間系統 | 單一固定 tick, 整數幀 | **四時間域並存**(秒/60FPS 邏輯幀/120FPS 物理幀/FrameCounter), 62 處分散轉換 | Stage 1 |
| 角色狀態 | 每 fighter 一個顯式狀態機 | ~34 個 bool 旗標笛卡爾積 + 順序敏感的 250 行 `_physics_process` | Stage 2 |
| 招式數據 | 單一 frame data 表 | 三個真相來源(AttackData.tres / 場景內嵌 smd_* / 硬編碼 fallback), 數值互相矛盾 | Stage 3 |
| hitbox 驅動 | frame data 的 active 窗口 | 動畫 Call Method/軌道開關(與數據分離) | Stage 3 |
| 輸入系統 | buffer → 結構化輸入幀 → 單一映射 | 三段各自偵測(InputManager/PlayerController/MoveSet) | Stage 4 |
| 測試 | 確定性 frame 測試 | 無(舊 "tests" 是 grep 源碼字符串) | ✅ Stage 0 |
| 日誌 | 分級/可關 | 687 個 print, 部分每幀輸出 | ✅ Stage 0 |
| 確定性 | 定點 + 固定 timestep | 定點物理(好), 但 hitstop 用 `Engine.time_scale`, 積分依賴 delta | 保留現有 hitstop 方式(已可工作), Stage 1 檢視 |
### 1.2 值得保留的好設計(不要動)
- 定點整數物理 (`SIMULATION_SCALE=1000`, `Vector2i`) — 對回放/線上对战正確
- 招式數據 .tres 化的方向(Stage 3 是收攏它, 不是丟掉它)
- `InputBuffer` 結構(Stage 4 保留核心)
- 120Hz 物理 + 60FPS 幀數據的雙層思路(Stage 1 是修正其執行, 不是廢掉)
- hitstop 用「跳過幀遞減」實現凍結的思路
- Area2D hitbox/hurtbox 碰撞結構
---
## 2. 總體原則(鐵律)
1. **不重寫**。分階段重構, 每階段結束遊戲可玩、測試全綠。
2. **行為一幀不變**(除非有意變更並記錄): 用 frame 測試 + `docs/systems/FRAME_DATA_TABLE.md`
   比對驗證, 不用肉眼。
3. **安全網優先**: 任何大改之前, 測試必須已存在且全綠。
4. **一輪一個關注點**: commit 寫清楚改了哪個不變式。
5. **架構守則**(已寫入 `.github/copilot-instructions.md`, 對 AI 與人類同等生效):
   1. 遊戲代碼禁止直接 `print()`, 走 `Debug.log/vlog`
   2. 新增計時器一律 **int 物理幀**; 禁止新增秒數遊戲邏輯計時器
   3. 禁止新增 bool 狀態旗標(Stage 2 前)
   4. 改戰鬥邏輯前後 frame tests 必須全綠
   5. 招式數據單一真相來源(Stage 3 前不得新增第三來源)
   6. 修 bug 禁止 print-observe 迭代; 先確定性重現; 不新增 `XXX_FIX_SUMMARY.md`
   7. 一輪 commit 一個關注點
---
## 3. 階段總覽
| 階段 | 目標 | 狀態 | 估算 |
|---|---|---|---|
| Stage 0 | 止血 + 安全網(DebugLogger / frame 測試 / frame data 表 / 守則) | ✅ 已併入 main | — |
| Stage 1 | 統一時間域(全遊戲邏輯 = int 物理幀) | 🔄 進行中(安全網 16 用例; landing family 已遷移) | 1~2 週末 |
| Stage 2 | 顯式狀態機(消除 34 旗標) | ⏳ | 2~4 週末 |
| Stage 3 | FrameData 收攏 + 數據問題清理 | ⏳ | 1~2 週末 |
| Stage 4 | 輸入系統收斂(單一 ActionMapper) | ⏳ | 1~2 週末 |
| Stage 5 | 清理(死代碼/文檔/tscn 拆分/CI) | ⏳ | 1 週末 |
---
## 4. Stage 0: 止血 + 安全網 ✅
### 4.1 交付內容(已在 main)
1. **DebugLogger autoload** (`scripts/core/DebugLogger.gd`, 名 `Debug`, 預設關)
   - `Debug.log("[TAG] ...")` 事件型; `Debug.vlog(...)` 每幀級(需 `verbose=true`)
   - 遊戲中 **Ctrl+D** 切換; `Debug.tags` 過濾
   - 681 處遊戲代碼 `print()` 已遷移; 13 處每幀日誌改 `vlog`
2. **Frame 測試框架** (`tests/frame_tests/`, 9 個用例) — 詳見 §10
3. **Frame Data 表** (`docs/systems/FRAME_DATA_TABLE.md`) — DAV/DEN/WOO 全招式
   total/startup/active/recovery + damage/hitstun/blockstun, 重構比對基準
4. **架構守則** (`.github/copilot-instructions.md` 頂部 7 條)
### 4.2 Stage 0 後的修正(已併入 main)
使用者在 Godot 編輯器回報的編譯錯誤與重審發現的隱患:
| # | 問題 | 修正 |
|---|---|---|
| 1 | `...args: Variant` 編譯錯(GDScript 變參數必須 `Array`) | → `...args: Array` |
| 2 | 批量替換誤把 logger 自己的 `print` 改成 `Debug.log` → **無限遞迴** | logger 內部改回原生 `print` |
| 3 | `hold/tap/wait_until` 與 9 個用例共 20+ 處 coroutine 呼叫漏 `await` | 補 `await`(test_08 漏了會必敗) |
| 4 | test_03 apex 用定點單位(550000)比較 px 值(540) → 必敗 | `/SIM_SCALE` 換 px, 窗口 60→90 幀 |
| 5 | test_07 呼叫參數內多行 lambda 的解析風險 | lambda 改存成變數再傳入 |
### 4.3 環境變動(2026-08-21)
- 專案已升級 **Godot 4.7.2**(`config/features = "4.7"`), main 歷史重壓為單一大 commit。
- 測試執行需改用 4.7.2 CLI(4.6 也可, 但與 main 一致用 4.7.2)。
### 4.4 Stage 0 收尾動作
- [x] 2026-08-23 在本地 Godot 4.7.2 跑 frame tests, 確認 **9/9 PASS**
- [x] 修正 4.7.2 headless runner 相容性: 測試改用明確 base script path,
  `failure_report()` 移除不支援的 list comprehension
- [x] 進入 Stage 1
---
## 5. Stage 1: 統一時間域 ⏳
**問題**: 遊戲邏輯混用四個時間域, 62 處 `*2`/`*120`/`/2.0` 分散轉換, 是反覆出 bug 的根源
(代碼中「🔴【關鍵修復】…需轉換為 ×120」類注释即證據)。
**目標不變式**:
- 遊戲邏輯的計時器 **全部是 int 物理幀**(`_physics_process` 每幀 `-1`)
- 幀數據(hitstun/blockstun/duration)以 60FPS 邏輯幀存放於資源, **載入時一次性 ×2** 轉物理幀
- 秒數只允許出現在: UI、攝影機、BGM、tween 視覺效果
- 全代碼只剩**一個** 邏輯幀↔物理幀 轉換點(數據載入邊界)
**工作項目**:
1. 盤點所有計時器並分類(目前已知混用點):
   - 物理幀型(對): `hitstun_frames` `blockstun_frames` `knockback_frames` `attack_duration_timer`
     `wakeup_timer` `layground_timer` `dash_timer` `current_move_state.timer`
   - 秒型(需遷移): `knockfly_timer` `hit_timer` `block_timer` `initial_hitstun`
     `landing_lock_timer` `jump_delay_timer` `neutral_timer` `floor_snap_immunity_timer`
     `dash_time`/`backdash_time` `combo_reset_timer` `decision_cooldown`(AI)
   - 混合(需拆): `air_hit_backjump_timer`(int 但初始化用 `* LOGIC_FPS * 2`)
2. 每個秒型計時器: 改為 int 物理幀, 更新所有讀取點
3. 收攏轉換: 所有 `logic_frames_to_physics_frames` / `* 2` / `* 120` 調用 →
   只剩數據載入邊界一處
4. hitstop 的 `Engine.time_scale` 方案保留(已可工作), 但 File 記為已知限制
**測試方法**:
- 既有 9 用例必須全綠(尤其 05/06 的 hitstun/blockstun 幀數斷言)
- **新增** frame-precise 用例:
  - `test_10_hitstun_decrement`: 命中後逐幀記錄 `hitstun_frames`, 斷言 hitstop 期間不遞減、
    結束後每物理幀 -1、精確 48 幀歸零
  - `test_11_landing_lock_frames`: 著地後 `is_landing` 無輸入時精確持續 23 物理幀
  - `test_12_dash_frames`: dash 持續 42 物理幀(0.35s×120)
- 比對 `FRAME_DATA_TABLE.md` 實測值不變
**驗收(DoD)**:
- [ ] 9+3 用例全綠
- [ ] `grep` 遊戲邏輯中無 `float` 計時器(秒域只剩 UI/camera/BGM/tween)
- [ ] 邏輯幀↔物理幀轉換只剩 1 處
- [ ] FRAME_DATA_TABLE 實測值無變化
---
## 6. Stage 2: 顯式狀態機 ⏳
**問題**: ~34 個 bool 旗標(`is_hit` `is_knockfly` `is_blocking` `is_attacking` `is_dashing`
`is_backdashing` `is_jumping` `is_crouching` `is_landing` `is_layground` `is_wakeup`
`is_wakeup_locked` `is_air_attacking` `is_air_hit_backjump` `is_facing_locked`
`is_special_moving` `has_air_attacked` `just_jumped` `is_push_back` `is_being_thrown`
`just_thrown` `is_opponent_proximity` `is_proximity_blocking` ...)互斥靠約定維護;
`player._physics_process` 250 行 if 鏈, 「取消判定必須在清空按鈕之前」類順序依賴。
**設計**:
- 狀態枚舉(單一活動狀態):
  ```
  Idle / Walk / Crouch / CrouchAttack* / Dash / Backdash /
  Jump_F / Jump_B / Jump_V / AirAttack* /
  Attack(ground) / Hitstun / Blockstun / Landing /
  Knockdown(layground) / Wakeup / Knockfly /
  Throwing / BeingThrown / KO
  ```
- **手寫小 FSM**(base 狀態類 + `enter/update/exit` + 過渡表), ~100 行。
  不用已安裝的 `godot_state_charts` 外掛: 功能過重、對格鬥遊戲難調、
  新手難以掌握; 自寫 FSM 可完全控制 frame 行為且方便測試。
  (Stage 5 把外掛從 `project.godot` 移除)
- 旗標的歸宿: 大部分消失(變成狀態本身或狀態欄位);
  `is_on_floor`/`facing_direction` 等物理量保留。
**遷移順序**(每遷一個子系統跑一次測試):
1. **攻擊系統**(邊界最清楚): Attack* 狀態擁有 startup/active/recovery 計數
2. **移動系統**: Walk/Dash/Jump/Landing
3. **受擊系統**: Hitstun/Blockstun/Knockfly/Knockdown/Wakeup
**測試方法**:
- 既有 12 個用例(Stage 1 後)必須全綠 — 狀態機對外部行為透明
- 新增: `test_13_state_machine_invariants` — 隨機輸入序列 600 幀,
  每幀斷言「恰好一個狀態活動」+ 狀態轉換合法性表
- `FRAME_DATA_TABLE.md` 實測值不變
**驗收(DoD)**:
- [ ] 全部 frame 測試全綠
- [ ] 0 個新增 bool 狀態旗標; Movement/Fighter/Player 的旗標數 < 10
- [ ] `world.reset_players()` 簡化為單一 reset 調用
- [ ] 新增一個攻擊只需: frame data 資源 + 動畫(不再改 8 處)
---
## 7. Stage 3: FrameData 收攏 + 數據問題清理 ⏳
**目標**: 每個招式一張 `FrameData` 資源, 單一真相來源:
```
startup / active_from / active_to / recovery /
damage / hitstun / blockstun / knockback /
movement (AttackMovement) /
multi-hit phases[] / knockfly params / projectile params
```
- hitbox active 窗口由 FrameData 驅動(每物理幀切換), 動畫純視覺
  (動畫長度應 = total, 但邏輯不再讀動畫長度)
- 普通攻擊(AttackData)與特殊招式(SpecialMoveData)合併為同一格式
**必須處理的數據問題**(詳見 `FRAME_DATA_TABLE.md` §已知數據問題):
1. **雙真相來源**: 場景內嵌 `smd_*`(生效) vs `data/specials/*.tres`(被忽略) —
   以生效值為準, .tres 對齊後刪除重複
2. **動畫長 0f**: DAV dpM/dpH(靠 smd duration 撐住)、DEN spnk(兩者皆無 → 疑似損毀, 需補)
3. **DAV super** hitbox 窗口解析異常(on=16 > off=10), 人工核對
4. **孤兒資源**: `data/attacks/*.tres`(引用不存在的 `res://AttackData.gd`) — 刪除
5. **WOO**: base MoveSet 無招式資料 — 決定: 完成 WOOMoveSet 或標記 WIP 並從選角移除
6. **hitbox 由動畫軌道驅動** — 改 FrameData 驅動
**測試方法**:
- 既有全部用例全綠
- 每個角色的每個招式: `test_14_<char>_move_frames` 模式 —
  觸發招式 → 斷言 active 窗口(幀)、總長(幀)、命中參數(伤害/hitstun/blockstun)
  與 FrameData 一致
- 100p 四段各自命中參數斷言
**驗收(DoD)**:
- [ ] 每招式只有一個數據來源; `MoveData` 27 參數構造消失(改 Resource 欄位)
- [ ] 動畫 0f 問題全部修正; 孤兒資源刪除
- [ ] 新招式測試全綠; FRAME_DATA_TABLE 更新為收攏後版本
---
## 8. Stage 4: 輸入系統收斂 ⏳
**問題**: 同一個「玩家按了什麼」由三處各自偵測 —
`InputManager`(歷史+方向指令宏)、`PlayerController`(buffer+雙擊+摔投窗口+優先級鏈)、
`MoveSet._handle_input`(150 行 if 鏈 + 變體選擇重複邏輯)。
**目標結構**:
```
InputMap → InputBuffer(保留核心) → InputFrame(結構化: 方向/按鈕/特殊)
        → ActionMapper(單一映射: 輸入 → 動作, 取消規則寫成數據)
ActionMapper 同時供人類輸入與 AI(合成 InputFrame)使用
```
- `MoveSet._handle_input` 的 150 行消失
- fireball/dp 變體選擇邏輯只剩一處
- 摔投(LP+LK 窗口)偵測只存在於 InputFrame 層
**測試方法**:
- 既有全部用例全綠
- **新增輸入宏用例**(Stage 0 的已知限制):
  - `test_15_qcf_fireball`: 模擬 下→下前→前 + MP 的幀序列 → 斷言 fireball 觸發
  - `test_16_dp_launcher`: 模擬 前下前 + 拳 → dpM 觸發、launcher 生效
  - `test_17_throw_window`: LP 與 LK 間距 0/1/2/4 幀 → 0~2 幀判定摔投、4 幀不判定
- AI 走同一 mapper: `test_18_ai_action_parity`(AI 發 fireball 的幀數與人類一致)
**驗收(DoD)**:
- [ ] 加一個特殊招式 = 1 個 FrameData + 1 個輸入序列資源 + 1 個動畫, 不改邏輯代碼
- [ ] 輸入宏測試全綠; 既有測試全綠
---
## 9. Stage 5: 清理 ⏳
**死代碼清單(已知)**:
- `player.gd::_physics_process_jump`(從未被呼叫, 跳躍走 JumpHandler)
- `post_physics_process()` / `update_hitbox_position()` / `_process_projectile_spawn()` 等 pass 方法
- `@deprecated` 變數(`initial_blockstun` `block_push_timer` `block_push_velocity`...)
- `scripts/debug/ai_behavior_old_backup.gd`、`ai/cpu_controller.gd` + `ai/specs/`(殘骸, 先確認無引用)
- `data/attacks/*.tres` 孤兒資源(Stage 3 刪)
- 根目錄 `AIR_PUSHBOX_QUICK_DIAGNOSIS.md` / `QUICK_DIAGNOSIS_CARD.md`(內容過時, 由 Debug logger 取代)
- `backup(for reference only do not change)/` 資料夾(確認無引用後移除)
**文檔收斂**: 68 篇 `docs/*.md`(大半 `XXX_FIX_SUMMARY.md`)→ 每系統一篇正式文檔 +
`DOCUMENTATION_INDEX.md` 重建; 修完系統不再新增 SUMMARY。
**場景**: 角色 tscn 的 AnimationLibrary 抽成獨立 `.res`(DAV.tscn 目前 7450 行)。
**CI**: GitHub Actions 跑 `godot --headless -s res://tests/frame_tests/run_tests.gd`,
PR 必綠。`godot_state_charts` 外掛從 `project.godot` 移除(遊戲未使用)。
**驗收(DoD)**:
- [ ] 無 `XXX_FIX_SUMMARY` 類文檔; docs < 20 篇
- [ ] CI 綠; 全部 frame 測試在 CI 通過
- [ ] 角色 tscn < 2000 行/個
---
## 10. 測試方法(貫穿所有階段)
### 10.1 設計哲學
格鬥遊戲邏輯建立在固定 120 FPS 物理 tick 上, 天然確定性。
frame 測試 = **腳本化輸入序列 → await 物理幀 → 斷言狀態/位置/血量**。
這是重構的安全網: 每改一個子系統跑一次, 保證「遊戲行為一幀不變」。
### 10.2 執行
```bash
# repo 根目錄, 需 Godot 4.7.x CLI (與 main 的 config/features=4.7 一致)
bash tests/frame_tests/run_frame_tests.sh
# 等同:
godot --headless --path . -s res://tests/frame_tests/run_tests.gd
# 退出碼: 0 = 全綠, 1 = 有失敗
```
### 10.3 現有用例(9 個, Stage 0)
| 用例 | 驗證 | 依賴的基準值 |
|---|---|---|
| 01 world_spawn | 生成/血量 100/面向/初始 Walk | — |
| 02 walk_movement | 走速 360px/s(24 幀=72px)、按住不觸發 dash | Movement.walk_speed |
| 03 jump_and_landing | 離地/apex/landing 進出/is_jumping 清除 | jump_vertical_speed |
| 04 ground_attack_frames | st_mp 啟動、48 物理幀內結束 | DAV st_mp 動畫 24f |
| 05 hit_damage_hitstun | 傷害 6.0、hitstun 48 物理幀、無 knockfly | p1_attack_data st_mp |
| 06 block_no_damage | blockstun 32 物理幀、不扣血 | 同上 |
| 07 fireball_spawn | Call Method 16f 時生成、spmove 恢復 | DAV fireballM smd |
| 08 frame_counter_determinism | 60 物理幀精確推進、邏輯幀換算 | FrameCounter |
| 09 debug_logger_default_off | Debug 預設關閉 | Stage 0 不變式 |
### 10.4 各階段擴展計劃
| 階段 | 新增用例 |
|---|---|
| Stage 1 | 10 hitstun 遞減精確性 / 11 landing lock 幀數 / 12 dash 幀數 |
| Stage 2 | 13 狀態機不變式(隨機輸入 600 幀) |
| Stage 3 | 14 每角色每招式 frame 斷言 / 100p 四段 |
| Stage 4 | 15 QCF 宏 / 16 DP 宏 / 17 摔投窗口 / 18 AI 對稱性 |
| Stage 5 | CI 化(無新用例, 全部進 CI) — workflow 已寫好待啟用, 見 §12.2 |
### 10.5 寫新用例的規則(詳見 `tests/frame_tests/README.md`)
1. 每個用例獨立 world(狀態隔離), 不需要清理
2. 計時用物理幀(`await_frames`), 1 邏輯幀 = 2 物理幀, 不用真實秒數
3. `hold/tap` 餵輸入; P2 動作帶 `_p2` 後綴
4. 命中相關等待窗口要留足(hitstop 用 `Engine.time_scale=0.02` 拖慢物理幀推進)
5. lambda 只能 capture 局部變數(先 `var me = p1` 再傳)
6. **所有 coroutine helper 呼叫必須 `await`**(Stage 0 修正過的教訓)
7. 測試輸出用原生 `print`(不經 Debug logger), 確保 runner 結果一定可見
8. 失敗時先分辦: 環境問題(Godot 版本/輸入映射) vs 行為改變(需對照 FrameData 表)
### 10.6 尚未覆蓋(誠實聲明)
- 方向指令宏的輸入模擬(Stage 4 補)
- 空中攻擊 / 摔投 / knockfly 完整流程(Stage 2/3/4 逐步補)
- 多玩家座標系極端情況(牆角) — 角落推擠用例待 Stage 3 後加
---
## 11. 風險清單與緩解
| 風險 | 等級 | 緩解 |
|---|---|---|
| 無 CI 前的驗證依賴使用者本地(沙箱下不到 Godot) | 高 → 待啟用後緩解 | CI workflow 已寫好(`ci/frame-tests.yml`, 容器 `barichello/godot-ci:4.7.2`); 搬入 `.github/workflows/` 後每次 push/PR 自動跑 |
| Godot 4.6→4.7.2 升級的引擎行為差異 | 中 | 升級後已跑過 Stage 0 測試(使用者確認中); 之後每階段都重跑 |
| Stage 1 大規模計時器遷移的隱性行為漂移 | 高 | 12 個用例 + 逐子系統遷移(一次一個計時器族) + FrameData 表比對 |
| Stage 2 狀態機遷移期間長(2~4 週末) | 中 | 按子系統切 3 段, 每段独立可驗證; 旗標與狀態並行期間用測試對齊 |
| DEN spnk / DAV dpM/dpH 數據損毀(動畫 0f) | 中 | Stage 3 處理; 處理前若觸發該招式先標記 skip |
| WOO 角色不完整 | 低 | Stage 3 決定去留 |
| 重構期間功能開發衝突 | 中 | 守則第 5/6 條: 新招式走現有數據管道, 不改邏輯; 衝突時先完成當前階段 |
---
## 12. 立即下一步
1. **[已完成]** Godot 4.7.2 baseline 9/9 PASS; `test_10~12` 安全網完成, **12/12 PASS**
2. **[待啟用]** CI 化提前(原 Stage 5): workflow 已寫好, 暫放 `ci/frame-tests.yml`,
  用容器 `barichello/godot-ci:4.7.2` 跑全部 frame 用例 + gdtoolkit 靜態解析。
  **尚未生效** —— 開此 PR 的自動化以 GitHub App 身分認證且無 `workflows` 權限,
  無法寫入 `.github/workflows/`。有寫入權限者執行
  `git mv ci/frame-tests.yml .github/workflows/frame-tests.yml` 即可啟用。
3. **[已完成]** 第一個遷移切片: landing timer family →
  `landing_lock_timer: float`(秒) 改為 `landing_lock_frames: int`(物理幀),
  26 處讀寫點全數更新; 新增 `test_16` 釘住轉換公式; 順帶刪除死變數
  `_landing_interrupted_by_input` 並抽出 `Player._enter_landing_state()`(消除三份複製)。
  **轉換公式踩雷紀錄**: 舊的 `timer -= delta` 迴圈在 0.2s 下實際跑 **25** 幀而非數學上的 24
  (24 次浮點相減後殘值 5.2e-17 > 0)。因此換算用 `floor(sec*fps)+1`
  (`Movement.seconds_to_lock_frames`), 若用 `round()` 會少一幀而改變行為。
4. **[下一切片]** `knockfly_timer` / `hit_timer` / `block_timer` / `block_push_timer`
  (`PushManager.gd:278-310` 的 `-= delta` 群)。這族的實質收益: `fighter.gd:90-95`
  在 hitstop 期間早退, 但 PushManager 的 delta 遞減不受該早退保護, 目前秒型計時器
  在 hitstop 下仍會前進 —— 改幀制後自動修正。
5. 每階段結束: 更新本文件狀態欄 + `FRAME_DATA_TABLE.md` + commit
---
## 附錄 A: 關鍵代碼位置(供各階段參考)
| 系統 | 檔案 |
|---|---|
| 狀態旗標/物理 | `scripts/core/Movement.gd` (468 行, 28 旗標) |
| hitstun/take_hit | `scripts/core/fighter.gd` (527 行) |
| 攻擊生命週期/250 行 if 鏈 | `scripts/core/player.gd` (860 行) |
| 特殊招式 | `scripts/combat/movesets/MoveSet.gd` (1042 行) + `DAVMoveSet.gd`/`DENMoveSet.gd` |
| 命中處理 | `scripts/combat/handlers/HitResponseHandler.gd` |
| 推擠/knockback | `scripts/core/PushManager.gd` (558 行) |
| 輸入 | `scripts/input/InputManager.gd` + `PlayerController.gd` + `InputBuffer.gd` |
| 世界/優勢計算 | `scripts/core/world.gd` (822 行) |
| hitstop | `scripts/core/slow_mo_controller.gd` |
| 幀數據資源 | `data/AttackData.gd` + `data/p1_attack_data.tres`(DAV/WOO) + `data/p2_attack_data.tres`(DEN) + `data/specials/*.tres` + 場景內嵌 `smd_*` |
| AI | `ai/` (AIBehavior 為主; cpu_controller/specs 為殘骸) |
| 測試 | `tests/frame_tests/` |
| 行為基準 | `docs/systems/FRAME_DATA_TABLE.md` |
## 附錄 B: 已完成 commit 記錄(歷史參考)
Stage 0 原始 5 commits + 修正 commit 已合併入 main, 並隨 Godot 4.7.2 升級
重壓為單一 commit `f0ee99f`。內容即 §4.1/§4.2 所列。

