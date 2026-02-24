# Hitbox 檢測系統實施測試文檔

## 概述

本文檔提供完整的測試步驟，驗證 Hitbox 檢測系統是否正確實施並運作。

## 系統組件

### 新增檔案

1. **`ai/HitboxCache.gd`** - 核心 Hitbox 快取系統
   - 自動掃描角色 Hitbox/Hurtbox 節點
   - 提供快速查詢 API
   - 支持真實 AABB 碰撞檢測

2. **`ui/HitboxDebugDisplay.gd`** - 視覺化調試面板
   - 實時顯示距離、範圍、碰撞狀態
   - 可配置的更新頻率

3. **`TEST_HITBOX_IMPLEMENTATION.md`** - 本文檔

### 修改檔案

1. **`ai/ThreatAssessment.gd`** - 使用真實 Hitbox 數據
2. **`ai/ai_behavior.gd`** - 增強調試輸出
3. **`world.gd`** - 初始化 HitboxCache

---

## 測試場景

### 場景 1：HitboxCache 初始化測試

**目的：** 驗證 HitboxCache 是否成功讀取所有角色的 Hitbox 數據

**步驟：**

1. 啟動遊戲（從主選單進入對戰場景）
2. 觀察 Console 輸出

**預期輸出：**

```
[WORLD] HitboxCache 已初始化
[HITBOX CACHE] 開始初始化...

[HITBOX CACHE] 掃描角色: Player1 (ID: DAV)
  ✅ Hurtbox: size=(120, 270), pos=(10, -5)
    ✅ st_mp: size=(70, 50), pos=(60, -90)
    ✅ st_mk: size=(90, 60), pos=(75, -60)
    ✅ cr_mp: size=(65, 45), pos=(55, -50)
    ✅ cr_mk: size=(85, 55), pos=(70, -30)
  📊 共掃描 4 個攻擊動畫的 Hitbox 數據

[HITBOX CACHE] 掃描角色: Player2 (ID: DEN)
  ✅ Hurtbox: size=(120, 270), pos=(10, -5)
    ✅ st_mp: size=(70, 50), pos=(60, -90)
    ✅ st_mk: size=(90, 60), pos=(75, -60)
    ✅ cr_mp: size=(65, 45), pos=(55, -50)
    ✅ cr_mk: size=(85, 55), pos=(70, -30)
  📊 共掃描 4 個攻擊動畫的 Hitbox 數據

[HITBOX CACHE] 初始化完成！耗時: XX ms
[HITBOX CACHE] 快取統計:
  📦 Hitbox 數據: 8 條
  📦 Hurtbox 數據: 2 條
```

**驗證點：**

✅ HitboxCache 成功初始化  
✅ 所有角色的 Hurtbox 數據被讀取  
✅ 所有攻擊的 Hitbox 數據被讀取  
✅ 數據尺寸合理（不為零）

---

### 場景 2：視覺化調試面板測試

**目的：** 驗證 HitboxDebugDisplay 是否正確顯示實時數據

**前提條件：**

1. 在 `world.tscn` 場景中添加 HitboxDebugDisplay：
   - 添加 `Label` 節點到 `UI` 容器
   - 命名為 `HitboxDebugDisplay`
   - 附加 `ui/HitboxDebugDisplay.gd` 腳本
   - 在 Inspector 中啟用 `Enabled`

**步驟：**

1. 啟動遊戲
2. 觀察左上角（或設置的位置）的調試面板
3. 控制角色移動，觀察距離變化
4. 執行攻擊，觀察 Hitbox 信息和碰撞狀態

**預期顯示：**

```
[HITBOX DEBUG]
========================================
📏 距離: 425.3 px

📦 Hitbox 信息:
  P1 Hurtbox: (120, 270)
  P2 Hurtbox: (120, 270)

🎯 碰撞檢測:
  ✅ 無碰撞

🚨 威脅評估:
  等級: NONE
========================================
```

**攻擊時顯示：**

```
[HITBOX DEBUG]
========================================
📏 距離: 85.2 px

📦 Hitbox 信息:
  P2 攻擊: st_mk
    尺寸: (90, 60)
    範圍: 120.5 px
  P1 Hurtbox: (120, 270)
  P2 Hurtbox: (120, 270)

🎯 碰撞檢測:
  ⚠️ P2 攻擊 (st_mk) 與 P1 碰撞！

🚨 威脅評估:
  等級: CRITICAL
  來源: st_mk
  撞擊幀數: 0
  建議: stand_block
========================================
```

