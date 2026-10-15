## 锤击音效组件：3 个 AudioStreamPlayer 轮询防打断，pitch_scale 随温度走 cfg_m0.pitch_curve（冷脆热闷）。
## 音频资源路径集中在此常量，替换正式素材时只改这里。
extends Node

## 锤击音效路径（CC0 真实采样，来源与许可见 audio/CREDITS.md）
const SFX_STRIKE_PATH: String = "res://audio/sfx_hammer_strike.ogg"

## 音调安全区间
const PITCH_MIN: float = 0.1
const PITCH_MAX: float = 4.0

var _players: Array[AudioStreamPlayer] = []
var _next_index: int = 0
var _pitch_curve: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var stream := load(SFX_STRIKE_PATH) as AudioStream

	for child: Node in get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			player.stream = stream
			_players.append(player)

	if stream == null:
		push_warning("sfx_striker: 未找到锤击音效 %s（占位/缺失，待替换）" % SFX_STRIKE_PATH)

	var cfg_m0 := load("res://data/cfg/cfg_m0.tres") as M0Cfg
	if cfg_m0 != null:
		_pitch_curve = cfg_m0.pitch_curve


## 播放一次锤击音：按温度调 pitch（冷=高频清脆，热=低频沉闷）。
## [param temp] 命中段温度（°C）
func play_strike(temp: float) -> void:
	if _players.is_empty():
		return

	var player := _players[_next_index]
	_next_index = (_next_index + 1) % _players.size()
	player.pitch_scale = clampf(CurveUtil.eval_curve(_pitch_curve, temp), PITCH_MIN, PITCH_MAX)
	player.play()
