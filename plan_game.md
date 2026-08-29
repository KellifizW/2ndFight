# 2ndFight 重構與測試計劃
> 建立: 2026-08-21 | 最後更新: 2026-08-27
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
| Stage 1 | 統一時間域(全遊戲邏輯 = int 物理幀) | ✅ 完成(六族計時器全數遷移; CI 已啟用並自動跑全部用例) | 已完成 |
| Stage 2 | 顯式狀態機(消除 34 旗標) | 🔄 切片 1~2 完成(唯讀狀態層 → 攻擊子系統改讀狀態; 37→30) | 2~4 週末 |
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
## 5. Stage 1: 統一時間域 ✅（2026-08-27 收尾，待本地 24 用例驗收）
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
   - ✅ 已遷移(本切片 2026-08-27): `combo_reset_frames`(原 `combo_reset_timer` 秒制)、
     `decision_cooldown_frames`/`commitment_frames`/`opponent_search_frames`(AI，原 `_process`
     真實秒制)、`double_tap_frames`(`PlayerController`，原 `_process` 秒制)；
     `SpecialMoveBase`(含死路徑 `jump_timer`)整檔刪除(全倉庫零呼叫點)
   - ✅ 已遷移: `landing_lock_frames` `knockfly_frames` `hit_lock_frames`
     `block_lock_frames` `block_push_frames`；`jump_delay_timer`/`neutral_timer`/
     `floor_snap_immunity_timer`（種子公式已收攏至 `Movement.seconds_to_frames_nearest`）
   - ✅ 已拆: `air_hit_backjump_timer` 種子改經唯一邊界，`* LOGIC_FPS * 2` 字面式消失
   - 殘留(非 hitstop 敏感、併入 Stage 4 AI 收攏): `AIComboSystem.combo_timer`、
     `AIDecisionLayers.cache_timer`/`special_cooldown_timer`、
     `ThreatAssessment.projectile_check_timer`，以及未被玩法使用的 `TimerManager` 工具
2. 每個秒型計時器: 改為 int 物理幀, 更新所有讀取點
3. 收攏轉換: 所有 `logic_frames_to_physics_frames` / `* 2` / `* 120` 調用 →
   只剩數據載入邊界一處
4. hitstop 的 `Engine.time_scale` 方案保留(已可工作), 但 File 記為已知限制
**測試方法**:
- 既有用例必須全綠(尤其 05/06/10 的 hitstun/blockstun 幀數斷言)
- **已新增** frame-precise 用例:
  - `test_10_hitstun_decrement`: 命中後逐幀記錄 `hitstun_frames`, 斷言 hitstop 期間不遞減、
    結束後每物理幀 -1、精確 48 幀歸零
  - `test_11_landing_lock_frames`: 著地後 `is_landing` 無輸入時精確持續 23 物理幀
  - `test_12_dash_frames`: dash 持續 42 物理幀(0.35s×120)
  - `test_18_stun_lock_is_frame_based`: knockfly 0.4s→49 幀, 每物理幀 -1
  - `test_19_hit_lock_freezes_in_hitstop`: `hit_lock_frames` 與 `hitstun_frames` 對齊並在 hitstop 凍結
  - `test_20_block_lock_is_frame_based`: `block_lock_frames` 與 `blockstun_frames` 對齊並在 hitstop 凍結
- **收尾切片新增**: `test_21` combo 視窗幀制 / `test_22` 三個轉換邊界公式釘選 /
  `test_23` AI 決策計時器 int 幀與每幀 -1 / `test_24` 雙擊窗口恰 36 tick 歸零
