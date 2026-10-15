## 锻打模拟：单击形变（主段 + 邻段衰减）、侧面打击位移、应力积累。
## 打击结果以 StrikeResult 同步返回（M0 零 signal），胶水层直调表现组件。
class_name ForgeSim
extends RefCounted


## 单次锤击结果（同步返回值承载事件数据）。
class StrikeResult extends RefCounted:
	## 命中段号
	var seg: int = 0

	## 打击面：0=上面（平面锻打）、1=左侧面、2=右侧面
	var face: int = 0

	## 可锻度 m（0=冷不可锻，1=完全可锻）
	var m: float = 0.0

	## 主段实际厚度变化（mm，含 clamp，负值 = 变薄）
	var d_thickness: float = 0.0

	## 本次新增应力（0~100 区间内的增量）
	var stress_added: float = 0.0

	## 冷击（m < 0.01）：不变形、应力照常积累
	var cold_hit: bool = false

	## 本次有段厚度触底 min_thickness
	var clamped_thickness: bool = false

	## 本次有段宽度触顶砧宽上限
	var clamped_width: bool = false


## 执行一次锤击，就地修改刀坯形变与应力。
## [param blade] 刀坯（就地修改）
## [param seg] 命中段号（越界会被 clamp）
## [param face] 打击面（0 上 / 1 左 / 2 右）
## [param hammer] 锤具表
## [param cfg] 模拟参数表
## [param anvil_width] 砧面宽度（mm，宽度上限基准）
## [return] 打击结果
static func strike(blade: BladeData, seg: int, face: int, hammer: HammerDef,
		cfg: SimCfg, anvil_width: float) -> StrikeResult:
	var result := StrikeResult.new()
	var count: int = blade.sections.size()
	result.seg = clampi(seg, 0, count - 1)
	result.face = face

	var sec: BladeData.SectionData = blade.sections[result.seg]
	result.m = clampf((sec.temp - cfg.forgeable_temp_zero) / cfg.forgeable_temp_span, 0.0, 1.0)
	result.cold_hit = result.m < 0.01

	if face == 0:
		_strike_flatten(blade, result, hammer, cfg, anvil_width)
		_apply_stress(sec, result, hammer, cfg)
	else:
		_strike_side(sec, result, hammer, cfg)

	return result


## 平面锻打：主段变薄展宽，邻段 [seg-2, seg+2] 按 falloff^|Δ| 衰减同公式换算。
static func _strike_flatten(blade: BladeData, result: StrikeResult, hammer: HammerDef,
		cfg: SimCfg, anvil_width: float) -> void:
	var d_thickness_main: float = -cfg.strike_k * hammer.power * result.m
	var count: int = blade.sections.size()

	# 主段
	result.d_thickness = _apply_flatten(blade.sections[result.seg], d_thickness_main,
			cfg, anvil_width, result)

	# 邻段 ±1、±2：各自按自身 w/th 换算展宽
	for offset: int in [-2, -1, 1, 2]:
		var index: int = result.seg + offset

		if index < 0 or index >= count:
			continue

		var d_neighbor: float = d_thickness_main * pow(cfg.neighbor_falloff, absi(offset))
		_apply_flatten(blade.sections[index], d_neighbor, cfg, anvil_width, result)


## 对单段施加变薄展宽（含厚度下限 / 宽度上限 clamp），返回实际厚度变化。
static func _apply_flatten(sec: BladeData.SectionData, d_thickness: float,
		cfg: SimCfg, anvil_width: float, result: StrikeResult) -> float:
	# 厚度：触底 min_thickness 则截断
	var wanted_th: float = sec.thickness + d_thickness
	var new_th: float = maxf(wanted_th, cfg.min_thickness)

	if wanted_th < cfg.min_thickness - 1e-9:
		result.clamped_thickness = true

	var applied_th: float = new_th - sec.thickness

	# 展宽：d_w = -d_th * (w/th) * spread_keep_ratio（用打击前的 w/th）
	var ratio: float = sec.width / sec.thickness if sec.thickness > 0.0 else 0.0
	var wanted_w: float = sec.width - applied_th * ratio * cfg.spread_keep_ratio

	# 宽度：触顶砧面宽度上限则截断
	var width_max: float = anvil_width * cfg.width_max_factor
	var new_w: float = minf(wanted_w, width_max)

	if wanted_w > width_max + 1e-9:
		result.clamped_width = true

	sec.thickness = new_th
	sec.width = new_w

	return applied_th


## 应力积累：仅主段，邻段不积累；clamp 0~100。
static func _apply_stress(sec: BladeData.SectionData, result: StrikeResult,
		hammer: HammerDef, cfg: SimCfg) -> void:
	var stress_delta: float = cfg.stress_s0 * hammer.power * hammer.stress_mult * ((1.0 - result.m) + 0.15)
	var new_stress: float = clampf(sec.stress + stress_delta, 0.0, 100.0)
	result.stress_added = new_stress - sec.stress
	sec.stress = new_stress


## 侧面打击：仅位移截面中心（offset_y），宽 / 厚 / 应力不变。
static func _strike_side(sec: BladeData.SectionData, result: StrikeResult,
		hammer: HammerDef, cfg: SimCfg) -> void:
	var offset_delta: float = cfg.strike_k * hammer.power * result.m * cfg.side_ratio

	if result.face == 1:
		sec.offset_y += offset_delta
	else:
		sec.offset_y -= offset_delta
