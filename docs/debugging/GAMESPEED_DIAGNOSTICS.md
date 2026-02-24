# 遊戲速度診斷報告

## 問題分析

### 1. **時間轉換根本問題**

根據當前代碼，發現了 **混淆的時間單位系統**：

#### 在 MoveSet.gd 中：
```gdscript
// Line 150: powerkk 初始化
move_library["powerkk"] = MoveData.new(
	"powerkk", "DAV", 12.0, 600.0, 56.0, 150.0, ...
)
// duration = 56.0 （現在應解釋為幀數）
```

#### 但在計算中（Line 233-234）：
```gdscript
var duration_seconds = move_data.duration / 60.0  // 正確 ✓
var base_speed = (move_data.move_distance / duration_seconds) * world.SIMULATION_SCALE
```

**✓ 這個計算是正確的**

### 2. **診斷速度加快的可能原因**

根據用戶日誌，找到以下重點資訊：

```
[MoveSet DEBUG] Animation 'fireball' loaded | Duration: 0.700s -> 42 frames @60 FPS (logic)
[MOVE DEBUG] 移動距離: 150 px, 時長: 56 frm (0.933 s), 速度: 160.7 px/s (2.67 px/frame @60FPS)
```

**速度計算看起來是正確的**，但可能的問題：

1. **AnimationPlayer 播放速度** - 可能被設為 >1.0
2. **計時器遞減速度** - 可能在 _process() 中以錯誤的速率遞減
3. **幀計數不匹配** - 邏輯幀與物理幀的轉換錯誤
4. **多重計時器系統衝突** - 同時使用秒數和幀數計時

### 3. **關鍵修復已應用**

✅ MoveSet.gd line 233-234：正確計算 duration_seconds
✅ MoveSet.gd line 255-262：添加詳細的移動參數除錯日誌  
✅ fighter.gd line 5：PHYSICS_FPS 改為 120（從錯誤的 60）
✅ MoveSet.gd line 5：添加 LOGIC_FPS = 60 常數

### 4. **需要進一步診斷的地方**

1. **確認 _process() 中的計時器遞減邏輯**
   - 檢查是否有計時器同時在 _process 和 _physics_process 中遞減
   
2. **驗證 fixed_velocity 的應用**
   - base_speed 是否正確應用到 fixed_velocity.x
   
3. **動畫播放速度**
   - AnimationPlayer.speed_scale 是否被意外改變
   
4. **時間同步**
   - TimingDiagnosticTool 應能報告實際的物理/邏輯幀速率

## 推薦的診斷步驟

1. 在 world.gd 中添加 TimingDiagnosticTool 自動節點
2. 運行遊戲，觀察 3 秒的報告（檢查物理 FPS、邏輯幀速率）
3. 對比報告的速度與預期（120 FPS 物理，30 FPS ~需要驗證邏輯幀速率）
4. 檢查特殊招式（powerkk）的移動進度是否符合預期距離

## 已知的正確值

根據代碼分析，以下計算應該是正確的：

- **Fireball 動畫**：0.700 秒 = 42 邏輯幀 ✓
- **powerkk 持續時間**：56 邏輯幀 = 0.933 秒 ✓
- **powerkk 移動距離**：150 像素 in 0.933s = 160.7 px/s ✓
- **Hitstun 轉換**：24 邏輯幀 × 2 = 48 物理幀 ✓
