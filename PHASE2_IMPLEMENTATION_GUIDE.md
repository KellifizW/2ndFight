# Phase 2 性能優化 - 實施和監測指南

## 📋 概述

Phase 2 的三項優化已全部實施：

| 優化項目 | 文件 | 預期改進 |
|---------|------|--------|
| 2.1 預計算幀數據快取 | `ai/FrameDataManager.gd` | 3-5% |
| 2.2 自適應決策間隔 | `ai/ai_behavior.gd` | 5-8% |
| 2.3 延遲加載 Hitbox 緩存 | `ai/HitboxCache.gd` | 消除初始化卡頓 |
| 性能監視工具 | `ai/AIPerformanceMonitor.gd` | 實時監測 |

**總預期性能提升：10-15%（加上 Phase 1 的 30-40% = 累計 40-55%）**

---

## 🎯 快速開始：設置性能監測

### 步驟 1：在遊戲場景中添加監視器

在 `world.gd` 或主遊戲場景的 `_ready()` 函數中：

```gdscript
func _ready() -> void:
	# ... 現有代碼 ...
	
	# 添加性能監視器
	var profiler = AIPerformanceMonitor.new()
	profiler.enabled = true
	profiler.log_interval = 5.0  # 每 5 秒輸出一次
	profiler.show_realtime = false  # 不需要每幀輸出
	add_child(profiler)
	
	if debug_mode:
		print("[WORLD] AI 性能監視器已添加")
```

### 步驟 2：運行遊戲並觀察控制台

1. 在 Godot 編輯器中運行遊戲
2. 打開 **Debug > Debugger > Console** 標籤
3. 玩遊戲或讓 AI 對戰
4. 等待 5 秒，查看性能報告

### 範例輸出

```
============================================================
█ AI PERFORMANCE REPORT - 5.0秒
============================================================

📊 幀速率:
  平均 FPS: 58.2
  平均幀時間: 17.18 ms
  最小幀時間: 16.10 ms
  最大幀時間: 22.45 ms
  樣本數: 291

⚙️ 決策系統:
  平均決策時間: 0.45 ms
  決策開銷: 2.6%
  決策調用數: 58

⚔️ 威脅評估:
  平均評估時間: 0.32 ms
  威脅評估開銷: 1.9%
  評估調用數: 58

⭐ 性能等級:
  A+ (卓越 - 60 FPS穩定)

============================================================
```

---

## 📊 性能指標解讀

### FPS 和幀時間

| 指標 | 目標 | 說明 |
|-----|------|------|
| 平均 FPS | ≥ 58 | 遊戲流暢度 |
| 最大幀時間 | < 25ms | 避免可見卡頓 |
| 最小幀時間 | > 15ms | 穩定性 |

### 決策系統開銷

**決策開銷 = (平均決策時間 / 平均幀時間) × 100%**

| 開銷 | 評估 | 建議 |
|-----|------|------|
| < 3% | ✅ 優秀 | 無需改動 |
| 3-5% | ⚠️ 可接受 | 監視中 |
| 5-10% | ⚠️ 需注意 | 考慮增加決策間隔 |
| > 10% | ❌ 過高 | 啟用自適應間隔或優化決策層 |

### 自適應決策間隔的影響

啟用 `enable_adaptive_interval = true` 後：

- **危急狀態 (CRITICAL)**：決策間隔 = 0.1s（每 6 幀）→ 快速反應
- **高威脅 (HIGH)**：決策間隔 = 0.15s（每 9 幀）→ 標準反應
- **中等威脅 (MEDIUM)**：決策間隔 = 0.25s（每 15 幀）→ 正常思考
- **遠距離 (SAFE)**：決策間隔 = 0.3s（每 18 幀）→ 放鬆思考

**預期效果**：在非危急情況下減少計算，危急時快速反應 → 性能提升 5-8%

---

## 🔧 配置優化選項

### 在 Inspector 中啟用優化

#### 1. FrameDataManager（幀數據快取）

在場景中找到 AIBehavior 節點，然後在其子節點中找到 FrameDataManager：

```
Inspector 面板：
✓ Enable Cache = True
```

**驗證**：控制台應顯示 `[FRAME DATA] Pre-computed 9 move entries`

#### 2. AIBehavior（自適應決策間隔）

在 AIBehavior 節點的 Inspector 中：

