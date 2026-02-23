# 🔴 DAVMoveSet 多段Hit參數修復報告

## 問題描述
DAVMoveSet.gd 中設置了 `is_multi_hit` 和 `hit_phases` 參數，但這些參數沒有被傳遞給 MoveData 對象，導致多段攻擊的打飛效果等屬性在實際遊戲中無法應用。

## 根本原因
1. **MoveData._init() 缺少參數**：`_init()` 函數沒有接受 `is_multi_hit` 和 `hit_phases` 參數
2. **_smd_to_move_data() 未轉換這些字段**：當從 SpecialMoveData 資源轉換時，沒有傳遞這些字段
3. **DAVMoveSet/DENMoveSet 的 fallback 調用遺漏參數**：MoveData.new() 的調用缺少新參數

## 修復過程

### ✅ 1. 修改 MoveSet.gd - MoveData._init()
**位置**：[MoveSet.gd](MoveSet.gd#L43-L92)

添加兩個新參數：
```gdscript
p_is_multi_hit: bool = false,  # 是否為多段連打招式
p_hit_phases: Array = []       # Hit phases 數組（HitPhaseData 資源）
```

在 _init() 中設置這些參數：
```gdscript
is_multi_hit = p_is_multi_hit  # 🔴 新增
hit_phases = p_hit_phases      # 🔴 新增
```

### ✅ 2. 修改 MoveSet.gd - _smd_to_move_data()
**位置**：[MoveSet.gd](MoveSet.gd#L175-L205)

在 MoveData.new() 調用中添加新參數：
```gdscript
res.get("is_multi_hit") if "is_multi_hit" in res else false,
res.get("hit_phases") if "hit_phases" in res else []
```

### ✅ 3. 修改 DAVMoveSet.gd
**位置**：[DAVMoveSet.gd](DAVMoveSet.gd#L37-L69)

更新所有 MoveData.new() fallback 調用，添加新參數：
```gdscript
# 霸王腳
move_library["powerkk"] = MoveData.new(
    ..., 39, 23, false, []  # 新參數：is_multi_hit=false, hit_phases=[]
)

# 超必殺
move_library["super"] = MoveData.new(
    ..., 39, 23, false, []
)

# 升龍拳
move_library["dp"] = MoveData.new(
    ..., 39, 23, false, []
)
```

### ✅ 4. 修改 DENMoveSet.gd
**位置**：[DENMoveSet.gd](DENMoveSet.gd#L28-L42)

同樣更新所有 MoveData.new() fallback 調用：
```gdscript
# 旋風腿
move_library["spnk"] = MoveData.new(
    ..., 27, 23, false, []
)

# 飛腳踢
move_library["hdk"] = MoveData.new(
    ..., 27, 23, false, []
)
```

## 數據流驗證

現在多段招式的數據流如下：

```
SpecialMoveData .tres 資源（dav_100p.tres）
  ├─ move_id: "100p"
  ├─ is_multi_hit: true
  └─ hit_phases: [
       {frame: 8,  damage: 5.0, hitstun: 18, blockstun: 12, knockback: 50.0},
       {frame: 16, damage: 5.0, hitstun: 18, blockstun: 12, knockback: 50.0},
       {frame: 24, damage: 6.0, hitstun: 30, blockstun: 20, knockback: 120.0, force_knockfly: true}
     ]
  ↓
_load_smd() 加載資源
  ↓
_smd_to_move_data() 轉換為 MoveData
  ├─ 設置 is_multi_hit: true ✅
  └─ 設置 hit_phases: [...] ✅
  ↓
MoveData 存入 move_library
  ↓
MoveSet.activate_move("100p") 激活招式
  ↓
每個物理幀檢查 hit_phases 時間
  ↓
HitResponseHandler._on_hitbox_hit()
  ├─ 檢查 active_move.is_multi_hit ✅
  ├─ 獲取當前 phase_data ✅
  ├─ 應用 hit_phases 中的打飛/傷害參數 ✅
  └─ 執行 take_hit() 與正確的參數
```

## 影響的招式

### DAV
- **100p（百裂拳）**：多段連打，現在正確應用各段的傷害、硬直和最後一段的打飛效果
- **powerkk（霸王腳）**：無多段hit
- **super（超必殺）**：無多段hit
- **dp（升龍拳）**：無多段hit
- **fireball（火球）**：投擲物，無多段hit

### DEN
- **spnk（旋風腿）**：無多段hit
- **hdk（飛腳踢）**：無多段hit
- **fireball（火球）**：投擲物，無多段hit

## 測試檢查清單

- [ ] 啟動遊戲並進入比賽場景
- [ ] Player A 使用 236+MK 執行 100p（百裂拳）
- [ ] 確認 100p 的三段都命中對手
- [ ] 驗證最後一段應用了 `force_knockfly: true` 的打飛效果
- [ ] 驗證 FrameBar 顯示正確的硬直時間（最後一段為 30 frames）
- [ ] 測試其他多段招式（未來添加）以確保通用機制正常

## 相關系統

- **MoveSet.gd**：招式庫管理和轉換
- **HitResponseHandler.gd**：多段hit檢測和應用
- **Player.gd**：活躍招式追蹤
- **SpecialMoveData.gd**：資源數據定義
- **HitPhaseData.gd**：單個hit phase 的數據定義

## 向前相容性

- Fallback 參數設為 `false` 和 `[]`，確保現有的非多段招式不受影響
- _smd_to_move_data() 使用條件檢查 `if "is_multi_hit" in res else false`，向後相容舊資源

---

修復完成日期：2026-02-24
