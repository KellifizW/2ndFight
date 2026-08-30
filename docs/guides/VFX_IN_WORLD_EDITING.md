# 2D 特效的編輯器工作流（world.tscn 所見即所得）

> 改動日期：2026-08-30
> 相關檔案：`assets/vfx/vfx.tscn`、`scripts/vfx/vfx_smoke.gd`、`scenes/gameplay/world.tscn`、
> `scripts/core/Movement.gd`、`scripts/handlers/LandingHandler.gd`、
> `scripts/combat/handlers/HitResponseHandler.gd`、`tests/frame_tests/cases/test_33_dash_smoke_one_shot.gd`

## 1. 為什麼要改

`land_smoke`（著地煙）與 `hit_spark_m`（中攻擊火花）是**執行期才生成的一次性特效**：
由 `VFXSmoke.spawn*()` 掛到 world 底下、播完 `queue_free()`。舊作法的代價是
**在編輯器打開 `world.tscn` 完全看不到任何特效節點**，要調特效只能開
`assets/vfx/vfx.tscn`、改程式、跑遊戲猜效果 —— 很不直觀。

同時舊邏輯把兩個特效綁死在單一角色：著地煙 `character_id == "WOO"` 才噴、
命中火花 `_is_woo_medium_attack()` 才播。格鬥遊戲的命中 / 著地回饋應該是
**遊戲全局**的：所有角色共用同一套特效，依「事件」觸發，而不是依「角色」開關。

## 2. 現在的機制：模板複製（template → duplicate）

```
world.tscn
└─ World
   └─ VFXLayer            ← 特效層（編輯器可見；執行期只裝模板）
      └─ SmokeVFX          ← assets/vfx/vfx.tscn 的實例，Inspector 勾了 is_template = true
```

- `assets/vfx/vfx.tscn` 的 `VFXSmoke` 腳本新增 `@export var is_template: bool = false`。
- 放在 `world.tscn` 的那份實例把 `is_template` 勾起來：執行期 `_ready()` 會
  **隱藏自己、停止動畫、並註冊到 `vfx_smoke_template` 群組**，只當複製來源。
- 觸發特效時 `VFXSmoke.spawn_animation()` 優先對**節點樹上的模板做 `duplicate()`**：
  模板在 `world.tscn` 裡被存下的任何覆蓋（子節點位置 / 大小 / 透明度、
  AnimationPlayer 動畫的 keyframe、SpriteFrames……）都會原樣帶進每一團特效。
  →「在 world.tscn 改什麼，遊戲裡就長什麼樣」。
- 副本一律 `is_template = false`（程式重設），照常播放、播完自己 `queue_free()`。
- 找不到模板時（例如直接 F6 執行 vfx.tscn、或精簡測試場景）自動退回舊路徑：
  `ResourcePreloader` 預載的 PackedScene（再退回 `load()`）。行為不變。

### 編輯器操作重點（world.tscn）

1. 選 `World/VFXLayer/SmokeVFX` 或其子節點（已開 editable children，
   Scene 面板可直接展開）。**先選到這層再調**，不要跑遊戲改程式。
2. `AnimatedSprite2D` → `SpriteFrames`：換圖 / 加格 / 調每張格的 `duration` 與 `speed`。
3. `AnimationPlayer` → `smoke` / `bdashsmoke` / `vjumpsmoke` / `land_smoke` /
   `hit_spark_m` 動畫：調整體 length、每格切換時刻（frame track）、
   `offset` / `scale` / `modulate` 逐格軌道。這些動畫名稱是**契約**，改名要同步改
   `vfx_smoke.gd` 的常量（test_33 會釘住它們存在）。
4. 特效出現的「位置」不在 world.tscn 調，而是在**角色場景**的
   `DashSmokePoint`（Marker2D）——每個角色腳下的生成點不同，本來就該由角色
   場景各自微調。著地煙對沒有 Marker 的角色會退回角色自身座標，不會不噴。
5. 注意：**生成時會覆寫副本的根節點 `global_position`（與 X 翻面）**。
   所以拖動 `SmokeVFX` 根節點的位置不會影響遊戲；要調視覺請改子節點
   （例如 `AnimatedSprite2D.position/offset/scale`）或動畫軌道 —— 這些都會被複製。
   `VFXSmoke.spawn_animation` 對根 `scale` 探「保留絕對值、只翻 X 符號」，
   因此模板根節點上調的大小**會**帶進副本。
6. 模板在執行期永遠不可見（`_ready()` 隱藏），不影響畫面與特效計數；
   在編輯器則照常顯示，方便所見即所得。

## 3. 全局化（不再綁定單一角色）

| 特效 | 觸發 | 之前 | 現在 |
| --- | --- | --- | --- |
| 著地煙 `land_smoke` | 任何角色正常著地（含被輸入中斷的零硬直著地） | 只有 `character_id == "WOO"` | **所有角色**（`Movement.spawn_landing_smoke()` 去掉角色判定；無 Marker 退回角色座標） |
| 中攻擊火花 `hit_spark_m` | 任何角色的 `*_mp` / `*_mk` 真正命中（非格擋） | 只有 WOO 的中攻擊（`_is_woo_medium_attack`） | **所有角色**（`HitResponseHandler._is_medium_attack()` 只看 attack_type 後綴） |
| 前衝煙 `smoke` | 前衝（有 `DashSmokePoint` 的角色才噴） | 依 Marker 開關 | 不變（三個角色都已內建 Marker） |
| 後撤步煙 `bdashsmoke` | 後衝（backdash）發動時，仿照前衝煙生成 | 後衝不噴煙 | 有 `DashSmokePoint` 的角色噴 `bdashsmoke` |
| 跳起煙 `vjumpsmoke` | 任何角色離地那一瞬間，仿照著地煙生成 | 只有著地煙 | 有 Marker 用 Marker、無則退回角色座標 |

命中特效的生成點仍是「接触點世界座標」（`_spawn_hit_vfx`），著地煙是
「落地當下的腳下位置」；兩者都掛 world、不跟著身體跑 —— 這部分契約由
test_33 釘住（父節點必須是 world、位置不追隨角色、播完自動消失）。

## 4. 驗證

```bash
# 靜態（CI static-check job）
gdparse <改過的 .gd>
python3 ci/check_signatures.py
python3 ci/check_type_inference.py

# 場景契約（需要 Godot 4.7.2）
godot --headless --path . -s res://tests/frame_tests/run_tests.gd   # 含 test_33
```

test_33 現行釘住的項目：三個角色場景都有 `DashSmokePoint`、world.tscn 有
`VFXLayer/SmokeVFX`（is_template、群組註冊、執行期不可見）、模板改動會帶進
副本、前衝恰一團煙且不追身、後衝噴恰一團 `bdashsmoke`、**跳起/著地煙為全局
（DAV 離地/著地都生成）**、播完自動 `queue_free()`、AnimationPlayer 五支動畫齊全。