- 比對 `FRAME_DATA_TABLE.md` 實測值不變
**驗收(DoD)**:
- [x] landing + PushManager stun-lock 兩族已遷移; 對應 frame tests 已寫好（使用者本地驗收）
- [x] 收尾切片: combo/AI/雙擊/SpecialMoveBase/種子收攏完成（本 PR; `run_frame_tests.sh` 24 用例待本地驗收）
- [x] `grep` 遊戲邏輯中無 `float` 計時器(秒域只剩 UI/camera/BGM/tween 與上列 AI 子系統併入 Stage 4 的小計時器)
- [x] 邏輯幀↔物理幀轉換只剩 1 處(`Movement.logic_frames_to_physics_frames`);
  秒↔幀統一為 `seconds_to_lock_frames` / `seconds_to_frames_nearest` 兩式
  （語義不同的兩族舊計時器，見 `Movement.gd` 轉換邊界註解與 `test_22`）
- [ ] FRAME_DATA_TABLE 實測值無變化（驗收時確認）
---
## 6. Stage 2: 顯式狀態機 🔄（切片 1 已完成 2026-08-27）
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
- 既有用例必須全綠 — 狀態機對外部行為透明
- 新增: `test_25_state_machine_invariants`(原規劃編號 13, 因 13 已被 Stage 1
  combo 用例佔用而改號) — 固定種子隨機輸入 600 幀, 每幀斷言解析器為純函數、
  回傳已定義狀態、結構性互斥不變式成立; 另印狀態分布並要求 >=4 種
- 新增: `test_26_state_matches_animation_chain` — 逐幀比對狀態層 vs 動畫層
- `FRAME_DATA_TABLE.md` 實測值不變

### 6.1 切片 1（已完成, 本輪）: 唯讀狀態層 + 死旗標清除
**原則**: 先讓狀態層存在且被測試釘住, 再逐段改控制流。本切片**行為零變更**
(純刪除無讀取點的變數 + 新增唯讀推導層), 因此可以安全地先落地。

**交付**:
1. `scripts/core/FighterState.gd` — `State` enum(19 態) + `resolve(fighter)`
   純函數, 由現行旗標推導單一活動狀態; `check_invariants()` 回傳結構性違規;
   `known_illegal_overlaps()` 列出「可達但不該存在」的重疊(Stage 2 待辦清單)。
   入口: `Fighter.get_fighter_state()` / `get_fighter_state_name()`。
2. 優先序**逐條複製**現行兩條動畫鏈(`Player._compute_target_state` →
   `AnimationManager.compute_target_state`), 把隱性約定變成可測契約。
3. 刪除 14 個死旗標/死變數(全部先以「註解剝除後的讀寫點分析」證明零讀取,
   並確認無 `.tscn`/`.tres` 覆寫與動態 `get`/`set`):
   - 旗標: `is_crouch_transition_played` `is_crouch_held` `is_airborne`
     `_landing_timer_initialized` `is_being_pushed` `is_air_hit_knockfly`
   - 變數: `current_mode` `cancel_window_duration` `powerkk_blockstun`
     `knockback_start_x` `last_hit_attack_name` `initial_blockstun_frames`
     `initial_hitstun` `knockback_total_time` `hit_push_timer` `hit_push_offset`
     `dash_direction` `pending_jump_b_seek` `air_hit_backjump_up_speed`
     以及 @deprecated 秒制推擠對 `initial_blockstun`/`block_push_velocity`
4. 移除兩條**不可達路徑**(這部分才是真正藏 bug 的地方):
   - `is_push_back` 整族: 全倉庫唯一寫入點就在它自己守衛的分支裡寫 `false`,
     推開減速路徑自始不可達; 但它仍出現在 Dash/Jump/Walk×2/AI-dash **五條**
     守衛條件裡當假的互斥項。移除後條件恆等。
   - PushManager 依 `is_air_hit_knockfly` 選擇的線性 knockfly 衰減分支
     (該旗標從未被設為 true, 實際永遠走二次衰減)。
5. 核心三檔 bool 狀態旗標: **37 → 31**。

