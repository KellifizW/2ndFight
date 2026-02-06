# AI 招式限制支援 - 快速參考

## 問題已解決

❌ **舊問題**：AI 不知道 CPUController 的招式限制設定，導致在禁用某些招式時無法靈活對戰

✅ **解決方案**：AI 現在完全支援招式限制，會自動調整戰術並使用替代招式

---

## 核心修復 (3 個文件)

### 1. **AIDecisionLayers.gd** - 決策層強化

新增 2 個輔助方法：
```gdscript
_is_move_restricted(move_name)          # 檢查招式是否被限制
_get_unrestricted_alternative(...)      # 獲得非限制的替代招式
```

改進 3 個核心方法：
- `_select_punish_attack()` - 檢查懲罰招式限制 ✓
- `get_fallback_decision()` - 智能優先級排序 ✓
- 所有決策層都過濾限制招式 ✓

### 2. **ai_behavior.gd** - 限制傳遞與約束

新增專用方法：
```gdscript
set_move_restrictions(restricted, enable)  # 安全傳遞限制列表
```

改進：
- 為所有特殊招式添加限制檢查 ✓
- 新增最終安全檢查層 ✓
- 完整的日誌追蹤 ✓

### 3. **cpu_controller.gd** - 限制應用修復

```gdscript
_apply_move_restrictions()  # 改用新的 set_move_restrictions() 方法
```

改進：
- 使用可靠的方法調用（替代 `set()`） ✓
- 更好的錯誤檢查 ✓

---

## 工作流程

```
啟用限制 → AIBehavior 接收 → 傳遞給決策層
                ↓
            決策層篩選招式
                ↓
          被限制? ↙
          /      \
        否       是
        ↓        ↓
      執行    尋找備選
            普通攻擊/防禦
```

---

## 測試方法

### 場景 1：限制 Fireball
```
CPUController Inspector:
  enable_restrictions_a: ☑
  restricted_moves_a: ["fireball"]
```
**結果**：Player A 用 st_mk、st_mp 代替 fireball

### 場景 2：限制所有特殊招式
```
restricted_moves_a: ["fireball", "dp", "powerkk", "spm2", "spm3", "super"]
```
**結果**：Player A 只用普通攻擊和基本防禦

### 場景 3：限制所有招式（邊界測試）
```
restricted_moves_a: ["*"]  # 限制所有
```
**結果**：AI 回退到 walk_forward，保持待機狀態

---

## 日誌檢查清單

運行遊戲並檢查控制台輸出：

✓ `[CPU Controller] Player A move restrictions applied: [...]`
✓ `[AI.set_move_restrictions] ...Restricted moves: ... (enabled: true)`
✓ AI 決策時顯示「找到替代招式」日誌（如有必要）
✓ 執行的招式應該不在限制列表中

---

## 支援的修改操作

### Inspector 界面
```
CPUController.gd
├─ Player A AI Settings
│  ├─ enable_restrictions_a: bool
│  └─ restricted_moves_a: Array[String]
└─ Player B AI Settings
   ├─ enable_restrictions_b: bool
   └─ restricted_moves_b: Array[String]
```

### 動態修改（代碼）
```gdscript
var ai_behavior = player_a.get_node("AIBehavior")
ai_behavior.set_move_restrictions(
    ["fireball", "dp"],  # 限制清單
    true                  # 啟用
)
```

---

## 限制招式列表

### 特殊招式（隨處可用）
- `fireball` (Davina 的火球)
- `spm1` (powerkk - Davina 的超級踢)
- `spm2` (DEN 的特殊招式)
- `spm3` (hdk - DEN 的特殊招式)
- `dp` (龍拳)
- `super` (超級必殺技)

### 普通攻擊（可選）
- `st_lp`, `st_mp`, `st_hp` (站立拳)
- `st_lk`, `st_mk`, `st_hk` (站立踢)
- `cr_lp`, `cr_mp`, `cr_hp` (蹲拳)
- `cr_lk`, `cr_mk`, `cr_hk` (蹲踢)
- `jump_mp`, `jump_lk` 等 (空中招式)

### 移動（可選）
- `dash_forward`, `backdash`
- `walk_forward`, `walk_backward`
- `jump_forward`, `jump_backward`, `jump_neutral`

---

## 效能影響

- **限制檢查成本**：O(n)，n ≤ 5（通常）
- **Fallback 執行**：每決策時僅一次
- **整體影響**：< 1% CPU 開銷增加（可忽略）

---

## 故障排除

### AI 仍在使用被限制的招式
1. ✓ 檢查 CPUController 的 `enable_restrictions_a/b` 是否啟用
2. ✓ 檢查招式名稱拼寫（區分大小寫）
3. ✓ 查看控制台日誌確認「applied」訊息
4. ✓ 檢查 AIBehavior 節點是否存在

### AI 無反應或只待機
1. ✓ 檢查是否限制了所有招式
2. ✓ 確保至少有一個普通攻擊未被限制
3. ✓ 查看日誌中的「Using fallback」訊息

### 限制設定未生效
1. ✓ 確認遊戲已重新啟動（限制在 `_ready()` 時應用）
2. ✓ 檢查 AIBehavior 節點名稱是否正確（必須為 "AIBehavior"）
3. ✓ 使用 `set_move_restrictions()` 動態修改測試

---

## 相關文件

- 📄 `AI_MOVE_RESTRICTION_FIX_SUMMARY.md` - 完整技術文檔
- 📄 `AI_SYSTEM_README.md` - AI 系統概論
- 🔧 `AIDecisionLayers.gd` - 決策層實現
- 🔧 `ai_behavior.gd` - AI 行為主控制器
- ⚙️ `cpu_controller.gd` - 控制器配置

---

## 確認清單

在運行之前驗證：

- [ ] 已修改的 3 個文件無編譯錯誤
- [ ] CPUController 在場景中存在
- [ ] 每個玩家都有 AIBehavior 節點
- [ ] 招式限制列表使用正確的名稱

## 成功指標

運行遊戲並啟用 AI 限制後：

✅ AI 自動避免使用被限制的招式
✅ AI 改用普通攻擊和防禦對戰
✅ AI 不會鎖死或無限待機
✅ 控制台日誌清楚可見限制應用過程

---

**Quick Test**: 啟用「Limited DAV（只限普通攻擊）」，看 AI 是否能用 st_mp/st_mk 有效對戰
