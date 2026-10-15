## 相机震动组件：挂在 Camera3D 上，trauma² 幅度的噪声位移 + 微 roll，线性衰减。
## 表现层专用 FastNoiseLite（固定 seed），不涉玩法复现。
extends Camera3D

## trauma 线性衰减速率（每秒）
const SHAKE_DECAY: float = 1.6

## 最大位移幅度（m，trauma=1 时）
const SHAKE_AMPLITUDE: float = 0.045

## 最大 roll 角（度，trauma=1 时）
const SHAKE_ROLL_DEG: float = 3.0

## 噪声采样频率（1/s）
const NOISE_SPEED: float = 28.0

var _trauma: float = 0.0
var _base_position: Vector3
var _base_rotation_deg: Vector3
var _noise: FastNoiseLite


func _ready() -> void:
	_base_position = position
	_base_rotation_deg = rotation_degrees

	_noise = FastNoiseLite.new()
	_noise.seed = 20261015
	_noise.frequency = 0.8
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


## 累加冲击量（0~1，越大约震）。
func add_trauma(value: float) -> void:
	_trauma = clampf(_trauma + value, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return

	_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)

	# 衰减到 0 时精确复位，避免浮点残留偏移
	if _trauma <= 0.0:
		position = _base_position
		rotation_degrees = _base_rotation_deg
		return

	var strength: float = _trauma * _trauma
	var time_s: float = Time.get_ticks_msec() * 0.001
	var offset := Vector3(
		_sample(time_s, 11.0),
		_sample(time_s, 37.0),
		_sample(time_s, 59.0)) * SHAKE_AMPLITUDE * strength

	position = _base_position + offset
	rotation_degrees = _base_rotation_deg + Vector3(0.0, 0.0, _sample(time_s, 83.0) * SHAKE_ROLL_DEG * strength)


## 按时间与通道号采样噪声（约 [-1, 1]）
func _sample(time_s: float, channel: float) -> float:
	return _noise.get_noise_2d(time_s * NOISE_SPEED, channel)
