優化以下 Markdown 規格：確保邏輯一致（如 if/elif 結構）、術語統一（如 "distance" 總用像素單位）、移除重複、添加遺漏邊界（如距離 < 0 的處理）。不要改動核心邏輯，只提升可讀性。
# AI Behavior Spec for Godot Fighting Game

## 概述
此規格描述格鬥遊戲中 AI 行為腳本（AIBehavior.gd）的邏輯，繼承自 Node。AI 控制玩家節點（parent），使用有限狀態機（FSM）管理行為：idle（閒置）、approach（接近）、attack（攻擊）、defend（防禦）、jump（跳躍）。AI 基於距離、對手狀態、健康、危險偵測等因素決策，生成輸入字典供 fighter.gd 使用。設計強調積極性：縮短計時器、增加追擊/逃角機率、綁定攻擊範圍檢查。依賴 Godot 的 Area2D（Hitbox/Hurtbox）進行碰撞偵測。

**依賴**：
- Parent: Player 節點（包含 healthbar、is_attacking、is_dashing 等）。
- Opponent: 另一玩家節點（透過 get_opponent 取得）。
- 組群: "players"（用於找對手）。
- 輸入: build_input_dict 返回字典，包含 input_dir、crouch_pressed 等。

**核心原則**：
- 積極進攻：80% 初始 approach，縮短計時器（0.3-0.6s），增加 poke/追擊機率。
- 防禦反應：被擊中強制 defend，蹲擋機率高（>80% 若對手蹲攻）。
- 距離管理：攻擊範圍 <45 像素，接近閾值 40 像素，遠距 dash/jump。
- 低血 (<50%) 更積極：提高攻擊機率。
- 除錯：僅 debug 建置下 print 狀態。

## 變數定義
- **parent: Node** (@onready)：父節點（Player）。
- **ai_enabled: bool**：AI 開關（預設 false，從 CPUController 傳入）。
- **current_state: String**：當前狀態（"idle", "approach", "attack", "defend", "jump"；初始 "idle"）。
- **state_timer: float**：狀態持續計時器（初始 randf() * 0.3 + 0.3）。
- **last_action_time: float**：上次動作時間（用於避連續，初始 0）。
- **input_dir_timer: float**：輸入方向穩定計時器（用於轉向，初始 0）。
- **dash_cooldown: float**：dash 冷卻（初始 0，持續 1.0s）。
- **recovery_timer: float**：被擊中恢復（初始 0，強制 0.5s）。
- **block_timer: float**：格擋持續（初始 0，強制 0.5s）。
- **crouch_timer: float**：蹲下持續（初始 0，持續 0.2s）。
- **random_poke_chance: float = 0.15**：隨機 poke 機率（中近距）。
- **jump_attack_chance: float = 0.6**：跳攻擊機率（對手跳躍或中距，綁定 can_attack）。
- **proactive_jump_chance: float = 0.3**：主動跳攻機率（中距 40-50 像素）。
- **opponent_recovery_time: float**：對手攻擊剩餘時間（從 opponent.attack_timer）。
- **opponent_stun_remaining: float**：對手 stun/block 剩餘（max(hit_timer, block_timer)）。
- **is_crouching: bool**：當前是否蹲下（初始 false）。

## 初始化 (_ready)
- **if** not parent: print("Warning: No parent Player found for AIBehavior")
- **if** parent:
  - print("Debug: AIBehavior ready for %s!" % parent.name)
  - state_timer = randf() * 0.3 + 0.3  # 隨機初始，打破對稱（0.3-0.6s）
- **else**:
  - print("Debug: AIBehavior ready for unknown!")

## 啟用/停用 (set_ai_enabled)
- **ai_enabled = enabled**
- **if** enabled:
  - current_state = "approach" if randf() > 0.2 else "idle"  # 80% 積極初始 approach
  - state_timer = randf() * 0.3 + 0.3
- **if** parent: print("Debug: AI %s for %s" % ["enabled" if enabled else "disabled", parent.name])
- **else**: print("Debug: AI %s for unknown" % ["enabled" if enabled else "disabled"])

