# DP 被擊中行為修改指南

## 快速答案
當角色被 DP 擊中時，主要有 **3 個檔案** 控制行為：

| 行為 | 檔案 | 位置 |
|------|------|------|
| **飛起高度、重力、水平速度** | [MoveSet.gd](MoveSet.gd#L162) | 第 162 行 DP 定義 |
| **受擊時間（Hitstun）** | [scripts/combat/handlers/HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd#L169) | 第 169-173 行 |
| **受擊物理應用** | [fighter.gd](fighter.gd#L177) | 第 177 行 `take_hit()` 函數 |

---

## 1️⃣ DP 參數定義 - [MoveSet.gd](MoveSet.gd#L162)

### 當前 DP 設定
```gdscript
# 第 162-163 行
move_library["dp"] = MoveData.new(
	"dp", "DAV", 5.0, 100.0, 47.0, 80.0, 4.0, -1700.0, false, false, 3000000.0, "special", true, "none", 0.0, 0.0, 0.0,
	6200000.0,      # ← knockfly_gravity (重力)
	-2700.0,        # ← knockfly_vertical_speed (飛起速度)
	20.0,           # ← knockfly_horizontal_speed (水平速度)
	39, 23          # hitstun: 39 frames, blockstun: 23 frames
)
```

### 修改這些參數以控制飛起行為

| 參數 | 當前值 | 說明 | 修改效果 |
|------|-------|------|---------|
| `knockfly_gravity` | `6200000.0` | 被擊中時的重力加速度 | **數值越大 → 下落越快** |
| `knockfly_vertical_speed` | `-2700.0` | 初始垂直速度（負值 = 向上） | **數值越負 → 飛得越高** |
| `knockfly_horizontal_speed` | `20.0` | 初始水平速度（被擊飛方向） | **數值越大 → 橫向移動越遠** |

### 示例修改

**讓角色飛得更高：**
```gdscript
knockfly_vertical_speed = -3500.0  # 原來 -2700.0，改更負的值
```

**讓角色下落速度變快：**
```gdscript
knockfly_gravity = 8000000.0  # 原來 6200000.0，增加數值
```

**調整水平距離：**
```gdscript
knockfly_horizontal_speed = 50.0  # 原來 20.0，增加數值增加橫向距離
```

---

## 2️⃣ 受擊時間設定 - [HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd#L169)

### 當前 DP Hitstun 設定
```gdscript
# 第 169-173 行
elif move_name == "dp":
	params.hitstun = 39     # 39 邏輯幀 = 0.65 秒
	params.blockstun = 23   # 23 邏輯幀 = 0.383 秒
	params.force_knockfly = true
	params.knockfly_params = {
		"gravity": active_move.knockfly_gravity,
		"vertical_speed": active_move.knockfly_vertical_speed,
		"horizontal_speed": active_move.knockfly_horizontal_speed,
		"duration": params.hitstun  # ← 飛行時間基於 hitstun
	}
```

### 修改 Hitstun 以控制受擊持續時間

**提高 Hitstun（讓對手被打得更久）：**
```gdscript
params.hitstun = 50  # 從 39 改為 50 邏輯幀（=0.833秒）
```

**降低 Hitstun（讓對手更快恢復）：**
```gdscript
params.hitstun = 30  # 從 39 改為 30 邏輯幀（=0.5秒）
```

> ⚠️ **重要**：Hitstun 也會影響 `duration` 參數，所以改變 hitstun 時會自動調整飛行時間。

---

## 3️⃣ 受擊物理應用 - [fighter.gd](fighter.gd#L177)

### `take_hit()` 函數的關鍵部分

```gdscript
func take_hit(
	hitstun_duration: int = 18,  # ← 邏輯幀（60FPS 基準）
	blockstun_duration: int = 10,
	damage: float = 10.0,
	skip_push: bool = false,
	force_knockfly: bool = false,  # ← 被 DP 強制設為 true
	knockfly_params: Dictionary = {},  # ← 包含 gravity, vertical_speed, horizontal_speed
	knockback_distance: float = -1.0
) -> void:
```

當 DP 擊中時，HitResponseHandler 會呼叫：
```gdscript
target.take_hit(
	hitstun_duration,
	blockstun_duration,
	damage,
	skip_push,
	force_knockfly = true,  # ← DP 強制啟用 knockfly
	knockfly_params = {      # ← 來自 MoveSet.gd 的參數
		"gravity": 6200000.0,
		"vertical_speed": -2700.0,
		"horizontal_speed": 20.0,
		"duration": 39  # 來自 hitstun
	},
	knockback
)
```

---

## 🎮 完整修改流程

### 步驟 1: 修改 DP 參數 (MoveSet.gd)
1. 開啟 [MoveSet.gd](MoveSet.gd)
2. 找到第 162 行 `move_library["dp"] = MoveData.new(...)`
3. 修改以下三個值：
   - `6200000.0` → 新的重力值
   - `-2700.0` → 新的飛起速度（更負 = 更高）
   - `20.0` → 新的水平速度

### 步驟 2: 修改 Hitstun 時間 (HitResponseHandler.gd)
1. 開啟 [scripts/combat/handlers/HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd)
2. 找到第 169 行 `elif move_name == "dp":`
3. 修改 `params.hitstun = 39` 為新的幀數

### 步驟 3: 測試
1. 啟動遊戲
2. 讓 AI 或玩家發動 DP
3. 觀察對手的受擊反應（飛起高度、下落速度、受擊時間）

---

## 📊 參數單位說明

| 參數 | 單位 | 示例 |
|------|------|------|
| `knockfly_gravity` | 固定點物理（SIMULATION_SCALE = 1000） | `6200000` = 物理加速度 |
| `knockfly_vertical_speed` | 固定點速度（像素/幀 × 1000） | `-2700` = 向上 2.7 像素/幀 |
| `knockfly_horizontal_speed` | 固定點速度 | `20` = 向前 0.02 像素/幀 |
| `hitstun` | 邏輯幀（60FPS 基準） | `39` = 0.65 秒 |

---

## 🔍 調試技巧

### 查看當前 DP 設定
執行遊戲，當對手被 DP 擊中時，控制台會輸出：
```
[TAKE_HIT] Player_B 接收擊中
  - 輸入 hitstun: 39 邏輯幀
  - 轉換為: 46 物理幀
  - 實際時間: 0.767秒
```

### 觀察飛起動畫
- 檢查角色是否立即進入 `knockfly` 狀態
- 查看 KnockflyHandler 在每幀應用的重力和速度
- 確認著地時間與 `duration` 參數一致

---

## 📁 相關檔案列表

| 檔案 | 用途 |
|------|------|
| [MoveSet.gd](MoveSet.gd) | DP 參數定義（gravity, speed） |
| [scripts/combat/handlers/HitResponseHandler.gd](scripts/combat/handlers/HitResponseHandler.gd) | Hitstun/blockstun 設定 |
| [fighter.gd](fighter.gd) | 受擊物理應用 |
| [KnockflyHandler.gd](KnockflyHandler.gd) | 被擊飛時的物理計算 |

---

## ✅ 快速參考

| 要達成的效果 | 修改的檔案和值 |
|------------|--------------|
| 飛得更高 | MoveSet.gd 第 162 行 `knockfly_vertical_speed` → 改更負 |
| 下落更快 | MoveSet.gd 第 162 行 `knockfly_gravity` → 改更大 |
| 飛得更遠（橫向） | MoveSet.gd 第 162 行 `knockfly_horizontal_speed` → 改更大 |
| 受擊時間更長 | HitResponseHandler.gd 第 170 行 `params.hitstun` → 改更大 |
| 受擊時間更短 | HitResponseHandler.gd 第 170 行 `params.hitstun` → 改更小 |