**驗證點：**

✅ 面板顯示正確的距離  
✅ 面板顯示正確的 Hurtbox 尺寸  
✅ 攻擊時顯示 Hitbox 信息  
✅ 碰撞檢測狀態正確更新  
✅ 威脅評估信息正確顯示

---

### 場景 3：AI 威脅評估測試

**目的：** 驗證 AI 是否正確使用真實 Hitbox 數據進行威脅評估

**前提條件：**

1. 啟用 AI：在 `world.tscn` 中設置其中一個玩家的 `AIBehavior` 節點：
   - `AI Enabled`: ✅
   - `Debug Mode`: ✅

2. 啟用 ThreatAssessment 調試：在 `ThreatAssessment.gd` 中設置 `debug_mode = true`

**步驟：**

1. 啟動遊戲（一個玩家 AI 控制，一個玩家手動控制）
2. 遠離 AI 玩家，觀察 Console 輸出
3. 靠近 AI 玩家（但不攻擊），觀察輸出
4. 攻擊 AI 玩家，觀察輸出和 AI 反應

**預期輸出 - 遠距離無威脅：**

```
[THREAT EVAL] Player1 檢查威脅 from Player2...
  📍 距離: 456.8 px
  📍 攻擊範圍: 120.5 px (真實 Hitbox)
  📍 AI Hurtbox 尺寸: (120, 270)
  📍 Hitbox 碰撞檢測: 無重疊
  ✅ 無威脅 (超出範圍)
```

**預期輸出 - 近距離高威脅：**

```
[THREAT EVAL] Player1 檢查威脅 from Player2...
  📍 距離: 95.2 px
  📍 攻擊範圍: 120.5 px (真實 Hitbox)
  📍 AI Hurtbox 尺寸: (120, 270)
  📍 Hitbox 碰撞檢測: 無重疊
  ⚠️ 威脅等級: HIGH (<12 幀)
```

**預期輸出 - Hitbox 碰撞 CRITICAL：**

```
[THREAT EVAL] Player1 檢查威脅 from Player2...
  📍 距離: 80.5 px
  📍 攻擊範圍: 120.5 px (真實 Hitbox)
  📍 AI Hurtbox 尺寸: (120, 270)
  📍 Hitbox 碰撞檢測: 有重疊
  🚨 威脅等級: CRITICAL (Hitbox 碰撞)

[AI DECISION] Player1
  動作: stand_block
  優先級: 100.0
  理由: Threat: st_mk
  威脅等級: CRITICAL
  威脅來源: st_mk
  撞擊幀數: 0
```

**驗證點：**

✅ AI 正確讀取真實 Hitbox 數據  
✅ 遠距離時無威脅  
✅ 近距離時威脅等級提升  
✅ Hitbox 碰撞時立即 CRITICAL  
✅ AI 自動執行防禦動作（格擋）

---

### 場景 4：AI 反應驗證測試

**目的：** 驗證 AI 是否根據真實 Hitbox 數據做出正確反應

**步驟：**

1. 啟動遊戲（AI vs 人類）
2. 在遠距離使用不同招式（st_mp, st_mk, cr_mk）
3. 在近距離使用不同招式
4. 觀察 AI 是否正確格擋

**預期行為：**

| 情況 | 距離 | AI 行為 | 驗證 |
|------|------|---------|------|
| st_mp (短範圍) | > 100 px | 無反應/移動 | ✅ |
| st_mp (短範圍) | < 80 px | 格擋 | ✅ |
| st_mk (長範圍) | > 130 px | 無反應/移動 | ✅ |
| st_mk (長範圍) | < 120 px | 格擋 | ✅ |
| cr_mk (低攻擊) | < 100 px | 蹲姿格擋 | ✅ |

**驗證點：**

✅ AI 對不同攻擊範圍的反應不同  
✅ AI 不會在超出範圍時格擋  
✅ AI 在真實碰撞範圍內正確防禦  
✅ AI 針對低攻擊使用蹲姿格擋

---

### 場景 5：動態同步測試

**目的：** 驗證修改編輯器 Hitbox 尺寸後，遊戲自動同步

**步驟：**