## 主要更新 (_physics_process(delta))
- **if** not ai_enabled: return
- opponent = get_opponent()
- parent_health = parent.healthbar.current_health if parent and parent.healthbar else 100.0
- opponent_health = opponent.healthbar.current_health if opponent and opponent.healthbar else 100.0
- **if** parent_health <= 0.0 or opponent_health <= 0.0: return  # 停止行為
- update_ai_state(delta)
- input_dir_timer -= delta
- dash_cooldown -= delta
- recovery_timer -= delta
- block_timer -= delta
- crouch_timer -= delta

## 狀態更新 (update_ai_state(delta))
- state_timer -= delta
- opponent = get_opponent()
- **if** not opponent: return
- opponent_recovery_time = opponent.attack_timer if opponent else 0.0
- opponent_stun_remaining = max(opponent.hit_timer, opponent.block_timer) if opponent else 0.0
- can_attack = is_in_attack_range(parent, opponent)
- in_danger = is_hitbox_overlapping_hurtbox(opponent, parent)
- opponent_attacking = opponent.is_attacking or opponent.is_dashing
- opponent_blocking = opponent.is_blocking or opponent.is_hit
- parent_health = parent.healthbar.current_health if parent.healthbar else 100.0
- is_low_health = parent_health < 50.0
- distance = abs(parent.global_position.x - opponent.global_position.x)
- is_cornered = parent.is_at_corner() if "is_at_corner" in parent else false
- opponent_jumping = opponent.is_jumping

- **if** parent.is_hit or parent.is_knockfly:
  - current_state = "defend"
  - recovery_timer = 0.5
  - block_timer = 0.5
  - state_timer = 0.5
  - print("Debug: AI hit or knockfly, entering defend state for %s" % parent.name)
  - return

- **match** current_state:
  - **"idle"**:
    - **if** last_action_time > 0.4:
      - **if** can_attack and distance < 45.0 and randf() > 0.05: current_state = "attack"
      - **elif** distance < 60.0 and randf() < random_poke_chance: current_state = "attack"
      - **elif** in_danger or (opponent_attacking and distance < 50.0): current_state = "defend"; block_timer = 0.5; state_timer = 0.5
      - **elif** is_cornered and distance < 80.0 and randf() > 0.3: current_state = "jump"; state_timer = 0.4
      - **elif** opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance: current_state = "attack"; state_timer = 0.5
      - **elif** distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance: current_state = "attack"; state_timer = 0.5
      - **elif** state_timer <= 0: current_state = "approach"; state_timer = randf() * 0.3 + 0.3
    - print debug: state, can_attack, in_danger 等

  - **"approach"**:
    - **if** last_action_time > 0.4:
      - **if** can_attack and distance < 45.0 and randf() > 0.05: current_state = "attack"
      - **elif** distance < 60.0 and randf() < random_poke_chance: current_state = "attack"
      - **elif** opponent_recovery_time < 0.1 and distance < 80.0 and randf() > 0.2: current_state = "attack"
      - **elif** opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance: current_state = "attack"; state_timer = 0.5
      - **elif** distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance: current_state = "attack"; state_timer = 0.5
      - **elif** in_danger or (opponent_attacking and distance < 50.0): current_state = "defend"; block_timer = 0.5; state_timer = 0.5
      - **elif** is_cornered and distance < 80.0 and randf() > 0.3: current_state = "jump"; state_timer = 0.4
      - **elif** state_timer <= 0: current_state = "approach" if distance > 40.0 else "idle"; state_timer = randf() * 0.3 + 0.3

  - **"attack"**:
    - **if** in_danger or (opponent_attacking and distance < 30.0): current_state = "defend"; block_timer = 0.5; state_timer = 0.5
    - **elif** distance > 45.0: current_state = "approach"; state_timer = randf() * 0.3 + 0.3
    - **elif** opponent_stun_remaining > 0.15 and distance < 40.0 and randf() > 0.1: state_timer = 0.3  # 追擊延長
    - **elif** opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance: state_timer = 0.5
    - **elif** distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance: state_timer = 0.5
    - **elif** state_timer <= 0 or distance > 40.0: current_state = "approach"; state_timer = randf() * 0.3 + 0.3

  - **"defend"**:
    - **if** recovery_timer > 0 or block_timer > 0: return
    - **if** not in_danger and (not opponent_attacking or distance > 50.0):
      - **if** opponent_recovery_time < 0.1 and can_attack and distance < 45.0 and randf() > 0.3: current_state = "attack"
      - **elif** opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance: current_state = "attack"; state_timer = 0.5
      - **elif** distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance: current_state = "attack"; state_timer = 0.5
      - **else**: current_state = "approach" if distance > 40.0 else "idle"; state_timer = randf() * 0.3 + 0.3
    - **elif** opponent_stun_remaining > 0.1 and randf() > 0.1: current_state = "attack"
    - **elif** state_timer <= 0: current_state = "approach" if distance > 40.0 else "idle"; state_timer = randf() * 0.3 + 0.3

  - **"jump"**:
    - **if** state_timer <= 0 or opponent.is_jumping: current_state = "approach"; state_timer = randf() * 0.3 + 0.3
    - **elif** in_danger or (opponent_attacking and distance < 50.0): current_state = "defend"; block_timer = 0.5; state_timer = 0.5
    - **elif** is_cornered and randf() > 0.4: state_timer = 0.4  # 延長逃角

