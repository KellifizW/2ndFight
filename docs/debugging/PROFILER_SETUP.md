# AIPerformanceMonitor 集成指南

## 快速集成（3 步驟）

### 步驟 1：在 world.gd 中添加監視器

打開 `world.gd`，在 `_ready()` 函數中添加：

```gdscript
func _ready() -> void:
	# ... 現有代碼 ...
	
	# ============================================================
	# AI 性能監視器（Phase 2 優化）
	# ============================================================
	var profiler = AIPerformanceMonitor.new()
	profiler.enabled = true
	profiler.log_interval = 5.0  # 每 5 秒輸出一次
	profiler.show_realtime = false  # 可選：每幀實時顯示
	add_child(profiler)
	
	if debug_mode:
		print("[WORLD] ✓ AI 性能監視器已添加")
```

### 步驟 2：運行遊戲

1. 在 Godot 編輯器中點擊 **播放按鈕** 運行遊戲
2. 打開 **Debug > Debugger > Console** 標籤（查看輸出）
3. 玩遊戲或讓 AI 對戰

### 步驟 3：查看性能報告

等待 5 秒後，控制台會自動輸出性能報告：

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

## 完整集成示例

如果你想要更完整的集成，這是完整的 `world.gd` 片段：

```gdscript
extends Node

# ... 現有代碼 ...

@export var debug_mode: bool = false
@export var enable_performance_monitoring: bool = true  # 新增
@export var profiling_interval: float = 5.0  # 新增

func _ready() -> void:
	# 初始化玩家、攝像機等（現有代碼）
	# ...
	
	# ============================================================
	# AI 性能監視器（Phase 2 優化）
	# ============================================================
	if enable_performance_monitoring:
		_setup_performance_monitoring()

func _setup_performance_monitoring() -> void:
	"""設置 AI 性能監視器"""
	var profiler = AIPerformanceMonitor.new()
	profiler.enabled = true
	profiler.log_interval = profiling_interval
	profiler.show_realtime = false  # 關閉即時輸出以減少控制台噪聲
	add_child(profiler)
	
	if debug_mode:
		print("[WORLD] ✓ AI 性能監視器已啟用")
		print("  • 監視間隔: %.1f 秒" % profiling_interval)
		print("  • 檢查 Console 標籤查看性能報告")
```

---

## 配置選項

### 完整配置示例

```gdscript
var profiler = AIPerformanceMonitor.new()

# 啟用/禁用監視器
profiler.enabled = true

# 性能報告輸出間隔（秒）
profiler.log_interval = 5.0  # 選項：3.0, 5.0, 10.0

# 即時性能顯示（每幀）
profiler.show_realtime = false  # 關閉以減少日誌

add_child(profiler)
```

### Inspector 配置（如果作為節點添加）

如果你將 AIPerformanceMonitor 作為場景節點添加：

```
Inspector 面板：
Enabled = ✓ True
Log Interval = 5.0
Show Realtime = ☐ False
```

---

## 解讀性能報告

### 綠色（優秀）指標

```
✅ 平均 FPS: 58.2+         → 遊戲流暢
✅ 決策開銷: < 3%           → 決策系統效率高
✅ 威脅評估開銷: < 2%       → 威脅評估高效
✅ 性能等級: A 或 A+        → 最優狀態
```

### 黃色（警告）指標

```
⚠️ 平均 FPS: 50-58         → 監視中，需注意
⚠️ 決策開銷: 3-5%           → 可接受，但不優秀
⚠️ 威脅評估開銷: 2-5%       → 可接受，但不優秀
⚠️ 性能等級: B 或 C        → 需要優化
```

### 紅色（問題）指標

```
❌ 平均 FPS: < 50           → 性能不足，需優化
❌ 決策開銷: > 5%           → 決策層過於複雜
❌ 威脅評估開銷: > 5%       → 威脅評估過於複雜
❌ 性能等級: D              → 立即採取行動
```

---

## 性能優化建議

### 如果決策開銷過高（> 5%）

**原因**：AI 決策層計算量大

**解決方案**：

```gdscript
# 在 ai_behavior.gd 中增加決策間隔
const DECISION_INTERVAL: float = 0.35  # 從 0.25 改為 0.35

# 或啟用自適應間隔
enable_adaptive_interval = true
```

### 如果威脅評估開銷過高（> 5%）

**原因**：威脅評估計算複雜

**解決方案**：

```gdscript
# 在 ThreatAssessment.gd 中禁用昂貴的計算
# 例如：禁用複雜的預測計算
```

### 如果 FPS 不穩定（波動大）

**原因**：某些幀的計算量特別大

**解決方案**：

```gdscript
# 在 max_frame_time > 25ms 時觸發優化
if max_frame_time > 25.0:
	print("⚠️ 檢測到幀時間過長，建議優化")
	# 禁用某些非關鍵功能
```

---

## 對比優化效果

### 方法 1：逐次對比

```
測試 1（優化前）：FPS 52, 決策開銷 7%
測試 2（僅啟用快取）：FPS 53, 決策開銷 6%
測試 3（再加自適應間隔）：FPS 57, 決策開銷 2%
```

