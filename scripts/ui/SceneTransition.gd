extends CanvasLayer
## Persistent black scene transition used by every gameplay/menu scene.

const FADE_DURATION: float = 0.35

var _overlay: ColorRect
var _transitioning: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Start every launch on black, then reveal the initial scene.
	_fade_in()

func transition_to(scene_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_overlay, "color:a", 1.0, FADE_DURATION)
	tween.tween_callback(_change_scene.bind(scene_path))

func _change_scene(scene_path: String) -> void:
	# A pause-menu transition begins while SceneTree is paused. Always restore it
	# before replacing the current scene so the destination can run normally.
	get_tree().paused = false
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("無法切換場景 %s（錯誤碼 %s）" % [scene_path, error])
		_transitioning = false
		_fade_in()
		return

	# change_scene_to_file swaps scenes at the end of the frame.
	await get_tree().process_frame
	_fade_in()

func _fade_in() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_overlay, "color:a", 0.0, FADE_DURATION)
	tween.tween_callback(func() -> void:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transitioning = false
	)