1. 打開 Godot 編輯器
2. 打開角色場景（例如 `characters/DAV.tscn`）
3. 選擇 `Hitbox/HitShape` 節點
4. 打開 `AnimationPlayer`，選擇 `st_mp` 動畫
5. 找到 Hitbox shape:size 的關鍵幀
6. 修改尺寸（例如從 `(70, 50)` 改為 `(100, 70)`）
7. 保存場景
8. 重新運行遊戲
9. 觀察 Console 輸出

**預期輸出：**

```
[HITBOX CACHE] 掃描角色: Player1 (ID: DAV)
    ✅ st_mp: size=(100, 70), pos=(60, -90)  # ← 新尺寸！
```

**驗證點：**

✅ HitboxCache 讀取到新尺寸  
✅ 無需修改任何代碼  
✅ AI 威脅評估自動使用新範圍  
✅ 調試面板顯示新尺寸

---

## 性能檢查

### CPU 使用率測試

**步驟：**

1. 啟動遊戲
2. 在 Godot 編輯器中打開 "Profiler"
3. 觀察 `HitboxCache` 和 `ThreatAssessment` 的執行時間

**預期結果：**

- `HitboxCache._initialize_cache()`: 一次性初始化，< 5ms
- `HitboxCache.check_hitbox_collision()`: 每次調用 < 0.1ms
- `ThreatAssessment.evaluate_threats()`: 每次調用 < 0.5ms

**驗證點：**

✅ 初始化時間合理  
✅ 查詢時間極短  
✅ 不影響遊戲幀率（保持 60 FPS）

---

## 調試指南

### 問題：HitboxCache 未初始化

**症狀：**

```
[THREAT EVAL] 警告：HitboxCache 未找到，將使用後備距離數據
```

**解決方案：**

1. 檢查 `world.gd` 中是否正確添加 HitboxCache：
   ```gdscript
   var hitbox_cache = HitboxCache.new()
   add_child(hitbox_cache)
   hitbox_cache.add_to_group("hitbox_cache")
   ```

2. 確保 `HitboxCache.gd` 腳本已正確保存在 `ai/` 目錄

3. 檢查 Console 是否有腳本加載錯誤

---

### 問題：Hitbox 數據為零

**症狀：**

```
[HITBOX CACHE] 掃描角色: Player1 (ID: DAV)
  ⚠️ Hurtbox 沒有有效的 shape
```

**解決方案：**

1. 打開角色場景，檢查 `Hurtbox/HurtShape` 節點是否存在
2. 檢查 `HurtShape` 的 `shape` 屬性是否為 `RectangleShape2D`
3. 檢查 `shape.size` 是否不為零
4. 對於 Hitbox，檢查動畫中是否有 `Hitbox/HitShape:shape:size` 軌道

---

### 問題：調試面板不顯示

**症狀：**

遊戲運行但看不到調試面板

**解決方案：**

1. 檢查 `HitboxDebugDisplay` 節點的 `Enabled` 是否為 `true`
2. 檢查 `Visible` 是否為 `true`
3. 檢查節點是否在 UI 容器中且 Z-index 正確
4. 檢查 Console 是否有腳本錯誤

---

### 問題：AI 仍使用硬編碼距離

**症狀：**

AI 威脅評估沒有顯示 "真實 Hitbox" 標記

**解決方案：**

1. 確保 `ThreatAssessment.debug_mode = true`
2. 檢查 `hitbox_cache` 是否正確連接：
   ```gdscript
   hitbox_cache = get_tree().get_first_node_in_group("hitbox_cache")
   ```
3. 確保 `hitbox_cache.is_initialized` 為 `true`

---

## 總結

本測試文檔涵蓋了 Hitbox 檢測系統的所有關鍵功能：

✅ 自動數據掃描和快取  
✅ 真實 AABB 碰撞檢測  
✅ 視覺化調試工具  
✅ AI 威脅評估集成  
✅ 零維護動態同步  
✅ 性能優化驗證  

完成所有測試場景後，系統即可投入使用。

---

## 後續擴展

### 未來可以添加的功能：

1. **多 Hitbox 支持** - 一個攻擊有多個 Hitbox（如旋風腿）
2. **動態 Hitbox** - 隨動畫時間變化的 Hitbox 尺寸
3. **3D Hitbox** - 支持 3D 格鬥遊戲（使用 AABB3D）
4. **Hitbox 可視化** - 在遊戲中繪製 Hitbox 邊界（調試模式）
5. **性能分析工具** - 更詳細的 Hitbox 查詢統計

---

**文檔版本：** 1.0  
**最後更新：** 2026-01-21  
**作者：** AI Assistant  
