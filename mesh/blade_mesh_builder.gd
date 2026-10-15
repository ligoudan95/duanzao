## 刀坯网格构建器：按 BladeData 段截面（宽 / 厚 / 偏移）沿 X 轴拉伸成条状网格。
## 顶点色 R = 归一化温度（火色 LUT），G = 锻打氧化皮量（按段累计形变映射，纯感知层）。
## 采用非索引三角（每面独立顶点）→ flat shading：段间/棱面硬棱线，段轮廓肉眼可辨。
## 单位约定：BladeData 为 mm，网格输出为 m（×0.001）。
class_name BladeMeshBuilder
extends RefCounted

## 氧化皮映射放大系数（截面减缩率 ×6 → 一锤约 6% 减缩 ≈ 0.36 氧化：emissive 压到 0.28，"锤一下黑一块"）
const OXIDE_SCALE: float = 6.0

## 氧化皮上限
const OXIDE_MAX: float = 0.85

## 构建整坯 ArrayMesh：相邻段截面环连四边形（两三角）+ 两端端帽。
## [param blade] 刀坯数据
## [param cfg] 模拟参数表（截面轮廓 / 火色温度区间）
## [param flash_seg] 受击闪光段号（-1 无；纯感知层强化，不动模拟数值）
## [param flash_strength] 闪光强度 0~1（受击段顶点温度色被抬升至白热后线性衰减）
## [param blank_area] 初始截面面积（mm²，宽×厚；0 = 不做氧化皮映射）
## [return] 可直接赋给 MeshInstance3D.mesh 的网格
static func build(blade: BladeData, cfg: SimCfg, flash_seg: int = -1, flash_strength: float = 0.0, blank_area: float = 0.0) -> ArrayMesh:
	var shape: PackedVector2Array = cfg.section_shape
	var shape_count: int = shape.size()

	if shape_count < 3 or blade.sections.is_empty():
		push_error("BladeMeshBuilder: 截面轮廓点数不足或刀坯为空")
		return ArrayMesh.new()

	# 预计算每段截面环的顶点位置与颜色（顶点色 R = 归一化温度，含闪光抬升）
	var ring_positions: Array[PackedVector3Array] = []
	var ring_colors: Array[PackedColorArray] = []
	ring_positions.resize(blade.sections.size())
	ring_colors.resize(blade.sections.size())

	for i: int in blade.sections.size():
		var sec: BladeData.SectionData = blade.sections[i]
		var heat_ratio: float = clampf(
			(sec.temp - cfg.heat_lut_temp_min) / (cfg.heat_lut_temp_max - cfg.heat_lut_temp_min),
			0.0, 1.0)

		if i == flash_seg:
			heat_ratio = maxf(heat_ratio, clampf(flash_strength, 0.0, 1.0))

		# 氧化皮量：截面面积相对初始坯料的累计减缩（锻过 = 面积缩 + 哑光暗）
		var oxide: float = 0.0
		if blank_area > 0.0:
			var reduction: float = clampf(1.0 - (sec.width * sec.thickness) / blank_area, 0.0, 1.0)
			oxide = clampf(reduction * OXIDE_SCALE, 0.0, OXIDE_MAX)

		var positions := PackedVector3Array()
		var colors := PackedColorArray()

		for p: int in shape_count:
			var pt: Vector2 = shape[p]
			# 截面轮廓：u=宽度轴(Z)、v=厚度轴(Y)，沿 X 轴排布（mm → m）
			positions.append(Vector3(
				sec.x * 0.001,
				(sec.offset_y + pt.y * sec.thickness * 0.5) * 0.001,
				pt.x * sec.width * 0.5 * 0.001))
			colors.append(Color(heat_ratio, oxide, 0.0, 1.0))

		ring_positions[i] = positions
		ring_colors[i] = colors

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 相邻截面环之间的侧面四边形：每面独立 6 顶点（flat shading 硬棱线）
	for i: int in blade.sections.size() - 1:
		for p: int in shape_count:
			var p_next: int = (p + 1) % shape_count
			_emit_tri(st,
				ring_positions[i][p], ring_colors[i][p],
				ring_positions[i][p_next], ring_colors[i][p_next],
				ring_positions[i + 1][p_next], ring_colors[i + 1][p_next])
			_emit_tri(st,
				ring_positions[i][p], ring_colors[i][p],
				ring_positions[i + 1][p_next], ring_colors[i + 1][p_next],
				ring_positions[i + 1][p], ring_colors[i + 1][p])

	# 端帽：首尾截面扇形三角（同样独立顶点）
	_add_cap_flat(st, blade, cfg, 0, true, shape_count, ring_positions, ring_colors, flash_seg, flash_strength, blank_area)
	_add_cap_flat(st, blade, cfg, blade.sections.size() - 1, false, shape_count, ring_positions, ring_colors, flash_seg, flash_strength, blank_area)

	st.generate_normals()

	return st.commit()


## 添加单端端帽（截面中心 + 扇形独立顶点三角）。
static func _add_cap_flat(st: SurfaceTool, blade: BladeData, cfg: SimCfg,
		section_index: int, is_head: bool, shape_count: int,
		ring_positions: Array[PackedVector3Array], ring_colors: Array[PackedColorArray],
		flash_seg: int, flash_strength: float, blank_area: float) -> void:
	var sec: BladeData.SectionData = blade.sections[section_index]
	var heat_ratio: float = clampf(
		(sec.temp - cfg.heat_lut_temp_min) / (cfg.heat_lut_temp_max - cfg.heat_lut_temp_min),
		0.0, 1.0)

	if section_index == flash_seg:
		heat_ratio = maxf(heat_ratio, clampf(flash_strength, 0.0, 1.0))

	var oxide: float = 0.0
	if blank_area > 0.0:
		var reduction: float = clampf(1.0 - (sec.width * sec.thickness) / blank_area, 0.0, 1.0)
		oxide = clampf(reduction * OXIDE_SCALE, 0.0, OXIDE_MAX)

	var center := Vector3(sec.x * 0.001, sec.offset_y * 0.001, 0.0)
	var center_color := Color(heat_ratio, oxide, 0.0, 1.0)

	for p: int in shape_count:
		var p_next: int = (p + 1) % shape_count
		var a: Vector3 = ring_positions[section_index][p]
		var b: Vector3 = ring_positions[section_index][p_next]

		if is_head:
			_emit_tri(st, center, center_color, b, ring_colors[section_index][p_next], a, ring_colors[section_index][p])
		else:
			_emit_tri(st, center, center_color, a, ring_colors[section_index][p], b, ring_colors[section_index][p_next])


## 发射单个独立顶点三角形（flat shading：每面法线独立）
static func _emit_tri(st: SurfaceTool,
		v0: Vector3, c0: Color, v1: Vector3, c1: Color, v2: Vector3, c2: Color) -> void:
	st.set_color(c0)
	st.add_vertex(v0)
	st.set_color(c1)
	st.add_vertex(v1)
	st.set_color(c2)
	st.add_vertex(v2)
