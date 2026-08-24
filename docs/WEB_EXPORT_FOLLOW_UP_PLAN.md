# Web 發布 Follow-up Plan

本分支已加入 Godot Web export preset 與 GitHub Pages workflow，目標是讓 `main`
分支更新後自動匯出並部署 `Web` preset。

## 尚未能在本地完成的驗證

目前執行環境沒有安裝 Godot 4.7.2 CLI，也沒有瀏覽器 WebGL 測試環境，因此尚未能
在本地實際完成以下工作：

- `godot --headless --export-release "Web" ...` 的實際匯出
- 確認所有動畫、粒子、Shader、碰撞和 120 Hz 物理在 WebAssembly 中運作
- 確認 Chrome、Edge、Firefox 的鍵盤輸入延遲與音效播放
- 確認 GitHub Pages 部署後的實際 URL

GitHub Actions 會使用 `barichello/godot-ci:4.7.2-stable` 執行 Web export；第一次
PR 或合併到 `main` 後，應優先檢查 workflow log。

## 已依要求保留的事項

- 沒有修正過期的 `res://` 資源路徑。
- 沒有接回主選單；`project.godot` 維持直接啟動 `world.tscn` 對戰。
- 沒有重新壓縮、降解析度或重編碼遊戲資源。
- Web preset 使用 `all_resources`，並排除開發用 addons、tests、docs、examples、
  backup 及已知孤兒 `data/attacks` 資源。

## 合併 PR 後的操作

1. 到 GitHub repository 的 **Settings → Pages**。
2. 將 Pages 的 Build and deployment source 設為 **GitHub Actions**。
3. 合併 PR 或手動執行 **Export and deploy Web game** workflow。
4. 於 workflow 的 `deploy` job 查看 `github-pages` environment URL。
5. 在 Chrome 與 Firefox 開啟頁面，打開開發者工具檢查 WebGL、WASM、資源載入錯誤。

## 後續風險與建議

### 高優先

- 若 export job 因場景中的舊 UID/path、腳本或孤兒資源失敗，需要在 workflow log 中
  針對實際錯誤補上 export exclude 或修正資源引用。
- 確認 GitHub Pages 發布的整個網站低於 GitHub Pages 的容量及部署時間限制。
- 以公開桌面瀏覽器測量啟動時間、記憶體、FPS 和 120 Hz physics 是否穩定。

### 中優先

- `world.gd` 已將 BGM 改為由第一個鍵盤、滑鼠、觸控或 gamepad user gesture
  啟動，以避開瀏覽器 autoplay 限制；仍需在 Chrome、Edge、Firefox 實際確認。
- 如果想加入 Web Threads，必須重新評估並加入 COOP/COEP cross-origin isolation
  headers；目前刻意使用 single-thread Web export 以降低 GitHub Pages 部署要求。
- 若要支援 Safari，需要另外測試其 WebGL 2.0 行為。

### 不在本 PR 範圍

- 過期資源路徑的整理。
- 圖片、字型及音訊的壓縮或最佳化。
- 不同裝置的觸控控制。
- 線上多人對戰。現有遊戲仍是本機玩家/AI 對戰；線上對戰需要 WebSocket/WebRTC
  伺服器、同步、延遲補償及斷線處理。
