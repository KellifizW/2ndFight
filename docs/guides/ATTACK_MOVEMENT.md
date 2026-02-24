# 攻擊移動系統使用指南

## 概述

攻擊移動系統允許你為每個攻擊動作添加**移動距離**和**加速度曲線**，讓角色在攻擊時向前或向後移動，並且支援多種不同的加速度模式（線性、加速-減速、爆發-減速等）。

## 架構說明

### 核心文件
- **AttackMovement.gd**: 移動資源類，定義移動屬性和曲線計算
- **AttackData.gd**: 攻擊數據資源類，每個攻擊都有 `*_movement` 屬性
- **Player.gd**: 主要邏輯，包含 `_process_attack_movement()` 和 `_execute_attack()`

### 工作流程
1. 創建 AttackMovement 資源（.tres 文件或代碼）
2. 在 AttackData 資源中將 AttackMovement 賦值給對應攻擊的 `*_movement` 屬性
3. 當玩家執行攻擊時，Player.gd 自動啟動移動系統
4. 每幀根據曲線類型計算速度並更新角色位置

---

## 1. 移動曲線類型

AttackMovement 支援 **7 種曲線類型**：

| 曲線類型 | 說明 | 適用場景 |
|---------|------|---------|
| `NONE` | 無移動 | 原地攻擊（默認） |
| `LINEAR` | 線性勻速移動 | 滑步攻擊、dash attack |
| `EASE_IN_OUT` | 加速-減速（S型曲線） | 平滑的衝刺重拳 |
| `EASE_IN` | 逐漸加速 | 蓄力衝刺 |
| `EASE_OUT` | 逐漸減速 | 突進後剎車 |
| `BURST` | 爆發-緩降（開始快速，然後減速） | 爆發重拳、飛踢 |
| `DASH` | 快速衝刺-慣性滑行（75%維持高速，25%減速） | 衝刺攻擊 |
| `CUSTOM` | 自訂曲線（使用 Godot Curve 資源） | 複雜動作 |

---

## 2. 屬性說明

### 基礎屬性

```gdscript
@export var distance: float = 0.0          # 移動總距離（像素）
@export var duration: float = 0.3          # 移動持續時間（秒）
@export var curve_type: MovementCurve = MovementCurve.NONE  # 曲線類型
```

### 進階屬性

```gdscript
@export var start_delay: float = 0.0      # 起始延遲（秒），例如動畫前搖不移動
@export var acceleration_ratio: float = 0.5  # 加速階段比例（0.0-1.0），用於 EASE_IN_OUT
@export var peak_speed_multiplier: float = 1.5  # 峰值速度倍率，用於 BURST/DASH
```

### 方向控制

```gdscript
@export var use_facing_direction: bool = true   # 使用角色朝向（true=面向方向移動）
@export var reverse_direction: bool = false     # 反向移動（true=向後移動）
@export var lock_direction: bool = true          # 鎖定移動方向（不受 facing_direction 改變影響）
```

### 物理屬性

```gdscript
@export var ignore_walls: bool = false          # 忽略牆壁碰撞（穿牆攻擊）
@export var can_be_blocked: bool = true         # 移動是否可被阻擋（受擊時停止）
```

---

## 3. 使用範例

### 範例 1: 簡單向前衝刺重拳（線性移動）

```gdscript
# data/attack_movement/st_hp_movement.gd
extends AttackMovement

func _init():
    distance = 80.0              # 向前移動 80 像素
    duration = 0.25              # 0.25 秒內完成
    curve_type = MovementCurve.LINEAR  # 勻速移動
    use_facing_direction = true  # 使用角色朝向
```

**在 AttackData 中使用**：
```gdscript
# 在 Godot 編輯器中：
# 1. 創建新的 AttackMovement 資源：右鍵 data/ → New Resource → AttackMovement
# 2. 設置屬性（distance=80, duration=0.25, curve_type=LINEAR）
# 3. 保存為 st_hp_movement.tres
# 4. 在 AttackData 資源中，將 st_hp_movement 拖入 st_hp_movement 屬性
```

---

### 範例 2: 爆發重拳（快速啟動-緩慢減速）

```gdscript
var burst_movement = AttackMovement.create_burst_lunge(
    120.0,    # 移動距離 120 像素
    0.35,     # 持續時間 0.35 秒
    2.0       # 峰值速度是平均速度的 2 倍
)

# 手動創建版本：
var burst_movement = AttackMovement.new()
burst_movement.distance = 120.0
burst_movement.duration = 0.35
burst_movement.curve_type = AttackMovement.MovementCurve.BURST
burst_movement.peak_speed_multiplier = 2.0
burst_movement.use_facing_direction = true
```

**數學說明**：
- 平均速度 = 120 / 0.35 ≈ 343 像素/秒
- 峰值速度 = 343 × 2.0 = 686 像素/秒（開始時）
- 速度曲線：使用三次方緩出函數（cubic ease-out）

---

### 範例 3: 平滑衝刺（加速-減速）

