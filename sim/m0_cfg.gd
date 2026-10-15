## M0 原型参数表 schema（data/cfg/cfg_m0.tres）
## 承载 M0 场景尺寸、输入节奏、种子与表现曲线（火花量 / 音调）。
class_name M0Cfg
extends Resource

## 刀坯总长（mm）
@export var blank_length: float = 180.0

## 刀坯初始宽度（mm）
@export var blank_width: float = 30.0

## 刀坯初始厚度（mm）
@export var blank_thickness: float = 8.0

## 分段数 N
@export var segment_count: int = 16

## 初始温度（°C，室温冷坯）
@export var initial_temp: float = 20.0

## 砧面宽度（mm），锻打宽度上限的基准
@export var anvil_face_width: float = 60.0

## 炉口区间世界 x 下限（米，场景空间，匹配 ForgeRig @ x=+3m 摆位）
@export var forge_mouth_x_min: float = 2.75

## 炉口区间世界 x 上限（米）
@export var forge_mouth_x_max: float = 2.95

## BladeRig 世界 x 平移下限（米）
@export var blade_x_min: float = -0.18

## BladeRig 世界 x 平移上限（米）
@export var blade_x_max: float = 2.76

## 锤击冷却（秒）
@export var strike_cooldown: float = 0.25

## 输入到落锤延迟（秒），M0 为 0（即打即中）
@export var input_to_impact_delay: float = 0.0

## 模拟种子（热源波动等所有随机），保证可复现
@export var sim_seed: int = 20261015

## 火花量曲线（温度 °C → 火花数）：成对锚点 (x,y,x,y,...) 分段线性
@export var spark_curve: PackedFloat32Array = PackedFloat32Array()

## 敲击音调曲线（温度 °C → pitch_scale）：冷脆热闷
@export var pitch_curve: PackedFloat32Array = PackedFloat32Array()