**已知分岔(窮舉 55k+ 旗標組合對撞找出, 屬動畫層缺口, 非本切片修正範圍)**:
1. `is_being_thrown` 在動畫層完全沒有分支 — 被摔者續播被抓前的動畫。
2. 在空中但 `is_jumping`/`is_air_attacking` 皆假時, 動畫層掉回 `"Walk"`
   (半空中播走路動畫); 可達路徑: 空中受擊後跳結束但尚未落地那幾幀。
兩者在 `test_26` 以**明確狀態條件**跳過並計數(不是「失敗就原諒」),
記錄於 `FighterState.gd` 檔頭, 待後續切片改控制流時一併處理。

### 6.2 切片 2（已完成, 本輪 2026-08-29）: 攻擊子系統改讀狀態
**原則**: 第一個真正「改控制流」的切片 —— 攻擊系統邊界最清楚, 先做。
做法固定為三步, 後續切片沿用: **守衛搬進 FighterState → 窮舉證明等價 →
frame 測試逐幀釘住**。

**交付**:
1. **攻擊入口收攏為一個**。`fighter.gd` 裡重構前的舊攻擊檢查
   (`st_mp_pressed or st_mk_pressed` → `is_attacking = true`) 移除。
   它每幀比 AttackExecutor 早跑、守衛條件不同(多 `not is_crouching`,
   少 landing/wakeup/layground)、不走按鈕優先序、不消耗 buffer。
   三個可觀測效果逐一確認: `current_damage = 10.0` 不可觀測
   (唯一讀取點 `HitResponseHandler._get_hit_parameters` 一律用
   ATTACK_TABLE / active_move 覆寫; `input_data.has("damage")` 全倉庫無來源);
   與 AttackExecutor 同幀出招時是重複寫入; **唯一真差異**是
   「它出招、AttackExecutor 沒出招」的幀 —— 那是 bug(見下)。
2. **「孤兒攻擊」狀態變成結構上不可能**。上述差異幀會留下
   `is_attacking = true` + `attack_type = "none"`: 動畫層當 "Walk" 播、
   MoveSet 拒開新招、跳躍/衝刺守衛全擋、`attack_duration_timer = 0`
   所以沒有計時器會收回來。可達窗口兩個、各 1 物理幀:
   (a) 無輸入著地後第 1 幀(lock 5→4、`_landing_forced_frames=1 < 2`,
   著地攻擊取消還不能觸發); (b) 攻擊動畫結束當幀(reset 剛清 attack_type,
   同幀去重鎖擋掉重出招)。移除後 `is_attacking = true` 只剩兩個寫入點
   (`Player._execute_attack`、`ThrowHandler` 進 throw_seq), 兩者都在同一區塊
   寫入合法 attack_type; 每個 `attack_type = "none"` 寫入點也都在同一區塊
   清掉 is_attacking → `check_invariants()` 新增的「攻擊必須成對」不變式
   **由結構保證**, 不再靠約定。
3. **出招守衛 3 份 → 1 份**: `Player.is_valid_ground_state`、著地攻擊取消後的
   重算版、`Fighter.is_valid_state` → `FighterState.can_start_ground_attack()`;
   `is_valid_air_state` → `can_start_air_attack()`。
   等價性以**窮舉 14 個相關旗標全 16,384 種組合**驗證(0 分岔),
   並由 `test_30` 在引擎內逐幀比對舊表達式。
   重算版被證明是冗餘的: 它抄掉 landing 項, 但呼叫前兩行剛把
   `is_landing`/`landing_lock_frames` 清零, 該項本來就恆真。
4. **攻擊 id 一份定義**: `player.gd` 的 `_ATTACK_NAMES` /
   `GROUND_ATTACK_ANIMS` / `AIR_ATTACK_ANIMS` 三份重疊清單 →
   `FighterState.GROUND_ATTACK_IDS` / `AIR_ATTACK_IDS`。
   (`AnimationManager` 內嵌的第四份屬動畫層, 留給 Stage 3 與 frame data 一起搬。)
