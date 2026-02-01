# Knockback 減速曲線自定義指南

## 概述
Knockback 減速曲線現在支援 **4 種預設模式** + 完全自由調整參數，讓你在 Inspector 中輕鬆調整角色的推進感。

## 在 Inspector 中的位置
PushManager 節點 → **Knockback Deceleration Curve** 組（Group）

## 4 種減速模式

### 1. **Power（幂函數）** - 最推薦
```
模式名稱: power
關鍵參數: knockback_deceleration_power
```

**原理**: 使用 `remaining_ratio ^ power` 計算速度倍數
- `power = 1.0` → 線性減速（勻速減慢）
- `power = 1.5` → 二次方減速（漸進式減慢，中期最明顯）✅ **推薦**
- `power = 2.0` → 三次方減速（開始快，後期極慢）
- `power = 3.0` → 極快減速（幾乎立刻停止）

**使用場景**: 大多數格鬥遊戲採用此方式，簡單直觀，易於調整

**調整方法**:
- 想要 **更長的後移距離** → 降低 power 值（如 1.2）
- 想要 **更短的後移距離** → 提高 power 值（如 2.5）
- 想要 **減速感更明顯** → power 值在 1.3-1.8 之間效果最好

---

### 2. **Ease Out（緩動出）** - 開始快減速，後期平緩
```
模式名稱: ease_out
關鍵參數: knockback_ease_strength (1.0-3.0)
```

**原理**: 使用 `1 - (1 - remaining_ratio)^strength` 計算
- `strength = 1.0` → 線性
- `strength = 1.5` → 柔和緩動（推薦試試）
- `strength = 2.0` → 標準緩動
- `strength = 3.0` → 很強的緩動

**特點**: 開始減速明顯，後期保持一定速度（不會完全停止）

**使用場景**: 想要角色 **保有一定動能** 的設計

---

### 3. **Ease In Out（緩動進出）** - S 形曲線
```
模式名稱: ease_in_out
關鍵參數: knockback_ease_strength
```

**原理**: S 形曲線，開始緩（減速不明顯）→ 中間快（快速減速）→ 後期緩（接近停止時緩）

**特點**: 物理感較強，最自然的減速感

**使用場景**: 追求最 **自然逼真** 的推進效果

---

### 4. **Linear Threshold（線性閾值）** - 分段式
```
模式名稱: linear_threshold
關鍵參數: knockback_linear_threshold (0.0-1.0)
          knockback_deceleration_power
```

**原理**: 
- 當 `remaining_ratio >= threshold` 時 → 線性減速（保持速度）
- 當 `remaining_ratio < threshold` 時 → 快速減速（power 控制）

**例子**: 若 threshold = 0.3，power = 2.0
- 前 70% 時間：以 100% 速度移動（線性）
- 後 30% 時間：快速減速（二次方）

**特點**: 前期保持高速，後期急速停止

**使用場景**: 想要 **明確的停止點** 而非漸進式減速

---

## 推薦配置組合

| 遊戲風格 | 模式 | 參數設定 | 說明 |
|---------|------|--------|------|
| 傳統格鬥（推薦） | `power` | power = 1.5 | 後移距離中等，減速感明顯 |
| 快節奏格鬥 | `power` | power = 2.0-2.5 | 後移距離短，立刻停止 |
| 重擊感強 | `power` | power = 1.0-1.2 | 後移距離長，保持一定動能 |
| 柔和設計 | `ease_out` | strength = 1.5 | 開始快減速，後期保持 |
| 自然逼真 | `ease_in_out` | strength = 2.0 | S 形曲線，最自然 |
| 明確停止點 | `linear_threshold` | threshold=0.3, power=2.0 | 前期高速，後期急停 |

---

## 其他參數

### `knockback_minimum_velocity_ratio` (0.05)
**用途**: 防止速度完全變成 0（目前註釋中，若需要請取消註釋）

```gdscript
# 在 calculate_knockback_speed_multiplier() 最後
return max(result, knockback_minimum_velocity_ratio)
```

**現在不啟用原因**: 讓角色在後移結束時完全停止，視覺上更清晰

---

## 快速調整清單

### 問題：後移到一半後距離極不明顯
**解決**: 降低 power 值（如 1.2-1.3）或改用 `ease_out` 模式

### 問題：後移太長，角色被打得太遠
**解決**: 提高 power 值（如 2.5）或改用 `linear_threshold` 增加前期線性比例

### 問題：後移感覺不順暢，太生硬
**解決**: 改用 `ease_in_out` 模式，享受 S 形曲線的流暢感

### 問題：想精確控制什麼時候減速最快
**解決**: 使用 `linear_threshold` 模式調整 `knockback_linear_threshold` 參數

---

## 測試方法

1. 進入遊戲，開啟 PushManager 的 Inspector
2. 修改 **Knockback Deceleration Curve** 組下的參數
3. 不需要重啟，直接攻擊對方觀察推進效果
4. 找到最滿意的參數後，記下來！

## 保存喜歡的設定

若找到完美的減速曲線參數，可以在 [Movement.gd](Movement.gd) 中的導出變數留下註解：

```gdscript
# 推薦減速曲線設定：
# 模式: power
# power: 1.5
```

---

**提示**: 試試不同的組合！格鬥遊戲的手感很大程度來自這類細微參數調整。
