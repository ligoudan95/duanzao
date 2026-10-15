## 热模拟：轴向传导 + 表面散热 + 炉口加热，固定步长（cfg_sim.dt），逐段先算后写。
## 所有项均为"速率"（°C/s），统一乘 dt 后累加；标定目标见表内注释。
class_name HeatSim
extends RefCounted


## 炉子运行时状态（波动系数 / 波动计时 / 参考体积）。
class ForgeState extends RefCounted:
	## 炉温波动系数（∈ [1-amp, 1+amp]，周期性重掷）
	var flux_factor: float = 1.0

	## 距下次波动重掷的累计时间（秒）
	var timer: float = 0.0

	## 加热项参考体积（建刀坯时按初始单段体积填充，mm³）
	var ref_volume: float = 0.0


## 推进一个固定步长的温度演化。
## [param blade] 刀坯（sections 的 temp 被就地更新）
## [param steel] 钢材表（传导 alpha / 散热 beta_base / 参考厚度）
## [param cfg] 模拟参数表（dt / 环境温度 / 温度上限等）
## [param forge_def] 炉具表（功率 / 热增益 / 波动参数）
## [param state] 炉子运行时状态（波动系数被就地更新）
## [param coverage] 各段炉口覆盖系数（0~1，长度 = 段数）
## [param rng] 确定性随机源（炉温波动重掷）
static func tick(blade: BladeData, steel: SteelDef, cfg: SimCfg, forge_def: ForgeDef,
		state: ForgeState, coverage: Array[float], rng: SimRng) -> void:
	# 波动重掷：计时超周期则重掷 flux_factor 并归零
	state.timer += cfg.dt

	if state.timer >= forge_def.flux_period:
		state.flux_factor = rng.randf_range(1.0 - forge_def.flux_amplitude, 1.0 + forge_def.flux_amplitude)
		state.timer = 0.0

	var count: int = blade.sections.size()
	var new_temps: Array[float] = []
	new_temps.resize(count)

	# 逐段先算后写，避免同帧内相邻段读到已更新的温度
	for i: int in count:
		var sec: BladeData.SectionData = blade.sections[i]
		var temp: float = sec.temp

		# 传导项：中段二阶差分；端段单邻差分（绝热端外无热流）
		var conduction: float = 0.0
		if count > 1:
			if i == 0:
				conduction = steel.alpha * (blade.sections[1].temp - temp)
			elif i == count - 1:
				conduction = steel.alpha * (blade.sections[count - 2].temp - temp)
			else:
				conduction = steel.alpha * (blade.sections[i - 1].temp + blade.sections[i + 1].temp - 2.0 * temp)

		# 散热项：beta_i = beta_base · 端段倍率 · (th_ref / thickness)
		var cooling: float = 0.0
		var temp_diff: float = temp - cfg.t_ambient

		if temp_diff > 0.0:
			var is_end: bool = i == 0 or i == count - 1
			var end_factor: float = cfg.end_cooling_factor if is_end else 1.0
			var beta: float = steel.beta_base * end_factor * (steel.th_ref / sec.thickness)
			cooling = beta * pow(temp_diff, cfg.cooling_exponent)

		# 加热项：炉内段升温，越薄（体积相对参考体积越小）升温越快
		var heating: float = 0.0
		var seg_volume: float = sec.width * sec.thickness * blade.segment_length

		if seg_volume > 0.0:
			heating = forge_def.power * forge_def.heat_gain * state.flux_factor * coverage[i] * (state.ref_volume / seg_volume)

		new_temps[i] = clampf(temp + cfg.dt * (conduction - cooling + heating), cfg.t_ambient, cfg.temp_max)

	# 全段写回
	for i: int in count:
		blade.sections[i].temp = new_temps[i]
