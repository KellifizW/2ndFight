# AI System

這個資料夾包含所有與AI對手相關的系統文件。

## 文件說明

### 核心AI系統
- **ai_behavior.gd** - AI行為主控制器，處理決策執行和行動承諾系統
- **AIDecisionLayers.gd** - 分層決策系統（生存、懲罰、戰術、定位、待機）
- **cpu_controller.gd** - CPU控制器，負責啟用/停用AI

### AI子系統
- **ThreatAssessment.gd** - 威脅評估系統（攻擊、火球、空中攻擊）
- **AIComboSystem.gd** - AI連段系統
- **FrameDataManager.gd** - 幀數據管理器
- **SpaceControl.gd** - 空間控制和定位系統

## 架構概覽

```
AIBehavior (主控制器)
├── AIDecisionLayers (決策層)
│   ├── ThreatAssessment (威脅評估)
│   ├── FrameDataManager (幀數據)
│   ├── AIComboSystem (連段系統)
│   └── SpaceControl (空間控制)
└── 行動承諾系統 (Action Commitment)
```

## 使用方式

AI系統自動附加到Player場景中，可通過以下方式控制：
- 按 **C** 鍵切換 Player A 的AI
- 按 **V** 鍵切換 Player B 的AI
- 對戰畫面左下 / 右下的 **P1 AI / P2 AI** 觸碰按鈕，滑鼠或觸控都可直接切換（Web 版也適用）

詳細文檔請參考項目根目錄的 AI_SYSTEM_README.md