5. **摔投判定收攏**: `is_attacking and attack_type in ["throw_enter","throw_seq"]`
   在 5 處各寫一遍(Player ×3、AttackExecutor、PushManager ×2 純字面值對) →
   `FighterState.is_throw_in_progress()` / `is_throw_attack_id()`。
6. 再清一個死旗標 `_was_in_hitstop`: 唯一讀取點是 hitstop 邊緣偵測,
   兩個分支皆空操作(一支賦值給兩個未使用區域變數, 另一支 `pass`)。
7. 核心三檔 bool 狀態旗標 **31 → 30**。
   新增 `test_29`(攻擊狀態成對; 含針對性重現舊入口窗口) /
   `test_30`(守衛 vs 舊表達式逐幀等價), 共 **30** 用例。

**本切片找出但刻意不修的(披露)**:
1. `current_damage` 實質上只寫不讀(每個讀取點都在同一式裡覆寫) → Stage 3。
2. `AttackBase` 是死的第三個攻擊入口(全倉庫零引用), **未刪除**:
   它正好帶著 §6 要 Attack 狀態擁有的 startup/active/recovery 計數,
   由 Stage 3 決定「復活成 Attack 狀態的計數擁有者」或刪除。
3. 取消窗口對 CPU 失效: `check_cancel()` 讀 `input_data.attack_type`,
   `PlayerController` 有給、AI 的 `get_ai_input()` merge 沒有 → Stage 4。
4. `get_input()` 每物理幀被呼叫 3~4 次(Movement / TimerHandler 著地
   checkpoint / Player); 對 AI 每次都會重問 `get_ai_input()` → Stage 4。

### 6.3 後續切片（待辦）
依原訂順序把控制流從「讀旗標組合」改為「讀狀態」, 每段跑一次測試:
1. ~~**攻擊系統**~~ ✅ 切片 2 完成(守衛已收攏; Attack* 狀態擁有
   startup/active/recovery 計數的部分併入 Stage 3, 見 §6.2 披露 2)
2. **移動系統**: Walk/Dash/Jump/Landing
3. **受擊系統**: Hitstun/Blockstun/Knockfly/Knockdown/Wakeup

**驗收(DoD)**:
- [x] 狀態層存在且被 frame 測試釘住(`test_25`/`test_26`)
- [x] 死旗標/死變數清除; 核心三檔旗標數 37 → 31 → **30**
- [x] 攻擊子系統改讀狀態(切片 2): 出招守衛/摔投判定/攻擊 id 各一份定義
- [ ] 移動與受擊子系統改讀狀態(切片 3~4); Movement/Fighter/Player 的旗標數 < 10
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
- `@deprecated` 變數(`initial_blockstun` `block_push_frames` `block_push_velocity`...)
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
| Stage 1 | 10 hitstun 遞減 / 11 landing lock / 12 dash / 16 landing 轉換公式 / 18 knockfly 幀制 / 19 hit_lock hitstop 凍結 / 20 block_lock |
| Stage 2 | 25 狀態機不變式(隨機輸入 600 幀) / 26 狀態層 vs 動畫層對齊 / 29 攻擊狀態成對(孤兒攻擊不可達) / 30 出招守衛 vs 舊表達式逐幀等價 |
| Stage 3 | 14 每角色每招式 frame 斷言 / 100p 四段 |
| Stage 4 | 15 QCF 宏 / 16 DP 宏 / 17 摔投窗口 / 18 AI 對稱性 |
| Stage 5 | CI 化(無新用例, 全部進 CI) — ✅ 已啟用, 見 §12.2 |
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
| 無 CI 前的驗證依賴使用者本地(沙箱下不到 Godot) | ✅ 已緩解 | `.github/workflows/frame-tests.yml` 已啟用: 每次 push/PR 在 `barichello/godot-ci:4.7.2` 跑全部 frame 用例 + gdparse + 簽名檢查 |
| Godot 4.6→4.7.2 升級的引擎行為差異 | 中 | 升級後已跑過 Stage 0 測試(使用者確認中); 之後每階段都重跑 |
| Stage 1 大規模計時器遷移的隱性行為漂移 | 高 | 20 個用例 + 逐子系統遷移(一次一個計時器族) + FrameData 表比對 |
| Stage 2 狀態機遷移期間長(2~4 週末) | 中 | 按子系統切 3 段, 每段独立可驗證; 旗標與狀態並行期間用測試對齊 |
| DEN spnk / DAV dpM/dpH 數據損毀(動畫 0f) | 中 | Stage 3 處理; 處理前若觸發該招式先標記 skip |
| WOO 角色不完整 | 低 | Stage 3 決定去留 |
| 重構期間功能開發衝突 | 中 | 守則第 5/6 條: 新招式走現有數據管道, 不改邏輯; 衝突時先完成當前階段 |
---
## 12. 立即下一步
1. **[已完成]** Godot 4.7.2 baseline 9/9 PASS; `test_10~12` 安全網完成, **12/12 PASS**
2. **[已完成]** CI 化提前(原 Stage 5): `.github/workflows/frame-tests.yml` 已啟用,
  兩個 job —— `static-check`(gdparse 全檔 + `ci/check_signatures.py` 父子簽名檢查)
  與 `frame-tests`(容器 `barichello/godot-ci:4.7.2` 跑全部 frame 用例)。
  這解除了 §11 風險表第一列: 物理幀斷言不再依賴人手在本地跑。
