extends Node
## 全域除錯日誌開關（Autoload 名稱: Debug）
##
## 遊戲代碼中原有的 print() 已全部改為 Debug.log()，
## 預設關閉，正常遊戲與 frame 測試時 console 保持乾淨。
##
## 開啟方式（任選其一）:
##   1. 遊戲中按 Ctrl+D 即時切換
##   2. 代碼中: Debug.enabled = true
##   3. 只看特定標籤: Debug.tags = ["THROW", "HIT"]
##      （訊息慣例: 以 [TAG] 開頭，例如 Debug.log("[JUMP] ...")）
##   4. 每幀級別的高頻追蹤日誌: Debug.verbose = true（僅影響 Debug.vlog()）
##
## 慣例:
##   - 事件型日誌（一次動作一次輸出）→ Debug.log()
##   - 每幀 / 高頻追蹤日誌 → Debug.vlog()（需要 verbose=true 才輸出）
##   - 錯誤與警告仍用 push_warning() / push_error()（引擎錯誤通道，不受此開關影響）
##
## ⚠️ 新代碼規則: 禁止在遊戲代碼中直接呼叫 print()，一律走本 logger。

@export var enabled: bool = false
@export var verbose: bool = false
@export var tags: PackedStringArray = []

## 事件型日誌。參數與 print() 相同（任意多個，用空格連接）。
func log(...args: Variant) -> void:
	if not enabled:
		return
	var text := _format(args)
	if not _matches_tags(text):
		return
	Debug.log(text)

## 高頻（每幀）日誌，需要 verbose=true 才會輸出。
func vlog(...args: Variant) -> void:
	if not (enabled and verbose):
		return
	Debug.log(_format(args))

func _matches_tags(text: String) -> bool:
	if tags.is_empty():
		return true
	for t in tags:
		if text.find("[" + t + "]") >= 0:
			return true
	return false

func _format(args: Array) -> String:
	var parts: PackedStringArray = []
	for a in args:
		parts.append(str(a))
	return " ".join(parts)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_D and Input.is_key_pressed(KEY_CTRL):
			enabled = not enabled
			verbose = enabled
			Debug.log("[DEBUG LOGGER] 除錯日誌: %s（再按 Ctrl+D 切換）" % ("開啟" if enabled else "關閉"))
