# 幀數轉換系統 - 快速開始指南

## 🎯 5 分鐘快速理解

### 什麼是幀轉換?
遊戲以**邏輯幀**(60 FPS)進行設計，但物理引擎以**物理幀**(120 FPS)運行。

```
設計者輸入: 18 幀 (60 FPS 基準)
    ↓ 轉換 (×2)
引擎使用: 36 幀 (120 FPS)
    ↓ 結果
實際時間: 0.3 秒
```

### 為什麼需要?
1. **設計直覺**: 設計師習慣 60 FPS 數字
2. **網絡安全**: 幀轉換結果確定性強
3. **性能**: 邏輯幀節省計算資源

---

## 📖 各系統簡介

### ✅ 已完成的系統

#### 一般攻擊 (AttackData.gd)
```gdscript
@export var st_mp_hitstun_frames: int = 24  // Inspector 輸入: 24
// 使用時自動轉換為物理幀: 24 × 2 = 48
```
✓ **完全自動**，設計者直接輸入幀數，無需手動轉換

#### 特殊招式 (MoveSet.gd)
```gdscript
move_library["super"] = MoveData.new(..., 156.0, ...)  // 邏輯幀
// _start_special() 自動轉換: 156 / 60 = 2.6 秒
```
✓ **自動轉換**到秒數用於 delta 計時

#### 投射物 (fireball.gd)
```gdscript
blockstun_duration_frames: int = 14  // 邏輯幀
// take_hit() 自動轉換為物理幀: 14 × 2 = 28
```
✓ **與一般攻擊相同**的轉換機制

---

## 🚀 如何使用

### 場景 1: 添加新的一般攻擊

**1. 在 AttackData.gd 中添加屬性**
```gdscript
@export var new_attack_hitstun_frames: int = 20  // 邏輯幀
@export var new_attack_blockstun_frames: int = 15
@export var new_attack_knockback: float = 300.0
```

**2. 在 Player.gd 中添加到 ATTACK_TABLE**
```gdscript
"new_attack": {
    "hitstun": attack_data.new_attack_hitstun_frames,
    "blockstun": attack_data.new_attack_blockstun_frames,
    "knockback": attack_data.new_attack_knockback
}
```

**3. 其他部分自動處理** ✅

---

### 場景 2: 添加新的特殊招式

**1. 在 MoveSet.gd 中添加 move_library 條目**
```gdscript
move_library["new_special"] = MoveData.new(
    "new_special",     // 名稱
    "DAV",             // 角色要求
    10.0,              // 傷害
    200.0,             // 擊退
    72.0,              // duration (邏輯幀!)
    100.0,             // move_distance
    0.0,               // jump_delay
    0.0,               // jump_speed
    false,             // is_freeze
    false,             // is_projectile
    0.0,               // gravity
    "special",         // sound_type
    false,             // penetrable
    "none"             // acceleration_curve
    // ... 其他參數
)
```

**2. 添加輔助方法**
```gdscript
func start_new_special() -> void:
    _start_special("new_special")
```

**3. 其他部分自動處理** ✅
- _start_special() 自動轉換: 72 / 60 = 1.2 秒
- process_move() 自動進行 delta 計時

---

### 場景 3: 理解時間值

#### 1 邏輯幀 = ?

**在設計師的視角**
```
1 邏輯幀 = 1 時間單位 (60 FPS 基準)
實際秒數 = 邏輯幀數 / 60
```

**例子**
```
30 邏輯幀 = 0.5 秒
60 邏輯幀 = 1.0 秒
120 邏輯幀 = 2.0 秒
```

#### 轉換公式

| 來源 | 目標 | 公式 | 例子 |
|------|------|------|------|
| 秒數 | 邏輯幀 | 秒數 × 60 | 0.5s → 30幀 |
| 邏輯幀 | 秒數 | 邏輑幀 ÷ 60 | 30幀 → 0.5s |
| 邏輯幀 | 物理幀 | 邏輯幀 × 2 | 30幀 → 60幀 |
| 物理幀 | 秒數 | 物理幀 ÷ 120 | 60幀 → 0.5s |

---

## 🔧 常見工作流

### 工作流 1: 調整攻擊後座

**需求**: 讓 st_mp 的特硬直增加 0.1 秒