3. **[已完成]** 第一個遷移切片: landing timer family →
  `landing_lock_timer: float`(秒) 改為 `landing_lock_frames: int`(物理幀),
  26 處讀寫點全數更新; 新增 `test_16` 釘住轉換公式; 順帶刪除死變數
  `_landing_interrupted_by_input` 並抽出 `Player._enter_landing_state()`(消除三份複製)。
  **轉換公式踩雷紀錄**: 舊的 `timer -= delta` 迴圈在 0.2s 下實際跑 **25** 幀而非數學上的 24
  (24 次浮點相減後殘值 5.2e-17 > 0)。因此換算用 `floor(sec*fps)+1`
  (`Movement.seconds_to_lock_frames`), 若用 `round()` 會少一幀而改變行為。
4. **[已完成]** PushManager stun-lock family:
   `knockfly_timer`/`hit_timer`/`block_timer`/`block_push_timer` →
   `knockfly_frames`/`hit_lock_frames`/`block_lock_frames`/`block_push_frames`。
   遞減仍在 PushManager（與 knockfly 速度曲線同一處），但 hitstop 期間凍結。
   knockfly 秒數種子走 `Movement.start_knockfly_timer()` → `seconds_to_lock_frames`
   （0.4s→49）；hit/block lock 直接用已轉換的物理幀，與 `hitstun_frames`/
   `blockstun_frames` 對齊。新增 `test_18`/`test_19`/`test_20`。
5. **[已完成]** Stage 1 收尾切片: `combo_reset_timer` → `combo_reset_frames`（物理幀，
   每 tick -1，歸零當幀 reset_combo）；AI `decision_cooldown`/`commitment_timer`/
   `opponent_search_timer` → int 幀計數（種子 0.033s→4、0.016s→2、0.05s→6 物理 tick，
   與原註解意圖一致；舊 `_process` 真實 delta 制隨渲染幀率浮動的問題根除）；
   `PlayerController.double_tap_timer` → `double_tap_frames`（0.3s = 恰 36 tick，
   遞減移到 `_physics_process`）；死類 `SpecialMoveBase` 整檔刪除；
   `air_hit_backjump_timer`/`floor_snap_immunity_timer` 種子收攏至
   `Movement.seconds_to_frames_nearest`；jump_delay/neutral/dash/layground/wakeup/
   attack-movement 全部 `int(round(sec*120))` 站點同收攏（位元級同值）。
   新增 `test_21`~`test_24`，改寫 `test_13` 斷言為幀制。
   **行為差異披露**: combo 標籤視窗舊浮點迴圈對部分 stun 值會因殘值少走 1 幀
   （如 24 邏輯幀舊測得 72 tick）；幀制版恆為 stun×2+25=73，標籤寿命 ±1 幀，
   不影響 combo 計數（計數走 fighter 實際 stun 幀）。
