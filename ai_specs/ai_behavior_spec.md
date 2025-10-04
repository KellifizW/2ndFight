// ...existing code...
# 優化後：AI Behavior Spec（精簡、邏輯一致、術語統一）

目的：在不改變核心決策與閾值的前提下，提高規格可讀性、移除重複、統一術語（distance 以像素為單位）、並加入必要的邊界檢查（例如 distance 的非負保護）。

## 概要
- 腳本：AIBehavior (extends Node)，以父節點 Player 為控制目標，使用有限狀態機（FSM）管理：idle / approach / attack / defend / jump。
- 輸入產生：返回 build_input_dict(...) 給 fighter.gd。
- 依賴：父節點有 healthbar、is_attacking、is_dashing 等；場景中有 "players" 組群以取得對手。

注意事項：
- 「distance」皆以像素為單位。
- 任何計算 distance 後，先做 distance = max(distance, 0.0) 以避免負值異常。

## 核心原則（不改動原有閾值）
- 積極性：80% 初始為 approach；狀態計時器在 0.3–0.6s 範圍內，反應較快。
- 防禦：被擊中或擊飛時強制 defend，蹲擋機率高（對手蹲攻時尤甚）。
- 距離管理：攻擊範圍 < 45 px；接近閾值 40 px；遠距離傾向 dash/jump。
- 低血 (<50%) 提高攻擊傾向。
- 除錯輸出僅在 debug build 顯示。

## 變數（摘要）
- parent: @onready 父 Player 節點
- ai_enabled: bool
- current_state: "idle" | "approach" | "attack" | "defend" | "jump"
- state_timer, last_action_time, input_dir_timer, dash_cooldown, recovery_timer, block_timer, crouch_timer: float
- random_poke_chance = 0.15, jump_attack_chance = 0.6, proactive_jump_chance = 0.3
- opponent_recovery_time, opponent_stun_remaining: float
- is_crouching: bool

## 初始化與啟用
- _ready(): 若 parent 存在，設 state_timer = randf() * 0.3 + 0.3，並輸出 debug（僅 debug build）。
- set_ai_enabled(enabled): ai_enabled = enabled；若 enabled 則 current_state 依機率設為 "approach"（80%）或 "idle"；重置 state_timer。

## 更新循環（_physics_process(delta)）
- 若 ai_enabled 為 false 或任一血量 <= 0，結束。
- 逐幀遞減各計時器（input_dir_timer、dash_cooldown、recovery_timer、block_timer、crouch_timer）。
- 呼叫 update_ai_state(delta)。

## 狀態更新要點（update_ai_state）
- 先計算對手與狀態：
  - opponent = get_opponent()（若 null 則 return）
  - distance = abs(parent.global_position.x - opponent.global_position.x); distance = max(distance, 0.0)
  - can_attack = is_in_attack_range(parent, opponent)
  - in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)
  - opponent_attacking = opponent.is_attacking or opponent.is_dashing
  - opponent_jumping, opponent_recovery_time, opponent_stun_remaining 如實讀取
- 被擊中或擊飛：立即進入 defend，設定 recovery_timer/block_timer/state_timer = 0.5，並 return。
- 使用一致的 if / elif（或 match）結構處理各 state 的轉換，保留原始閾值與機率判定（例如距離檢查、poke、jump attack、corner escape、punish 等）。
- 每次 state 判定結束後更新 last_action_time 與必要的 debug 輸出（僅在 debug build）。

## 輸入產生（get_ai_input）
- 若 ai_disabled，直接回傳 neutral input（build_input_dict(0, false, false, false, "none", 0.2, 0.0, false, false)）。
- 確認 parent 與 opponent 血量；若任一為 0，回傳 neutral input。
- 若 opponent 為 null，朝對方向（input_dir = 1）返回。
- 計算相同的一組輔助變數（distance、can_attack、in_danger、is_cornered、opponent_jumping、等），並先做 distance = max(distance, 0.0)。
- 被擊中/被擊飛/在 block_timer 時：後退（依 x 座標決定方向）、嘗試 crouch block（crouch_timer 管理），直接返回（不執行攻擊）。
- 移動邏輯：
  - distance > 100 -> 向對手移動
  - 40 < distance <= 100 -> 向對手移動
  - distance < 35 -> 靠近時若能攻擊則停位攻擊；否則後退
  - 35 <= distance <= 40 -> 停位
  - 若 in_danger 且 distance < 30 -> 強制後退
- 狀態特定輸入（defend / approach / attack / jump）：保持原有行為分支與機率，不改閾值，但確保每處使用一致的 guard（例如先確認 can_attack、distance 的範圍、以及是否在角落）。
- 低血邏輯與跟跳攻擊保持原有機率與條件，但在使用 distance 時皆以 pixels 並先 clamp。

## 輔助函數（摘要）
- is_in_attack_range(attacker, target): 優先檢查 Hitbox/Hurtbox 重疊，否則以 distance < 45 px 作為後備。
- is_hitbox_overlapping_hurtbox(attacker, target): 檢查 Area2D 重疊。
- get_opponent(): 從 group "players" 中回傳非 parent 的節點。
- build_input_dict(...): 返回固定格式字典。

## 風格與一致性建議（只改說明，不改邏輯）
- 全文統一用詞：distance（px）、can_attack（布林）、in_danger（布林）。
- 所有距離比較以像素顯式註明（例如 distance < 45 px）。
- 所有隨機判斷保留 randf()，但在規格中標示其目的（如「增加多樣性」或「懲罰窗口」）。
- 在每個分支中先列出 guard 條件（例如：if parent.is_hit: ... return），接著才是狀態轉換，避免互相散落的早期 return。

## 小結
本檔為閱讀與 lint 友好的版本，保留原始設計意圖與閾值，移除重複描述，統一術語，並加入 distance 非負保護。實作可參考現有 [ai_behavior.gd](ai_behavior.gd) 中的函式與閾值，確保程式碼與規格一致。
// ...existing code...