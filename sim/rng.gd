## 确定性随机源：sim 层所有随机必须经此类（种子可指定，保证比赛/AI/淬裂可复现）。
## 表现层特效噪声不使用本类（不涉玩法复现）。
class_name SimRng
extends RefCounted

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## 以指定种子初始化随机序列；同种子必产生同序列。
func setup(seed_val: int) -> void:
	_rng.seed = seed_val


## 返回 [from, to) 内的确定性随机浮点数。
func randf_range(from_value: float, to_value: float) -> float:
	return _rng.randf_range(from_value, to_value)


## 以概率 p 返回 true（M0 预留接口，淬裂掷签等 M1+ 使用）。
func chance(p: float) -> bool:
	return _rng.randf() < p
