# 100p 多段連打招式 - 動畫與Hitbox設置指南

## 🎯 概述

100p是DAV的新招式，由以下部分組成：
- **輸入**: 236 + MK (下→下前→前 + 踢)
- **類型**: 多段連打招式（3段）
- **總時長**: 60幀 (1秒 @ 60 FPS基準)
- **打击时机**: 第8幀、第16幀、第24幀

---

## 📋 設置步驟（在Godot編輯器中）

### 步驟1：打開DAV角色場景
在Godot編輯器中打開 `characters/DAV.tscn`

### 步驟2：在AnimationPlayer中新增100p動畫
1. 選擇 **AnimationPlayer** 節點
2. 在Animation面板中，點擊 **新建動畫** (New Animation)
3. 命名為 `100p`
4. 設置動畫時長: **1.0秒** (重要：基於60 FPS設計)
5. 將動畫幀速設置為: **1.0** (表示每幀0.016秒，60 FPS)

### 步驟3：添加動畫幀
假設你有DAV的連打動畫資源（如在 `assets/characters/DAV/` 中）：

創建3個連打幀段：
- **第1段** (幀 0-7): 準備姿態
- **第2段** (幀 8-15): 第1次打擊（8幀觸發hitbox）
- **第3段** (幀 16-23): 第2次打擊（16幀觸發hitbox）
- **第4段** (幀 24-59): 第3次打擊+回收（24幀觸發最後hitbox，然後回復為idle）

> **備註**: 如果你沒有實際的動畫圖像，可以暫時使用任何現有的踢擊動畫（如 `st_mk`) 作為佔位符

### 步驟4：添加Hitbox激活事件

在AnimationPlayer的100p動畫中，添加以下**軌道事件**：

```
時間     方法調用             參數
─────────────────────────────────────
0.133s   activate_hitbox     (frame=8)    # 第1段，持續約2幀
0.267s   deactivate_hitbox   
0.267s   activate_hitbox     (frame=16)   # 第2段，持續約2幀
0.400s   deactivate_hitbox
0.400s   activate_hitbox     (frame=24)   # 第3段最長，持續約3幀
0.967s   deactivate_hitbox   # 招式結束前停用
```

> **時間計算**: frame / 60 FPS
> - 8幀 = 8/60 = 0.133秒
> - 16幀 = 16/60 = 0.267秒
> - 24幀 = 24/60 = 0.400秒

### 步驟5：設置HitshapeSize（Hitbox碰撞框）

在DAV場景中選擇 **Hitbox/HitShape** (CollisionShape2D)：

1. 設置 **形狀**: RectangleShape2D
2. 設置 **大小**: 約 60x80 像素（根據角色的踢擊幀寬度調整）
3. 設置 **位置**: 相對於角色的踢擊點
   - 水平: +30 到 +50（向前）
   - 垂直: -20 到 +10（根據踢擊高度調整）

> **提示**: 可以在編輯器中拖動 HitShape 的綠色邊框來調整位置和大小

### 步驟6：配置AnimationTree條件

在Player.gd或AnimationManager中，確保100p能夠觸發動畫：

```gdscript
# 以下代碼應該已自動工作，因為MoveSet會查詢move_id="100p"
animation_state.travel("100p")  # 觸發100p動畫狀態轉換
```

---

## 🔧 多段Hit的工作原理

### 數據驅動流程

```
InputManager 檢測 236+MK
  ↓
PlayerController 記錄 spm1_pressed
  ↓
Player.gd 執行 _handle_input()
  ↓
MoveSet.activate_move("100p") 
  ① 加載 dav_100p.tres 資源
  ② 檢查 is_multi_hit = true
  ③ 讀取 hit_phases 數組 （第8、16、24幀）
  ④ 播放 "100p" 動畫
  ↓
每幀執行 MoveSet._physics_process()
  ↓
當前幀 == hit_phases[i].frame
  ↓
HitResponseHandler 檢測 Hitbox 碰撞
  ↓
目標 take_hit() 並傳遞當前段的傷害/硬直
```

### Hit階段配置 (dav_100p.tres)

```
hit_phases = [
  {frame: 8,  damage: 5.0, hitstun: 18, blockstun: 12, knockback: 50.0},    # 第1段
  {frame: 16, damage: 5.0, hitstun: 18, blockstun: 12, knockback: 50.0},    # 第2段
  {frame: 24, damage: 6.0, hitstun: 30, blockstun: 20, knockback: 120.0}    # 第3段（終結）
]
```

---

## ✅ 檢查清單

完成設置後，在遊戲中測試以下項目：

- [ ] 輸入 236 + MK，DAV執行100p招式
- [ ] 第1段Hitbox激活於約0.13秒
- [ ] 第2段Hitbox激活於約0.27秒
- [ ] 第3段Hitbox激活於約0.40秒
- [ ] 對手被擊中時播放受擊動畫
- [ ] 傷害數值正確 (第1段5, 第2段5, 第3段6 = 總16)
- [ ] 最後一段有較強的硬直 (hitstun_frames=30)
- [ ] 招式播放完畢後自動返回待命狀態

---

## 🐛 調試技巧

### 查看Hit時機
啟用 `FrameBar` 或 `FrameCounter` 進行視覺化確認：
- 每幀打印 `[100p] frame=%d, hit_phases_triggered=[...]`

### 檢查Hitbox碰撞
1. 在編輯器中選擇 HitShape
2. 啟用 **Visible Collision Shapes** (在Scene視圖中)
3. 運行遊戲，並於100p施展時觀察綠色的HitBox框

### 驗證多段Hit追蹤
檢查 HitResponseHandler.multi_hit_targets 字典：
```gdscript
# 應該看到類似:
# {target_player_b: {hit_index: 0, last_hit_frame: 120}}  # 第1段
# {target_player_b: {hit_index: 1, last_hit_frame: 132}}  # 第2段
# {target_player_b: {hit_index: 2, last_hit_frame: 144}}  # 第3段
```

---

## 📚 相關文件

| 文件 | 用途 |
|------|------|
| `data/specials/inputs/100p_input.tres` | 輸入序列定義（236+MK） |
| `data/specials/dav_100p.tres` | 招式資源（傷害、硬直、hit_phases） |
| `InputManager.gd` | 已添加 `check_100p_input()` 方法 |
| `PlayerController.gd` | 已添加100p的輸入檢測邏輯 |
| `characters/DAV.tscn` | **需要添加**: 100p動畫 + Hitbox事件 |
| `MoveSet.gd` | 已添加100p.tres至LEGACY資源列表 |

---

## 💡 進階：動畫複用

如果你已經有st_mk（踢擊）的動畫，可以複用它作為100p的基礎，然後：
1. 複製st_mk動畫為100p
2. 調整速度（可能需要加快）
3. 新增中間的第2段打擊動畫幀
4. 添加Hitbox事件

或者，使用 **AnimationTree StateMachine** 自動拼接多個動畫段：
```gdscript
# 播放st_mk 3次（每次延遲）
animation_state.travel("st_mk")  # 執行初始攻擊
# ... 等待 8幀
animation_state.travel("st_mk")  # 執行第2次攻擊
# ... 等待 8幀
animation_state.travel("st_mk")  # 執行第3次攻擊
```