```gdscript
var smooth_dash = AttackMovement.create_smooth_dash(
    150.0,    # 移動距離 150 像素
    0.4       # 持續時間 0.4 秒
)

# 或手動配置：
var smooth_dash = AttackMovement.new()
smooth_dash.distance = 150.0
smooth_dash.duration = 0.4
smooth_dash.curve_type = AttackMovement.MovementCurve.EASE_IN_OUT
smooth_dash.acceleration_ratio = 0.5  # 前 50% 加速，後 50% 減速
```

**速度變化**：
- 0% → 50%: 從 0 加速到最大速度（使用三次方緩入）
- 50% → 100%: 從最大速度減速到 0（使用三次方緩出）

---

### 範例 4: 向後退攻擊（反向移動）

```gdscript
var retreat_attack = AttackMovement.new()
retreat_attack.distance = 50.0
retreat_attack.duration = 0.2
retreat_attack.curve_type = AttackMovement.MovementCurve.LINEAR
retreat_attack.use_facing_direction = true
retreat_attack.reverse_direction = true  # 向後移動
```

**效果**：角色在執行攻擊時向後退 50 像素。

---

### 範例 5: 延遲移動（前搖不動，後期衝刺）

```gdscript
var delayed_dash = AttackMovement.new()
delayed_dash.distance = 100.0
delayed_dash.duration = 0.3
delayed_dash.start_delay = 0.15  # 前 0.15 秒不移動
delayed_dash.curve_type = AttackMovement.MovementCurve.DASH
```

**時間軸**：
- 0.00s - 0.15s: 不移動（前搖動畫）
- 0.15s - 0.30s: 快速衝刺 100 像素

---

### 範例 6: 自訂曲線

```gdscript
# 先在 Godot 編輯器中創建 Curve 資源：
# 1. 右鍵 → New Resource → Curve
# 2. 設計自己的速度曲線（例如：鋸齒狀、波浪狀）
# 3. 保存為 custom_attack_curve.tres

var custom_movement = AttackMovement.new()
custom_movement.distance = 90.0
custom_movement.duration = 0.35
custom_movement.curve_type = AttackMovement.MovementCurve.CUSTOM
custom_movement.custom_curve = preload("res://data/curves/custom_attack_curve.tres")
```

---

## 4. 靜態工廠方法

AttackMovement 提供便捷的創建方法：

```gdscript
# 1. 線性衝刺
var linear = AttackMovement.create_linear_dash(distance, duration)

# 2. 平滑衝刺（加速-減速）
var smooth = AttackMovement.create_smooth_dash(distance, duration)

# 3. 爆發衝刺（快速啟動-緩慢減速）
var burst = AttackMovement.create_burst_lunge(distance, duration, peak_speed_mult)

# 4. 快速衝刺（75% 維持高速，25% 減速）
var dash = AttackMovement.create_dash_attack(distance, duration, peak_speed_mult)
```

---

## 5. 在 Inspector 中配置

### 方法 A: 使用編輯器創建

1. **創建 AttackMovement 資源**：
   - 右鍵 `data/` 資料夾 → `New Resource` → 搜尋 `AttackMovement`
   - 設置屬性（distance, duration, curve_type 等）
   - 保存為 `st_hp_movement.tres`

2. **綁定到 AttackData**：
   - 打開 AttackData 資源（例如 `player_attacks.tres`）
   - 找到 `st_hp_movement` 屬性
   - 拖入剛才創建的 `st_hp_movement.tres`

3. **測試**：
   - 執行遊戲
   - 按下 st_hp 按鈕
   - 角色應該會向前移動並攻擊

### 方法 B: 使用代碼動態創建

```gdscript
# 在 Player._ready() 中動態設置
func _ready():
    super._ready()
    
    # 為 st_hp 設置移動
    var hp_movement = AttackMovement.create_burst_lunge(120.0, 0.35, 2.0)
    attack_data.st_hp_movement = hp_movement
    
    # 為 st_lp 設置輕微移動
    var lp_movement = AttackMovement.create_linear_dash(30.0, 0.15)
    attack_data.st_lp_movement = lp_movement
```

---

## 6. 進階技巧

### 技巧 1: 不同力量的攻擊使用不同移動

```gdscript
# 輕拳：小距離線性移動
st_lp_movement = AttackMovement.create_linear_dash(30.0, 0.15)

# 中拳：中距離平滑移動
st_mp_movement = AttackMovement.create_smooth_dash(60.0, 0.25)

# 重拳：長距離爆發移動
st_hp_movement = AttackMovement.create_burst_lunge(120.0, 0.35, 2.0)
```

### 技巧 2: 蹲下攻擊使用更小移動

```gdscript
# 站立攻擊
st_hp_movement.distance = 100.0

# 蹲下攻擊（更短距離）
cr_hp_movement.distance = 50.0
cr_hp_movement.curve_type = AttackMovement.MovementCurve.LINEAR
```

### 技巧 3: 特殊動作組合

