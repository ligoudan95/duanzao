## 火色 LUT 生成工具（一次性运行）：godot --headless -s res://tools/gen_heat_lut.gd
## 按火色物理锚点生成 256×1 PNG → res://fx/heat_color_lut.png
extends SceneTree

## 火色锚点温度（°C），与 cfg_sim.heat_lut_temp_min/max 对应
var _anchor_temps: PackedFloat32Array = PackedFloat32Array([480.0, 550.0, 700.0, 850.0, 1050.0, 1250.0, 1350.0])

## 火色锚点颜色（480 黑 → 1350 白亮）
var _anchor_colors: Array[Color] = [
	Color(0.00, 0.00, 0.00),
	Color(0.35, 0.02, 0.00),
	Color(0.55, 0.08, 0.00),
	Color(1.00, 0.30, 0.02),
	Color(1.00, 0.55, 0.10),
	Color(1.00, 0.85, 0.50),
	Color(1.00, 0.97, 0.85),
]

## LUT 温度映射范围（与 cfg_sim 一致）
const TEMP_MIN: float = 480.0
const TEMP_MAX: float = 1350.0
const LUT_WIDTH: int = 256


func _init() -> void:
	_generate_lut()
	quit()


## 生成并保存 LUT 图片
func _generate_lut() -> void:
	var image := Image.create(LUT_WIDTH, 1, false, Image.FORMAT_RGB8)

	for x: int in LUT_WIDTH:
		var ratio: float = float(x) / float(LUT_WIDTH - 1)
		var temp: float = TEMP_MIN + ratio * (TEMP_MAX - TEMP_MIN)
		image.set_pixel(x, 0, _eval_color(temp))

	var err := image.save_png("res://fx/heat_color_lut.png")

	if err != OK:
		push_error("gen_heat_lut: 保存失败 code=%d" % err)
	else:
		print("gen_heat_lut: 已生成 res://fx/heat_color_lut.png")


## 温度 → 锚点间分段线性插值颜色
func _eval_color(temp: float) -> Color:
	var count: int = _anchor_temps.size()

	if temp <= _anchor_temps[0]:
		return _anchor_colors[0]

	if temp >= _anchor_temps[count - 1]:
		return _anchor_colors[count - 1]

	for i: int in count - 1:
		var t0: float = _anchor_temps[i]
		var t1: float = _anchor_temps[i + 1]

		if temp >= t0 and temp <= t1:
			var ratio: float = (temp - t0) / (t1 - t0)
			return _anchor_colors[i].lerp(_anchor_colors[i + 1], ratio)

	return _anchor_colors[count - 1]
