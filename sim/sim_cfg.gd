## 全局模拟参数表 schema（data/cfg/cfg_sim.tres）
## 承载热传导 / 锻打形变 / 应力等所有模拟层公式参数，代码零硬编码数值。
class_name SimCfg
extends Resource

## 固定模拟步长（秒），10Hz
@export var dt: float = 0.1

## 环境温度（°C）
@export var t_ambient: float = 20.0

## 散热指数：(T - t_ambient) ^ cooling_exponent
@export var cooling_exponent: float = 1.15

## 端段散热倍率（刀坯两端散热更快）
@export var end_cooling_factor: float = 1.6

## 温度上限（°C）
@export var temp_max: float = 1400.0

## 火色 LUT 映射温度下限（°C），低于此温度为冷黑
@export var heat_lut_temp_min: float = 480.0

## 火色 LUT 映射温度上限（°C）
@export var heat_lut_temp_max: float = 1350.0

## 归一化截面轮廓（8 点，u=宽度轴 [-1,1]，v=厚度轴 [-1,1]）：脊平楔刃
@export var section_shape: PackedVector2Array = PackedVector2Array()

## 可锻温度下限（°C），低于此温度 m=0（冷打）
@export var forgeable_temp_zero: float = 700.0

## 可锻温度过渡区间宽度（°C），zero+span 处 m=1
@export var forgeable_temp_span: float = 200.0

## 锻打击深系数：d_thickness = -strike_k * power * m
@export var strike_k: float = 0.6

## 延展保留比：展宽量 = 击深量 * (w/th) * spread_keep_ratio（体积近似守恒）
@export var spread_keep_ratio: float = 0.88

## 邻段击深衰减（|Δ|=1 衰减 falloff，|Δ|=2 衰减 falloff^2）
@export var neighbor_falloff: float = 0.35

## 应力基准系数：stress += stress_s0 * power * stress_mult * ((1-m)+0.15)
@export var stress_s0: float = 4.0

## 最小厚度（mm），低于此不再变薄
@export var min_thickness: float = 1.5

## 宽度上限系数：宽度 ≤ anvil_face_width * width_max_factor
@export var width_max_factor: float = 1.3

## 侧面打击的位移比：offset = strike_k * power * m * side_ratio
@export var side_ratio: float = 0.5
