## 炉具表 schema（data/props/prop_forge_coal.tres，id 前缀 prop_）
class_name ForgeDef
extends Resource

## 记录 id（prop_ 前缀，文件名 == id）
@export var id: String = ""

## 炉力系数（与 heat_gain 相乘：功率·增益≈60 °C/s 标定）
@export var power: float = 3.0

## 热增益（°C/s，标定目标：炉内段约 60 °C/s 升温）
@export var heat_gain: float = 20.0

## 炉温波动幅度（flux_factor ∈ [1-amp, 1+amp]）
@export var flux_amplitude: float = 0.15

## 炉温波动周期（秒）
@export var flux_period: float = 1.0
