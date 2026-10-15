## 锤具表 schema（data/props/prop_hammer_*.tres，id 前缀 prop_）
class_name HammerDef
extends Resource

## 记录 id（prop_ 前缀，文件名 == id）
@export var id: String = ""

## 显示名
@export var display_name: String = ""

## 锤力系数（0~1，与 strike_k 相乘决定击深）
@export var power: float = 0.4

## 应力倍率（手锤锻打更温和）
@export var stress_mult: float = 0.5

## 震屏冲击量（0~1，表现层）
@export var shake_trauma: float = 0.15
