# Sakuga Engine 摔投系統最佳實踐教學 (GDScript 版本)

## 目錄
1. [系統架構概述](#系統架構概述)
2. [為什麼選擇這個方案](#為什麼選擇這個方案)
3. [實作步驟](#實作步驟)
4. [完整代碼示例](#完整代碼示例)
5. [在 Godot 編輯器中配置](#在-godot-編輯器中配置)
6. [測試與除錯](#測試與除錯)
7. [常見問題](#常見問題)

---

## 系統架構概述

### 核心理念：關注點分離

```
┌─────────────────────────────────────────────────┐
│           摔投系統三大組件                        │
├─────────────────────────────────────────────────┤
│                                                 │
│  1. ThrowPivot (位置控制)                       │
│     └─ 控制被摔者在每一幀的位置                  │
│     └─ 可以設定多個時間點形成軌跡                │
│                                                 │
│  2. AnimationEvent (時機控制)                   │
│     └─ 決定何時釋放對手                         │
│     └─ 可以加入條件判斷                         │
│     └─ 支援 Rollback Netcode                    │
│                                                 │
│  3. ThrowDetachmentSettings (參數設定)          │
│     └─ 擊退速度、硬直時間等數值                  │
│     └─ 可重複使用的資源                         │
│                                                 │
└─────────────────────────────────────────────────┘
```

### 資料流程

```
執行摔技 → 循環更新位置 (ThrowPivot)
         ↓
    Frame 29 到達
         ↓
    AnimationEvent 觸發
         ↓
    ThrowReleaseEvent.execute()
         ↓
    檢查條件（是否被抓、是否逃脫）
         ↓
    應用 ThrowDetachmentSettings
         ↓
    對手被拋出 （設定速度、硬直）
```

---

## 為什麼選擇這個方案

### ✅ 業界標準
- **Arc System Works** (Guilty Gear Strive)
- **Capcom** (Street Fighter 6)  
- **Lab Zero Games** (Skullgirls)

都使用類似的 Frame-based Event System

### ✅ Rollback Netcode 相容
```gdscript
# AnimationEvent 是確定性的
func _process_frame_29():
    if animation_events.has(29):
        animation_events[29].execute(self)
    # 每次 rollback 重放都會得到相同結果
```

### ✅ 幀精確控制
```gdscript
# 不依賴時間，只依賴幀數
var current_frame = 29  # 精確到幀
# 不是：var current_time = 0.483  # 會受幀率影響
```

### ✅ 易於維護和擴展
```gdscript
# 想要延後拋出時機？
throw_release_event.frame = 29  # 改成 → 32

# 想要改拋出強度？
throw_detach_settings.knockback.x = -25000  # 改數值即可

# 想要多段摔投？
# 新增多個 ThrowReleaseEvent，不同 frame
```

---

## 實作步驟

### 步驟 1：創建 ThrowReleaseEvent (GDScript)

創建文件：`Scripts/SakugaEngine/Resources/Animation Events/throw_release_event.gd`

```gdscript
@tool
extends Resource
class_name ThrowReleaseEvent

## 摔投釋放事件
## 在指定幀數釋放被摔的對手
## 用於 AnimationEventsList 系統

@export var target_index: int = 0  ## 目標對手索引（通常為 0）
@export var release_settings: ThrowDetachmentSettings  ## 釋放參數設定

## 實現 IAnimationEvent 介面
func execute(owner: SakugaActor) -> void:
	if not owner is SakugaFighter:
		push_error("ThrowReleaseEvent 只能用於 SakugaFighter")
		return
	
	var fighter = owner as SakugaFighter
	execute_throw_release(fighter)


## 執行摔投釋放邏輯
func execute_throw_release(fighter: SakugaFighter) -> void:
	# 獲取對手
	var opponent = fighter.get_opponent()
	if not opponent:
		print("警告：找不到對手")
		return
	
	# 檢查對手是否處於被抓狀態
	if not opponent.is_grabbed():
		print("警告：對手未被抓住，無法釋放")
		return
	
	# 檢查釋放設定
	if not release_settings:
		push_error("ThrowReleaseEvent 缺少 release_settings 設定")
		return
	
	# === 執行釋放 ===
	var side = fighter.body.player_side
	
	# 設定對手方向
	if release_settings.invert_side:
		opponent.body.player_side = -side
	else:
		opponent.body.player_side = side
	
	# 設定硬直類型
	opponent.hitstun_type = release_settings.hitstun_type
	
	# 啟動硬直時間
	opponent.hit_stun.start(release_settings.hitstun)
	
	# 設定彈牆效果
	opponent.h_bounce_intensity = release_settings.horizontal_bounce_intensity
	opponent.v_bounce_intensity = release_settings.vertical_bounce_intensity
	
	if release_settings.horizontal_bounce > 0:
		opponent.horizontal_bounce.start(release_settings.horizontal_bounce)
	
	if release_settings.vertical_bounce > 0:
		opponent.vertical_bounce.start(release_settings.vertical_bounce)
	
	# 推動角色（設定初始速度）
	opponent.push_character(
		release_settings.hit_knockback_time,
		release_settings.hit_knockback.x * side,
		release_settings.hit_knockback.y,
		release_settings.hit_knockback_gravity,
		release_settings.hit_knockback_inertia
	)
	
	print("摔投釋放成功 - Frame: ", fighter.animator.frame)
```

---

### 步驟 2：修改 SakugaFighter 的 ThrowPivoting

**目標：** 移除 `ThrowPivoting()` 中的釋放邏輯，只保留位置控制

找到文件：`Scripts/SakugaEngine/Components/SakugaFighter.cs`（或 .gd 版本）

修改 `throw_pivoting()` 方法：

```gdscript
func throw_pivoting() -> void:
	var curr_state = get_opponent().animator.get_current_state()
	if curr_state.throw_pivot.is_empty():
		return
	
	for i in range(curr_state.throw_pivot.size()):
		var next_frame = curr_state.duration
		if i + 1 < curr_state.throw_pivot.size():
			next_frame = curr_state.throw_pivot[i + 1].frame
		
		var current_pivot = curr_state.throw_pivot[i]
		
		if animator.frame >= current_pivot.frame and animator.frame < next_frame:
			var side = get_opponent().body.player_side
			
			# 切換受擊動畫
			var hit_reaction = current_pivot.throw_state
			if hit_reaction >= 0:
				animator.play_state(stance.get_current_stance().hit_reactions[hit_reaction], true)
			
			# === 只處理位置控制 ===
			# 移除了 ThrowDetach 的判斷和執行
			# 這些邏輯現在由 ThrowReleaseEvent 處理
			
			body.fixed_velocity = Vector2i.ZERO
			body.fixed_position.x = get_opponent().body.fixed_position.x + current_pivot.pivot_position.x * side
			body.fixed_position.y = get_opponent().body.fixed_position.y + current_pivot.pivot_position.y
	
	# 防止角色太靠近牆壁
	var pushback_side = 1 if body.fixed_position.x > 0 else -1
	if abs(body.fixed_position.x - get_opponent().body.fixed_position.x) <= 5:
		get_opponent().body.fixed_position.x -= 5 * pushback_side
```

**關鍵改變：**
- ❌ 移除：`if currentPivot.ThrowDetach == null` 的判斷
- ❌ 移除：所有與 `ThrowDetach` 相關的釋放邏輯
- ✅ 保留：位置更新邏輯
- ✅ 保留：動畫切換邏輯

---

## 完整代碼示例

### 1. ThrowPivot 資源（位置控制）

在 Godot 編輯器中創建，或在 .tres 文件中：

```tres
[sub_resource type="Resource" id="ThrowPivot_1"]
script = ExtResource("ThrowPivot")
frame = 1
pivot_position = Vector2i(3000, 0)
throw_state = -1

[sub_resource type="Resource" id="ThrowPivot_2"]
script = ExtResource("ThrowPivot")
frame = 17
pivot_position = Vector2i(5000, 8000)
throw_state = -1

[sub_resource type="Resource" id="ThrowPivot_3"]
script = ExtResource("ThrowPivot")
frame = 21
pivot_position = Vector2i(0, 10000)
throw_state = -1

[sub_resource type="Resource" id="ThrowPivot_4"]
script = ExtResource("ThrowPivot")
frame = 25
pivot_position = Vector2i(-8000, 0)
throw_state = -1
```

**注意：** 這些 ThrowPivot **不包含** ThrowDetach，只控制位置

---

### 2. ThrowDetachmentSettings 資源（參數設定）

```tres
[sub_resource type="Resource" id="ThrowDetach_Settings"]
script = ExtResource("ThrowDetachmentSettings")
invert_side = false
hitstun_type = 2  # LAUNCH
hit_knockback = Vector2i(-20000, 60000)
hit_knockback_gravity = 200000
hit_knockback_time = 8
hit_knockback_inertia = true
hitstun = 50
horizontal_bounce = 0
horizontal_bounce_intensity = 0
vertical_bounce = 0
vertical_bounce_intensity = 0
```

---

### 3. ThrowReleaseEvent 資源（時機控制）

```tres
[sub_resource type="Resource" id="ThrowRelease_Event"]
script = ExtResource("throw_release_event.gd")
target_index = 0
release_settings = SubResource("ThrowDetach_Settings")
```

---

### 4. AnimationEventsList（將事件綁定到幀）

```tres
[sub_resource type="Resource" id="AnimEventList_Release"]
script = ExtResource("AnimationEventsList")
frame = 29  # 在第 29 幀觸發
events = Array[Object]([SubResource("ThrowRelease_Event")])
```

---

### 5. FighterState（完整狀態設定）

```tres
[resource]
script = ExtResource("FighterState")
state_name = "Throw_Sequence"
type = 2  # GRAPPLE
duration = 42

# 位置控制
throw_pivot = Array[Object]([
    SubResource("ThrowPivot_1"),
    SubResource("ThrowPivot_2"),
    SubResource("ThrowPivot_3"),
    SubResource("ThrowPivot_4")
])

# 事件控制（包含釋放事件）
animation_events = Array[Object]([
    SubResource("AnimEventList_Damage"),    # Frame 26: 造成傷害
    SubResource("AnimEventList_Release")    # Frame 29: 釋放對手
])

state_transitions = Array[Object]([SubResource("Transition_ToIdle")])
animation_settings = Array[Object]([SubResource("AnimSettings")])
```

---

## 在 Godot 編輯器中配置

### 方法 A：在 Inspector 中創建

1. **打開角色的狀態資源**
   - 路徑：`Fighters/YourCharacter/States/XX_Throw.tres`

2. **設定 Throw Pivot（位置）**
   ```
   Inspector → Throw Pivot (展開)
   → Add Element (添加 4-5 個)
   → 每個設定：
      - Frame: 1, 17, 21, 25
      - Pivot Position: 對應的相對位置
      - Throw State: -1 (或指定受擊動畫)
   ```

3. **創建 ThrowDetachmentSettings**
   ```
   右鍵 → New Resource → ThrowDetachmentSettings
   設定擊退參數：
   - Hit Knockback: Vector2i(-20000, 60000)
   - Hitstun: 50
   - Hit Knockback Gravity: 200000
   儲存為獨立資源（可重複使用）
   ```

4. **創建 ThrowReleaseEvent**
   ```
   Inspector → Animation Events
   → Add Element
   → Frame: 29
   → Events → Add Element
   → 選擇 Script: throw_release_event.gd
   → Release Settings: 拖入剛才的 ThrowDetachmentSettings
   ```

---

### 方法 B：複製現有範例

1. **複製 Kaede 的摔投狀態**
   ```
   Fighters/Kaede/States/60_Kaede_Throw_seq.tres
   → 複製到你的角色資料夾
   → 修改數值
   ```

2. **調整參數**
   - 修改 `throw_pivot` 的位置和幀數
   - 修改 `animation_events` 的觸發幀
   - 修改 `release_settings` 的力道

---

## 測試與除錯

### Debug 輸出

在 `throw_release_event.gd` 中添加詳細 log：

```gdscript
func execute_throw_release(fighter: SakugaFighter) -> void:
	print("=== ThrowReleaseEvent Debug ===")
	print("執行者: ", fighter.name)
	print("當前幀: ", fighter.animator.frame)
	
	var opponent = fighter.get_opponent()
	print("對手: ", opponent.name if opponent else "NULL")
	print("對手被抓狀態: ", opponent.is_grabbed() if opponent else false)
	
	if not opponent or not opponent.is_grabbed():
		print("❌ 釋放失敗：條件不符")
		return
	
	# ... 執行釋放邏輯 ...
	
	print("✅ 釋放成功")
	print("擊退速度: ", release_settings.hit_knockback)
	print("硬直時間: ", release_settings.hitstun)
	print("==============================")
```

---

### 常見問題排查

#### 問題 1：對手沒有被拋出

**檢查清單：**
```gdscript
# 1. AnimationEvent 是否在正確的幀觸發？
print("Animation Events: ", current_state.animation_events)

# 2. ThrowReleaseEvent 的 frame 是否正確？
for event_list in animation_events:
    print("Event Frame: ", event_list.frame)

# 3. 對手是否處於被抓狀態？
print("Opponent IsGrabbed: ", opponent.is_grabbed())
print("Opponent HitstunType: ", opponent.hitstun_type)

# 4. release_settings 是否為 null？
print("Release Settings: ", throw_release_event.release_settings)
```

#### 問題 2：拋出時機不對

```gdscript
# 檢查 AnimationEventsList 的執行
# 在 SakugaFighter 或 AnimationController 中：

func process_animation_events():
    for event_list in current_state.animation_events:
        if animator.frame == event_list.frame:
            print("觸發事件於幀: ", event_list.frame)
            for event in event_list.events:
                event.execute(self)
```

#### 問題 3：Rollback 後出現異常

```gdscript
# 確保所有狀態都可序列化：
func save_state(buffer: StreamPeerBuffer):
    buffer.put_u8(hitstun_type)  # 保存被抓狀態
    buffer.put_32(animator.frame)  # 保存當前幀
    # ... 其他狀態

func load_state(buffer: StreamPeerBuffer):
    hitstun_type = buffer.get_u8()
    animator.frame = buffer.get_32()
    # ... 恢復其他狀態
```

---

## 進階應用

### 1. 條件式摔投釋放

添加更多判斷條件：

```gdscript
# 在 throw_release_event.gd 中
func execute_throw_release(fighter: SakugaFighter) -> void:
	var opponent = fighter.get_opponent()
	
	# 基本檢查
	if not opponent or not opponent.is_grabbed():
		return
	
	# 進階條件：檢查對手是否成功逃脫
	if opponent.throw_escaped:
		print("對手已逃脫，取消釋放")
		return
	
	# 進階條件：檢查位置（例如：靠近牆壁時改變力道）
	if abs(opponent.body.fixed_position.x) > 800000:  # 靠近牆壁
		release_settings.hit_knockback.x *= 0.5  # 減少水平擊退
	
	# 進階條件：根據計量槽決定威力
	if fighter.variables.super_gauge >= 5000:
		release_settings.hitstun += 10  # 增加硬直
		fighter.variables.add_super_gauge(-1000)  # 消耗計量
	
	# 執行釋放...
```

---

### 2. 多段摔投

在同一個狀態添加多個 ThrowReleaseEvent：

```tres
# 第一段：Frame 15 - 小幅拋起
[sub_resource type="Resource" id="ThrowRelease_Part1"]
script = ExtResource("throw_release_event.gd")
release_settings = SubResource("ThrowDetach_Weak")

[sub_resource type="Resource" id="AnimEventList_Part1"]
frame = 15
events = Array[Object]([SubResource("ThrowRelease_Part1")])

# 第二段：Frame 29 - 強力摔下
[sub_resource type="Resource" id="ThrowRelease_Part2"]
script = ExtResource("throw_release_event.gd")
release_settings = SubResource("ThrowDetach_Strong")

[sub_resource type="Resource" id="AnimEventList_Part2"]
frame = 29
events = Array[Object]([SubResource("ThrowRelease_Part2")])
```

---

### 3. 可逃脫的摔投

結合 `ThrowEscape()` 系統：

```gdscript
# 在 SakugaFighter 中
func throw_escape() -> void:
	if not hit_stop.is_running():
		return
	if hitstun_type <= Global.HitstunType.STAGGER:
		return
	
	# 檢測連打輸入
	if inputs.is_being_pressed(inputs.current_history, Global.INPUT_ANY_BUTTON):
		hitstun_type = 0
		throw_escaped = true  # 標記已逃脫
		throw_escape_action()
		get_opponent().throw_escape_action()

# ThrowReleaseEvent 會檢查這個標記
func execute_throw_release(fighter: SakugaFighter) -> void:
	var opponent = fighter.get_opponent()
	
	# 檢查對手是否逃脫
	if opponent.throw_escaped:
		print("對手已逃脫摔投")
		return  # 不執行釋放
	
	# 正常釋放邏輯...
```

---

### 4. 方向相關的摔投

根據對手的輸入方向改變拋出方向：

```gdscript
func execute_throw_release(fighter: SakugaFighter) -> void:
	var opponent = fighter.get_opponent()
	var side = fighter.body.player_side
	
	# 檢查對手的輸入方向
	var opponent_input = opponent.inputs.input_history[opponent.inputs.current_history].raw_input
	
	# 如果對手按向前（嘗試掙脫）
	if opponent_input & Global.INPUT_RIGHT and side > 0:
		# 改變拋出方向為向前
		release_settings.hit_knockback.x = abs(release_settings.hit_knockback.x)
	elif opponent_input & Global.INPUT_LEFT and side < 0:
		release_settings.hit_knockback.x = abs(release_settings.hit_knockback.x)
	
	# 執行釋放...
```

---

## 性能優化建議

### 1. 資源重複使用

```gdscript
# 創建共用的 ThrowDetachmentSettings
# res://Shared/ThrowSettings/standard_throw.tres
# res://Shared/ThrowSettings/power_throw.tres
# res://Shared/ThrowSettings/air_throw.tres

# 所有角色共用這些設定，減少記憶體
```

### 2. 事件池（如果有大量角色）

```gdscript
# 全域事件管理器
class_name ThrowEventManager

static var event_pool: Array[ThrowReleaseEvent] = []

static func get_event() -> ThrowReleaseEvent:
	if event_pool.is_empty():
		return ThrowReleaseEvent.new()
	return event_pool.pop_back()

static func return_event(event: ThrowReleaseEvent) -> void:
	event_pool.append(event)
```

---

## 與 C# 版本的對比

| 特性 | GDScript 版本 | C# 版本 |
|------|--------------|---------|
| 執行速度 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 開發速度 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 類型安全 | ⭐⭐⭐ (動態類型) | ⭐⭐⭐⭐⭐ (靜態類型) |
| Godot 整合 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 熱重載 | ✅ 支援 | ⚠️ 有限支援 |
| IDE 支援 | VSCode + Godot | Visual Studio |

**建議：**
- 快速原型、小型專案 → GDScript
- 大型專案、需要高性能 → C#
- 混合使用：核心邏輯用 C#，配置用 GDScript

---

## 完整範例檔案結構

```
YourFighter/
├── States/
│   └── 60_YourCharacter_Throw.tres       # 狀態資源
│       ├── throw_pivot (位置陣列)
│       ├── animation_events (事件陣列)
│       │   └── ThrowReleaseEvent (Frame 29)
│       └── animation_settings
│
├── Scripts/
│   └── throw_release_event.gd            # 自訂事件腳本
│
└── Resources/
    └── throw_detach_standard.tres        # 可重複使用的參數
```

---

## 總結

### ✅ 這個方案的優勢

1. **Frame-Precise（幀精確）**: 不受幀率影響
2. **Rollback Compatible（Rollback 相容）**: 完全確定性
3. **Maintainable（易維護）**: 關注點清晰分離
4. **Extensible（可擴展）**: 輕鬆加入新功能
5. **Designer-Friendly（設計師友好）**: 視覺化編輯

### 🎯 核心原則

```
位置 (ThrowPivot)  → 控制「在哪裡」
事件 (AnimationEvent) → 控制「什麼時候」
參數 (ThrowDetachment) → 控制「怎麼拋」
```

### 📚 延伸閱讀

- Guilty Gear Strive 開發者訪談：Frame-based System
- Skullgirls GGPO 實作：確定性遊戲邏輯
- Fighting Game Glossary：摔投機制術語

---

## 版本歷史

- **v1.0** (2026-02-08): 初版教學
  - 基於 Sakuga Engine 現有架構
  - GDScript 實作範例
  - 完整配置指南

---

**作者**: Sakuga Engine Community  
**授權**: MIT License  
**更新**: 2026-02-08