**步驟**:
1. 打開 `data/AttackData.gd`
2. 找到 `st_mp_blockstun_frames: int = 16`
3. 計算: 0.267s + 0.1s = 0.367s = 22 幀
4. 改為 `st_mp_blockstun_frames: int = 22`
5. **完成** ✅

---

### 工作流 2: 調整特殊招式持續時間

**需求**: Super 特殊招式太快，延長 0.5 秒

**步驟**:
1. 打開 `MoveSet.gd`
2. 找到 `move_library["super"]` 行
3. 找到 `duration: 156.0` (原 2.6 秒)
4. 計算: 2.6s + 0.5s = 3.1s = 186 幀
5. 改為 `duration: 186.0`
6. **完成** ✅ (process_move() 會自動計算: 186/60 = 3.1s)

---

### 工作流 3: 理解命中堆疊

**問題**: 為什麼 st_mp 的硬直是 24 幀？

**答案追蹤**:
1. AttackData.gd: `st_mp_hitstun_frames = 24`
2. Fighter.gd: `24 × 2 = 48 物理幀`
3. Fighter.take_hit(): `48 / 120 = 0.4 秒`

**結論**: 24 邏輯幀 = 0.4 秒 ✓

---

## 📊 參考表

### 常用時間值

**一般攻擊**
```
快速攻擊:    18-24 邏輯幀 (0.3-0.4s)
中速攻擊:    30-39 邏輯幀 (0.5-0.65s)
慢速攻擊:    45-60 邏輯幀 (0.75-1.0s)
```

**特殊招式**
```
快速特殊:    36-54 邏輯幀 (0.6-0.9s)
中速特殊:    72-90 邏輯幀 (1.2-1.5s)
慢速特殊:    120-180 邏輯幀 (2.0-3.0s)
```

**三相運動**
```
不動比例:    0.2-0.3 (前 20-30%)
加速比例:    0.2-0.3 (中 20-30%)
減速比例:    0.4-0.5 (後 40-50%)
```

---

## ⚠️ 常見陷阱

### 陷阱 1: 混淆邏輯幀和秒數
❌ **錯誤**:
```gdscript
@export var attack_time: float = 18  // 秒? 幀?
```

✅ **正確**:
```gdscript
@export var attack_hitstun_frames: int = 18  // 清楚: 邏輯幀
```

### 陷阱 2: 忘記秒數轉換 (特殊招式)
❌ **錯誤**:
```gdscript
current_move_state.timer = move_data.duration  // duration 是幀數!
```

✅ **正確**:
```gdscript
current_move_state.timer = move_data.duration / 60.0  // 轉換為秒數
```

### 陷阱 3: 手動計算轉換
❌ **不推薦**:
```gdscript
// 手動計算會出錯
var duration_in_seconds = 156 / 60.0  // 容易遺忘
```

✅ **推薦**:
```gdscript
// 系統自動轉換，不需要手動
current_move_state.timer = move_data.duration / 60.0
```

---

## 🧪 驗證自己的改動

添加新攻擊後，檢查清單:

- [ ] 在 AttackData.gd 中添加了 `_frames` 屬性?
- [ ] 在 Player.ATTACK_TABLE 中添加了條目?
- [ ] 動畫已創建並設置?
- [ ] 測試遊戲: 按下按鍵是否執行?
- [ ] 時間是否正確? (使用 FrameBar 檢查)

---

## 📞 獲得幫助

### 調試技巧

1. **檢查控制台輸出**
```
[HitResponseHandler] PlayerA → PlayerB | Hitstun: 24 frames (0.40s)
[TAKE_HIT] Input: hitstun=24 → physics_hitstun=48
```

2. **使用 FrameBar**
```
在 world.gd 中啟用 FrameBar 節點
顯示實際的幀優勢
```

3. **查看源代碼**
- AttackData.gd: 攻擊定義
- MoveSet.gd: 特殊招式定義
- Fighter.gd: 轉換邏輯

---

## ✅ 系統健康檢查

運行以下檢查確保系統正常:

```bash
# 1. 驗證 AttackData 幀值
grep "_frames" data/AttackData.gd | head -5

# 2. 驗證轉換函數
grep "logic_frames_to_physics_frames" fighter.gd

# 3. 驗證 MoveSet 轉換
grep "duration / 60.0" MoveSet.gd
```

---

**🎮 準備好添加新攻擊和特殊招式了嗎?**

開始使用上面的工作流吧! 有任何問題，參考參考表和常見陷阱部分。