```
Inspector 面板：
✓ Enable Adaptive Interval = True
Decision Interval Override = 0.0  # 使用自適應
```

**驗證**：調試模式下應顯示決策時的 `決策間隔: 0.XXX (自適應)`

#### 3. HitboxCache（延遲加載）

在 HitboxCache 節點的 Inspector 中：

```
Inspector 面板：
✓ Enable Lazy Loading = True
Debug Mode = True  # 查看加載進度
```

**驗證**：控制台應顯示：
```
[HITBOX CACHE] 延迟加载已啟用，將分幀掃描 2 個角色
[HITBOX CACHE] 延迟加載完成！
```

#### 4. AIPerformanceMonitor（性能監測）

在 world 場景中添加 AIPerformanceMonitor 節點：

```
Inspector 面板：
✓ Enabled = True
Log Interval = 5.0  # 每 5 秒輸出
Show Realtime = False
```

---

## 🧪 性能測試步驟

### 測試 1：基準性能測量（5 分鐘）

**目標**：建立優化前的基準線

1. 禁用所有 Phase 2 優化：
   - `FrameDataManager.enable_cache = false`
   - `AIBehavior.enable_adaptive_interval = false`
   - `HitboxCache.enable_lazy_loading = false`

2. 運行遊戲，進行 AI 對戰（5 分鐘）

3. 記錄數據：
   - 平均 FPS: _____
   - 決策開銷: _____ %
   - 威脅評估開銷: _____ %

4. 保存報告為 `PHASE2_BASELINE.txt`

### 測試 2：啟用全部優化

**目標**：測量優化效果

1. 啟用所有 Phase 2 優化：
   - `FrameDataManager.enable_cache = true`
   - `AIBehavior.enable_adaptive_interval = true`
   - `HitboxCache.enable_lazy_loading = true`

2. 運行相同場景（5 分鐘）

3. 記錄數據並計算改進：

```
平均 FPS 改進 = ((新 FPS - 基準 FPS) / 基準 FPS) × 100%
決策開銷改進 = 基準開銷% - 新開銷%
```

4. 保存報告為 `PHASE2_OPTIMIZED.txt`

### 測試 3：各優化的單獨效果

為了驗證每個優化的實際影響，進行 3 次單獨測試：

#### 3A：僅啟用幀數據快取
```
enable_cache = true
enable_adaptive_interval = false
enable_lazy_loading = false
```

#### 3B：僅啟用自適應間隔
```
enable_cache = false
enable_adaptive_interval = true
enable_lazy_loading = false
```

#### 3C：僅啟用延遲加載
```
enable_cache = false
enable_adaptive_interval = false
enable_lazy_loading = true
```

**預期結果**：
- 3A：FPS +1-2%
- 3B：FPS +3-5%
- 3C：消除初始化卡頓（見下方）

---

## 🎬 初始化卡頓測試

### 測試延遲加載效果

#### 方法 1：監測加載時間

啟用 `HitboxCache.debug_mode = true`，觀察控制台：

```
// 延迟加载禁用時：
[HITBOX CACHE] 初始化完成！耗時: 156 ms  // 一次性卡頓

// 延迟加载启用時：
[HITBOX CACHE] 延迟加载已啟用，將分幀掃描 2 個角色
[HITBOX CACHE] 延迟加載完成！  // 分散在多幀，無明顯卡頓
```

#### 方法 2：FPS 圖表觀察

使用 Godot 的 Debugger > Profiler：

1. 開始遊戲時觀察 FPS 圖表
2. **禁用延遲加載**：應看到初始化時出現 FPS 下降峰值
3. **啟用延遲加載**：初始化期間 FPS 應保持穩定

---

## 📈 預期性能改進總結

### Phase 1 + Phase 2 累計改進

| 階段 | 優化項目 | 預期改進 | 狀態 |
|-----|---------|---------|------|
| Phase 1 | 決策快取 + 投射物快取 + 跳過 AI 輸入 + 增加決策間隔 | 30-40% | ✅ 已實施 |
| Phase 2 | 幀數據預計算 + 自適應間隔 + 延遲 Hitbox 加載 | +10-15% | ✅ 已實施 |
| **累計** | | **40-55%** | ✅ |

### 典型性能曲線

