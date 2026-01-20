# AI System Architecture - 2ndFight

## 概述 (Overview)

新的 AI 系統採用**分層決策架構**，提供更智能、更準確的 AI 行為。系統由 6 個核心模組組成，每個模組負責特定功能。

The new AI system uses a **layered decision architecture** for more intelligent and accurate AI behavior. The system consists of 6 core modules, each responsible for specific functionality.

## 架構圖 (Architecture Diagram)

```
AIBehavior (Main Controller - 主控制器)
│
├── ThreatAssessment (威脅評估系統)
│   └── Detects and evaluates incoming threats
│       - Ground attacks (地面攻擊)
│       - Projectiles (飛行道具)
│       - Air attacks (空中攻擊)
│
├── AIDecisionLayers (分層決策系統)
│   ├── Layer 1: SURVIVAL (100) - 生存層
│   ├── Layer 2: PUNISH (90) - 懲罰層
│   ├── Layer 3: TACTICAL (50-70) - 戰術層
│   ├── Layer 4: POSITIONING (30) - 定位層
│   └── Layer 5: IDLE (10) - 待機層
│
├── FrameDataManager (幀數據管理器)
│   └── Precise frame data for all moves
│       - Startup frames (啟動幀)
│       - Active frames (活躍幀)
│       - Recovery frames (恢復幀)
│
├── AIComboSystem (連段系統)
│   └── Pre-defined combo library
│       - Combo execution tracking (連段執行追蹤)
│       - Distance-based combo selection (距離選擇)
│
└── SpaceControl (空間控制)
    └── Position and distance management
        - Zone detection (區域檢測)
        - Corner escape (角落逃脫)
        - Ideal distance calculation (理想距離計算)
```

## 核心模組 (Core Modules)

### 1. AIBehavior.gd (主控制器)

**職責 (Responsibilities):**
- 初始化和管理所有子系統
- 協調各模組之間的通信
- 將決策轉換為遊戲輸入
- 處理連段執行流程

**關鍵方法 (Key Methods):**
- `get_ai_input()` - 獲取 AI 輸入（主要入口）
- `_action_to_input(action: String)` - 動作轉輸入
- `set_ai_enabled(enabled: bool)` - 啟用/停用 AI
- `find_opponent()` - 尋找對手

### 2. ThreatAssessment.gd (威脅評估)

**職責 (Responsibilities):**
- 即時檢測攻擊威脅
- 計算威脅等級和反應時間
- 推薦最佳防禦策略

**威脅等級 (Threat Levels):**
- `CRITICAL` (< 8 幀) - 立即格擋
- `HIGH` (8-15 幀) - 準備防禦
- `MEDIUM` (15-25 幀) - 調整距離
- `LOW` (> 25 幀) - 主動進攻
- `NONE` - 無威脅

**關鍵方法 (Key Methods):**
- `evaluate_threats(ai_player, opponent)` - 評估所有威脅
- `_evaluate_attack_threat()` - 評估地面攻擊
- `_evaluate_projectile_threat()` - 評估飛行道具
- `_calculate_frames_to_hit()` - 計算擊中幀數

### 3. AIDecisionLayers.gd (分層決策)

**職責 (Responsibilities):**
- 基於優先級的決策系統
- 情境感知的動作選擇
- 多層次戰術規劃

**決策層級 (Decision Layers):**

1. **SURVIVAL (100)** - 生存層
   - 處理緊急威脅
   - 立即防禦反應
   - 最高優先級

2. **PUNISH (90)** - 懲罰層
   - 檢測對手硬直
   - 選擇最佳懲罰招式
   - 利用幀優勢

3. **TACTICAL (50-70)** - 戰術層
   - 距離管理
   - 攻擊選擇
   - 連段執行

4. **POSITIONING (30)** - 定位層
   - 空間控制
   - 距離調整
   - 角落逃脫

5. **IDLE (10)** - 待機層
   - 預設行為
   - 隨機動作
   - 最低優先級

**關鍵方法 (Key Methods):**
- `get_best_decision(ai_player, opponent)` - 獲取最佳決策
- `_evaluate_survival_layer()` - 評估生存層
- `_evaluate_punish_layer()` - 評估懲罰層
- `_evaluate_tactical_layer()` - 評估戰術層

### 4. FrameDataManager.gd (幀數據管理)

**職責 (Responsibilities):**
- 儲存所有招式的幀數據
- 精確計算恢復幀數
- 判斷對手狀態

**幀數據結構 (Frame Data Structure):**
```gdscript
{
    "move_name": {
        "startup": 5,    # 啟動幀
        "active": 3,     # 活躍幀
        "recovery": 8,   # 恢復幀
        "total": 16      # 總幀數
    }
}
```