- last_action_time += delta
- **if** parent and OS.is_debug_build(): print debug 狀態細節

## 輸入生成 (get_ai_input)
- **if** not ai_enabled: return build_input_dict(0, false, false, false, "none", 0.2, 0.0, false, false)
- 檢查健康：**if** parent_health <= 0.0 or opponent_health <= 0.0: return 空輸入
- 初始化：input_dir=0, crouch_pressed=false, jump_pressed=false, attack_pressed=false, spm1_pressed=false, dash_pressed=false, attack_type="none", blockstun_duration=0.2, damage=0.0
- opponent = get_opponent(); **if** not opponent: input_dir=1; return 字典
- distance, opponent_attacking, time_since_last=last_action_time, can_attack, in_danger, is_cornered, opponent_stun_remaining, opponent_recovery_time, opponent_jumping

- **if** parent.is_hit or parent.is_knockfly or block_timer > 0:
  - input_dir = -1 if parent.x < opponent.x else 1  # 後退
  - **if** crouch_timer > 0: crouch_pressed = is_crouching
  - **else**:
    - crouch_pressed = (opponent.is_crouching and opponent_attacking and randf() > 0.8) or (parent.is_hit and randf() > 0.8)
    - **if** crouch_pressed: crouch_timer=0.2; is_crouching=true; print crouch block
    - **else**: is_crouching=false; print standing block
  - return 字典（無攻擊）

- **移動邏輯**：
  - **if** distance > 100.0: input_dir = 向對手方向 (1 or -1)
  - **elif** distance > 40.0: input_dir = 向對手
  - **elif** distance < 35.0:
    - **if** can_attack: input_dir=0  # 靜止攻擊
    - **else**: input_dir = 遠離對手
  - **else**: input_dir=0  # 35-40 靜止
  - **if** in_danger and distance < 30.0: input_dir = 遠離
  - **穩定方向**：**if** input_dir_timer <= 0: last_input_dir = input_dir; input_dir_timer=0.5

