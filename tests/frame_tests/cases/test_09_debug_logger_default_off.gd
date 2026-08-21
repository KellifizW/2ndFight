extends FrameTestCase
## Debug logger 預設值：遊戲代碼日誌預設關閉（Stage 0 新不變式）
## 透過節點取得，不依賴 autoload 全域識別碼解析

func run() -> bool:
	var dbg = world.get_tree().root.get_node_or_null("Debug")
	check(dbg != null, "Debug (DebugLogger) 節點不存在")
	if dbg == null:
		return false

	check(dbg.enabled == false, "Debug.enabled 預設應為 false（避免 per-frame 日誌污染 console）")
	check(dbg.verbose == false, "Debug.verbose 預設應為 false")
	check(dbg.tags.size() == 0, "Debug.tags 預設應為空")

	# 功能驗證：關閉時 log() 不應該輸出（無法直接抓 stdout，改為驗證開關可切換）
	dbg.enabled = true
	check(dbg.enabled == true, "Debug.enabled 應可程式化開啟")
	dbg.enabled = false

	return not has_failures()