```gdscript
# 第一段：快速衝刺
var rush_part1 = AttackMovement.create_dash_attack(150.0, 0.3, 2.0)

# 第二段：剎車攻擊（向後退）
var rush_part2 = AttackMovement.new()
rush_part2.distance = 40.0
rush_part2.duration = 0.2
rush_part2.curve_type = AttackMovement.MovementCurve.EASE_OUT
rush_part2.reverse_direction = true

# 在動畫中切換（使用動畫事件或取消系統）
```

---

## 7. 調試技巧

### 檢查移動是否啟動

在 Player.gd 的 `_start_attack_movement` 中添加 print：

```gdscript
func _start_attack_movement(attack_name: String) -> void:
    if not attack_name in ATTACK_TABLE:
        return
    
    var attack_dict = ATTACK_TABLE[attack_name]
    if not "movement" in attack_dict or attack_dict.movement == null:
        print("[Movement] %s 沒有設定移動" % attack_name)
        return
    
    current_attack_movement = attack_dict.movement
    attack_movement_timer = 0.0
    attack_movement_active = true
    
    print("[Movement] 啟動 %s 移動：距離=%d, 持續時間=%.2f, 曲線=%s" % [
        attack_name,
        current_attack_movement.distance,
        current_attack_movement.duration,
        current_attack_movement.curve_type
    ])
```

### 可視化速度曲線

在 FrameBar.gd 或新的 Debug 節點中添加：

```gdscript
func _draw():
    if player.attack_movement_active and player.current_attack_movement:
        var movement = player.current_attack_movement
        var time_progress = (player.attack_movement_timer - movement.start_delay) / movement.duration
        time_progress = clamp(time_progress, 0.0, 1.0)
        
        var speed_mult = movement.get_speed_multiplier(time_progress * movement.duration)
        
        # 繪製速度條
        var bar_width = 100
        var bar_height = 10
        var fill_width = bar_width * speed_mult / movement.peak_speed_multiplier
        
        draw_rect(Rect2(10, 10, bar_width, bar_height), Color.DARK_GRAY)
        draw_rect(Rect2(10, 10, fill_width, bar_height), Color.GREEN)
```

---

## 8. 性能考量

- **每幀計算**：移動系統在 `_physics_process()` 中每幀執行一次，性能消耗極低
- **內存**：每個 AttackMovement 資源約佔用 200-300 bytes
- **建議**：如果有 20+ 個攻擊動作，可以共用相同的 AttackMovement 資源

```gdscript
# 共用資源範例
var light_punch_movement = AttackMovement.create_linear_dash(30.0, 0.15)

# 所有輕拳使用同一個資源
attack_data.st_lp_movement = light_punch_movement
attack_data.cr_lp_movement = light_punch_movement
attack_data.jump_lp_movement = light_punch_movement
```

---

## 9. 常見問題

### Q: 攻擊移動時撞牆會怎樣？
A: 默認情況下，角色會停在牆邊（由 Movement.gd 的碰撞處理）。如果設置 `ignore_walls = true`，角色可以穿牆。

### Q: 如何讓攻擊移動在空中也生效？
A: 空中攻擊同樣支持移動，只需在 `jump_mp_movement` 或 `jump_mk_movement` 中設置即可。

### Q: 移動方向會受對手位置影響嗎？
A: 不會。移動方向由 `use_facing_direction` 和 `reverse_direction` 決定，不受對手位置影響。如果需要自動調整方向，修改 `_process_attack_movement()` 中的 `move_direction` 計算。

### Q: 如何讓特定攻擊不移動？
A: 將該攻擊的 `*_movement` 設為 `null`，或將 `distance` 設為 0。

---

## 10. 數學原理

### EASE_IN_OUT 曲線公式

```gdscript
func _ease_in_cubic(t: float) -> float:
    return t * t * t  # y = x³

func _ease_out_cubic(t: float) -> float:
    var f = t - 1.0
    return f * f * f + 1.0  # y = (x-1)³ + 1
```

### BURST 曲線（三次方緩出）

```
速度倍率 = 1.0 + (peak_speed_multiplier - 1.0) * (1 - t)³
```

### DASH 曲線（75% 高速 + 25% 減速）

```
if t < 0.75:
    速度倍率 = peak_speed_multiplier
else:
    速度倍率 = peak_speed_multiplier * (1 - (t - 0.75) / 0.25)³
```

---

## 11. 總結

攻擊移動系統提供了：
- ✅ **靈活的曲線類型**：7 種預設曲線 + 自訂曲線
- ✅ **簡單的配置**：在 Inspector 中拖放資源即可
- ✅ **高效的性能**：每幀計算，無額外開銷
- ✅ **完整的方向控制**：支援前進、後退、鎖定方向
- ✅ **物理整合**：與固定點物理系統完美配合

**下一步**：
1. 為現有攻擊創建 AttackMovement 資源
2. 調整 `distance` 和 `duration` 以匹配動畫速度
3. 測試不同曲線類型的視覺效果
4. 根據角色風格調整移動參數（例如：重型角色使用 BURST，速度型角色使用 DASH）
