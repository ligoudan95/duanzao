## 锤击动画组件：触发一次 0.12s 挥击/回弹动画。
extends Node3D

@onready var _anim_player: AnimationPlayer = $AnimationPlayer


## 触发一次挥击动画（连打时打断重播）。
func play_impact() -> void:
	_anim_player.stop()
	_anim_player.play("strike")