- **狀態特定輸入**：
  - **"defend" or (in_danger and opponent_attacking)**:
    - input_dir = -last_input_dir if distance < 30.0 else 0
    - **if** in_danger or opponent_attacking or block_timer > 0: 類似上述 crouch/block 邏輯
    - **if** is_cornered and randf() > 0.5: jump_pressed=true; crouch_pressed=false; print corner escape
    - **else if** randf() > 0.98: input_dir=0  # 少見中立暫停
    - **elif** randf() > 0.98 and distance > 50.0: jump_pressed=true

  - **"approach"**:
    - **if** distance > 45.0: input_dir = 向對手; print forcing approach
    - **if** time_since_last > 0.3 and dash_cooldown <= 0:
      - **if** distance > 100.0 and not is_cornered and randf() > 0.7: dash_pressed=true; dash_cooldown=1.0
      - **elif** randf() > 0.98 and distance > 50.0: input_dir=-last_input_dir; input_dir_timer=0.5
      - **elif** opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance: jump_pressed=true; attack_pressed=true; damage=10.0; attack_type="attack"
      - **elif** distance > 40.0 and distance < 50.0 and randf() < proactive_jump_chance: jump_pressed=true; attack_pressed=true; damage=10.0; attack_type="attack"
      - **elif** distance > 50.0 and opponent_stun_remaining > 0.0 and randf() < 0.3: spm1_pressed=true; damage=20.0; attack_pressed=false
    - **if** is_cornered: input_dir=-last_input_dir; **if** randf() > 0.5: jump_pressed=true

  - **"attack"**:
    - **if** distance < 50.0 and time_since_last > 0.4 and distance < 45.0:
      - action_roll = randf()
      - **if** (opponent_stun_remaining > 0.05 or randf() < 0.3) and action_roll < 0.4: spm1_pressed=true; damage=20.0
      - **elif** opponent_recovery_time < 0.1 and action_roll < 0.4: spm1_pressed=true; damage=20.0
      - **elif** opponent_jumping and distance < 50.0 and can_attack and action_roll < 0.5: jump_pressed=true; attack_pressed=true; damage=10.0; attack_type="attack"
      - **elif** distance > 40.0 and distance < 50.0 and action_roll < 0.5: jump_pressed=true; attack_pressed=true; damage=10.0; attack_type="attack"
      - **else**: attack_pressed=true; damage=10.0; attack_type="attack"
      - state_timer=0.4
    - **else if** distance > 45.0: print too far
    - **if** randf() > 0.98 and distance > 50.0: input_dir=0
    - **elif** distance > 50.0 and randf() < 0.2: spm1_pressed=true; damage=20.0

  - **"jump"**:
    - jump_pressed=true; crouch_pressed=false; crouch_timer=0.0; is_crouching=false
    - input_dir = last_input_dir * (-1 if is_cornered else 1)
    - **if** opponent_jumping and distance < 50.0 and can_attack and randf() < jump_attack_chance: attack_pressed=true; damage=10.0; attack_type="attack"

- **低血邏輯**：**if** parent_health < 50.0:
  - **if** randf() > 0.3: attack_pressed = true if can_attack and distance < 45.0 else false
  - spm1_pressed = true if distance > 30 and randf() > 0.4 else false

- **跟跳攻擊**：**if** opponent_jumping and distance < 50.0 and can_attack and randf() > 0.4:
  - jump_pressed=true; attack_pressed=true; damage=10.0; attack_type="attack"; crouch_pressed=false; crouch_timer=0.0; is_crouching=false

- print debug 輸入細節
- return build_input_dict(...)

## 輔助函數
- **is_in_attack_range(attacker: Node, target: Node) -> bool**：
  - **if** not attacker.Hitbox or not target.Hurtbox: return false
  - hitbox = attacker.Hitbox; hurtbox = target.Hurtbox
  - **foreach** area in hitbox.overlapping_areas: **if** area == hurtbox and area.parent != attacker: return true
  - distance = abs(attacker.x - target.x)
  - return distance < 45.0  # 匹配 Hitbox 大小 (25+13.5)

- **is_hitbox_overlapping_hurtbox(attacker: Node, target: Node) -> bool**：類似上述，檢查 attacker.Hitbox 與 target.Hurtbox 重疊。

- **is_opponent_close(opponent: Node) -> bool**：distance < 30.0

- **build_input_dict(input_dir: int, crouch: bool, jump: bool, attack: bool, a_type: String, bstun: float, dmg: float, spm1: bool, dash: bool) -> Dictionary**：
  - return { "input_dir": input_dir, "crouch_pressed": crouch, "jump_pressed": jump, "attack_pressed": attack, "attack_type": a_type, "blockstun_duration": bstun, "damage": dmg, "spm1_pressed": spm1, "dash_pressed": dash }

- **get_opponent() -> Node**：
  - all_players = get_tree().get_nodes_in_group("players")
  - **foreach** p in all_players: **if** p != parent: return p
  - return null