**關鍵方法 (Key Methods):**
- `get_startup_frames(move_name)` - 獲取啟動幀數
- `get_recovery_frames_remaining(player)` - 獲取剩餘恢復幀
- `is_in_recovery(player)` - 判斷是否在恢復中

### 5. AIComboSystem.gd (連段系統)

**職責 (Responsibilities):**
- 管理預設連段庫
- 追蹤連段執行狀態
- 判斷連段可行性

**連段結構 (Combo Structure):**
```gdscript
{
    "combo_name": {
        "moves": ["st_mp", "st_mk", "fireball"],
        "conditions": {"distance_max": 95},
        "damage": 42.0
    }
}
```

**關鍵方法 (Key Methods):**
- `get_available_combos()` - 獲取可用連段
- `start_combo(combo_id)` - 開始執行連段
- `get_next_combo_move()` - 獲取下一招
- `is_executing_combo()` - 是否正在執行連段

### 6. SpaceControl.gd (空間控制)

**職責 (Responsibilities):**
- 區域判斷和管理
- 角落檢測和逃脫
- 理想距離計算

**區域定義 (Zone Definitions):**
- `FAR` (> 250px) - 遠距離
- `MID` (100-250px) - 中距離
- `CLOSE` (< 100px) - 近距離
- `CORNER` - 角落狀態

**關鍵方法 (Key Methods):**
- `get_current_zone()` - 獲取當前區域
- `is_in_corner()` - 是否在角落
- `get_ideal_distance()` - 獲取理想距離
- `get_escape_action()` - 獲取逃脫動作

## 整合方式 (Integration)

### 1. 角色場景 (Character Scene)

每個角色場景（DAV.tscn, DEN.tscn）應包含：
```
Player (extends Fighter)
├── AIBehavior (自動初始化子系統)
├── PlayerController
└── MoveSet
```

### 2. 啟用 AI (Enable AI)

通過 `cpu_controller.gd` 或直接調用：
```gdscript
var ai_behavior = player.get_node("AIBehavior")
ai_behavior.set_ai_enabled(true)
```

### 3. 獲取輸入 (Get Input)

Player.gd 已整合：
```gdscript
func get_input() -> Dictionary:
    if is_ai_controlled:
        var ai = $AIBehavior
        if ai: return ai.get_ai_input()
    # ... player input
```

## 調試模式 (Debug Mode)

啟用調試輸出：
```gdscript
ai_behavior.debug_mode = true
```

調試輸出示例：
```
[AI] stand_block (priority: 100.0) - Threat: st_mk
[AI] st_mk (priority: 90.0) - Punish opportunity
[AI] Combo step: st_mp
```

## 效能優勢 (Performance Benefits)

| 特性 | 舊版 AI | 新版 AI |
|------|---------|---------|
| 決策速度 | 0.4s 統一冷卻 | 分層即時 (0-0.1s) |
| 格擋能力 | 需切換狀態 | 威脅自動觸發 |
| 攻擊選擇 | 隨機 | 情境感知 |
| 連段能力 | 無 | 預設庫支援 |
| 可維護性 | 單文件混亂 | 模組化清晰 |
| 反應準確度 | 基於距離 | 基於幀數據 |

## 擴展指南 (Extension Guide)

### 添加新招式 (Add New Move)

1. 在 `FrameDataManager.gd` 中添加幀數據：
```gdscript
frame_database["new_move"] = {
    "startup": 8, "active": 4, "recovery": 12, "total": 24
}
```

2. 在 `ThreatAssessment.gd` 中添加範圍：
```gdscript
attack_ranges["new_move"] = 110.0
startup_frames["new_move"] = 8
```

### 添加新連段 (Add New Combo)

在 `AIComboSystem.gd` 的 `combo_database` 中添加：
```gdscript
"new_combo": {
    "moves": ["st_mp", "new_move"],
    "conditions": {"distance_max": 80},
    "damage": 30.0
}
```

### 調整決策優先級 (Adjust Decision Priorities)

在 `AIDecisionLayers.gd` 中修改各層的 `priority` 值。

## 已知限制 (Known Limitations)

1. 連段系統當前使用簡單的順序執行，不支援分支
2. 威脅評估不考慮多個同時威脅的優先級
3. 幀數據需要手動維護和更新

## 未來改進 (Future Improvements)

- [ ] 動態學習對手模式
- [ ] 更複雜的連段分支系統
- [ ] 多威脅同時處理優先級
- [ ] 自動幀數據提取
- [ ] 角色特定戰術模板
- [ ] 難度等級系統

## 維護者 (Maintainers)

- GitHub Copilot AI
- KellifizW

## 授權 (License)

MIT License
