# Fireball 參數修改指南

## 三個修改位置

### 1️⃣ MoveSet.gd (特殊招式定義 - 主要參數)
**位置**: [MoveSet.gd](MoveSet.gd#L157-L159) 第157-159行

```gdscript
move_library["fireball"] = MoveData.new(
    "fireball",      # 招式名稱
    "*",             # 角色要求（"*"代表所有角色）
    10.0,            # 🟢 傷害值 (可修改)
    150.0,           # 🟢 擊飛距離/Knockback基數 (可修改)
    18.0,            # 🟢 持續時間 = 18 邏輯幀 = 0.3秒 (可修改)
    0.0,             # 移動距離（投射物為0）
    0.0,             # 跳躍延遲
    0.0,             # 跳躍速度
    false,           # 是否凍結遊戲
    true,            # 是否為投射物
    0.0,             # 重力
    "fireball",      # 音效類型
    true,            # 是否穿透
    "none",          # 加速度曲線
    0.0, 0.0, 0.0,  # 三相運動參數
    0.0, 0.0, 0.0   # Knockfly參數（投射物不用）
)
```

**修改方法**:
```gdscript
# 增加傷害
move_library["fireball"].damage = 12.0  # 原值 10.0

# 增加擊飛距離
move_library["fireball"].knockback = 200.0  # 原值 150.0

# 增加持續時間
move_library["fireball"].duration = 24.0  # 原值 18.0 (24幀 = 0.4秒)
```

---

### 2️⃣ HitResponseHandler.gd (命中時的受擊參數)
**位置**: [HitResponseHandler.gd](HitResponseHandler.gd#L152-L155) 第152-155行

```gdscript
elif move_name == "fireball":
    params.hitstun = 21     # 🟢 被擊中時的僵直幀數 = 0.35秒 (可修改)
    params.blockstun = 14   # 🟢 格擋時的僵直幀數 = 0.233秒 (可修改)
    params.skip_push = true # 跳過推動物理（投射物的推動已獨立處理）
```

**說明**:
- `hitstun`: 被fireball直接擊中時的受擊僵直（邏輯幀）
- `blockstun`: 用格擋格擋fireball時的格擋僵直（邏輯幀）
- `skip_push`: 投射物不進行推動計算

**修改方法**:
```gdscript
# 增加被擊中僵直時間
params.hitstun = 27     # 原值 21 (27幀 = 0.45秒)

# 增加格擋僵直時間
params.blockstun = 18   # 原值 14 (18幀 = 0.3秒)
```

---

### 3️⃣ fireball.gd (投射物本身的參數)
**位置**: [fireball.gd](fireball.gd#L5-L6) 第5-6行 + 第35-38行

```gdscript
# ── 第 5-6 行：基礎參數 ──
var damage: float = 8.0                           # 🟢 預設傷害值 (可修改)
var blockstun_duration_frames: int = 14           # 🟢 格擋時間 = 14幀 (可修改)

# ── 第 35-38 行：角色特定參數 ──
if owner_character_id == "DAV":
    speed = 800.0        # 🟢 DAV的fireball速度 (可修改)
    damage = 8.0         # 🟢 DAV的fireball傷害 (可修改)
elif owner_character_id == "DEN":
    speed = 600.0        # 🟢 DEN的fireball速度 (可修改)
    damage = 7.0         # 🟢 DEN的fireball傷害 (可修改)
```

**修改方法**:
```gdscript
# 修改 DAV 的 fireball 速度
if owner_character_id == "DAV":
    speed = 1000.0  # 原值 800.0 (更快)
    damage = 10.0   # 原值 8.0 (更強)

# 修改 DEN 的 fireball 速度
elif owner_character_id == "DEN":
    speed = 750.0   # 原值 600.0 (更快)
    damage = 8.0    # 原值 7.0 (更強)
```

---

## 📊 參數對應表

| 參數 | 位置 | 含義 | 單位 | 推薦範圍 |
|------|------|------|------|---------|
| damage | MoveSet.gd + fireball.gd | 傷害值 | 數值 | 5.0-15.0 |
| knockback | MoveSet.gd | 擊飛距離基數 | 固定點單位 | 100-300 |
| duration | MoveSet.gd | 招式持續時間 | 邏輯幀 @60FPS | 12-24 |
| hitstun | HitResponseHandler.gd | 被擊中僵直 | 邏輯幀 @60FPS | 18-30 |
| blockstun | HitResponseHandler.gd | 格擋僵直 | 邏輯幀 @60FPS | 12-20 |
| speed | fireball.gd | 投射物移動速度 | 像素/秒 | 600-1200 |

---

## 🧪 測試建議

修改後，建議測試以下項目：

### 傷害值調整
- [ ] 1 個 fireball 的傷害是否符合預期
- [ ] 2 個 fireball 是否能組合傷害
- [ ] fireball + 其他招式的傷害組合

### 時間值調整
- [ ] 被擊中後的僵直時間是否合理
- [ ] 格擋後的僵直時間是否合理
- [ ] 投射物飛行時間是否符合動畫長度

### 速度調整
- [ ] 投射物移動速度是否影響躲避難度
- [ ] DAV 和 DEN 的速度差異是否合理

---

## 💡 常見修改場景

### 場景 1: 增強 Fireball 威力
```gdscript
// MoveSet.gd 第 157-159 行
move_library["fireball"] = MoveData.new(
    "fireball", "*", 12.0, 200.0, 18.0, 0.0, 0.0, 0.0, false, true, 0.0, "fireball", true, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    //                 ↑ 傷害 10→12    ↑ 擊飛 150→200
)

// HitResponseHandler.gd 第 152-155 行
elif move_name == "fireball":
    params.hitstun = 24     // 21→24 幀
    params.blockstun = 16   // 14→16 幀
```

### 場景 2: 調整投射物速度
```gdscript
// fireball.gd 第 35-38 行
if owner_character_id == "DAV":
    speed = 1000.0  // 800.0→1000.0 (更快)
```

### 場景 3: 讓 Fireball 更難躲避
```gdscript
// fireball.gd 第 5-6 行
var damage: float = 10.0              // 8.0→10.0
var blockstun_duration_frames: int = 20  // 14→20 幀
```

---

## ⚠️ 注意事項

1. **邏輯幀單位**: HitResponseHandler 和 fireball.gd 的時間參數都是邏輯幀（60 FPS基準）
   - 1 邏輯幀 = 1/60 秒 ≈ 0.0167 秒
   - 18 邏輯幀 = 0.3 秒

2. **damage 值的優先級**: 
   - MoveSet.gd 中的 damage 值是主要值
   - fireball.gd 中的 damage 只是預設值

3. **speed 單位**: fireball.gd 的 speed 是像素/秒，不是邏輯幀

4. **角色特定參數**: fireball.gd 中針對 DAV 和 DEN 有不同的參數設定

---

## 🔄 DP 修復說明

同時修復了 DP 第一次命中時角色閃飛的問題：

**問題**: `knockfly_velocity_x` 被計算但未應用到 `fixed_velocity.x`

**修正**: Fighter.gd 第272行後添加
```gdscript
fixed_velocity.x = int(knockfly_velocity_x)
```

這確保 knockfly 的水平速度在第一次命中時就被正確應用。

---

**現在您可以根據需要快速調整 Fireball 的所有參數了！** 🎮
