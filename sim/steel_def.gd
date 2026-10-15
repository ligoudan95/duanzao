## 钢材表 schema（data/steels/*.tres，id 前缀 steel_）
## 热学参数：传导系数 alpha、散热基准 beta_base、参考厚度 th_ref。
class_name SteelDef
extends Resource

## 记录 id（steel_ 前缀，文件名 == id）
@export var id: String = ""

## 显示名
@export var display_name: String = ""

## 轴向传导系数（无量纲，按 dt 缩放后参与扩散）
@export var alpha: float = 0.08

## 散热基准系数（1/s，标定目标：850°C 静置约 100s 降到 700°C）
@export var beta_base: float = 0.0006

## 参考厚度（mm），实际散热 beta = beta_base * (th_ref / thickness)
@export var th_ref: float = 8.0
