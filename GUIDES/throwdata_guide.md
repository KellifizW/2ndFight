# 摔投數據系統 (Throw Data System)

## 概述

throw_data 現已變成與 AttackData 相同的 **資源系統**，每個角色可以有自己獨特的摔投表現。

## 文件位置

- **資源類定義**：[data/ThrowData.gd](../../data/ThrowData.gd)
- **P1（DAV）摔投數據**：[data/p1_throw_data.tres](../../data/p1_throw_data.tres)
- **P2（DEN）摔投數據**：[data/p2_throw_data.tres](../../data/p2_throw_data.tres)
- **使用位置**：[player.gd](../../player.gd) - `_on_thrown()` 方法

## 使用方式

### 1. 在角色場景中設置 throw_data

在 Character 場景中（例如 `DAV.tscn` 或 `DEN.tscn`）：

```
Player 節點 (script: player.gd)
  ├─ Attack Data: res://data/p1_attack_data.tres
  ├─ Throw Data: res://data/p1_throw_data.tres  ← 拖入對應的 throw_data 資源
  └─ Character Data: res://characters/dav.character.tres
```

### 2. 調整摔投參數

在 Inspector 中選擇 `.tres` 檔案，直接修改參數：

| 參數 | 說明 | 默認值 |
|------|------|--------|
| `throw_damage` | 摔投傷害 | 8.0 |
| `throw_hitstun_frames` | 被摔投時的眩暈時間（邏輯幀 @60FPS） | 36 幀 = 0.6秒 |
| `throw_blockstun_frames` | 防守時的僵直時間 | 18 幀 = 0.3秒 |
| `throw_knockback_horizontal` | 水平推力（像素/幀，未縮放） | 120.0 |
| `throw_launch_horizontal_speed` | 追加水平速度（像素/幀） | 0.0 |
| `throw_launch_vertical_speed` | 垂直速度（像素/幀，負數=向上） | -2200.0 |
| `throw_gravity` | 被摔投時的重力（固定點單位） | 1900000.0 |
| `throw_enter_duration` | throw_enter 動畫幀數 @60FPS | 30 = 0.5秒 |
| `throw_seq_duration` | throw_seq 動畫幀數 @60FPS | 60 = 1.0秒 |

## 關鍵參數說明

### 垂直速度（launch_vertical_speed）

**單位**：像素/幀（未乘以 SIMULATION_SCALE）

**參考值**：
- `-400.0` = 一般 knock fly（很低）
- `-2200.0` = 中等高度（當前 throw 設置）
- `-3200.0` = 最高（DP 等強大特殊招式）

**如何計算**：
```
被動停留時間 ≈ 2 × |垂直速度| / 重力

例：-2200 / 1900000 ≈ 0.12秒 ≈ 7幀停留時間
```

### 重力（gravity）

**單位**：固定點單位（已乘以 1000）

**參考值**：
- `1700000.0` = 標準重力
- `1900000.0` = 當前值（略高，加快落地）
- `2000000.0` = 很高（極快落地）

**影響**：越大 = 被摔投者下落越快

## 程式數據流

```
Player．gd
  ├─ @export throw_data: ThrowData
  ├─ get_throw_data() → 返回資源的字典
  └─ _on_thrown(thrower)
       ├─ 讀取 thrower.get_throw_data()
       ├─ 解析字典中的參數
       └─ 應用垂直/水平速度和重力
```

## 實際例子

### 創建 P3（新角色）的摔投

1. **複製** `data/p1_throw_data.tres` → `data/p3_throw_data.tres`
2. **修改** 根據角色特性：
   ```
   throw_damage = 9.0            # 更強
   throw_knockback_horizontal = 150.0  # 更遠
   throw_launch_vertical_speed = -2800.0  # 更高
   ```
3. **在角色場景中** 拖入 `p3_throw_data.tres`

### P1 vs P2 對比

| 參數 | P1 (DAV) | P2 (DEN) |
|------|----------|----------|
| 傷害 | 8.0 | 8.0 |
| 水平推力 | 120.0 | **140.0** ← 更遠 |
| 追加水平速度 | 0.0 | 0.0 |
| 垂直速度 | -2200.0 | **-2400.0** ← 更高 |

現在 DEN 的摔投會比 DAV 更遠、更高！

## 調試

查看摔投被應用時的日誌：

```
[THROWN] throw_data from thrower: {damage: 8.0, hitstun: 36, ...}
[THROWN] throw_data applied: damage=8.0, hitstun=36, knockback=120.0, vert_speed=-2200.0, gravity=1900000.0
[THROWN] Applied velocities: knockback_x=-120000, vertical_y=-2200000, gravity=1900000
```

如果沒有看到這些日誌，檢查：
1. ✅ 角色場景中是否設置了 throw_data
2. ✅ throw_data.tres 檔案是否正確
3. ✅ get_throw_data() 是否返回有效的字典
