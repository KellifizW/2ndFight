# Hitstun 單位分析報告

## 問題描述
設定 fireball hitstun = 30 時，角色硬直了 **1 秒**（而不是預期的 0.5 秒）

## 現有代碼流程

### 1. MoveSet.gd (L11-12)
```gdscript
var hitstun: int = 18  # 🟢 新增: 被击中後的參數(邏輯幀)，預設 18
var blockstun: int = 10  # 🟢 新增: 被格擋後的參数(邏輯幀)，預設 10
```
**宣稱**：邏輯幀（60 FPS 基準）

### 2. fireball.gd (L241, L250)
```gdscript
var final_hitstun = fb_params["hitstun"]  # 從 MoveSet 讀取 = 30
target.take_hit(final_hitstun, ...)       # 傳給 take_hit()
```
**傳遞**：直接傳遞 MoveSet 的值（30）

### 3. fighter.gd (L193)
```gdscript
var physics_hitstun = logic_frames_to_physics_frames(hitstun_duration)

func logic_frames_to_physics_frames(logic_frames: int) -> int:
	return int(round(logic_frames * float(PHYSICS_FPS) / float(LOGIC_FPS)))
	#      30 * (60 / 60) = 30 物理幀
```

### 4. fighter.gd (L198)
```gdscript
print("    → 實際時間: %.3f秒" % (physics_hitstun / float(PHYSICS_FPS)))
	# 30 / 60 = 0.5 秒
```

## 問題診斷

### 如果你看到 1 秒硬直，代表：
- **實際 PHYSICS_FPS ≠ 60**？或
- **轉換中有 2 倍係數**？

### 可能原因
1. **Engine.physics_ticks_per_second = 120**（Godot 4 預設）
   - 則 logic_frames_to_physics_frames(30) = 30 * (120/60) = **60 物理幀**
   - 在 120 FPS 下 = 60/120 = **0.5 秒**（仍不是 1 秒）

2. **轉換發生了兩次**
   - fireball.gd 可能又轉換了一次？
   - 或 Fighter.take_hit() 內部轉換有問題？

## 實際值檢查表

| hitstun 設定 | 預期時間（60 FPS） | 實際看到 | 推斷 PHYSICS_FPS |
|-----------|------------|------|-----------|
| 30        | 0.5 秒      | 1.0 秒 | 120（需確認轉換）|
| 10        | 0.167 秒    | ?    | |
| 18        | 0.3 秒      | ?    | |

## 立即需要檢查的地方

### ✅ 驗證方案 A：檢查實際 PHYSICS_FPS
在遊戲運行時查看 console 輸出：
```
[TAKE_HIT] ... → 實際時間: X.XXXs
```
這會告訴我們實際計算的時間。

### ✅ 驗證方案 B：檢查轉換是否重複
- fireball.gd 是否有隱藏的轉換？
- fighter.gd 的 logic_frames_to_physics_frames() 中的 PHYSICS_FPS 值是多少？

### ✅ 驗證方案 C：直接修改 fireball 測試
改成 `"fireball", "*", 10.0, 80.0, 18.0, 0.0, 0.0, 0.0, false, true, 0.0, "fireball", true, "none", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 15, 10`
即 hitstun = 15（而非 30），看硬直時間是否變成 0.25 秒

## 建議修正

### 選項 1：假設 PHYSICS_FPS = 120
如果系統確實運行在 120 FPS，而轉換公式正確，那麼：
- hitstun = 30 邏輯幀 = 30 * (120/60) = 60 物理幀 = 0.5 秒 ✓
- 你看到 1 秒 = 需要 hitstun = 15 才能達到相同時間

### 選項 2：改為物理幀直接指定
如果邏輯幀的轉換太複雜，改為直接指定物理幀：
```gdscript
# MoveSet.gd L11-12 改為：
var hitstun: int = 18  # 🟢 物理幀直接指定（120 FPS）
var blockstun: int = 10  # 🟢 物理幀直接指定（120 FPS）

# fireball.gd L250 改為：
target.take_hit_frames(final_hitstun, final_blockstun, ...)  # 不經轉換
```

## 待檢查的文件

1. **fighter.gd L5-7**：確認 PHYSICS_FPS 和 LOGIC_FPS 的值
2. **fireball.gd L247**：查看實際列印的 hitstun 值
3. **Fighter.take_hit() L198 輸出**：確認實際計算的秒數
4. **world.gd**：確認 Engine.physics_ticks_per_second 設定

---

**下一步**：請在遊戲中測試 fireball hitstun=30 時，複製並貼上 console 的以下輸出：
1. `[Fireball Hit] 使用 MoveSet 參數: hitstun=...`
2. `[TAKE_HIT] ... → 實際時間: X.XXXs`

這會告訴我們轉換中到底發生了什麼。