```
優化前：
  平均 FPS: 45-50 FPS
  決策開銷: 8-12%
  初始化時間: 150+ ms 卡頓

Phase 1 後：
  平均 FPS: 55-60 FPS  (+20-30%)
  決策開銷: 4-6%
  
Phase 2 後：
  平均 FPS: 58-60 FPS  (+3-5%)
  決策開銷: 2-3%
  初始化時間: 無明顯卡頓

累計改進：
  FPS: +30-50%
  決策開銷: -4-9%
```

---

## 🐛 故障排除

### 問題 1：自適應間隔無效

**症狀**：啟用 `enable_adaptive_interval` 後沒有看到變化

**檢查清單**：
- [ ] `AIBehavior.enable_adaptive_interval = true`?
- [ ] `decision_interval_override == 0`?（允許自適應）
- [ ] 啟用調試模式查看決策日誌？
- [ ] ThreatAssessment 正確初始化？

**解決**：
```gdscript
# 在 AIBehavior._init_subsystems() 後添加
if debug_mode:
    print("[AI] Adaptive interval: %s" % ai_behavior.enable_adaptive_interval)
    print("[AI] Threat system valid: %s" % (ai_behavior.threat_system != null))
```

### 問題 2：延遲加載卡住

**症狀**：`[HITBOX CACHE] 延迟加載完成！` 永不出現

**檢查清單**：
- [ ] Hitbox 節點是否有效？
- [ ] Player 節點是否在 "players" 組中？
- [ ] 場景是否完全加載？

**解決**：
```gdscript
# 增加診斷輸出
if debug_mode:
    print("[HITBOX CACHE] Players found: %d" % players_to_scan.size())
    print("[HITBOX CACHE] Progress: %d/%d" % [cache_progress, players_to_scan.size()])
```

### 問題 3：性能監視器無數據

**症狀**：AIPerformanceMonitor 沒有輸出報告

**檢查清單**：
- [ ] `AIPerformanceMonitor.enabled = true`?
- [ ] 檢查 Console 是否有初始化消息？
- [ ] 是否等待了足夠長的時間（log_interval 秒）？

**解決**：
```gdscript
# 強制立即輸出
if profiler:
    profiler.log_timer = profiler.log_interval  # 觸發下一次輸出
```

---

## 📋 優化清單

完成以下所有步驟以獲得最佳性能：

- [ ] 啟用 FrameDataManager.enable_cache = true
- [ ] 啟用 AIBehavior.enable_adaptive_interval = true
- [ ] 啟用 HitboxCache.enable_lazy_loading = true
- [ ] 在主場景中添加 AIPerformanceMonitor
- [ ] 執行基準性能測試
- [ ] 執行優化後性能測試
- [ ] 對比改進百分比
- [ ] 記錄結果到 PHASE2_RESULTS.txt

---

## 🔗 相關文件

- [AI_PERFORMANCE_OPTIMIZATION_GUIDE.md](./AI_PERFORMANCE_OPTIMIZATION_GUIDE.md) - 完整優化指南
- [ai/FrameDataManager.gd](./FrameDataManager.gd) - 幀數據快取實現
- [ai/ai_behavior.gd](./ai_behavior.gd) - 自適應決策實現
- [ai/HitboxCache.gd](./HitboxCache.gd) - 延遲加載實現
- [ai/AIPerformanceMonitor.gd](./AIPerformanceMonitor.gd) - 性能監測工具

---

## 📝 開發筆記

### 何時使用每個優化

1. **幀數據快取**：始終啟用（無負面影響）
2. **自適應決策間隔**：在 AI 表現良好時啟用
3. **延遲加載**：在初始化卡頓時啟用

### 微調參數

在 `ai_behavior.gd` 中調整：

```gdscript
# 改變自適應間隔的反應速度
const INTERVAL_CRITICAL: float = 0.08   # 更快反應
const INTERVAL_HIGH: float = 0.12
const INTERVAL_NORMAL: float = 0.25
const INTERVAL_SAFE: float = 0.35
```

在 `HitboxCache.gd` 中調整：

```gdscript
# 加快/減慢延遲加載速度
call_deferred("_lazy_load_next_character")  # 每幀 1 個
# 改為：
await get_tree().process_frame  # 等待指定幀數
_lazy_load_next_character()
```

---

**最後更新**：2026-01-23  
**状态**：Phase 2 完全實施 ✅
