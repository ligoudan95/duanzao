## 分段线性曲线求值工具：成对锚点 (x0,y0,x1,y1,...) 的 PackedFloat32Array 曲线。
## 用于火花量 / 音调等表现曲线（数据存 cfg 表）。
class_name CurveUtil
extends RefCounted


## 对成对锚点曲线求值：x 超出锚点范围时取端点值。
## [param points] 锚点数组（长度为偶数，x 升序）
## [param x] 查询值
## [return] 分段线性插值结果（空数组返回 0）
static func eval_curve(points: PackedFloat32Array, x: float) -> float:
	if points.is_empty():
		return 0.0

	var pair_count: int = points.size() / 2

	if pair_count == 1:
		return points[1]

	# 端点截断
	if x <= points[0]:
		return points[1]

	var last_index: int = (pair_count - 1) * 2

	if x >= points[last_index]:
		return points[last_index + 1]

	# 区间内分段线性插值
	for i: int in pair_count - 1:
		var x0: float = points[i * 2]
		var y0: float = points[i * 2 + 1]
		var x1: float = points[(i + 1) * 2]
		var y1: float = points[(i + 1) * 2 + 1]

		if x >= x0 and x <= x1:
			var t: float = (x - x0) / (x1 - x0)

			return lerpf(y0, y1, t)

	return points[1]
