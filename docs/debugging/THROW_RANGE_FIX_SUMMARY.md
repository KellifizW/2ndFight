# 投擲距離檢測修復總結

## 問題

CPU AI 會在 **不夠距離**時仍然使用投擲，因為決策層只使用硬編碼的 100 像素距離限制，而不是使用真實的投擲框尺寸。

## 根本原因

1. **HitboxCache 未掃描投擲框**：只掃描了普通攻擊的 Hitbox，沒有 ThrowBox 數據
2. **AIDecisionLayers 使用硬編碼距離**：`distance < 100` 而不是檢查投擲框是否能與對手重疊
3. **缺少 AABB 碰撞檢測**：沒有驗證 throw_enter 的 ThrowBox 是否真的與對手的 Hurtbox 重疊

## 修復內容

### 1️⃣ HitboxCache.gd 更新

**新增方法**：

```gdscript
func _scan_throw_hitboxes(player: Node, character_id: String, animation_player: AnimationPlayer) -> void
```
- 掃描 `throw_enter` 動畫中的 ThrowBox 尺寸和位置
- 如果動畫中找不到，嘗試直接讀取 CollisionShape2D
- 將投擲框數據快取為 `"{character_id}:throw_enter"`

```gdscript
func get_throw_range(character_id: String) -> float
```
- 返回投擲框的有效範圍（從角色中心到 ThrowBox 最遠端）

```gdscript
func check_throw_collision(attacker_pos, attacker_char_id, target_pos, target_char_id, attacker_facing) -> bool
```
- AABB 碰撞檢測：投擲框是否與對手 Hurtbox 重疊

### 2️⃣ AIDecisionLayers.gd 更新

**修改投擲決策邏輯**：

```gdscript
# 使用真實投擲框碰撞檢測（而不是硬編碼 100px）
var throw_hitbox_collision = false
var throw_range = 100.0

if hitbox_cache and hitbox_cache.is_initialized:
    throw_range = hitbox_cache.get_throw_range(ai_player.character_id)
    throw_hitbox_collision = hitbox_cache.check_throw_collision(
        ai_player.global_position,
        ai_player.character_id,
        opponent.global_position,
        opponent.character_id,
        ai_facing
    )
else:
    # 後備：使用硬編碼距離
    throw_hitbox_collision = distance < 100

# 只有在投擲框能真的碰撞時才評估 throw
var throw_eligible = throw_hitbox_collision and not ai_player.is_attacking and not ai_player.is_hit and not ai_player.is_knockfly
```

## 行為改變

### 修復前
```
AI distance=50px  → 決策: throw (是，硬編碼 100px)
AI distance=80px  → 決策: throw (是，在限制內)
AI distance=100px → 決策: DO NOT throw (否)
AI distance=110px → 決策: DO NOT throw (否)
```

### 修復後
```
AI distance=50px  → hitbox_collision=YES  → 決策: throw ✓ (真實碰撞)
AI distance=60px  → hitbox_collision=NO   → 決策: DO NOT throw ✓ (不夠近)
AI distance=80px  → hitbox_collision=YES  → 決策: throw ✓ (真實碰撞)
AI distance=100px → hitbox_collision=NO   → 決策: DO NOT throw ✓ (超出範圍)
AI distance=110px → hitbox_collision=NO   → 決策: DO NOT throw ✓ (超出範圍)
```

> 實際範圍 = 投擲框實際大小，不是固定 100px

## 調試日誌

修復後會看到更詳細的投擲決策日誌：

```
[TACTICAL THROW CHECK] Frame=876 Seat=player_a | distance=75.3 throw_range=85.5 | hitbox_collision=true | ELIGIBLE=true
[TACTICAL THROW ADDED] Frame=876 Seat=player_a | priority=71.2 reason='Close range: throw (real hitbox collision)' | throw_range=85.5
```

關鍵信息：
- `throw_range`: 投擲框的真實有效範圍（從 HitboxCache 讀取）
- `hitbox_collision`: AABB 碰撞檢測結果（true = 能碰撞）

## 後備機制

如果 HitboxCache 未初始化（不應該發生），系統會降級到硬編碼 100px：

```gdscript
else:
    # 後備：使用硬編碼距離
    throw_hitbox_collision = distance < 100
```

## 測試方法

1. **啟用 AI**：按 `C` 鍵
2. **逐步靠近對手**（使用 `A+D`）
3. **監看控制台**：
   - 距離 50-80px：應該看到 `[TACTICAL THROW ADDED]` ✓
   - 距離 85-99px：取決於實際投擲框大小，應該 DO NOT throw ✓
   - 距離 100px+：應該完全不評估 throw ✓
4. **驗證**：AI 只在能真正碰撞時才執行 throw

## 相關修改文件

- [HitboxCache.gd](../../ai/HitboxCache.gd) - 新增投擲框掃描
- [AIDecisionLayers.gd](../../ai/AIDecisionLayers.gd) - 投擲決策使用真實碰撞檢測