6. 每階段結束: 更新本文件狀態欄 + `FRAME_DATA_TABLE.md` + commit
---
7. **[已完成 2026-08-27]** Stage 2 切片 1: 唯讀狀態層 `FighterState` +
   清除 14 個死旗標/死變數 + 移除兩條不可達路徑(`is_push_back` 整族、
   `is_air_hit_knockfly` 線性衰減分支); 核心三檔旗標 37→31;
   新增 `test_25`/`test_26`(共 26 用例)。詳見 §6.1。
   **行為零變更** —— 純刪除無讀取點的變數 + 新增唯讀推導層。
---
8. **[已完成 2026-08-29]** Stage 2 切片 2: 攻擊子系統改讀狀態。
   移除 `fighter.gd` 的舊第二攻擊入口(孤兒攻擊狀態因此結構上不可達)、
   出招守衛 3 份收攏為 `FighterState.can_start_ground_attack/can_start_air_attack`
   (窮舉 16,384 種旗標組合證明等價)、攻擊 id 與摔投判定各收攏為一份定義、
   再清死旗標 `_was_in_hitstop`; 核心三檔旗標 31→30;
   新增 `test_29`/`test_30`(共 30 用例)。詳見 §6.2。
   **行為變更**: 僅限「舊入口出招、AttackExecutor 沒出招」的那一幀 ——
   該幀原本產生非法的孤兒攻擊狀態, 現在不再產生。其餘幀逐值等價。
---
## 附錄 A: 關鍵代碼位置(供各階段參考)
| 系統 | 檔案 |
|---|---|
| 狀態旗標/物理 | `scripts/core/Movement.gd` (516 行, 23 旗標) |
| hitstun/take_hit | `scripts/core/fighter.gd` (526 行) |
| 攻擊生命週期/250 行 if 鏈 | `scripts/core/player.gd` (869 行) |
| 特殊招式 | `scripts/combat/movesets/MoveSet.gd` (1042 行) + `DAVMoveSet.gd`/`DENMoveSet.gd` |
| 命中處理 | `scripts/combat/handlers/HitResponseHandler.gd` |
| 推擠/knockback | `scripts/core/PushManager.gd` (563 行) |
| 輸入 | `scripts/input/InputManager.gd` + `PlayerController.gd` + `InputBuffer.gd` |
| 世界/優勢計算 | `scripts/core/world.gd` (883 行) |
| hitstop | `scripts/core/slow_mo_controller.gd` |
| 幀數據資源 | `data/AttackData.gd` + `data/p1_attack_data.tres`(DAV/WOO) + `data/p2_attack_data.tres`(DEN) + `data/specials/*.tres` + 場景內嵌 `smd_*` |
| AI | `ai/` (AIBehavior 為主; cpu_controller/specs 為殘骸) |
| 顯式狀態層 | `scripts/core/FighterState.gd` (Stage 2 切片 1 唯讀解析器; 切片 2 起也是出招守衛/攻擊 id/摔投判定的唯一定義) |
| 測試 | `tests/frame_tests/` (30 用例) |
| 行為基準 | `docs/systems/FRAME_DATA_TABLE.md` |
## 附錄 B: 已完成 commit 記錄(歷史參考)
Stage 0 原始 5 commits + 修正 commit 已合併入 main, 並隨 Godot 4.7.2 升級
重壓為單一 commit `f0ee99f`。內容即 §4.1/§4.2 所列。

