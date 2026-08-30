extends Node2D
class_name VFXSmoke

@onready var _anim_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	# 播完後 stop():sprite 回到「無動畫 = 不可見」,
	# 下次 play_smoke() 會從第 0 幀重新播放
	_anim_player.animation_finished.connect(_on_animation_finished)

func play_smoke() -> void:
	_anim_player.play("dash_smoke")

func _on_animation_finished(_anim_name: StringName) -> void:
	_anim_player.stop()