### 方法 2：自動對比腳本

```gdscript
# 添加到 world.gd
var perf_baseline: Dictionary = {}
var perf_optimized: Dictionary = {}

func record_baseline_performance() -> void:
	# 禁用所有優化
	# 運行 5 分鐘
	# 記錄性能數據
	pass

func record_optimized_performance() -> void:
	# 啟用所有優化
	# 運行 5 分鐘
	# 記錄性能數據
	pass

func compare_performance() -> void:
	var fps_improvement = ((perf_optimized.fps - perf_baseline.fps) / perf_baseline.fps) * 100
	print("FPS 改進: %.1f%%" % fps_improvement)
```

---

## 故障排除

### 問題 1：監視器沒有輸出

**症狀**：等待 5 秒後沒有看到性能報告

**檢查**：
- [ ] 是否啟用了監視器？ `profiler.enabled = true`
- [ ] 是否添加為子節點？ `add_child(profiler)`
- [ ] 控制台標籤是否開啟？ **Debug > Debugger > Console**
- [ ] 是否真的等待了 5 秒？計時器可能需要重置

**解決**：
```gdscript
# 強制立即輸出
profiler.log_timer = profiler.log_interval
```

### 問題 2：FPS 突然下降

**症狀**：性能報告顯示 FPS 異常低

**可能原因**：
- Godot 編輯器運行（性能差）✗ 使用編譯版本
- 其他進程佔用 CPU ✗ 關閉背景應用
- 場景複雜度高 ✗ 簡化場景進行測試

**測試**：
```gdscript
# 檢查是否在編輯器中運行
if Engine.is_editor_hint():
	print("⚠️ 在編輯器中運行，性能測試結果不準確")
```

### 問題 3：決策開銷異常高

**症狀**：決策開銷 > 10%

**可能原因**：
- AIBehavior 計算過於複雜
- ThreatAssessment 評估昂貴
- 決策層邏輯冗長

**診斷**：
```gdscript
# 添加更詳細的計時
var decision_start = Time.get_ticks_usec()
var decision = decision_layers.get_best_decision(parent, opponent)
var decision_end = Time.get_ticks_usec()
print("決策計算耗時: %.2f ms" % ((decision_end - decision_start) / 1000.0))
```

---

## 進階使用

### 自訂性能報告

```gdscript
# 擴展 AIPerformanceMonitor 進行自訂報告
class CustomProfiler extends AIPerformanceMonitor:
	func _print_stats() -> void:
		# 呼叫父方法
		super._print_stats()
		
		# 添加自訂輸出
		print("\n🎮 遊戲狀態:")
		print("  玩家 1 HP: %d" % get_player_1_hp())
		print("  玩家 2 HP: %d" % get_player_2_hp())
		print("  回合數: %d" % get_round_number())
```

### 性能日誌存檔

```gdscript
# 自動保存性能報告到文件
class LoggingProfiler extends AIPerformanceMonitor:
	var log_file: FileAccess
	
	func _ready() -> void:
		super._ready()
		log_file = FileAccess.open("user://perf_log.txt", FileAccess.WRITE)
	
	func _print_stats() -> void:
		super._print_stats()
		
		# 也寫入文件
		if log_file:
			var report = "FPS: %d, Decision overhead: %.1f%%" % [...]
			log_file.store_line(report)
```

---

## 即時監控（可選）

如果想要更頻繁的監控：

```gdscript
profiler.show_realtime = true  # 啟用即時輸出

# 控制台將每秒顯示一次：
# 🔴 [FPS] 58.2 (幀時: 17.18 ms)
```

**注意**：啟用即時輸出會增加控制台噪聲，不推薦在最終版本中使用。

---

## 性能基準

### 目標性能指標

| 指標 | 目標 | 優秀 | 可接受 | 需改進 |
|-----|------|------|--------|--------|
| FPS | ≥ 60 | 60 | 55-58 | < 55 |
| 決策開銷 | < 2% | < 2% | 2-5% | > 5% |
| 威脅開銷 | < 1% | < 1% | 1-3% | > 3% |
| 最大幀時 | < 16.7ms | < 16.7ms | 16.7-25ms | > 25ms |

---

## 下一步

1. ✅ 集成 AIPerformanceMonitor
2. ✅ 運行遊戲並查看性能報告
3. ✅ 記錄基準性能數據
4. ✅ 啟用所有 Phase 2 優化
5. ✅ 對比優化前後性能
6. ✅ 根據結果進行微調（見上方優化建議）

---

**監視準備就緒！現在運行遊戲查看性能改進。**

參考文檔：
- [PHASE2_QUICK_START.md](./PHASE2_QUICK_START.md)
- [PHASE2_IMPLEMENTATION_GUIDE.md](./PHASE2_IMPLEMENTATION_GUIDE.md)
- [PHASE2_COMPLETION_SUMMARY.md](./PHASE2_COMPLETION_SUMMARY.md)
